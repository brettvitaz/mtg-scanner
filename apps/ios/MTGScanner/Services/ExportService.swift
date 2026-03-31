import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case csv = "CSV"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .csv: return "csv"
        }
    }

    var mimeType: String {
        switch self {
        case .json: return "application/json"
        case .csv: return "text/csv"
        }
    }
}

struct ExportService {

    func export(items: [CollectionItem], format: ExportFormat, name: String) -> ExportFile? {
        let data: Data?
        switch format {
        case .json: data = exportJSON(items: items)
        case .csv: data = exportCSV(items: items)
        }
        guard let data else { return nil }
        return ExportFile(
            data: data,
            filename: "\(name).\(format.fileExtension)",
            mimeType: format.mimeType
        )
    }

    // MARK: - JSON

    private func exportJSON(items: [CollectionItem]) -> Data? {
        let records = items.map { ExportRecord(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(records)
    }

    // MARK: - CSV

    private func exportCSV(items: [CollectionItem]) -> Data? {
        var lines: [String] = []
        lines.append(csvHeader)
        for item in items {
            lines.append(csvRow(for: item))
        }
        return lines.joined(separator: "\n").data(using: .utf8)
    }

    private var csvHeader: String {
        "title,edition,set_code,collector_number,foil,rarity,mana_cost,type_line,scryfall_id"
    }

    private func csvRow(for item: CollectionItem) -> String {
        [
            csvEscape(item.title),
            csvEscape(item.edition),
            csvEscape(item.setCode ?? ""),
            csvEscape(item.collectorNumber ?? ""),
            item.foil ? "true" : "false",
            csvEscape(item.rarity ?? ""),
            csvEscape(item.manaCost ?? ""),
            csvEscape(item.typeLine ?? ""),
            csvEscape(item.scryfallId ?? "")
        ].joined(separator: ",")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

// MARK: - Supporting Types

struct ExportFile {
    let data: Data
    let filename: String
    let mimeType: String
}

struct ExportRecord: Codable {
    let title: String
    let edition: String
    let setCode: String?
    let collectorNumber: String?
    let foil: Bool
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
    let addedAt: Date

    init(from item: CollectionItem) {
        self.title = item.title
        self.edition = item.edition
        self.setCode = item.setCode
        self.collectorNumber = item.collectorNumber
        self.foil = item.foil
        self.rarity = item.rarity
        self.typeLine = item.typeLine
        self.oracleText = item.oracleText
        self.manaCost = item.manaCost
        self.power = item.power
        self.toughness = item.toughness
        self.loyalty = item.loyalty
        self.defense = item.defense
        self.scryfallId = item.scryfallId
        self.imageUrl = item.imageUrl
        self.addedAt = item.addedAt
    }

    enum CodingKeys: String, CodingKey {
        case title, edition, foil, rarity, power, toughness, loyalty, defense
        case setCode = "set_code"
        case collectorNumber = "collector_number"
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case manaCost = "mana_cost"
        case scryfallId = "scryfall_id"
        case imageUrl = "image_url"
        case addedAt = "added_at"
    }
}
