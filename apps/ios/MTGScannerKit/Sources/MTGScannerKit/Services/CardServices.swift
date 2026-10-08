import Foundation

/// Identifies cards in captured images.
protocol CardRecognizer: Sendable {
    func recognizeImage(data: Data, filename: String, contentType: String) async throws -> RecognitionResult

    /// Recognizes pre-cropped card images and merges them into one result.
    func recognizeBatch(
        crops: [(data: Data, filename: String)],
        contentType: String
    ) async throws -> RecognitionResult
}

/// Looks up card names and their printings.
protocol CardCatalog: Sendable {
    func searchCardNames(query: String) async throws -> [String]
    func fetchPrintings(name: String) async throws -> [CardPrinting]
}

/// Looks up the price of a card printing.
protocol PriceSource: Sendable {
    func fetchPrice(name: String, scryfallId: String?, isFoil: Bool) async throws -> CardPrice
}
