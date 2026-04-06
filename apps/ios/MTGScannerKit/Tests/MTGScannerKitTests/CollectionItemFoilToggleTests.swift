import XCTest
@testable import MTGScanner

final class CollectionItemFoilToggleTests: XCTestCase {
    func testToggleFoilIfNoDuplicateSucceedsWhenUniqueAmongInboxItems() {
        let item = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: false, scryfallId: "abc-123")
        let sibling = CollectionItem(title: "Counterspell", edition: "DMR", foil: false, scryfallId: "def-456")

        let toggled = item.toggleFoilIfNoDuplicate(in: [item, sibling])

        XCTAssertTrue(toggled)
        XCTAssertTrue(item.foil)
    }

    func testToggleFoilIfNoDuplicateBlocksDuplicateInInbox() {
        let item = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: false, scryfallId: "abc-123")
        let sibling = CollectionItem(title: "Lightning Bolt", edition: "M11", foil: true, scryfallId: "abc-123")

        let toggled = item.toggleFoilIfNoDuplicate(in: [item, sibling])

        XCTAssertFalse(toggled)
        XCTAssertFalse(item.foil)
    }

    func testToggleFoilIfNoDuplicateBlocksDuplicateInCollection() {
        let collection = CardCollection(name: "Binder")
        let item = CollectionItem(title: "Forest", edition: "Foundations", collectorNumber: "276", foil: false)
        let sibling = CollectionItem(title: "Forest", edition: "Foundations", collectorNumber: "276", foil: true)
        item.collection = collection
        sibling.collection = collection

        let toggled = item.toggleFoilIfNoDuplicate(in: [item, sibling])

        XCTAssertFalse(toggled)
        XCTAssertFalse(item.foil)
    }

    func testToggleFoilIfNoDuplicateBlocksDuplicateInDeck() {
        let deck = Deck(name: "Ramp")
        let item = CollectionItem(title: "Sol Ring", edition: "C21", foil: false, scryfallId: "sr-1")
        let sibling = CollectionItem(title: "Sol Ring", edition: "Commander Masters", foil: true, scryfallId: "sr-1")
        item.deck = deck
        sibling.deck = deck

        let toggled = item.toggleFoilIfNoDuplicate(in: [item, sibling])

        XCTAssertFalse(toggled)
        XCTAssertFalse(item.foil)
    }

    // MARK: - Bulk foil toggle (toggleSelectedFoil logic)

    func testBulkToggleAllSucceedWhenNoCollisions() {
        let item1 = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: false, scryfallId: "a1")
        let item2 = CollectionItem(title: "Counterspell", edition: "DMR", foil: false, scryfallId: "b2")
        let items = [item1, item2]
        var skipped = 0
        for item in items where !item.toggleFoilIfNoDuplicate(in: items) {
            skipped += 1
        }
        XCTAssertEqual(skipped, 0)
        XCTAssertTrue(item1.foil)
        XCTAssertTrue(item2.foil)
    }

    func testBulkToggleSkipsItemsWithCollisions() {
        let item = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: false, scryfallId: "a1")
        let blocker = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: true, scryfallId: "a1")
        let other = CollectionItem(title: "Counterspell", edition: "DMR", foil: false, scryfallId: "b2")
        let items = [item, other]
        let siblings = [item, blocker, other]
        var skipped = 0
        for it in items where !it.toggleFoilIfNoDuplicate(in: siblings) {
            skipped += 1
        }
        XCTAssertEqual(skipped, 1)
        XCTAssertFalse(item.foil)
        XCTAssertTrue(other.foil)
    }

    func testBulkToggleAllSkippedWhenAllCollide() {
        let item1 = CollectionItem(title: "Sol Ring", edition: "C21", foil: false, scryfallId: "sr-1")
        let blocker1 = CollectionItem(title: "Sol Ring", edition: "C21", foil: true, scryfallId: "sr-1")
        let item2 = CollectionItem(title: "Forest", edition: "M10", foil: false, scryfallId: "fo-1")
        let blocker2 = CollectionItem(title: "Forest", edition: "M10", foil: true, scryfallId: "fo-1")
        let items = [item1, item2]
        let siblings = [item1, blocker1, item2, blocker2]
        var skipped = 0
        for it in items where !it.toggleFoilIfNoDuplicate(in: siblings) {
            skipped += 1
        }
        XCTAssertEqual(skipped, 2)
        XCTAssertFalse(item1.foil)
        XCTAssertFalse(item2.foil)
    }

    // MARK: - Unconditional foil toggle

    func testToggleFoilUnconditionallyTogglesFoil() {
        let item = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: false, scryfallId: "abc-123")
        item.toggleFoilUnconditionally()
        XCTAssertTrue(item.foil)
        item.toggleFoilUnconditionally()
        XCTAssertFalse(item.foil)
    }

    func testToggleFoilUnconditionallyIgnoresCollisions() {
        let item = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: false, scryfallId: "abc-123")
        let sibling = CollectionItem(title: "Lightning Bolt", edition: "M11", foil: true, scryfallId: "abc-123")

        item.toggleFoilUnconditionally()

        XCTAssertTrue(item.foil)
        XCTAssertTrue(sibling.foil)
    }
}
