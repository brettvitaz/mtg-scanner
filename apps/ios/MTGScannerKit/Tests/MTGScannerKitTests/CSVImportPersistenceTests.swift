import SwiftData
import XCTest
@testable import MTGScannerKit

final class CSVImportPersistenceTests: XCTestCase {
    @MainActor
    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    @MainActor
    func testCollectionMergesExistingAndRepeatedRowsAndKeepsFoilSeparate() throws {
        let context = try context()
        let collection = CardCollection(name: "Binder")
        context.insert(collection)
        let existing = CollectionItem(from: try CSVImportTestFixtures.printing(), foil: false, quantity: 3)
        existing.collection = collection
        context.insert(existing)
        try context.save()
        let rows = try [
            CSVImportTestFixtures.row(), CSVImportTestFixtures.row(id: 3, quantity: 4),
            CSVImportTestFixtures.row(id: 4, quantity: 1, foil: true)
        ]
        let count = try CSVImportPersistence().save(
            rows: rows, to: .collection(collection), context: context, commit: context.save
        )
        XCTAssertEqual(count, 7)
        XCTAssertEqual(collection.items.count, 2)
        XCTAssertEqual(existing.quantity, 9)
        let foil = try XCTUnwrap(collection.items.first(where: \.foil))
        XCTAssertEqual(foil.quantity, 1)
        XCTAssertEqual(foil.oracleText, "Deal 3 damage.")
        XCTAssertEqual(foil.collectorNumber, "146")
        XCTAssertNil(foil.deck)
    }

    @MainActor
    func testDeckMergesNewRepeatedRowsAndSkipsInvalidRow() throws {
        let context = try context()
        let deck = Deck(name: "Deck")
        context.insert(deck)
        let before = deck.updatedAt
        var skipped = CSVImportRow(id: 4, title: "Invalid", record: nil, issue: "Invalid")
        skipped.isSkipped = true
        let rows = try [CSVImportTestFixtures.row(), CSVImportTestFixtures.row(id: 3), skipped]
        let count = try CSVImportPersistence().save(
            rows: rows, to: .deck(deck), context: context, commit: context.save
        )
        XCTAssertEqual(count, 4)
        XCTAssertEqual(deck.items.count, 1)
        XCTAssertEqual(deck.items.first?.quantity, 4)
        XCTAssertNil(deck.items.first?.collection)
        XCTAssertGreaterThanOrEqual(deck.updatedAt, before)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testCommitFailureRestoresExistingQuantitiesRelationshipsAndTimestamp() throws {
        let context = try context()
        let deck = Deck(name: "Deck")
        context.insert(deck)
        let existing = CollectionItem(from: try CSVImportTestFixtures.printing(), foil: false, quantity: 3)
        existing.deck = deck
        context.insert(existing)
        try context.save()
        let timestamp = deck.updatedAt
        let rows = try [CSVImportTestFixtures.row(), CSVImportTestFixtures.row(id: 3, foil: true)]
        XCTAssertThrowsError(try CSVImportPersistence().save(rows: rows, to: .deck(deck), context: context) {
            throw CSVImportError(message: "Disk full")
        })
        XCTAssertEqual(existing.quantity, 3)
        XCTAssertEqual(deck.updatedAt, timestamp)
        XCTAssertEqual(deck.items.count, 1)
        try context.save()
        let items = try context.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.quantity, 3)
    }

    @MainActor
    func testOverflowFailsBeforeAnyMutationOrCommit() throws {
        let context = try context()
        let collection = CardCollection(name: "Binder")
        context.insert(collection)
        let existing = CollectionItem(from: try CSVImportTestFixtures.printing(), foil: false, quantity: Int.max)
        existing.collection = collection
        context.insert(existing)
        try context.save()
        let row = try CSVImportTestFixtures.row(quantity: 1)
        var committed = false
        XCTAssertThrowsError(try CSVImportPersistence().save(
            rows: [row], to: .collection(collection), context: context, commit: { committed = true }
        ))
        XCTAssertFalse(committed)
        XCTAssertEqual(existing.quantity, Int.max)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testUnresolvedAndAllSkippedImportsAreRejected() throws {
        let context = try context()
        let deck = Deck(name: "Deck")
        context.insert(deck)
        var row = CSVImportRow(id: 2, title: "Bolt", record: CSVImportTestFixtures.record())
        XCTAssertThrowsError(try CSVImportPersistence().save(
            rows: [row], to: .deck(deck), context: context, commit: context.save
        ))
        row.isSkipped = true
        XCTAssertThrowsError(try CSVImportPersistence().save(
            rows: [row], to: .deck(deck), context: context, commit: context.save
        ))
        XCTAssertTrue(deck.items.isEmpty)
    }
}
