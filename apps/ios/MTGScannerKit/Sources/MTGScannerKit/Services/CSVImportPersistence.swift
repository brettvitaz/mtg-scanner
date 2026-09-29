import Foundation
import SwiftData

@MainActor
enum CSVImportDestination {
    case collection(CardCollection)
    case deck(Deck)

    var name: String {
        switch self {
        case .collection(let collection): collection.name
        case .deck(let deck): deck.name
        }
    }

    var items: [CollectionItem] {
        switch self {
        case .collection(let collection): collection.items
        case .deck(let deck): deck.items
        }
    }

    var updatedAt: Date {
        get {
            switch self {
            case .collection(let collection): collection.updatedAt
            case .deck(let deck): deck.updatedAt
            }
        }
        nonmutating set {
            switch self {
            case .collection(let collection): collection.updatedAt = newValue
            case .deck(let deck): deck.updatedAt = newValue
            }
        }
    }

    func assign(_ item: CollectionItem) {
        switch self {
        case .collection(let collection): item.collection = collection
        case .deck(let deck): item.deck = deck
        }
    }
}

@MainActor
struct CSVImportPersistence {
    func save(
        rows: [CSVImportRow], to destination: CSVImportDestination, context: ModelContext,
        commit: () throws -> Void
    ) throws -> Int {
        let additions = try preparedItems(rows)
        try validateQuantities(additions, existing: destination.items)
        let importedQuantity = additions.reduce(0) { $0 + $1.quantity }
        let originals = destination.items.map { ($0, $0.quantity) }
        let timestamp = destination.updatedAt
        var inserted: [CollectionItem] = []
        do {
            inserted = apply(additions, to: destination, context: context)
            destination.updatedAt = Date()
            try commit()
        } catch {
            for (item, quantity) in originals { item.quantity = quantity }
            for item in inserted { item.collection = nil; item.deck = nil; context.delete(item) }
            destination.updatedAt = timestamp
            throw error
        }
        return importedQuantity
    }

    private func apply(
        _ additions: [CollectionItem], to destination: CSVImportDestination, context: ModelContext
    ) -> [CollectionItem] {
        var siblings = destination.items
        var inserted: [CollectionItem] = []
        for item in additions {
            if let existing = siblings.first(where: { $0.matches(item) }) {
                existing.quantity = max(1, existing.quantity) + item.quantity
                continue
            }
            destination.assign(item)
            context.insert(item)
            inserted.append(item)
            siblings.append(item)
        }
        return inserted
    }

    private func preparedItems(_ rows: [CSVImportRow]) throws -> [CollectionItem] {
        let active = rows.filter { !$0.isSkipped }
        guard !active.isEmpty else { throw CSVImportError(message: "Resolve at least one row to import.") }
        return try active.map { row in
            guard let record = row.record, let printing = row.printing,
                  CSVPrintingResolver().supportsFinish(record, printing: printing) else {
                throw CSVImportError(message: "Resolve or skip every row before importing.")
            }
            return CollectionItem(from: printing, foil: record.foil, quantity: record.quantity)
        }
    }

    private func validateQuantities(_ additions: [CollectionItem], existing: [CollectionItem]) throws {
        var totals: [(CollectionItem, Int)] = existing.map { ($0, max(1, $0.quantity)) }
        var total = 0
        for item in additions {
            total = try adding(total, item.quantity)
            if let index = totals.firstIndex(where: { $0.0.matches(item) }) {
                totals[index].1 = try adding(totals[index].1, item.quantity)
            } else {
                totals.append((item, item.quantity))
            }
        }
        // The destination quantity total must also remain representable.
        _ = try totals.reduce(0) { try adding($0, $1.1) }
    }

    private func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard rhs > 0, !result.overflow else {
            throw CSVImportError(message: "The imported quantity is too large. Reduce it in the CSV and try again.")
        }
        return result.partialValue
    }
}
