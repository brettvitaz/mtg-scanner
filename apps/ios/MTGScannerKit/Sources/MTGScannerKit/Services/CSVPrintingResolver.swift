import Foundation

struct CSVPrintingResolver {
    func resolve(_ record: CSVImportRecord, among printings: [CardPrinting]) -> CardPrinting? {
        let candidates = printings.filter { matches(record, printing: $0) }
        guard candidates.count == 1, let printing = candidates.first,
              supportsFinish(record, printing: printing) else { return nil }
        return printing
    }

    func supportsFinish(_ record: CSVImportRecord, printing: CardPrinting) -> Bool {
        record.foil ? printing.hasFoil : printing.hasNonFoil
    }

    private func matches(_ record: CSVImportRecord, printing: CardPrinting) -> Bool {
        guard normalized(record.title) == normalized(printing.name) else { return false }
        if let identifier = record.scryfallId,
           normalized(identifier) != normalized(printing.scryfallId ?? "") { return false }
        if let code = record.setCode {
            guard normalized(code) == normalized(printing.setCode) else { return false }
        } else {
            guard normalized(record.edition) == normalized(printing.setName ?? "")
                    || normalized(record.edition) == normalized(printing.setCode) else { return false }
        }
        if let number = record.collectorNumber {
            guard normalized(number) == normalized(printing.collectorNumber ?? "") else { return false }
        }
        return true
    }

    private func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
