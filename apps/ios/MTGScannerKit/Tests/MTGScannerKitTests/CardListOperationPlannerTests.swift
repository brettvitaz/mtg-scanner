import XCTest
@testable import MTGScannerKit

@MainActor
final class CardListOperationPlannerTests: XCTestCase {
    private typealias Fixture = CardListOperationTestFixtures

    private func plan(
        target: [CollectionItem], tool: [CollectionItem], operation: CardListOperation = .subtract
    ) throws -> CardListOperationPlan {
        var snapshot = Fixture.list().snapshot()
        snapshot.items = target.map(CardItemSnapshot.init)
        return try CardListOperationPlanner().plan(
            target: snapshot, toolItems: tool.map(CardItemSnapshot.init), toolName: "sell", operation: operation
        )
    }

    func testFiveMinusThreeLeavesTwo() throws {
        let result = try plan(target: [Fixture.item(5)], tool: [Fixture.item(3)])
        XCTAssertEqual(result.resultItems.map(\.quantity), [2])
        XCTAssertEqual(result.affectedQuantity, 3)
        XCTAssertEqual(result.unavailableQuantity, 0)
        XCTAssertEqual(result.beforeQuantity, 5)
        XCTAssertEqual(result.afterQuantity, 2)
    }

    func testThreeMinusFiveRemovesThreeAndReportsTwoUnavailable() throws {
        let result = try plan(target: [Fixture.item(3)], tool: [Fixture.item(5)])
        XCTAssertTrue(result.resultItems.isEmpty)
        XCTAssertEqual(result.affectedQuantity, 3)
        XCTAssertEqual(result.unavailableQuantity, 2)
        XCTAssertEqual(result.changes.first?.after, 0)
    }

    func testDifferentPrintingAndFoilAreNotRemoved() throws {
        let result = try plan(
            target: [Fixture.item(4), Fixture.item(2, id: "other")],
            tool: [Fixture.item(1, foil: true), Fixture.item(3, id: "missing")]
        )
        XCTAssertEqual(result.afterQuantity, 6)
        XCTAssertEqual(result.unavailableQuantity, 4)
        XCTAssertFalse(result.canApply)
    }

    func testDuplicateRowsAreAggregatedOnBothSides() throws {
        let result = try plan(
            target: [Fixture.item(2), Fixture.item(3)], tool: [Fixture.item(1), Fixture.item(2)]
        )
        XCTAssertEqual(result.resultItems.count, 1)
        XCTAssertEqual(result.resultItems.first?.quantity, 2)
        XCTAssertEqual(result.changes.count, 1)
        XCTAssertEqual(result.changes.first?.requested, 3)
    }

    func testAdditionSumsQuantitiesAndKeepsFinishSeparate() throws {
        let result = try plan(
            target: [Fixture.item(3)], tool: [Fixture.item(2), Fixture.item(1, foil: true)], operation: .add
        )
        XCTAssertEqual(result.affectedQuantity, 3)
        XCTAssertEqual(result.afterQuantity, 6)
        XCTAssertEqual(result.resultItems.first(where: { $0.card.foil == false })?.quantity, 5)
        XCTAssertEqual(result.resultItems.first(where: { $0.card.foil == true })?.quantity, 1)
    }

    func testFallbackIdentityMatchesMissingIDButRespectsCollectorNumber() throws {
        let different = Fixture.item(1, id: nil)
        different.collectorNumber = "147"
        let result = try plan(target: [Fixture.item(5)], tool: [Fixture.item(2, id: nil), different])
        XCTAssertEqual(result.afterQuantity, 3)
        XCTAssertEqual(result.unavailableQuantity, 1)
    }

    func testAmbiguousFallbackDoesNotChooseArbitraryPrinting() {
        XCTAssertThrowsError(try plan(
            target: [Fixture.item(2, id: "a"), Fixture.item(3, id: "b")], tool: [Fixture.item(1, id: nil)]
        ))
    }

    func testLegacyZeroAndNegativeQuantitiesRepresentOneCopy() throws {
        let result = try plan(target: [Fixture.item(0), Fixture.item(-4, foil: true)], tool: [Fixture.item(1)])
        XCTAssertEqual(result.beforeQuantity, 2)
        XCTAssertEqual(result.afterQuantity, 1)
    }

    func testEmptyToolAndEntirelyUnmatchedSubtractionCannotApply() throws {
        XCTAssertFalse(try plan(target: [Fixture.item(2)], tool: []).canApply)
        XCTAssertFalse(try plan(target: [], tool: [Fixture.item(2)]).canApply)
        let addition = try plan(target: [], tool: [Fixture.item(2)], operation: .add)
        XCTAssertEqual(addition.afterQuantity, 2)
    }

    func testOverflowInRowAndTotalIsRejected() {
        XCTAssertThrowsError(try plan(target: [Fixture.item(Int.max)], tool: [Fixture.item(1)], operation: .add))
        XCTAssertThrowsError(try plan(
            target: [], tool: [Fixture.item(Int.max), Fixture.item(1, foil: true)], operation: .add
        ))
    }

    func testSnapshotDetectsPrintingMetadataChangesWithSameItemID() {
        let item = Fixture.item(2)
        let before = CardItemSnapshot(item)
        item.collectorNumber = "200"
        XCTAssertNotEqual(CardItemSnapshot(item), before)
        item.collectorNumber = "146"
        item.priceBuy = "3.00"
        XCTAssertNotEqual(CardItemSnapshot(item), before)
    }

    func testQuantitySummaryHandlesUnrepresentableListTotal() throws {
        let context = try Fixture.context()
        let list = Fixture.list()
        list.insert(in: context)
        Fixture.item(Int.max, in: list, context: context)
        Fixture.item(1, foil: true, in: list, context: context)
        XCTAssertEqual(list.quantitySummary, "Quantity too large")
    }

    func testSameListCannotBeUsedAsTool() {
        let list = Fixture.list()
        XCTAssertThrowsError(try Fixture.plan(target: list, tool: list, operation: .add))
    }

    func testPreviewNamesTargetAndWarnsAboutDeletingUnmatchedEntries() throws {
        let target = Fixture.list(name: "Main Collection")
        let tool = Fixture.list(name: "sell")
        let context = try Fixture.context()
        target.insert(in: context)
        tool.insert(in: context)
        Fixture.item(3, in: target, context: context)
        Fixture.item(5, in: tool, context: context)
        let result = try Fixture.plan(target: target, tool: tool, deleteTool: true)
        XCTAssertEqual(result.buttonTitle, "Subtract 3 Cards")
        XCTAssertTrue(result.outcome.contains("from Main Collection"))
        XCTAssertTrue(result.outcome.contains("Delete the entire sell list, including unmatched cards"))
    }
}
