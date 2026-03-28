import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var latestResult: RecognitionResult = .sample
    @Published var corrections: [UUID: CardCorrection] = [:]
    @Published var apiBaseURL: String {
        didSet { persistAPIBaseURL() }
    }
    @Published var isRecognizing = false
    @Published var statusMessage = "Point camera at cards to scan."
    @Published var lastUploadedFilename: String?
    /// Crops detected during the last capture, for display in the preview.
    @Published var lastDetectedCrops: [UIImage] = []
    @Published var shouldShowResults = false

    private let apiClient = APIClient()
    private let cropService = CardCropService()
    private let correctionsStoreKey = "card_corrections"
    private let apiBaseURLStoreKey = "api_base_url"

    init() {
        self.apiBaseURL = UserDefaults.standard.string(forKey: apiBaseURLStoreKey) ?? AppConfig.defaultAPIBaseURL
        loadCorrections()
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
    func recognizeImage(image: UIImage, filename: String) async {
        isRecognizing = true
        lastDetectedCrops = []
        statusMessage = "Detecting cards…"
        lastUploadedFilename = filename

        let cropResult = await cropService.detectAndCrop(image: image)
        lastDetectedCrops = cropResult.crops

        if !cropResult.crops.isEmpty {
            await recognizeViaBatch(crops: cropResult.crops, baseFilename: filename)
        } else {
            // No crops found — upload the full image.
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                statusMessage = "Failed to encode image."
                isRecognizing = false
                return
            }
            let contentType = "image/jpeg"
            await recognizeViaSingleImage(data: data, filename: filename, contentType: contentType)
        }

        isRecognizing = false
        shouldShowResults = true
    }

    // MARK: - Private recognition helpers

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
            statusMessage = "Recognition finished (\(cropPairs.count) crop(s)). Open Results to inspect."
        } catch {
            statusMessage = "Batch recognition failed: \(error.localizedDescription)"
        }
    }

    private func recognizeViaSingleImage(data: Data, filename: String, contentType: String) async {
        statusMessage = "No crops found — uploading full image…"

        do {
            latestResult = try await apiClient.recognizeImage(
                data: data,
                filename: filename,
                contentType: contentType,
                baseURL: apiBaseURL
            )
            statusMessage = "Recognition finished. Open Results to inspect the response."
        } catch {
            statusMessage = "Recognition failed: \(error.localizedDescription)"
        }
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
