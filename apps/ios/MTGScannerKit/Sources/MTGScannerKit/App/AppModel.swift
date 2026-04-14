import Foundation
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
public final class AppModel {
    var latestResult: RecognitionResult = .sample
    var corrections: [UUID: CardCorrection] = [:]

    /// SwiftData model context, set after app launch.
    public var modelContext: ModelContext?
    var apiBaseURL: String {
        didSet { persistAPIBaseURL() }
    }
    var onDeviceCropEnabled: Bool {
        didSet { persistOnDeviceCrop() }
    }
    var autoScanCaptureDelay: Double {
        didSet { UserDefaults.standard.set(autoScanCaptureDelay, forKey: autoScanCaptureDelayKey) }
    }
    var autoScanConfidenceThreshold: Double {
        didSet { UserDefaults.standard.set(autoScanConfidenceThreshold, forKey: autoScanConfidenceKey) }
    }
    var maxConcurrentUploads: Int {
        didSet { UserDefaults.standard.set(maxConcurrentUploads, forKey: maxConcurrentUploadsKey) }
    }
    var motionBurstPreset: MotionBurstPreset {
        didSet { UserDefaults.standard.set(motionBurstPreset.rawValue, forKey: motionBurstPresetKey) }
    }
    var motionBurstMotionThreshold: Double {
        didSet { UserDefaults.standard.set(motionBurstMotionThreshold, forKey: motionBurstMotionThresholdKey) }
    }
    var motionBurstMinPeakThreshold: Double {
        didSet { UserDefaults.standard.set(motionBurstMinPeakThreshold, forKey: motionBurstMinPeakThresholdKey) }
    }
    var exposureBias: Double {
        didSet { UserDefaults.standard.set(exposureBias, forKey: exposureBiasKey) }
    }
    var isRecognizing = false
    var statusMessage = "Point camera at cards to scan."
    var lastUploadedFilename: String?
    /// Crops detected during the last capture, for display in the preview.
    var lastDetectedCrops: [UIImage] = []
    /// Crop images keyed by the corresponding RecognizedCard.id.
    var cardCropImages: [UUID: UIImage] = [:]
    var shouldShowResults = false
    /// Navigation path for the Results tab — reset to dismiss detail views.
    var resultsNavigationPath = NavigationPath()
    /// When true, shows a connection-unavailable alert.
    var showConnectionAlert = false
    var connectionAlertMessage = ""
    var showUndoAlert = false
    private var latestUndoAction: (@MainActor () -> Void)?

    /// Torch level to restore when returning to scan view (same session only, not persisted)
    var lastTorchLevel: Float = 0

    private let apiClient = APIClient()
    private let cropService = CardCropService()
    private let correctionsStoreKey = "card_corrections"
    private let apiBaseURLStoreKey = "api_base_url"
    private let onDeviceCropStoreKey = "on_device_crop_enabled"
    private let autoScanCaptureDelayKey = "auto_scan_capture_delay"
    private let autoScanConfidenceKey = "auto_scan_confidence_threshold"
    private let maxConcurrentUploadsKey = "max_concurrent_uploads"
    private let motionBurstPresetKey = "motion_burst_preset"
    private let motionBurstMotionThresholdKey = "motion_burst_motion_threshold"
    private let motionBurstMinPeakThresholdKey = "motion_burst_min_peak_threshold"
    private let exposureBiasKey = "exposure_bias"

    public init() {
        self.apiBaseURL = UserDefaults.standard.string(forKey: apiBaseURLStoreKey) ?? AppConfig.defaultAPIBaseURL
        self.onDeviceCropEnabled = UserDefaults.standard.object(forKey: onDeviceCropStoreKey) as? Bool ?? true
        let storedDelay = UserDefaults.standard.double(forKey: autoScanCaptureDelayKey)
        self.autoScanCaptureDelay = Self.clampAutoScanCaptureDelay(storedDelay)
        let storedConf = UserDefaults.standard.double(forKey: autoScanConfidenceKey)
        self.autoScanConfidenceThreshold = Self.clampAutoScanConfidence(storedConf)
        let storedConcurrent = UserDefaults.standard.integer(forKey: maxConcurrentUploadsKey)
        self.maxConcurrentUploads = Self.clampMaxConcurrentUploads(storedConcurrent)
        let storedPreset = UserDefaults.standard.string(forKey: motionBurstPresetKey)
        self.motionBurstPreset = MotionBurstPreset(rawValue: storedPreset ?? "") ?? .balanced
        let storedMotionThreshold = UserDefaults.standard.double(forKey: motionBurstMotionThresholdKey)
        self.motionBurstMotionThreshold = storedMotionThreshold > 0 ? storedMotionThreshold : 0.015
        let storedMinPeak = UserDefaults.standard.double(forKey: motionBurstMinPeakThresholdKey)
        self.motionBurstMinPeakThreshold = storedMinPeak > 0 ? storedMinPeak : 0.05
        let storedBias = UserDefaults.standard.object(forKey: exposureBiasKey) as? Double
        self.exposureBias = storedBias ?? 0.0
        loadCorrections()
    }

