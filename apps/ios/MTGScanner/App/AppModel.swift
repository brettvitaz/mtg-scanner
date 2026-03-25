import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var latestResult: RecognitionResult = .sample
    @Published var corrections: [UUID: CardCorrection] = [:]
    @Published var apiBaseURL: String = AppConfig.defaultAPIBaseURL
    @Published var isRecognizing = false
    @Published var statusMessage = "Pick a card photo to start a mocked scan."
    @Published var lastUploadedFilename: String?

    private let apiClient = APIClient()
    private let correctionsStoreKey = "card_corrections"

    init() {
        loadCorrections()
    }

    func recognizeImage(data: Data, filename: String, contentType: String) async {
        isRecognizing = true
        statusMessage = "Uploading \(filename)…"
        lastUploadedFilename = filename

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

        isRecognizing = false
    }

    func loadSampleResult() {
        latestResult = .sample
        statusMessage = "Loaded the local sample response without calling the API."
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

    private func loadCorrections() {
        guard
            let data = UserDefaults.standard.data(forKey: correctionsStoreKey),
            let stored = try? JSONDecoder().decode([UUID: CardCorrection].self, from: data)
        else { return }
        corrections = stored
    }
}
