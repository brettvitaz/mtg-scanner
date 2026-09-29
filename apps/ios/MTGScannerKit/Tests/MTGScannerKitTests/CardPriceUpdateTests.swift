import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class CardPriceUpdateTests: XCTestCase {
    private let price = CardPrice(priceRetail: "$2.00", qtyRetail: 5, priceBuy: "$0.50", qtyBuying: 12, url: nil)

    func testApplyingResponseUpdatesPricesAndBuyingQuantityTogether() {
        let item = makeItem()
        XCTAssertTrue(item.apply(price: price, matching: PriceFetchRequest(item: item)))
        XCTAssertEqual(item.priceRetail, "$2.00")
        XCTAssertEqual(item.priceBuy, "$0.50")
        XCTAssertEqual(item.qtyBuying, 12)
        XCTAssertEqual(item.duplicate().qtyBuying, 12)
    }

    func testResponseWithUnknownQuantityClearsPreviousAvailability() {
        let item = makeItem()
        let unknown = CardPrice(priceRetail: "$2.00", qtyRetail: nil, priceBuy: nil, qtyBuying: nil, url: nil)
        XCTAssertTrue(item.apply(price: unknown, matching: PriceFetchRequest(item: item)))
        XCTAssertNil(item.qtyBuying)
        XCTAssertNil(item.priceBuy)
    }

    func testFoilToggleClearsPricesAndRejectsOldResponse() {
        let item = makeItem()
        let request = PriceFetchRequest(item: item)
        item.toggleFoilUnconditionally()
        XCTAssertNil(item.priceRetail)
        XCTAssertNil(item.priceBuy)
        XCTAssertNil(item.qtyBuying)
        XCTAssertFalse(item.apply(price: price, matching: request))
        XCTAssertNil(item.qtyBuying)
    }

    func testBlockedFoilTogglePreservesPricingAndAvailability() {
        let item = makeItem()
        let sibling = item.duplicate()
        sibling.foil = true
        XCTAssertFalse(item.toggleFoilIfNoDuplicate(in: [item, sibling]))
        XCTAssertEqual(item.priceBuy, "$0.25")
        XCTAssertEqual(item.qtyBuying, 2)
    }

    func testPrintingEditInvalidatesAvailabilityAndRejectsOldResponse() {
        let item = makeItem()
        let request = PriceFetchRequest(item: item)
        let printing = CardPrinting(card: RecognizedCard(id: UUID(), title: "Forest", edition: "Set"))
        item.apply(printing: printing, foil: false)
        XCTAssertNil(item.priceRetail)
        XCTAssertNil(item.qtyBuying)
        XCTAssertFalse(item.apply(price: price, matching: request))
    }

    func testDeletedItemRejectsResponse() throws {
        let container = try ModelContainer(for: CollectionItem.self, CardCollection.self, Deck.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let item = makeItem()
        container.mainContext.insert(item)
        try container.mainContext.save()
        let request = PriceFetchRequest(item: item)
        container.mainContext.delete(item)
        XCTAssertFalse(item.apply(price: price, matching: request))
        XCTAssertEqual(item.qtyBuying, 2)
    }

    private func makeItem() -> CollectionItem {
        CollectionItem(title: "Lightning Bolt", edition: "Magic 2010", priceRetail: "$1.00",
                       priceBuy: "$0.25", qtyBuying: 2)
    }
}
