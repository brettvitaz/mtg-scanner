import XCTest
@testable import MTGScannerKit

@MainActor
final class CardListOperationViewModelTests: XCTestCase {
    private typealias Fixture = CardListOperationTestFixtures

    func testChangingTargetClearsToolAndPreview() throws {
        let context = try Fixture.context()
        let target = Fixture.list()
        let tool = Fixture.list(name: "sell")
        target.insert(in: context)
        tool.insert(in: context)
        Fixture.item(2, in: tool, context: context)
        let model = CardListOperationViewModel(target: target)
        XCTAssertNil(model.plan)
        XCTAssertEqual(model.operation, .add)
        XCTAssertFalse(model.deleteTool)
        model.chooseTool(tool)
        XCTAssertTrue(model.canApply)
        model.chooseTarget(tool)
        XCTAssertNil(model.tool)
        XCTAssertNil(model.plan)
    }

    func testApplyAndUndoIgnoreRepeatedSubmission() throws {
        let context = try Fixture.context()
        let target = Fixture.list()
        let tool = Fixture.list(name: "sell")
        target.insert(in: context)
        tool.insert(in: context)
        Fixture.item(2, in: tool, context: context)
        try context.save()
        let model = CardListOperationViewModel(target: target)
        model.chooseTool(tool)
        var commits = 0
        let commit = { commits += 1; try context.save() }
        model.apply(context: context, commit: commit)
        model.apply(context: context, commit: commit)
        XCTAssertEqual(commits, 1)
        XCTAssertEqual(target.items.totalQuantity, 2)
        model.undo(context: context, commit: commit)
        model.undo(context: context, commit: commit)
        XCTAssertEqual(commits, 2)
        XCTAssertTrue(model.wasUndone)
        XCTAssertTrue(target.items.isEmpty)
    }

    func testStalePreviewRefreshesAndRequiresAnotherSubmission() throws {
        let context = try Fixture.context()
        let target = Fixture.list()
        let tool = Fixture.list(name: "sell")
        target.insert(in: context)
        tool.insert(in: context)
        Fixture.item(2, in: tool, context: context)
        try context.save()
        let model = CardListOperationViewModel(target: target)
        model.chooseTool(tool)
        tool.items.first?.quantity = 3
        model.apply(context: context, commit: context.save)
        XCTAssertNil(model.receipt)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.plan?.affectedQuantity, 3)
        XCTAssertTrue(target.items.isEmpty)
        model.apply(context: context, commit: context.save)
        XCTAssertEqual(target.items.totalQuantity, 3)
        XCTAssertNil(model.errorMessage)
    }

    func testCSVDefaultsToAddAndNeverDeletesAList() throws {
        let context = try Fixture.context()
        let target = Fixture.list()
        target.insert(in: context)
        let rows = try [CSVImportTestFixtures.row()]
        let model = CardListOperationViewModel(
            target: target, csvItems: try CSVImportPersistence().preparedItems(rows), csvName: "cards.csv"
        )
        model.deleteTool = true
        model.refresh()
        XCTAssertTrue(model.isCSV)
        XCTAssertEqual(model.operation, .add)
        XCTAssertEqual(model.plan?.toolName, "cards.csv")
        XCTAssertEqual(model.plan?.deleteTool, false)
    }

    func testSaveFailureRetainsInputsAndAllowsRetry() throws {
        let context = try Fixture.context()
        let target = Fixture.list()
        let tool = Fixture.list(name: "sell")
        target.insert(in: context)
        tool.insert(in: context)
        Fixture.item(2, in: tool, context: context)
        try context.save()
        let model = CardListOperationViewModel(target: target)
        model.chooseTool(tool)
        model.apply(context: context) { throw CardListOperationError(message: "Disk full") }
        XCTAssertEqual(model.tool?.id, tool.id)
        XCTAssertNil(model.receipt)
        XCTAssertEqual(model.errorMessage, "Disk full")
        XCTAssertTrue(model.canApply)
        model.apply(context: context, commit: context.save)
        XCTAssertEqual(target.items.totalQuantity, 2)
    }
}
