import XCTest
@testable import MTGScannerKit

final class CollectionItemFromPrintingTests: XCTestCase {

    // MARK: - Helpers

    private func makePrinting(
        name: String = "Lightning Bolt",
        setCode: String = "M10",
        setName: String? = "Magic 2010",
        collectorNumber: String? = "146",
        rarity: String? = "common",
        scryfallId: String? = "abc-123",
        imageUrl: String? = "https://example.com/image.png",
        setSymbolUrl: String? = "https://example.com/m10.svg",
        cardKingdomUrl: String? = "https://ck.com/bolt",
        cardKingdomFoilUrl: String? = "https://ck.com/bolt-foil",
        colorIdentity: String? = "R"
    ) -> CardPrinting {
        CardPrinting(
            name: name,
            setCode: setCode,
            setName: setName,
            collectorNumber: collectorNumber,
            rarity: rarity,
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            manaCost: "{R}",
            power: nil,
            toughness: nil,
            loyalty: nil,
            defense: nil,
            scryfallId: scryfallId,
            imageUrl: imageUrl,
            setSymbolUrl: setSymbolUrl,
            cardKingdomUrl: cardKingdomUrl,
            cardKingdomFoilUrl: cardKingdomFoilUrl,
            colorIdentity: colorIdentity
        )
    }

    // MARK: - Field mapping

    func testMapsAllFields() {
        let printing = makePrinting()
        let item = CollectionItem(from: printing, foil: false, quantity: 2)

        XCTAssertEqual(item.title, "Lightning Bolt")
        XCTAssertEqual(item.edition, "Magic 2010")
        XCTAssertEqual(item.setCode, "M10")
        XCTAssertEqual(item.collectorNumber, "146")
        XCTAssertFalse(item.foil)
        XCTAssertEqual(item.rarity, "common")
        XCTAssertEqual(item.typeLine, "Instant")
        XCTAssertEqual(item.oracleText, "Lightning Bolt deals 3 damage to any target.")
        XCTAssertEqual(item.manaCost, "{R}")
        XCTAssertEqual(item.scryfallId, "abc-123")
        XCTAssertEqual(item.imageUrl, "https://example.com/image.png")
        XCTAssertEqual(item.setSymbolUrl, "https://example.com/m10.svg")
        XCTAssertEqual(item.cardKingdomUrl, "https://ck.com/bolt")
        XCTAssertEqual(item.colorIdentity, "R")
        XCTAssertEqual(item.quantity, 2)
    }

    // MARK: - Card Kingdom URL selection

    func testFoilUsesCardKingdomFoilUrl() {
        let printing = makePrinting()
        let item = CollectionItem(from: printing, foil: true, quantity: 1)

        XCTAssertTrue(item.foil)
        XCTAssertEqual(item.cardKingdomUrl, "https://ck.com/bolt-foil")
    }

    func testFoilFallsBackToRegularUrlWhenNoFoilUrl() {
        let printing = makePrinting(cardKingdomFoilUrl: nil)
        let item = CollectionItem(from: printing, foil: true, quantity: 1)

        XCTAssertEqual(item.cardKingdomUrl, "https://ck.com/bolt")
    }

    func testNonFoilUsesRegularUrl() {
        let printing = makePrinting()
        let item = CollectionItem(from: printing, foil: false, quantity: 1)

        XCTAssertEqual(item.cardKingdomUrl, "https://ck.com/bolt")
    }

    // MARK: - Edition fallback

    func testFallsBackToSetCodeWhenSetNameIsNil() {
        let printing = makePrinting(setName: nil)
        let item = CollectionItem(from: printing, foil: false, quantity: 1)

        XCTAssertEqual(item.edition, "M10")
    }
}
