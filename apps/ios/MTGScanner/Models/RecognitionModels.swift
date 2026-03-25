import Foundation

struct RecognitionResult: Codable {
    let cards: [RecognizedCard]

    static let sample = RecognitionResult(cards: [
        RecognizedCard(
            title: "Lightning Bolt",
            edition: "Magic 2010",
            collectorNumber: "146",
            foil: false,
            confidence: 0.98,
            notes: "Mocked recognition result for upload 'lightning-bolt.jpg' (image/jpeg)."
        )
    ])
}

struct RecognizedCard: Codable, Identifiable {
    let id = UUID()
    let title: String?
    let edition: String?
    let collectorNumber: String?
    let foil: Bool?
    let confidence: Double
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case title
        case edition
        case collectorNumber = "collector_number"
        case foil
        case confidence
        case notes
    }
}