    private static func clampAutoScanCaptureDelay(_ value: Double) -> Double {
        guard value > 0 else { return 2.0 }
        return min(max(value, 0.5), 5.0)
    }

    private static func clampAutoScanConfidence(_ value: Double) -> Double {
        guard value > 0 else { return 0.5 }
        return min(max(value, 0.3), 0.9)
    }

    private static func clampMaxConcurrentUploads(_ value: Int) -> Int {
        guard value > 0 else { return 2 }
        return min(max(value, 1), 6)
    }

    // MARK: - Recognition entry points

    /// Recognise cards in a single image (camera capture or photo library).
    ///
    /// Flow:
    /// 1. Run on-device crop detection.
    /// 2. If ≥1 usable crop found → upload to batch endpoint.
    /// 3. Otherwise → fall back to single-image endpoint.
    func recognizeImage(data: Data, filename: String, contentType: String) async {
        guard let uiImage = UIImage(data: data) else {
            statusMessage = "Could not decode image for detection."
            return
        }
        let supportedContentTypes = UTType(mimeType: contentType).map { [$0] } ?? []
        guard let payload = RecognitionImagePayload.importedPhoto(
            data: data,
            image: uiImage,
            supportedContentTypes: supportedContentTypes
        ) else {
            statusMessage = "Failed to prepare image for upload."
            return
        }
        await recognizeImage(payload: payload, filename: filename)
    }

    /// Recognise cards from a UIImage directly (avoids Data round-trip for camera captures).
    ///
    /// When `onDeviceCropEnabled` is true, runs on-device detection first and uploads
    /// crops to the batch endpoint. When false, sends the full image to the single-image endpoint.
    func recognizeImage(image: UIImage, filename: String) async {
        guard let payload = RecognitionImagePayload.generatedJPEG(from: image) else {
            statusMessage = "Failed to encode image."
            return
        }
        await recognizeImage(payload: payload, filename: filename)
    }

    private func recognizeImage(payload: RecognitionImagePayload, filename: String) async {
        resultsNavigationPath = NavigationPath()

        do {
            try await apiClient.checkHealth(baseURL: apiBaseURL)
        } catch {
            connectionAlertMessage = "Cannot reach the server at \(apiBaseURL). Check your connection and API settings."
            showConnectionAlert = true
            return
        }

        isRecognizing = true
        lastDetectedCrops = []
        cardCropImages = [:]
        lastUploadedFilename = filename

        if onDeviceCropEnabled {
            statusMessage = "Detecting cards…"
            let cropResult = await cropService.detectAndCrop(image: payload.displayImage)
            lastDetectedCrops = cropResult.crops
            if !cropResult.crops.isEmpty {
                await recognizeViaBatch(crops: cropResult.crops, baseFilename: filename)
            } else {
                await uploadFullImage(payload: payload, filename: filename)
            }
        } else {
            statusMessage = "Uploading full image…"
            await uploadFullImage(payload: payload, filename: filename)
        }

        isRecognizing = false
        persistRecognizedCards()
        shouldShowResults = true
    }

    // MARK: - Private recognition helpers

    private func uploadFullImage(payload: RecognitionImagePayload, filename: String) async {
        await recognizeViaSingleImage(data: payload.uploadData, filename: filename, contentType: payload.contentType)
    }

    private func recognizeViaBatch(crops: [UIImage], baseFilename: String) async {
        let stem = (baseFilename as NSString).deletingPathExtension
        var cropPairs: [(data: Data, filename: String)] = []
        for (i, crop) in crops.enumerated() {
            guard let payload = RecognitionImagePayload.generatedJPEG(from: crop) else { continue }
            let ext = payload.preferredFilenameExtension
            cropPairs.append((data: payload.uploadData, filename: "\(stem)-crop-\(i).\(ext)"))
        }

        guard !cropPairs.isEmpty else {
            // All crop encodings failed — fall back.
            statusMessage = "Crop encoding failed, uploading full image…"
            return
        }

        statusMessage = "Uploading \(cropPairs.count) crop(s)…"

        do {
            latestResult = try await apiClient.recognizeBatch(
                crops: cropPairs,
                baseURL: apiBaseURL
            )
            associateCropsWithCards()
            statusMessage = "Recognition finished (\(cropPairs.count) crop(s)). Open Results to inspect."
        } catch {
            statusMessage = "Batch recognition failed: \(error.localizedDescription)"
        }
    }

