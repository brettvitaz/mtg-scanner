import Foundation
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var latestResult: RecognitionResult = .sample
    @Published var corrections: [UUID: CardCorrection] = [:]

    /// SwiftData model context, set after app launch.
    var modelContext: ModelContext?
    @Published var apiBaseURL: String {
        didSet { persistAPIBaseURL() }
    }
    @Published var onDeviceCropEnabled: Bool {
        didSet { persistOnDeviceCrop() }
    }
    @Published var quickScanEnabled: Bool {
        didSet { UserDefaults.standard.set(quickScanEnabled, forKey: quickScanEnabledKey) }
    }
    @Published var quickScanCaptureDelay: Double {
        didSet { UserDefaults.standard.set(quickScanCaptureDelay, forKey: quickScanCaptureDelayKey) }
    }
    @Published var quickScanConfidenceThreshold: Double {
        didSet { UserDefaults.standard.set(quickScanConfidenceThreshold, forKey: quickScanConfidenceKey) }
    }
    @Published var isRecognizing = false
    @Published var statusMessage = "Point camera at cards to scan."
    @Published var lastUploadedFilename: String?
    /// Crops detected during the last capture, for display in the preview.
    @Published var lastDetectedCrops: [UIImage] = []
    /// Crop images keyed by the corresponding RecognizedCard.id.
    @Published var cardCropImages: [UUID: UIImage] = [:]
    @Published var shouldShowResults = false
    /// Navigation path for the Results tab — reset to dismiss detail views.
    @Published var resultsNavigationPath = NavigationPath()
    /// When true, shows a connection-unavailable alert.
    @Published var showConnectionAlert = false
    @Published var connectionAlertMessage = ""

    private let apiClient = APIClient()
    private let cropService = CardCropService()
    private let correctionsStoreKey = "card_corrections"
    private let apiBaseURLStoreKey = "api_base_url"
    private let onDeviceCropStoreKey = "on_device_crop_enabled"
    private let quickScanEnabledKey = "quick_scan_enabled"
    private let quickScanCaptureDelayKey = "quick_scan_capture_delay"
    private let quickScanConfidenceKey = "quick_scan_confidence_threshold"

    init() {
        self.apiBaseURL = UserDefaults.standard.string(forKey: apiBaseURLStoreKey) ?? AppConfig.defaultAPIBaseURL
        self.onDeviceCropEnabled = UserDefaults.standard.object(forKey: onDeviceCropStoreKey) as? Bool ?? true
        self.quickScanEnabled = UserDefaults.standard.bool(forKey: quickScanEnabledKey)
        let storedDelay = UserDefaults.standard.double(forKey: quickScanCaptureDelayKey)
        self.quickScanCaptureDelay = Self.clampQuickScanCaptureDelay(storedDelay)
        let storedConf = UserDefaults.standard.double(forKey: quickScanConfidenceKey)
        self.quickScanConfidenceThreshold = Self.clampQuickScanConfidence(storedConf)
        loadCorrections()
    }

    private static func clampQuickScanCaptureDelay(_ value: Double) -> Double {
        guard value > 0 else { return 2.0 }
        return min(max(value, 0.5), 5.0)
    }

    private static func clampQuickScanConfidence(_ value: Double) -> Double {
        guard value > 0 else { return 0.5 }
        return min(max(value, 0.3), 0.9)
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
        await recognizeImage(image: uiImage, filename: filename)
    }

    /// Recognise cards from a UIImage directly (avoids Data round-trip for camera captures).
    ///
    /// When `onDeviceCropEnabled` is true, runs on-device detection first and uploads
    /// crops to the batch endpoint. When false, sends the full image to the single-image endpoint.
    func recognizeImage(image: UIImage, filename: String) async {
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
            let cropResult = await cropService.detectAndCrop(image: image)
            lastDetectedCrops = cropResult.crops
            if !cropResult.crops.isEmpty {
                await recognizeViaBatch(crops: cropResult.crops, baseFilename: filename)
            } else {
                await uploadFullImage(image: image, filename: filename)
            }
        } else {
            statusMessage = "Uploading full image…"
            await uploadFullImage(image: image, filename: filename)
        }

        isRecognizing = false
        persistRecognizedCards()
        shouldShowResults = true
    }

    // MARK: - Private recognition helpers

    private func uploadFullImage(image: UIImage, filename: String) async {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            statusMessage = "Failed to encode image."
            return
        }
        await recognizeViaSingleImage(data: data, filename: filename, contentType: "image/jpeg")
    }

    private func recognizeViaBatch(crops: [UIImage], baseFilename: String) async {
        let stem = (baseFilename as NSString).deletingPathExtension
        var cropPairs: [(data: Data, filename: String)] = []
        for (i, crop) in crops.enumerated() {
            guard let jpegData = crop.jpegData(compressionQuality: 0.9) else { continue }
            cropPairs.append((data: jpegData, filename: "\(stem)-crop-\(i).jpg"))
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

    // MARK: - Printings

    func fetchPrintings(name: String) async throws -> [CardPrinting] {
        return try await apiClient.fetchPrintings(name: name, baseURL: apiBaseURL)
    }

    // MARK: - Prices

    func fetchPrice(name: String, scryfallId: String?, isFoil: Bool) async throws -> CardPrice {
        return try await apiClient.fetchPrice(
            name: name, scryfallId: scryfallId, isFoil: isFoil, baseURL: apiBaseURL
        )
    }

    // MARK: - Corrections

    func saveCorrection(_ correction: CardCorrection) {
        corrections[correction.id] = correction
        persistCorrections()
    }

    func correction(for card: RecognizedCard) -> CardCorrection {
        corrections[card.id] ?? CardCorrection(from: card)
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

    func resetAPIBaseURL() {
        apiBaseURL = AppConfig.defaultAPIBaseURL
    }

    private func loadCorrections() {
        guard
            let data = UserDefaults.standard.data(forKey: correctionsStoreKey),
            let stored = try? JSONDecoder().decode([UUID: CardCorrection].self, from: data)
        else { return }
        corrections = stored
    }
}
