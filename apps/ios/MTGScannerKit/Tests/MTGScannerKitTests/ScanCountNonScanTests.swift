import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class ScanCountNonScanTests: XCTestCase {
    func testManualAddAndMergePreserveScanCount() throws {
        let fixture = try setup()
        let app = fixture.app
        let context = fixture.context
        let target = fixture.target
        let model = AddCardViewModel()
        model.quantity = 3
        let printing = try CSVImportTestFixtures.printing()
        for _ in 0..<2 {
            let item = model.buildCollectionItem(from: printing)
            mergeOrInsert(item, into: target.items, context: context) { target.assign($0) }
            try context.save()
            XCTAssertEqual(app.newlyScannedCardCount, 2)
        }
        XCTAssertEqual(target.items.count, 1)
        XCTAssertEqual(target.items.first?.quantity, 6)
    }

    func testCSVReviewApplyAndUndoPreserveScanCount() throws {
        let fixture = try setup()
        let app = fixture.app
        let context = fixture.context
        let target = fixture.target
        let review = CSVImportViewModel()
        review.rows = try [CSVImportTestFixtures.row(quantity: 3), CSVImportTestFixtures.row(id: 3, quantity: 7)]
        review.toggleSkip(3)
        let operation = CardListOperationViewModel(
            target: target, csvItems: try CSVImportPersistence().preparedItems(review.rows),
            csvName: "cards.csv", operation: .add
        )
        XCTAssertTrue(operation.canApply)
        operation.apply(context: context, commit: context.save)
        XCTAssertNotNil(operation.receipt)
        XCTAssertEqual(target.items.totalQuantity, 3)
        XCTAssertEqual(app.newlyScannedCardCount, 2)
        operation.undo(context: context, commit: context.save)
        XCTAssertTrue(operation.wasUndone)
        XCTAssertEqual(target.items.totalQuantity, 0)
        XCTAssertEqual(app.newlyScannedCardCount, 2)
    }

    func testCardEditSaveAndCorrectionPreserveScanCount() throws {
        let previousCorrections = UserDefaults.standard.data(forKey: "card_corrections")
        defer { UserDefaults.standard.set(previousCorrections, forKey: "card_corrections") }
        let fixture = try setup()
        let app = fixture.app
        let context = fixture.context
        let target = fixture.target
        let item = CollectionItem(title: "Wrong card", edition: "Old set", quantity: 4)
        target.assign(item)
        context.insert(item)
        try context.save()
        let draft = CardEditDraft(card: item.toRecognizedCard())
        draft.select(try CSVImportTestFixtures.printing(), foil: true)
        XCTAssertTrue(draft.save(item: item, context: context, merge: false))
        let detail = CardDetailViewModel(card: item.toRecognizedCard(), cropImage: nil)
        detail.selectedPrinting = draft.printing
        detail.editTitle = item.title
        detail.editEdition = item.edition
        detail.editCollectorNumber = item.collectorNumber ?? ""
        detail.editFoil = item.foil
        detail.saveCorrection(to: app)
        XCTAssertEqual(item.title, "Lightning Bolt")
        XCTAssertEqual(item.quantity, 4)
        XCTAssertTrue(item.foil)
        XCTAssertNotNil(app.corrections[item.id])
        XCTAssertEqual(app.newlyScannedCardCount, 2)
    }

    private func setup() throws -> NonScanFixture {
        let app = AppModel()
        let context = try makeScanCountContext()
        app.modelContext = context
        let collection = CardCollection(name: "Binder")
        context.insert(collection)
        try context.save()
        app.recordScannedCard()
        app.recordScannedCard()
        return NonScanFixture(app: app, context: context, target: .collection(collection))
    }
}

@MainActor
private struct NonScanFixture {
    let app: AppModel
    let context: ModelContext
    let target: CardListReference
}