    private func recognizeViaSingleImage(data: Data, filename: String, contentType: String) async {
        statusMessage = "Uploading full image…"

        do {
            latestResult = try await apiClient.recognizeImage(
                data: data,
                filename: filename,
                contentType: contentType,
                baseURL: apiBaseURL
            )
            associateCropsWithCards()
            statusMessage = "Recognition finished. Open Results to inspect the response."
        } catch {
            statusMessage = "Recognition failed: \(error.localizedDescription)"
        }
    }

    private func associateCropsWithCards() {
        for (index, card) in latestResult.cards.enumerated() {
            if index < lastDetectedCrops.count {
                cardCropImages[card.id] = lastDetectedCrops[index]
            } else if let base64String = card.cropImageData,
                      let data = Data(base64Encoded: base64String),
                      let image = UIImage(data: data) {
                cardCropImages[card.id] = image
            }
        }
    }

    // MARK: - Persistence

    /// Insert recognized cards into SwiftData as inbox items (no collection or deck).
    private func persistRecognizedCards() {
        guard let modelContext else { return }
        for card in latestResult.cards {
            let correction = corrections[card.id]
            let item = CollectionItem(from: card, correction: correction)
            modelContext.insert(item)
        }
    }

}

// MARK: - Card Search and Printings

extension AppModel {
    func searchCardNames(query: String) async throws -> [String] {
        return try await apiClient.searchCardNames(query: query, baseURL: apiBaseURL)
    }

    func fetchPrintings(name: String) async throws -> [CardPrinting] {
        return try await apiClient.fetchPrintings(name: name, baseURL: apiBaseURL)
    }
}

// MARK: - Prices

extension AppModel {
    func fetchPrice(name: String, scryfallId: String?, isFoil: Bool) async throws -> CardPrice {
        return try await apiClient.fetchPrice(
            name: name, scryfallId: scryfallId, isFoil: isFoil, baseURL: apiBaseURL
        )
    }

    func fetchMissingPrices(for items: [CollectionItem]) async {
        for item in items where item.priceRetail == nil && item.priceBuy == nil {
            guard let price = try? await fetchPrice(
                name: item.title, scryfallId: item.scryfallId, isFoil: item.foil
            ) else { continue }
            item.priceRetail = price.priceRetail
            item.priceBuy = price.priceBuy
        }
    }
}

// MARK: - Corrections

extension AppModel {
    func saveCorrection(_ correction: CardCorrection) {
        corrections[correction.id] = correction
        persistCorrections()
    }

    func correction(for card: RecognizedCard) -> CardCorrection {
        corrections[card.id] ?? CardCorrection(from: card)
    }

    func resetAPIBaseURL() {
        apiBaseURL = AppConfig.defaultAPIBaseURL
    }

    private func persistCorrections() {
        guard let data = try? JSONEncoder().encode(corrections) else { return }
        UserDefaults.standard.set(data, forKey: correctionsStoreKey)
    }

    private func persistAPIBaseURL() {
        UserDefaults.standard.set(apiBaseURL, forKey: apiBaseURLStoreKey)
    }

    private func persistOnDeviceCrop() {
        UserDefaults.standard.set(onDeviceCropEnabled, forKey: onDeviceCropStoreKey)
    }

    private func loadCorrections() {
        guard
            let data = UserDefaults.standard.data(forKey: correctionsStoreKey),
            let stored = try? JSONDecoder().decode([UUID: CardCorrection].self, from: data)
        else { return }
        corrections = stored
    }
}

// MARK: - Undo

extension AppModel {
    func registerUndoAction(_ action: @escaping @MainActor () -> Void) {
        latestUndoAction = action
    }

    func undoLatestDelete() {
        guard latestUndoAction != nil else { return }
        showUndoAlert = true
    }

    func confirmUndo() {
        guard let latestUndoAction else { return }
        latestUndoAction()
        self.latestUndoAction = nil
    }

    func resetMotionBurstSettings() {
        motionBurstPreset = .balanced
        motionBurstMotionThreshold = 0.015
        motionBurstMinPeakThreshold = 0.05
    }
}

// MARK: - Motion Burst Preset

public enum MotionBurstPreset: String, CaseIterable, Sendable {
    case fast
    case balanced
    case conservative
    case custom

    public var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .conservative: return "Conservative"
        case .custom: return "Custom"
        }
    }

    var configuration: MotionBurstConfiguration {
        switch self {
        case .fast: return .fast
        case .balanced: return .balanced
        case .conservative: return .conservative
        case .custom: return .balanced // Custom uses stored values
        }
    }
}
