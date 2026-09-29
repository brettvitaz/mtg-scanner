import Foundation
@testable import MTGScannerKit

enum CSVImportTestFixtures {
    static func printing(
        number: String = "146", identifier: String = "bolt-146", finishes: String? = "nonfoil,foil"
    ) throws -> CardPrinting {
        let fields: [String: Any] = [
            "name": "Lightning Bolt", "set_code": "M10", "set_name": "Magic 2010",
            "collector_number": number, "scryfall_id": identifier, "rarity": "common", "type_line": "Instant",
            "mana_cost": "{R}", "oracle_text": "Deal 3 damage.", "image_url": "https://example.com/bolt.jpg",
            "finishes": (finishes as Any?) ?? NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(CardPrinting.self, from: data)
    }

    static func record(
        quantity: Int = 2, foil: Bool = false, number: String? = nil, identifier: String? = nil
    ) -> CSVImportRecord {
        CSVImportRecord(
            title: "Lightning Bolt", edition: "Magic 2010", setCode: "M10", collectorNumber: number,
            scryfallId: identifier, quantity: quantity, foil: foil
        )
    }

    static func row(id: Int = 2, quantity: Int = 2, foil: Bool = false) throws -> CSVImportRow {
        CSVImportRow(
            id: id, title: "Lightning Bolt", record: record(quantity: quantity, foil: foil), printing: try printing()
        )
    }
}
