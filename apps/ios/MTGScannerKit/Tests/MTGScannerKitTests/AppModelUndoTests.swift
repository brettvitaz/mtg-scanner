import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class AppModelUndoTests: XCTestCase {
    func testEachListKeepsOnlyItsLatestDeletion() {
        let store = AppModel().deleteUndo
        let collection = CardDeleteUndoScope.collection(UUID())
        let otherCollection = CardDeleteUndoScope.collection(UUID())
        let deck = CardDeleteUndoScope.deck(UUID())
        let first = CollectionItem(title: "First", edition: "Test")
        let latest = CollectionItem(title: "Latest", edition: "Test")
        for scope in [CardDeleteUndoScope.results, collection, otherCollection, deck] {
            store.register([first], in: scope)
        }
        store.register([latest], in: collection)
        XCTAssertEqual(store.deletion(in: collection)?.items.first?.id, latest.id)
        for scope in [CardDeleteUndoScope.results, otherCollection, deck] {
            XCTAssertEqual(store.deletion(in: scope)?.items.first?.id, first.id)
        }
        store.register([], in: collection)
        XCTAssertEqual(store.deletion(in: collection)?.items.first?.id, latest.id)
    }

    func testNavigationDisablesUndoElsewhereAndPreservesItOnReturn() {
        let store = CardDeleteUndoStore()
        let item = CollectionItem(title: "Bolt", edition: "Test")
        store.register([item], in: .results)
        var availability = CardDeleteUndoAvailability(selectedTab: 1)
        XCTAssertTrue(availability.allows(.results))
        for tab in [0, 2, 3] {
            availability.selectedTab = tab
            XCTAssertFalse(availability.allows(.results))
        }
        availability.selectedTab = 1
        XCTAssertTrue(availability.allows(.results))
        XCTAssertEqual(store.deletion(in: .results)?.items.first?.id, item.id)
    }

    func testHiddenPagesPresentationsInactiveSceneAndTextEditingBlockUndo() {
        let scope = CardDeleteUndoScope.deck(UUID())
        XCTAssertTrue(CardDeleteUndoAvailability(selectedTab: 2).allows(scope))
        let blockedStates = [
            CardDeleteUndoAvailability(selectedTab: nil),
            CardDeleteUndoAvailability(selectedTab: 2, pageVisible: false),
            CardDeleteUndoAvailability(selectedTab: 2, blocked: true),
            CardDeleteUndoAvailability(selectedTab: 2, sceneActive: false),
            CardDeleteUndoAvailability(selectedTab: 2, editingText: true)
        ]
        for availability in blockedStates {
            XCTAssertFalse(availability.allows(scope))
            XCTAssertFalse(availability.allowsShake(scope, shakeEnabled: true))
        }
        let available = CardDeleteUndoAvailability(selectedTab: 2)
        XCTAssertFalse(available.allowsShake(scope, shakeEnabled: false))
        XCTAssertTrue(available.allowsShake(scope, shakeEnabled: true))
    }

    func testMessagesDescribeSingleCardAndBulkEntriesRatherThanQuantity() throws {
        let store = CardDeleteUndoStore()
        let card = CollectionItem(title: "Lightning Bolt", edition: "M10", quantity: 4)
        store.register([card], in: .results)
        XCTAssertEqual(try XCTUnwrap(store.deletion(in: .results)).message(destination: "Results"),
                       "Restore “Lightning Bolt” to Results?")
        store.register([card, CollectionItem(title: "Island", edition: "Test")], in: .results)
        XCTAssertEqual(try XCTUnwrap(store.deletion(in: .results)).message(destination: "Trade Binder"),
                       "Restore 2 deleted entries to “Trade Binder”?")
    }

    func testSavedSingleAndBulkDeletesRestoreSnapshotsAndRelationshipsInEveryList() throws {
        let context = try makeContext()
        let collection = CardCollection(name: "Binder")
        let deck = Deck(name: "Deck")
        context.insert(collection)
        context.insert(deck)
        let scopes: [CardDeleteUndoScope] = [.results, .collection(collection.id), .deck(deck.id)]
        for scope in scopes {
            for count in [1, 3] {
                try assertRestoration(count: count, scope: scope, context: context)
            }
        }
    }

    func testRestoreFlushesUnsavedDeletionBeforeRestoring() throws {
        let context = try makeContext()
        let item = CollectionItem(title: "Bolt", edition: "Test")
        context.insert(item)
        try context.save()
        let store = CardDeleteUndoStore()
        store.register([item], in: .results)
        context.delete(item)
        let deletion = try XCTUnwrap(store.deletion(in: .results))
        try store.restore(in: .results, deletionID: deletion.id, context: context, commit: context.save)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionItem>()).map(\.id), [item.id])
    }

    func testCancellationAndStaleConfirmationDoNotConsumeReplacement() throws {
        let context = try makeContext()
        let store = CardDeleteUndoStore()
        let item = CollectionItem(title: "First", edition: "Test")
        store.register([item], in: .results)
        let cancelled = try XCTUnwrap(store.deletion(in: .results))
        XCTAssertEqual(store.deletion(in: .results)?.id, cancelled.id)
        store.register([CollectionItem(title: "Next", edition: "Test")], in: .results)
        let latest = try XCTUnwrap(store.deletion(in: .results))
        try store.restore(in: .results, deletionID: cancelled.id, context: context, commit: context.save)
        XCTAssertEqual(store.deletion(in: .results)?.id, latest.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectionItem>()).isEmpty)
    }

    func testDeletedDestinationsAreNeverRecreated() throws {
        let context = try makeContext()
        let collection = CardCollection(name: "Removed")
        let deck = Deck(name: "Removed")
        context.insert(collection)
        context.insert(deck)
        let scopes: [CardDeleteUndoScope] = [.collection(collection.id), .deck(deck.id)]
        let store = CardDeleteUndoStore()
        for scope in scopes { store.register([CollectionItem(title: "Bolt", edition: "Test")], in: scope) }
        context.delete(collection)
        context.delete(deck)
        try context.save()
        for scope in scopes {
            let deletion = try XCTUnwrap(store.deletion(in: scope))
            XCTAssertThrowsError(try store.restore(
                in: scope, deletionID: deletion.id, context: context, commit: context.save
            ))
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<CardCollection>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Deck>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectionItem>()).isEmpty)
    }

    func testSaveFailureRestoresPostDeleteStateAndAllowsRetry() throws {
        let context = try makeContext()
        let collection = CardCollection(name: "Binder")
        context.insert(collection)
        let item = CollectionItem(title: "Bolt", edition: "Test", quantity: 4, collection: collection)
        context.insert(item)
        try context.save()
        let store = CardDeleteUndoStore()
        let scope = CardDeleteUndoScope.collection(collection.id)
        store.register([item], in: scope)
        context.delete(item)
        try context.save()
        let date = collection.updatedAt
        let deletion = try XCTUnwrap(store.deletion(in: scope))
        XCTAssertThrowsError(try store.restore(in: scope, deletionID: deletion.id, context: context) {
            throw CardListOperationError(message: "Test save failure")
        })
        XCTAssertTrue(collection.items.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectionItem>()).isEmpty)
        XCTAssertEqual(collection.updatedAt, date)
        XCTAssertEqual(store.deletion(in: scope)?.id, deletion.id)
        try store.restore(in: scope, deletionID: deletion.id, context: context, commit: context.save)
        XCTAssertEqual(collection.items.map(\.quantity), [4])
        XCTAssertNil(store.deletion(in: scope))
    }

    func testExistingIDsBlockUndoWithoutChangingInventory() throws {
        let context = try makeContext()
        let item = CollectionItem(title: "Bolt", edition: "Test")
        context.insert(item)
        try context.save()
        let store = CardDeleteUndoStore()
        store.register([item], in: .results)
        let deletion = try XCTUnwrap(store.deletion(in: .results))
        XCTAssertThrowsError(try store.restore(
            in: .results, deletionID: deletion.id, context: context, commit: context.save
        ))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionItem>()).map(\.id), [item.id])
        XCTAssertNotNil(store.deletion(in: .results))
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func assertRestoration(count: Int, scope: CardDeleteUndoScope, context: ModelContext) throws {
        let store = CardDeleteUndoStore()
        let destination = try scope.destination(in: context)
        let items = (0..<count).map { index in
            CollectionItem(title: "Card \(index)", edition: "M10", foil: true,
                           priceRetail: "1.50", priceBuy: "0.50", qtyBuying: 2, quantity: index + 3)
        }
        for item in items { context.insert(item); destination?.assign(item) }
        try context.save()
        let snapshots = items.map(CardItemSnapshot.init)
        store.register(items, in: scope)
        for item in items { context.delete(item) }
        try context.save()
        let deletion = try XCTUnwrap(store.deletion(in: scope))
        try store.restore(in: scope, deletionID: deletion.id, context: context, commit: context.save)
        let ids = Set(snapshots.map(\.id))
        let restored = try context.fetch(FetchDescriptor<CollectionItem>()).filter { ids.contains($0.id) }
        XCTAssertEqual(Set(restored.map(\.id)), ids)
        for item in restored {
            XCTAssertEqual(CardItemSnapshot(item), snapshots.first(where: { $0.id == item.id }))
            switch scope {
            case .results: XCTAssertNil(item.collection); XCTAssertNil(item.deck)
            case .collection(let id): XCTAssertEqual(item.collection?.id, id); XCTAssertNil(item.deck)
            case .deck(let id): XCTAssertEqual(item.deck?.id, id); XCTAssertNil(item.collection)
            }
        }
        try store.restore(in: scope, deletionID: deletion.id, context: context, commit: context.save)
        XCTAssertNil(store.deletion(in: scope))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionItem>()).filter { ids.contains($0.id) }.count, count)
    }
}
