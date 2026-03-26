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
    let id: UUID
    let title: String?
    let edition: String?
    let collectorNumber: String?
    let foil: Bool?
    let confidence: Double
    let notes: String?

    init(
        id: UUID = UUID(),
        title: String? = nil,
        edition: String? = nil,
        collectorNumber: String? = nil,
        foil: Bool? = nil,
        confidence: Double = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.edition = edition
        self.collectorNumber = collectorNumber
        self.foil = foil
        self.confidence = confidence
        self.notes = notes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.edition = try container.decodeIfPresent(String.self, forKey: .edition)
        self.collectorNumber = try container.decodeIfPresent(String.self, forKey: .collectorNumber)
        self.foil = try container.decodeIfPresent(Bool.self, forKey: .foil)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(edition, forKey: .edition)
        try container.encodeIfPresent(collectorNumber, forKey: .collectorNumber)
        try container.encodeIfPresent(foil, forKey: .foil)
        try container.encode(confidence, forKey: .confidence)
        try container.encodeIfPresent(notes, forKey: .notes)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case edition
        case collectorNumber = "collector_number"
        case foil
        case confidence
        case notes
    }
}

/// Mutable correction overlay for a recognized card.
struct CardCorrection: Identifiable, Codable {
    let id: UUID           // matches RecognizedCard.id
    var title: String
    var edition: String
    var collectorNumber: String
    var foil: Bool

    init(from card: RecognizedCard) {
        self.id = card.id
        self.title = card.title ?? ""
        self.edition = card.edition ?? ""
        self.collectorNumber = card.collectorNumber ?? ""
        self.foil = card.foil ?? false
    }
}
