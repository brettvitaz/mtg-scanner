import SwiftData
import XCTest
@testable import MTGScanner

final class CollectionModelsTests: XCTestCase {

    // MARK: - CollectionItem init

    func testCollectionItemInitSetsAllFields() {
        let item = CollectionItem(
            title: "Lightning Bolt",
            edition: "Magic 2010",
            setCode: "M10",
            collectorNumber: "146",
            foil: false,
            rarity: "common",
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            manaCost: "{R}",
            scryfallId: "abc-123",
            imageUrl: "https://example.com/image.png",
            setSymbolUrl: "https://example.com/symbol.svg",
            cardKingdomUrl: "https://example.com/ck",
            quantity: 3
        )

        XCTAssertEqual(item.title, "Lightning Bolt")
        XCTAssertEqual(item.edition, "Magic 2010")
        XCTAssertEqual(item.setCode, "M10")
        XCTAssertEqual(item.collectorNumber, "146")
        XCTAssertFalse(item.foil)
        XCTAssertEqual(item.rarity, "common")
        XCTAssertEqual(item.typeLine, "Instant")
        XCTAssertEqual(item.oracleText, "Lightning Bolt deals 3 damage to any target.")
        XCTAssertEqual(item.manaCost, "{R}")
        XCTAssertEqual(item.quantity, 3)
        XCTAssertNil(item.collection)
        XCTAssertNil(item.deck)
    }

    func testCollectionItemDefaultQuantityIsOne() {
        let item = CollectionItem(title: "Test", edition: "Test Set")
        XCTAssertEqual(item.quantity, 1)
    }

    func testCollectionItemInitDefaultsToCurrentDate() {
        let before = Date()
        let item = CollectionItem(title: "Test", edition: "Test Set")
        let after = Date()

        XCTAssertGreaterThanOrEqual(item.addedAt, before)
        XCTAssertLessThanOrEqual(item.addedAt, after)
    }

    // MARK: - CollectionItem from RecognizedCard

    func testCollectionItemFromRecognizedCard() {
        let card = RecognizedCard(
            title: "Counterspell",
            edition: "Dominaria Remastered",
            collectorNumber: "64",
            foil: true,
            confidence: 0.95,
            setCode: "DMR",
            rarity: "uncommon",
            typeLine: "Instant",
            oracleText: "Counter target spell.",
            manaCost: "{U}{U}",
            scryfallId: "def-456",
            imageUrl: "https://example.com/cs.png",
            setSymbolUrl: "https://example.com/dmr.svg",
            cardKingdomUrl: "https://example.com/ck-cs"
        )

        let item = CollectionItem(from: card)

        XCTAssertEqual(item.title, "Counterspell")
        XCTAssertEqual(item.edition, "Dominaria Remastered")
        XCTAssertEqual(item.setCode, "DMR")
        XCTAssertEqual(item.collectorNumber, "64")
        XCTAssertTrue(item.foil)
        XCTAssertEqual(item.rarity, "uncommon")
        XCTAssertEqual(item.typeLine, "Instant")
        XCTAssertEqual(item.oracleText, "Counter target spell.")
        XCTAssertEqual(item.manaCost, "{U}{U}")
        XCTAssertEqual(item.scryfallId, "def-456")
        XCTAssertEqual(item.imageUrl, "https://example.com/cs.png")
        XCTAssertEqual(item.quantity, 1)
    }

    func testCollectionItemFromRecognizedCardWithNilFields() {
        let card = RecognizedCard(confidence: 0.5)
        let item = CollectionItem(from: card)

        XCTAssertEqual(item.title, "Unknown")
        XCTAssertEqual(item.edition, "Unknown")
        XCTAssertNil(item.setCode)
        XCTAssertNil(item.collectorNumber)
        XCTAssertFalse(item.foil)
    }

    // MARK: - CollectionItem from RecognizedCard with Correction

    func testCollectionItemAppliesCorrection() {
        let card = RecognizedCard(
            title: "Lightening Bolt",
            edition: "Magic 2010",
            collectorNumber: "146",
            foil: false,
            confidence: 0.8,
            setCode: "M10"
        )
        let correction = CardCorrection(from: RecognizedCard(
            id: card.id,
            title: "Lightning Bolt",
            edition: "Magic 2011",
            collectorNumber: "150",
            foil: true,
            confidence: 0.8
        ))

        let item = CollectionItem(from: card, correction: correction)

        XCTAssertEqual(item.title, "Lightning Bolt")
        XCTAssertEqual(item.edition, "Magic 2011")
        XCTAssertEqual(item.collectorNumber, "150")
        XCTAssertTrue(item.foil)
        // setCode comes from the original card, not correction
        XCTAssertEqual(item.setCode, "M10")
    }

    func testCollectionItemCorrectionWithEmptyStringsFallsBackToCard() {
        let card = RecognizedCard(
            title: "Lightning Bolt",
            edition: "Magic 2010",
            collectorNumber: "146",
            confidence: 0.9
        )
        // Correction with empty strings should fall back to card values
        var correction = CardCorrection(from: card)
        correction.title = ""
        correction.edition = ""
        correction.collectorNumber = ""

        let item = CollectionItem(from: card, correction: correction)

        XCTAssertEqual(item.title, "Lightning Bolt")
        XCTAssertEqual(item.edition, "Magic 2010")
        XCTAssertEqual(item.collectorNumber, "146")
    }

