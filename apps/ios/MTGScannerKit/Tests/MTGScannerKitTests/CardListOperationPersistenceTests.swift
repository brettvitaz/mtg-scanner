import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class CardListOperationPersistenceTests: XCTestCase {
    private typealias Fixture = CardListOperationTestFixtures
    private let persistence = CardListOperationPersistence()

    private struct Scenario {
        let context: ModelContext
        let target: CardListReference
        let tool: CardListReference
    }

    private func setup(
        targetKind: CardListKind = .collection, toolKind: CardListKind = .deck
    ) throws -> Scenario {
        let context = try Fixture.context()
        let target = Fixture.list(targetKind, name: "Target")
        let tool = Fixture.list(toolKind, name: "sell")
        target.insert(in: context)
        tool.insert(in: context)
        Fixture.item(3, in: target, context: context)
        Fixture.item(5, in: tool, context: context)
        try context.save()
        return Scenario(context: context, target: target, tool: tool)
    }

    func testEveryOperationAndCleanupAcrossAllListPairingsCanBeUndone() throws {
        for targetKind in [CardListKind.collection, .deck] {
            for toolKind in [CardListKind.collection, .deck] {
                try verifyOperations(targetKind: targetKind, toolKind: toolKind)
            }
        }
    }

    private func verifyOperations(targetKind: CardListKind, toolKind: CardListKind) throws {
        for operation in CardListOperation.allCases {
            for deleteTool in [false, true] {
                let scenario = try setup(targetKind: targetKind, toolKind: toolKind)
                let context = scenario.context
                let target = scenario.target
                let tool = scenario.tool
                let beforeTarget = target.snapshot()
                let beforeTool = tool.snapshot()
                let plan = try Fixture.plan(target: target, tool: tool, operation: operation, deleteTool: deleteTool)
                let receipt = try persistence.apply(plan, context: context, commit: context.save)
                XCTAssertEqual(target.items.totalQuantity, operation == .add ? 8 : 0)
                XCTAssertNotNil(try CardListReference.find(beforeTarget, in: context))
                let savedTool = try CardListReference.find(beforeTool, in: context)
                XCTAssertEqual(savedTool == nil, deleteTool)
                XCTAssertEqual(tool.isDeleted, deleteTool)
                if !deleteTool { XCTAssertEqual(savedTool?.snapshot(), beforeTool) }
                try persistence.undo(receipt, context: context, commit: context.save)
                XCTAssertEqual(target.snapshot(), beforeTarget)
                XCTAssertEqual(try CardListReference.find(beforeTool, in: context)?.snapshot(), beforeTool)
                XCTAssertFalse(context.hasChanges)
            }
        }
    }

    func testDeletingToolAlsoDeletesUnmatchedCardsWithoutAddingThemToTarget() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let tool = scenario.tool
        Fixture.item(2, id: "unmatched", in: tool, context: context)
        try context.save()
        let beforeTool = tool.snapshot()
        let plan = try Fixture.plan(target: target, tool: tool, deleteTool: true)
        let receipt = try persistence.apply(plan, context: context, commit: context.save)
        XCTAssertEqual(plan.unavailableQuantity, 4)
        XCTAssertTrue(target.items.isEmpty)
        XCTAssertNil(try CardListReference.find(beforeTool, in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectionItem>()).isEmpty)
        try persistence.undo(receipt, context: context, commit: context.save)
        XCTAssertEqual(try CardListReference.find(beforeTool, in: context)?.items.totalQuantity, 7)
    }

    func testAdditionPreservesTargetMetadataAndCopiesNewToolRows() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let tool = scenario.tool
        let existing = try XCTUnwrap(target.items.first)
        existing.priceRetail = "9.99"
        let source = Fixture.item(1, foil: true, in: tool, context: context)
        try context.save()
        let plan = try Fixture.plan(target: target, tool: tool, operation: .add)
        _ = try persistence.apply(plan, context: context, commit: context.save)
        XCTAssertEqual(existing.priceRetail, "9.99")
        let copy = try XCTUnwrap(target.items.first(where: \.foil))
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.oracleText, source.oracleText)
        XCTAssertEqual(copy.priceBuy, source.priceBuy)
        XCTAssertEqual(copy.addedAt, source.addedAt)
        XCTAssertNil(copy.deck)
    }

    func testFailedSaveRestoresDeletedRowsAndToolAndPreservesUnrelatedEdits() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let tool = scenario.tool
        let unrelated = Deck(name: "Other")
        context.insert(unrelated)
        try context.save()
        let beforeTarget = target.snapshot()
        let beforeTool = tool.snapshot()
        unrelated.name = "Pending edit"
        let plan = try Fixture.plan(target: target, tool: tool, deleteTool: true)
        XCTAssertThrowsError(try persistence.apply(plan, context: context) {
            throw CardListOperationError(message: "Disk full")
        })
        XCTAssertEqual(target.snapshot(), beforeTarget)
        XCTAssertEqual(tool.snapshot(), beforeTool)
        XCTAssertEqual(unrelated.name, "Pending edit")
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionItem>()).count, 2)
        XCTAssertEqual(try CardListReference.find(beforeTool, in: context)?.snapshot(), beforeTool)
    }

    func testFailedUndoRestoresPostOperationStateAndCanBeRetried() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let tool = scenario.tool
        let beforeTool = tool.snapshot()
        let plan = try Fixture.plan(target: target, tool: tool, deleteTool: true)
        let receipt = try persistence.apply(plan, context: context, commit: context.save)
        XCTAssertThrowsError(try persistence.undo(receipt, context: context) {
            throw CardListOperationError(message: "Disk full")
        })
        XCTAssertEqual(target.snapshot(), receipt.afterTarget)
        XCTAssertNil(try CardListReference.find(beforeTool, in: context))
        try persistence.undo(receipt, context: context, commit: context.save)
        XCTAssertEqual(target.items.totalQuantity, 3)
    }

    func testTargetAndToolEditsInvalidatePreviewWithoutSaving() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let tool = scenario.tool
        let plan = try Fixture.plan(target: target, tool: tool)
        tool.items.first?.quantity = 4
        var saves = 0
        XCTAssertThrowsError(try persistence.apply(plan, context: context) { saves += 1 })
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(target.items.totalQuantity, 3)
        let fresh = try Fixture.plan(target: target, tool: tool)
        target.items.first?.foil = true
        XCTAssertThrowsError(try persistence.apply(fresh, context: context) { saves += 1 })
        XCTAssertEqual(saves, 0)
    }

    func testDeletedTargetInvalidatesPreview() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let tool = scenario.tool
        let plan = try Fixture.plan(target: target, tool: tool)
        target.delete(in: context)
        try context.save()
        XCTAssertThrowsError(try persistence.apply(plan, context: context, commit: context.save))
    }

    func testEditingTargetAfterApplyBlocksUndo() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let tool = scenario.tool
        let plan = try Fixture.plan(target: target, tool: tool, operation: .add)
        let receipt = try persistence.apply(plan, context: context, commit: context.save)
        target.items.first?.quantity = 9
        XCTAssertThrowsError(try persistence.undo(receipt, context: context, commit: context.save))
        XCTAssertEqual(target.items.totalQuantity, 9)
    }

    func testKeptToolCanBeEditedWithoutBlockingUndo() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let tool = scenario.tool
        let plan = try Fixture.plan(target: target, tool: tool, operation: .add)
        let receipt = try persistence.apply(plan, context: context, commit: context.save)
        tool.items.first?.quantity = 7
        try persistence.undo(receipt, context: context, commit: context.save)
        XCTAssertEqual(tool.items.totalQuantity, 7)
        XCTAssertEqual(target.items.totalQuantity, 3)
    }

    func testPriceRefreshDoesNotInvalidatePreviewOrUndoAndLatestPricesAreKept() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let tool = scenario.tool
        let plan = try Fixture.plan(target: target, tool: tool, operation: .add)
        target.items.first?.priceRetail = "9.99"
        let receipt = try persistence.apply(plan, context: context, commit: context.save)
        target.items.first?.priceBuy = "2.50"
        try persistence.undo(receipt, context: context, commit: context.save)
        XCTAssertEqual(target.items.totalQuantity, 3)
        XCTAssertEqual(target.items.first?.priceRetail, "9.99")
        XCTAssertEqual(target.items.first?.priceBuy, "2.50")
    }

    func testRenamingTargetInvalidatesPreview() throws {
        let scenario = try setup()
        let plan = try Fixture.plan(target: scenario.target, tool: scenario.tool, operation: .add)
        switch scenario.target {
        case .collection(let list): list.name = "Renamed"
        case .deck(let list): list.name = "Renamed"
        }
        XCTAssertThrowsError(try persistence.apply(plan, context: scenario.context, commit: scenario.context.save))
    }

    func testNoChangeCannotDeleteTool() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let tool = scenario.tool
        target.items.first?.foil = true
        try context.save()
        let plan = try Fixture.plan(target: target, tool: tool, deleteTool: true)
        XCTAssertThrowsError(try persistence.apply(plan, context: context, commit: context.save))
        XCTAssertEqual(tool.items.totalQuantity, 5)
        XCTAssertFalse(context.hasChanges)
    }

    func testCSVSubtractionUsesSharedPlannerAndUndo() throws {
        let scenario = try setup()
        let context = scenario.context
        let target = scenario.target
        let rows = try [CSVImportTestFixtures.row(quantity: 5)]
        target.items.first?.scryfallId = try CSVImportTestFixtures.printing().scryfallId
        try context.save()
        let plan = try CardListOperationPlanner().plan(
            target: target.snapshot(), toolItems: CSVImportPersistence().preparedItems(rows),
            toolName: "sell.csv", operation: .subtract
        )
        let receipt = try persistence.apply(plan, context: context, commit: context.save)
        XCTAssertEqual(plan.affectedQuantity, 3)
        XCTAssertEqual(plan.unavailableQuantity, 2)
        XCTAssertTrue(target.items.isEmpty)
        try persistence.undo(receipt, context: context, commit: context.save)
        XCTAssertEqual(target.items.totalQuantity, 3)
    }
}
