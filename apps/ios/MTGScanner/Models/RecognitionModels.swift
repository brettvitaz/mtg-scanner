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
            notes: "Mocked recognition result for upload 'lightning-bolt.jpg' (image/jpeg).",
            setCode: "M10",
            rarity: "common",
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            manaCost: "{R}",
            imageUrl: "https://api.scryfall.com/cards/e3285e6b-3e79-4d7c-bf96-d920f973b122?format=image&version=normal",
            setSymbolUrl: "https://svgs.scryfall.io/sets/m10.svg"
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
    let setCode: String?
    let rarity: String?
    let typeLine: String?
    let oracleText: String?
    let manaCost: String?
    let power: String?
    let toughness: String?
    let loyalty: String?
    let defense: String?
    let scryfallId: String?
    let imageUrl: String?
    let setSymbolUrl: String?
    let cardKingdomUrl: String?
    let cardKingdomFoilUrl: String?
    let cropImageData: String?

    init(
        id: UUID = UUID(),
        title: String? = nil,
        edition: String? = nil,
        collectorNumber: String? = nil,
        foil: Bool? = nil,
        confidence: Double = 0,
        notes: String? = nil,
        setCode: String? = nil,
        rarity: String? = nil,
        typeLine: String? = nil,
        oracleText: String? = nil,
        manaCost: String? = nil,
        power: String? = nil,
        toughness: String? = nil,
        loyalty: String? = nil,
        defense: String? = nil,
        scryfallId: String? = nil,
        imageUrl: String? = nil,
        setSymbolUrl: String? = nil,
        cardKingdomUrl: String? = nil,
        cardKingdomFoilUrl: String? = nil,
        cropImageData: String? = nil
    ) {
        self.id = id
        self.title = title
        self.edition = edition
        self.collectorNumber = collectorNumber
        self.foil = foil
        self.confidence = confidence
        self.notes = notes
        self.setCode = setCode
        self.rarity = rarity
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.manaCost = manaCost
        self.power = power
        self.toughness = toughness
        self.loyalty = loyalty
        self.defense = defense
        self.scryfallId = scryfallId
        self.imageUrl = imageUrl
        self.setSymbolUrl = setSymbolUrl
        self.cardKingdomUrl = cardKingdomUrl
        self.cardKingdomFoilUrl = cardKingdomFoilUrl
        self.cropImageData = cropImageData
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
        self.setCode = try container.decodeIfPresent(String.self, forKey: .setCode)
        self.rarity = try container.decodeIfPresent(String.self, forKey: .rarity)
        self.typeLine = try container.decodeIfPresent(String.self, forKey: .typeLine)
        self.oracleText = try container.decodeIfPresent(String.self, forKey: .oracleText)
        self.manaCost = try container.decodeIfPresent(String.self, forKey: .manaCost)
        self.power = try container.decodeIfPresent(String.self, forKey: .power)
        self.toughness = try container.decodeIfPresent(String.self, forKey: .toughness)
        self.loyalty = try container.decodeIfPresent(String.self, forKey: .loyalty)
        self.defense = try container.decodeIfPresent(String.self, forKey: .defense)
        self.scryfallId = try container.decodeIfPresent(String.self, forKey: .scryfallId)
        self.imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        self.setSymbolUrl = try container.decodeIfPresent(String.self, forKey: .setSymbolUrl)
        self.cardKingdomUrl = try container.decodeIfPresent(String.self, forKey: .cardKingdomUrl)
        self.cardKingdomFoilUrl = try container.decodeIfPresent(String.self, forKey: .cardKingdomFoilUrl)
        self.cropImageData = try container.decodeIfPresent(String.self, forKey: .cropImageData)
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
        try container.encodeIfPresent(setCode, forKey: .setCode)
        try container.encodeIfPresent(rarity, forKey: .rarity)
        try container.encodeIfPresent(typeLine, forKey: .typeLine)
        try container.encodeIfPresent(oracleText, forKey: .oracleText)
        try container.encodeIfPresent(manaCost, forKey: .manaCost)
        try container.encodeIfPresent(power, forKey: .power)
        try container.encodeIfPresent(toughness, forKey: .toughness)
        try container.encodeIfPresent(loyalty, forKey: .loyalty)
        try container.encodeIfPresent(defense, forKey: .defense)
        try container.encodeIfPresent(scryfallId, forKey: .scryfallId)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(setSymbolUrl, forKey: .setSymbolUrl)
        try container.encodeIfPresent(cardKingdomUrl, forKey: .cardKingdomUrl)
        try container.encodeIfPresent(cardKingdomFoilUrl, forKey: .cardKingdomFoilUrl)
        try container.encodeIfPresent(cropImageData, forKey: .cropImageData)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case edition
        case collectorNumber = "collector_number"
        case foil
        case confidence
        case notes
        case setCode = "set_code"
        case rarity
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case manaCost = "mana_cost"
        case power
        case toughness
        case loyalty
        case defense
        case scryfallId = "scryfall_id"
        case imageUrl = "image_url"
        case setSymbolUrl = "set_symbol_url"
        case cardKingdomUrl = "card_kingdom_url"
        case cardKingdomFoilUrl = "card_kingdom_foil_url"
        case cropImageData = "crop_image_data"
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

/// A printing of a card from the printings endpoint.
struct CardPrinting: Codable, Identifiable {
    var id: String { "\(setCode)-\(collectorNumber ?? "unknown")" }
    let name: String
    let setCode: String
    let setName: String?
    let collectorNumber: String?
    let rarity: String?
    let typeLine: String?
    let oracleText: String?
    let manaCost: String?
    let power: String?
    let toughness: String?
    let loyalty: String?
    let defense: String?
    let scryfallId: String?
    let imageUrl: String?
    let setSymbolUrl: String?
    let cardKingdomUrl: String?
    let cardKingdomFoilUrl: String?

    enum CodingKeys: String, CodingKey {
        case name
        case setCode = "set_code"
        case setName = "set_name"
        case collectorNumber = "collector_number"
        case rarity
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case manaCost = "mana_cost"
        case power
        case toughness
        case loyalty
        case defense
        case scryfallId = "scryfall_id"
        case imageUrl = "image_url"
        case setSymbolUrl = "set_symbol_url"
        case cardKingdomUrl = "card_kingdom_url"
        case cardKingdomFoilUrl = "card_kingdom_foil_url"
    }
}

/// Response from the printings endpoint.
struct CardPrintingsResponse: Codable {
    let printings: [CardPrinting]
}
