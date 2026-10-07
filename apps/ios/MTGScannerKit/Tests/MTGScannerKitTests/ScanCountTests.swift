import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class ScanCountTests: XCTestCase {
    func testCountsAccumulateAcrossOtherTabVisits() {
        let app = AppModel()
        XCTAssertNil(app.resultsBadgeText)
        for tab in [0, 2, 3, 0] {
            app.selectTab(tab)
            app.recordScannedCard()
        }
        XCTAssertEqual(app.newlyScannedCardCount, 4)
        XCTAssertEqual(app.resultsBadgeText, "4")
    }

    func testOpeningResultsClearsAndSuppressesCountUntilLeaving() {
        let app = AppModel()
        app.recordScannedCard()
        app.selectTab(1)
        XCTAssertNil(app.resultsBadgeText)
        app.recordScannedCard()
        XCTAssertEqual(app.newlyScannedCardCount, 0)
        app.selectTab(2)
        app.recordScannedCard()
        XCTAssertEqual(app.newlyScannedCardCount, 1)
    }

    func testNewAppSessionDoesNotRestorePreviousCount() {
        let app = AppModel()
        app.recordScannedCard()
        let relaunched = AppModel()
        XCTAssertEqual(relaunched.newlyScannedCardCount, 0)
        XCTAssertNil(relaunched.resultsBadgeText)
    }

    func testBadgeCapsDisplayButAccessibilityKeepsExactCount() {
        let app = AppModel()
        assertBadge(app, count: 1, badge: "1", accessibility: "1 newly scanned card")
        assertBadge(app, count: 99, badge: "99", accessibility: "99 newly scanned cards")
        assertBadge(app, count: 100, badge: "99+", accessibility: "100 newly scanned cards")
        assertBadge(app, count: 1_000, badge: "99+", accessibility: "1000 newly scanned cards")
        app.selectTab(1)
        XCTAssertEqual(app.resultsBadgeAccessibilityValue, "")
    }

    func testNonScanListMutationsDoNotChangeBadge() throws {
        let app = AppModel()
        let context = try makeScanCountContext()
        app.modelContext = context
        let existing = CollectionItem(title: "Island", edition: "Test")
        context.insert(existing)
        try context.save()
        app.recordScannedCard()
        let imported = CollectionItem(title: "Bolt", edition: "Test")
        context.insert(imported)
        existing.quantity = 4
        let collection = CardCollection(name: "Binder")
        context.insert(collection)
        imported.collection = collection
        app.deleteUndo.register([existing], in: .results)
        context.delete(existing)
        try context.save()
        let deletion = try XCTUnwrap(app.deleteUndo.deletion(in: .results))
        try app.deleteUndo.restore(in: .results, deletionID: deletion.id, context: context, commit: context.save)
        XCTAssertEqual(app.newlyScannedCardCount, 1)
    }

    private func assertBadge(_ app: AppModel, count: Int, badge: String, accessibility: String) {
        while app.newlyScannedCardCount < count { app.recordScannedCard() }
        XCTAssertEqual(app.resultsBadgeText, badge)
        XCTAssertEqual(app.resultsBadgeAccessibilityValue, accessibility)
    }
}

@MainActor
func makeScanCountContext() throws -> ModelContext {
    let schema = Schema([CollectionItem.self, CardCollection.self, Deck.self])
    let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    context.autosaveEnabled = false
    return context
}
