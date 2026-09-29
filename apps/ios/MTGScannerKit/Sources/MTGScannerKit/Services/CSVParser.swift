import Foundation

struct CSVImportError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

struct CSVParser {
    func parse(_ text: String) throws -> [[String]] {
        var reader = CSVReader()
        // Normalize record separators; preserve embedded newlines as newlines.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for character in normalized {
            try reader.consume(character)
        }
        return try reader.finish()
    }
}

private struct CSVReader {
    enum State { case unquoted, quoted, closedQuote }
    var state: State = .unquoted
    var field = ""
    var record: [String] = []
    var records: [[String]] = []
    var hasContent = false

    mutating func consume(_ character: Character) throws {
        if state == .quoted {
            if character == "\"" { state = .closedQuote } else { field.append(character) }
            return
        }
        if state == .closedQuote && character == "\"" {
            field.append(character)
            state = .quoted
            return
        }
        if character == "," { appendField(); hasContent = true; return }
        if character == "\n" { appendRecord(); return }
        guard state != .closedQuote else { throw malformed() }
        if character == "\"" {
            guard field.isEmpty else { throw malformed() }
            state = .quoted
        } else {
            field.append(character)
        }
        hasContent = true
    }

    mutating func finish() throws -> [[String]] {
        guard state != .quoted else { throw malformed() }
        if hasContent || !record.isEmpty || !field.isEmpty { appendRecord() }
        return records
    }

    mutating func appendField() {
        record.append(field)
        field = ""
        state = .unquoted
    }

    mutating func appendRecord() {
        appendField()
        records.append(record)
        record = []
        hasContent = false
    }

    func malformed() -> CSVImportError {
        CSVImportError(message: "Malformed CSV at record \(records.count + 1). Check quoted fields and try again.")
    }
}
