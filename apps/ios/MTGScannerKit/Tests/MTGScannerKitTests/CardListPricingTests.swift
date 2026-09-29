import SwiftData
import XCTest
@testable import MTGScannerKit

final class CardListPricingTests: XCTestCase {
    func testTotalsMultiplyQuantitiesWithoutCappingAtBuyingLimit() {
        let first = item(retail: "$0.10", buylist: "$0.05", quantity: 3)
        first.qtyBuying = 1
        let second = item(retail: "$1,234.56", buylist: " 12.40 ", quantity: 2)
        let totals = CardListPricing(items: [first, second])
        XCTAssertEqual(totals.retail.amount, Decimal(string: "2469.42"))
        XCTAssertEqual(totals.buylist.amount, Decimal(string: "24.95"))
        XCTAssertEqual(totals.retail.pricedQuantity, 5)
        XCTAssertEqual(totals.buylist.displayAmount, "$24.95")
    }

    func testCoverageIsIndependentAndMissingPricesArePartial() {
        let totals = CardListPricing(items: [
            item(retail: "$2.50", buylist: nil, quantity: 3),
            item(retail: "invalid", buylist: "$1.00", quantity: 2)
        ])
        XCTAssertEqual(totals.retail.amount, Decimal(string: "7.50"))
        XCTAssertEqual(totals.retail.pricedQuantity, 3)
        XCTAssertEqual(totals.buylist.pricedQuantity, 2)
        XCTAssertTrue(totals.retail.isPartial)
        XCTAssertTrue(totals.buylist.isPartial)
        XCTAssertEqual(totals.buylist.accessibilitySummary(label: "Buylist"),
                       "Buylist total $2.00, partial total, 2 of 5 cards priced")
    }

    func testUnavailablePricesDifferFromValidZeroAndEmptyList() {
        let unavailable = CardListPricing(items: [item(retail: nil, buylist: "-1.00")])
        XCTAssertEqual(unavailable.retail.displayAmount, "—")
        XCTAssertEqual(unavailable.buylist.displayAmount, "—")
        XCTAssertFalse(unavailable.buylist.isPartial)
        let zero = CardListPricing(items: [item(retail: "$0.00", buylist: "0")])
        XCTAssertEqual(zero.buylist.displayAmount, "$0.00")
        XCTAssertEqual(zero.retail.pricedQuantity, 1)
        XCTAssertEqual(CardListPricing(items: []).buylist.displayAmount, "$0.00")
    }

    func testParsingRejectsMalformedAndNegativeAmounts() {
        for value in [nil, "", "—", "NaN", "-0.01", "1.2.3", "$1.234", "1x", "1e3",
                      "$1,2.00", "1$00", "$1,,000"] as [String?] {
            XCTAssertNil(CardPriceTotal.parse(value), "Unexpected price: \(value ?? "nil")")
        }
        XCTAssertEqual(CardPriceTotal.parse("  $1,234.50 \n"), Decimal(string: "1234.50"))
    }

    func testStoredNonpositiveQuantityUsesOneCopy() {
        let totals = CardListPricing(items: [
            item(retail: "$1.00", buylist: "$0.50", quantity: 0),
            item(retail: "$2.00", buylist: "$0.25", quantity: -3)
        ])
        XCTAssertEqual(totals.retail.amount, 3)
        XCTAssertEqual(totals.buylist.amount, Decimal(string: "0.75"))
        XCTAssertEqual(totals.retail.totalQuantity, 2)
    }

    func testTotalsRecomputeAfterQuantityAndPriceEdits() {
        let card = item(retail: "$2.00", buylist: nil)
        XCTAssertEqual(CardListPricing(items: [card]).retail.amount, 2)
        card.quantity = 4
        card.priceBuy = "$0.75"
        let updated = CardListPricing(items: [card])
        XCTAssertEqual(updated.retail.amount, 8)
        XCTAssertEqual(updated.buylist.amount, 3)
        XCTAssertFalse(updated.buylist.isPartial)
    }

    private func item(retail: String?, buylist: String?, quantity: Int = 1) -> CollectionItem {
        CollectionItem(title: "Card", edition: "Set", priceRetail: retail, priceBuy: buylist, quantity: quantity)
    }
}

final class CKBuyingFilterTests: XCTestCase {
    func testOnlyPositiveBuyingQuantityPassesRegardlessOfPrice() {
        let items = [makeItem("Positive", buying: 1), makeItem("Zero", buying: 0),
                     makeItem("Unknown", buying: nil), makeItem("Invalid", buying: -1)]
        let filter = CardFilterState()
        XCTAssertEqual(filter.apply(to: items).count, 4)
        filter.ckBuyingOnly = true
        XCTAssertEqual(filter.apply(to: items).map(\.title), ["Positive"])
        XCTAssertTrue(filter.isFilterActive)
        filter.reset()
        XCTAssertFalse(filter.ckBuyingOnly)
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to: items).count, 4)
    }

    func testBuyingFilterCombinesWithSearchAndTotals() {
        let bolt = makeItem("Lightning Bolt", buying: 2)
        bolt.priceBuy = "$0.50"
        bolt.quantity = 4
        let filter = CardFilterState()
        filter.ckBuyingOnly = true
        filter.searchText = "bolt"
        let displayed = filter.apply(to: [bolt, makeItem("Forest", buying: 10), makeItem("Bolt", buying: 0)])
        XCTAssertEqual(displayed.map(\.id), [bolt.id])
        XCTAssertEqual(CardListPricing(items: displayed).buylist.amount, 2)
        XCTAssertEqual(displayed.totalQuantity, 4)
        bolt.qtyBuying = 0
        XCTAssertTrue(filter.apply(to: displayed).isEmpty)
    }

    func testStatusLabelsDistinguishZeroUnknownAndPositive() {
        XCTAssertEqual(makeItem("Zero", buying: 0).buyingStatusLabel, "CK not buying")
        XCTAssertEqual(makeItem("Unknown", buying: nil).buyingStatusLabel, "CK status unknown")
        let buying = makeItem("Buying", buying: 12)
        XCTAssertNil(buying.buyingStatusLabel)
        XCTAssertEqual(buying.buyingAccessibilitySummary, "CK buying 12 copies")
        XCTAssertEqual(makeItem("Invalid", buying: -1).buyingStatusLabel, "CK status unknown")
    }

    func testPriceSortLabelsKeepIdentifiersAndPriceMapping() {
        XCTAssertEqual(CardSortField.priceBuy.rawValue, "Buy Price")
        XCTAssertEqual(CardSortField.priceBuy.displayName, "Buylist Price")
        XCTAssertEqual(CardSortField.priceRetail.rawValue, "Sell Price")
        XCTAssertEqual(CardSortField.priceRetail.displayName, "Retail Price")
        let first = makeItem("A", buying: 5)
        let second = makeItem("B", buying: 1)
        first.priceBuy = "$2.00"
        second.priceBuy = "$1.00"
        let filter = CardFilterState()
        filter.sort = CardSortOption(field: .priceBuy, direction: .ascending)
        XCTAssertEqual(filter.apply(to: [first, second]).map(\.title), ["B", "A"])
    }

    private func makeItem(_ name: String, buying: Int?) -> CollectionItem {
        CollectionItem(title: name, edition: "Set", qtyBuying: buying)
    }
}