    // MARK: - CollectionItem duplicate

    func testDuplicateCreatesIndependentCopy() {
        let original = CollectionItem(
            title: "Sol Ring",
            edition: "Commander 2021",
            setCode: "C21",
            collectorNumber: "263",
            foil: true,
            rarity: "uncommon",
            quantity: 2
        )

        let copy = original.duplicate()

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.title, original.title)
        XCTAssertEqual(copy.edition, original.edition)
        XCTAssertEqual(copy.setCode, original.setCode)
        XCTAssertEqual(copy.collectorNumber, original.collectorNumber)
        XCTAssertEqual(copy.foil, original.foil)
        XCTAssertEqual(copy.rarity, original.rarity)
        XCTAssertEqual(copy.quantity, 2)
        XCTAssertNil(copy.collection)
        XCTAssertNil(copy.deck)
    }

}

// MARK: - matches tests

extension CollectionModelsTests {
    func testMatchesByScryfallIdAndFoil() {
        let a = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: false, scryfallId: "abc-123")
        let b = CollectionItem(title: "Lightning Bolt", edition: "M11", foil: false, scryfallId: "abc-123")
        XCTAssertTrue(a.matches(b))
    }

    func testMatchesByScryfallIdDistinguishesFoil() {
        let a = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: false, scryfallId: "abc-123")
        let b = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: true, scryfallId: "abc-123")
        XCTAssertFalse(a.matches(b))
    }

    func testMatchesFallsBackToIdentityFields() {
        let a = CollectionItem(title: "Forest", edition: "Foundations", collectorNumber: "276", foil: false)
        let b = CollectionItem(title: "Forest", edition: "Foundations", collectorNumber: "276", foil: false)
        XCTAssertTrue(a.matches(b))
    }

    func testMatchesFallbackDistinguishesByCollectorNumber() {
        let a = CollectionItem(title: "Forest", edition: "Foundations", collectorNumber: "276", foil: false)
        let b = CollectionItem(title: "Forest", edition: "Foundations", collectorNumber: "277", foil: false)
        XCTAssertFalse(a.matches(b))
    }

    func testMatchesReturnsFalseForDifferentCards() {
        let a = CollectionItem(title: "Lightning Bolt", edition: "M10", foil: false, scryfallId: "abc-123")
        let b = CollectionItem(title: "Counterspell", edition: "DMR", foil: false, scryfallId: "def-456")
        XCTAssertFalse(a.matches(b))
    }

}

// MARK: - mergeOrInsert tests

extension CollectionModelsTests {
    func testMergeOrInsertIncrementsQuantityWhenMatchFound() throws {
        let container = try ModelContainer(
            for: CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let existing = CollectionItem(title: "Sol Ring", edition: "C21", foil: false, scryfallId: "sr-1", quantity: 2)
        context.insert(existing)
        let incoming = CollectionItem(title: "Sol Ring", edition: "C21", foil: false, scryfallId: "sr-1", quantity: 1)
        let result = mergeOrInsert(incoming, into: [existing], context: context)
        XCTAssertEqual(result.id, existing.id)
        XCTAssertEqual(existing.quantity, 3)
    }

    func testMergeOrInsertCreatesNewRowWhenNoMatch() throws {
        let container = try ModelContainer(
            for: CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let existing = CollectionItem(
            title: "Forest", edition: "Foundations", foil: false, scryfallId: "f-1", quantity: 1
        )
        context.insert(existing)
        let incoming = CollectionItem(
            title: "Island", edition: "Foundations", foil: false, scryfallId: "i-1", quantity: 1
        )
        let result = mergeOrInsert(incoming, into: [existing], context: context)
        XCTAssertNotEqual(result.id, existing.id)
        XCTAssertEqual(existing.quantity, 1)
        let fetched = try context.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(fetched.count, 2)
    }

    // MARK: - CardCollection

    func testCardCollectionInit() {
        let before = Date()
        let collection = CardCollection(name: "My Rares")
        let after = Date()

        XCTAssertEqual(collection.name, "My Rares")
        XCTAssertTrue(collection.items.isEmpty)
        XCTAssertGreaterThanOrEqual(collection.createdAt, before)
        XCTAssertLessThanOrEqual(collection.createdAt, after)
        XCTAssertGreaterThanOrEqual(collection.updatedAt, before)
        XCTAssertLessThanOrEqual(collection.updatedAt, after)
    }

    // MARK: - Deck

    func testDeckInit() {
        let before = Date()
        let deck = Deck(name: "Red Aggro")
        let after = Date()

        XCTAssertEqual(deck.name, "Red Aggro")
        XCTAssertTrue(deck.items.isEmpty)
        XCTAssertGreaterThanOrEqual(deck.createdAt, before)
        XCTAssertLessThanOrEqual(deck.createdAt, after)
        XCTAssertGreaterThanOrEqual(deck.updatedAt, before)
        XCTAssertLessThanOrEqual(deck.updatedAt, after)
    }
}
