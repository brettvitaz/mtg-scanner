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
}
