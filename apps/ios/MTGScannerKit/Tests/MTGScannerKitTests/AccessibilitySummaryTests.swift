import XCTest

@testable import MTGScannerKit

final class AccessibilitySummaryTests: XCTestCase {

    @MainActor
    func testCollectionItemRowSummaryIncludesCoreCardDetails() {
        let item = CollectionItem(
            title: "Lightning Bolt",
            edition: "Magic 2010",
            collectorNumber: "146",
            foil: true,
            priceRetail: "1.25",
            priceBuy: "0.50",
            quantity: 3
        )

        XCTAssertEqual(
            CollectionItemRow.accessibilitySummary(for: item),
            "Lightning Bolt, Magic 2010, collector number 146, foil, quantity 3, sell price 1.25, buy price 0.50"
        )
    }
}
