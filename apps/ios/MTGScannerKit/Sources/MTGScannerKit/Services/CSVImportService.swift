import Foundation

struct CSVImportRecord: Sendable {
    let title: String
    let edition: String
    let setCode: String?
    let collectorNumber: String?
    let scryfallId: String?
    let quantity: Int
    let foil: Bool
}

struct CSVImportRow: Identifiable, Sendable {
    let id: Int
    let title: String
    let record: CSVImportRecord?
    var issue: String?
    var printing: CardPrinting?
    var isSkipped = false
}

struct CSVImportService {
    func read(url: URL) async throws -> [CSVImportRow] {
        let task = Task.detached {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try Task.checkCancellation()
            return try CSVImportService().parse(data: data)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func parse(data: Data) throws -> [CSVImportRow] {
        guard var text = String(data: data, encoding: .utf8) else {
            throw CSVImportError(message: "Choose a UTF-8 CSV exported by this app.")
        }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        let records = try CSVParser().parse(text)
        guard let header = records.first else { throw CSVImportError(message: "The CSV is empty.") }
        let columns = try columnMap(header)
        return records.dropFirst().enumerated().compactMap { offset, values in
            guard values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                return nil
            }
            return row(values, columns: columns, width: header.count, number: offset + 2)
        }
    }

    private func columnMap(_ header: [String]) throws -> [String: Int] {
        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(names).count == names.count else {
            throw CSVImportError(message: "The CSV contains duplicate column headers.")
        }
        let required: Set<String> = ["title", "edition", "quantity", "foil"]
        let missing = required.subtracting(names).sorted()
        guard missing.isEmpty else {
            throw CSVImportError(message: "Missing required columns: \(missing.joined(separator: ", ")).")
        }
        return Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, $0.offset) })
    }

    private func row(_ values: [String], columns: [String: Int], width: Int, number: Int) -> CSVImportRow {
        func value(_ key: String) -> String {
            guard let index = columns[key], values.indices.contains(index) else { return "" }
            return values[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = value("title")
        let issue = validationIssue(values: values, width: width, value: value)
        guard issue == nil, let quantity = Int(value("quantity")) else {
            return CSVImportRow(id: number, title: title, record: nil, issue: issue)
        }
        let record = CSVImportRecord(
            title: title, edition: value("edition"), setCode: value("set_code").nonEmpty,
            collectorNumber: value("collector_number").nonEmpty, scryfallId: value("scryfall_id").nonEmpty,
            quantity: quantity, foil: value("foil").lowercased() == "true"
        )
        return CSVImportRow(id: number, title: title, record: record)
    }

    private func validationIssue(values: [String], width: Int, value: (String) -> String) -> String? {
        guard values.count == width else {
            return "Column count does not match the header. Fix the file or skip this row."
        }
        guard !value("title").isEmpty, !value("edition").isEmpty else {
            return "Title and edition are required. Fix the file or skip this row."
        }
        guard let quantity = Int(value("quantity")), quantity > 0 else {
            return "Quantity must be a positive whole number. Fix the file or skip this row."
        }
        guard ["true", "false"].contains(value("foil").lowercased()) else {
            return "Foil must be true or false. Fix the file or skip this row."
        }
        return nil
    }
}
