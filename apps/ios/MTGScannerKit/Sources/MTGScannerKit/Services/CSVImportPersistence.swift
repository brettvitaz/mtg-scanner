import SwiftData

@MainActor
struct CSVImportPersistence {
    func preparedItems(_ rows: [CSVImportRow]) throws -> [CardItemSnapshot] {
        let active = rows.filter { !$0.isSkipped }
        guard !active.isEmpty else { throw CSVImportError(message: "Resolve at least one row to import.") }
        return try active.map { row in
            guard let record = row.record, let printing = row.printing,
                  record.quantity > 0, CSVPrintingResolver().supportsFinish(record, printing: printing) else {
                throw CSVImportError(message: "Resolve or skip every row before importing.")
            }
            return CardItemSnapshot(CollectionItem(from: printing, foil: record.foil, quantity: record.quantity))
        }
    }

    func save(
        rows: [CSVImportRow], to destination: CardListReference, context: ModelContext,
        commit: () throws -> Void
    ) throws -> Int {
        let plan = try CardListOperationPlanner().plan(
            target: destination.snapshot(), toolItems: preparedItems(rows), toolName: "CSV", operation: .add
        )
        return try CardListOperationPersistence().apply(plan, context: context, commit: commit).plan.affectedQuantity
    }
}
