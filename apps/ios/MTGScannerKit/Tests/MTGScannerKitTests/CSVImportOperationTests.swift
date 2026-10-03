import XCTest
@testable import MTGScannerKit

@MainActor
final class CSVImportOperationTests: XCTestCase {
    private typealias Fixture = CardListOperationTestFixtures

    func testCSVAddAppliesOnlyIncludedRowsAndCanUndo() throws {
        for kind in [CardListKind.collection, .deck] {
            let context = try Fixture.context()
            let target = Fixture.list(kind)
            target.insert(in: context)
            Fixture.item(3, id: "bolt-146", in: target, context: context)
            try context.save()
            let review = CSVImportViewModel()
            review.rows = try [
                CSVImportTestFixtures.row(quantity: 2),
                CSVImportTestFixtures.row(id: 3, quantity: 50)
            ]
            review.toggleSkip(3)
            let model = CardListOperationViewModel(
                target: target, csvItems: try CSVImportPersistence().preparedItems(review.rows),
                csvName: "cards.csv", operation: .add
            )
            XCTAssertTrue(model.canApply)
            XCTAssertEqual(model.plan?.beforeQuantity, 3)
            XCTAssertEqual(model.plan?.afterQuantity, 5)
            model.apply(context: context, commit: context.save)
            XCTAssertEqual(target.items.totalQuantity, 5)
            model.undo(context: context, commit: context.save)
            XCTAssertEqual(target.items.totalQuantity, 3)
        }
    }

    func testCSVSubtractReportsShortfallPreservesOtherFinishesAndCanUndo() throws {
        for kind in [CardListKind.collection, .deck] {
            let context = try Fixture.context()
            let target = Fixture.list(kind)
            target.insert(in: context)
            Fixture.item(3, id: "bolt-146", in: target, context: context)
            Fixture.item(4, id: "bolt-146", foil: true, in: target, context: context)
            try context.save()
            let review = CSVImportViewModel()
            review.rows = try [CSVImportTestFixtures.row(quantity: 5)]
            let model = CardListOperationViewModel(
                target: target, csvItems: try CSVImportPersistence().preparedItems(review.rows),
                csvName: "sale.csv", operation: .subtract
            )
            XCTAssertEqual(model.operation, .subtract)
            XCTAssertEqual(model.plan?.affectedQuantity, 3)
            XCTAssertEqual(model.plan?.unavailableQuantity, 2)
            XCTAssertEqual(model.plan?.afterQuantity, 4)
            model.apply(context: context, commit: context.save)
            XCTAssertEqual(target.items.totalQuantity, 4)
            XCTAssertEqual(target.items.first?.foil, true)
            model.undo(context: context, commit: context.save)
            XCTAssertEqual(target.items.totalQuantity, 7)
            XCTAssertEqual(target.items.filter { $0.foil == false }.first?.quantity, 3)
        }
    }

    func testCSVReviewChangingOperationRecomputesChangesWithoutSaving() throws {
        let context = try Fixture.context()
        let target = Fixture.list()
        target.insert(in: context)
        Fixture.item(3, id: "bolt-146", in: target, context: context)
        try context.save()
        let model = CardListOperationViewModel(
            target: target, csvItems: try CSVImportPersistence().preparedItems([CSVImportTestFixtures.row()]),
            csvName: "cards.csv", operation: .add
        )
        XCTAssertEqual(model.plan?.afterQuantity, 5)
        model.operation = .subtract
        model.refresh()
        XCTAssertEqual(model.plan?.afterQuantity, 1)
        XCTAssertEqual(target.items.totalQuantity, 3)
        XCTAssertNil(model.receipt)
    }
}
