import Foundation
@testable import MTGScannerKit

/// Card recognizer that forwards each call to a test-supplied closure.
struct StubCardRecognizer: CardRecognizer {
    var recognize: @Sendable (Data, String, String) async throws -> RecognitionResult
    var recognizeBatch: @Sendable ([(data: Data, filename: String)], String) async throws -> RecognitionResult
        = { _, _ in throw URLError(.unsupportedURL) }

    func recognizeImage(data: Data, filename: String, contentType: String) async throws -> RecognitionResult {
        try await recognize(data, filename, contentType)
    }

    func recognizeBatch(
        crops: [(data: Data, filename: String)],
        contentType: String
    ) async throws -> RecognitionResult {
        try await recognizeBatch(crops, contentType)
    }
}
