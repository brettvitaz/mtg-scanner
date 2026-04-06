import XCTest
@testable import MTGScanner

final class CollectionItemMoveTests: XCTestCase {

    // MARK: - Move to collection

    func testMoveItemToCollectionClearsDeckRelationship() {
        let sourceDeck = Deck(name: "Source")
        let targetCollection = CardCollection(name: "Binder")
        let item = CollectionItem(title: "Sol Ring", edition: "C21", scryfallId: "sr-1")
        item.deck = sourceDeck

        item.deck = nil
        item.collection = targetCollection

        XCTAssertNil(item.deck)
        XCTAssertIdentical(item.collection, targetCollection)
    }

    // MARK: - Move to deck

    func testMoveItemToDeckClearsCollectionRelationship() {
        let targetDeck = Deck(name: "Target")
        let sourceCollection = CardCollection(name: "Binder")
        let item = CollectionItem(title: "Sol Ring", edition: "C21", scryfallId: "sr-1")
        item.collection = sourceCollection

        item.collection = nil
        item.deck = targetDeck

        XCTAssertNil(item.collection)
        XCTAssertIdentical(item.deck, targetDeck)
    }

    func testMoveItemToAnotherDeckClearsCollectionIfSet() {
        let sourceDeck = Deck(name: "Source")
        let targetDeck = Deck(name: "Target")
        let collection = CardCollection(name: "Binder")
        let item = CollectionItem(title: "Sol Ring", edition: "C21", scryfallId: "sr-1")
        item.deck = sourceDeck
        item.collection = collection

        item.collection = nil
        item.deck = targetDeck

        XCTAssertNil(item.collection)
        XCTAssertIdentical(item.deck, targetDeck)
    }
}
