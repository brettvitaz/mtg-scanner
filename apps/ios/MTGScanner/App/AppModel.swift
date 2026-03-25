import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var latestResult: RecognitionResult = .sample
    @Published var apiBaseURL: String = AppConfig.defaultAPIBaseURL
    @Published var isRecognizing = false
    @Published var statusMessage = "Pick a card photo to start a mocked scan."
    @Published var lastUploadedFilename: String?

    private let apiClient = APIClient()

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
            statusMessage = "Recognition finished. Open Results to inspect the mocked API response."
        } catch {
            statusMessage = "Recognition failed: \(error.localizedDescription)"
        }

        isRecognizing = false
    }

    func loadSampleResult() {
        latestResult = .sample
        statusMessage = "Loaded the local sample response without calling the API."
    }
}
