import XCTest
@testable import MTGScannerKit

final class CSVImportReviewTests: XCTestCase {
    @MainActor
    func testReviewGroupsPreserveFileOrderAndCountOnlyReadyCopies() throws {
        let model = CSVImportViewModel()
        var skipped = try CSVImportTestFixtures.row(id: 7, quantity: 100)
        skipped.isSkipped = true
        model.rows = [
            try CSVImportTestFixtures.row(id: 2, quantity: 4),
            CSVImportRow(id: 4, title: "Ambiguous", record: CSVImportTestFixtures.record(quantity: 9)),
            CSVImportRow(id: 5, title: "Invalid", record: nil, issue: "Invalid quantity"),
            skipped,
            try CSVImportTestFixtures.row(id: 8, quantity: 3)
        ]
        XCTAssertEqual(model.readyRows.map(\.id), [2, 8])
        XCTAssertEqual(model.attentionRows.map(\.id), [4, 5])
        XCTAssertEqual(model.skippedRows.map(\.id), [7])
        XCTAssertEqual(model.readyQuantity, 7)
        XCTAssertEqual(model.totalQuantity, 16)
        XCTAssertFalse(model.canImport)
    }

    @MainActor
    func testChoosingSkippingAndIncludingMoveRowsBetweenGroups() throws {
        let model = CSVImportViewModel()
        model.rows = [CSVImportRow(id: 2, title: "Lightning Bolt", record: CSVImportTestFixtures.record())]
        model.toggleSkip(2)
        XCTAssertEqual(model.skippedRows.map(\.id), [2])
        XCTAssertTrue(model.attentionRows.isEmpty)
        XCTAssertEqual(model.readyQuantity, 0)
        model.toggleSkip(2)
        XCTAssertEqual(model.attentionRows.map(\.id), [2])
        model.choose(try CSVImportTestFixtures.printing(), for: 2)
        XCTAssertTrue(model.attentionRows.isEmpty)
        XCTAssertEqual(model.readyQuantity, 2)
        XCTAssertTrue(model.canImport)
        model.toggleSkip(2)
        XCTAssertTrue(model.readyRows.isEmpty)
        XCTAssertFalse(model.canImport)
        model.toggleSkip(2)
        XCTAssertEqual(model.readyRows.map(\.id), [2])
        XCTAssertTrue(model.canImport)
    }

    @MainActor
    func testChoosingSkippedRowIncludesItAndClearsIssue() throws {
        let model = CSVImportViewModel()
        model.rows = [CSVImportRow(
            id: 2, title: "Lightning Bolt", record: CSVImportTestFixtures.record(), issue: "Ambiguous", isSkipped: true
        )]
        model.choose(try CSVImportTestFixtures.printing(), for: 2)
        XCTAssertTrue(model.skippedRows.isEmpty)
        XCTAssertEqual(model.readyRows.map(\.id), [2])
        XCTAssertNil(model.rows[0].issue)
        XCTAssertTrue(model.canImport)
    }

    @MainActor
    func testEmptyAndInvalidRowsNeverBecomeReady() {
        let model = CSVImportViewModel()
        XCTAssertEqual(model.readyQuantity, 0)
        XCTAssertTrue(model.attentionRows.isEmpty)
        XCTAssertFalse(model.canImport)
        model.rows = [CSVImportRow(id: 3, title: "Invalid", record: nil, issue: "Invalid quantity")]
        model.toggleSkip(3)
        XCTAssertEqual(model.skippedCount, 1)
        XCTAssertEqual(model.readyQuantity, 0)
        XCTAssertFalse(model.canImport)
        model.toggleSkip(3)
        XCTAssertEqual(model.attentionRows.map(\.id), [3])
        XCTAssertFalse(model.canImport)
    }

    @MainActor
    func testSkipAllUnmatchedPreservesMatchedRowsAndExistingSkips() throws {
        let model = CSVImportViewModel()
        var skipped = try CSVImportTestFixtures.row(id: 6, quantity: 8)
        skipped.isSkipped = true
        model.rows = [
            try CSVImportTestFixtures.row(id: 2, quantity: 4),
            CSVImportRow(id: 3, title: "Ambiguous", record: CSVImportTestFixtures.record()),
            CSVImportRow(id: 5, title: "Invalid", record: nil, issue: "Invalid quantity"),
            skipped
        ]
        model.skipAllUnmatched()
        XCTAssertEqual(model.readyRows.map(\.id), [2])
        XCTAssertEqual(model.readyQuantity, 4)
        XCTAssertEqual(model.skippedRows.map(\.id), [3, 5, 6])
        XCTAssertTrue(model.attentionRows.isEmpty)
        XCTAssertTrue(model.canImport)
        model.skipAllUnmatched()
        XCTAssertEqual(model.skippedRows.map(\.id), [3, 5, 6])
        model.toggleSkip(3)
        XCTAssertEqual(model.attentionRows.map(\.id), [3])
        XCTAssertFalse(model.canImport)
    }

    @MainActor
    func testSkipAllUnmatchedDoesNothingWhileLoading() {
        let model = CSVImportViewModel()
        model.rows = [CSVImportRow(id: 2, title: "Unmatched", record: CSVImportTestFixtures.record())]
        model.isLoading = true
        model.skipAllUnmatched()
        XCTAssertFalse(model.rows[0].isSkipped)
        model.isLoading = false
        model.skipAllUnmatched()
        XCTAssertTrue(model.rows[0].isSkipped)
        XCTAssertFalse(model.canImport)
    }

    @MainActor
    func testSkipAllUnmatchedHandlesEmptyAndAllReadyFiles() throws {
        let model = CSVImportViewModel()
        model.skipAllUnmatched()
        XCTAssertTrue(model.rows.isEmpty)
        model.rows = try [CSVImportTestFixtures.row()]
        model.skipAllUnmatched()
        XCTAssertEqual(model.skippedCount, 0)
        XCTAssertTrue(model.canImport)
    }

    @MainActor
    func testUndoBulkSkipRestoresOnlyTheLastBatch() throws {
        let model = CSVImportViewModel()
        var existingSkip = try CSVImportTestFixtures.row(id: 5)
        existingSkip.isSkipped = true
        model.rows = [
            try CSVImportTestFixtures.row(),
            CSVImportRow(id: 3, title: "Unmatched", record: CSVImportTestFixtures.record(), issue: "Ambiguous"),
            CSVImportRow(id: 4, title: "Invalid", record: nil, issue: "Invalid quantity"),
            existingSkip
        ]
        model.skipAllUnmatched()
        XCTAssertEqual(model.bulkSkippedCount, 2)
        XCTAssertTrue(model.canUndoSkipAll)
        model.skipAllUnmatched()
        XCTAssertEqual(model.bulkSkippedCount, 2)
        model.undoSkipAllUnmatched()
        XCTAssertEqual(model.attentionRows.map(\.id), [3, 4])
        XCTAssertEqual(model.skippedRows.map(\.id), [5])
        XCTAssertEqual(model.readyRows.map(\.id), [2])
        XCTAssertEqual(model.rows[1].issue, "Ambiguous")
        XCTAssertFalse(model.canUndoSkipAll)
        XCTAssertEqual(model.bulkSkippedCount, 0)
        XCTAssertFalse(model.canImport)
    }

    @MainActor
    func testManualChangesAreNotOverwrittenByBulkUndo() throws {
        let model = CSVImportViewModel()
        model.rows = (2...4).map {
            CSVImportRow(id: $0, title: "Lightning Bolt", record: CSVImportTestFixtures.record())
        }
        model.skipAllUnmatched()
        model.choose(try CSVImportTestFixtures.printing(), for: 2)
        model.toggleSkip(3)
        model.toggleSkip(3)
        XCTAssertEqual(model.bulkSkippedCount, 1)
        model.undoSkipAllUnmatched()
        XCTAssertEqual(model.readyRows.map(\.id), [2])
        XCTAssertEqual(model.skippedRows.map(\.id), [3])
        XCTAssertEqual(model.attentionRows.map(\.id), [4])
    }

    @MainActor
    func testLoadingBlocksUndoAndChoosingNewFileClearsBatch() async {
        let model = CSVImportViewModel()
        model.rows = [CSVImportRow(id: 2, title: "Unmatched", record: CSVImportTestFixtures.record())]
        model.skipAllUnmatched()
        model.isLoading = true
        model.undoSkipAllUnmatched()
        XCTAssertTrue(model.rows[0].isSkipped)
        XCTAssertFalse(model.canUndoSkipAll)
        model.isLoading = false
        XCTAssertTrue(model.canUndoSkipAll)
        let absentFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).csv")
        await model.load(url: absentFile) { _ in XCTFail("Missing file must not fetch cards"); return [] }
        XCTAssertFalse(model.canUndoSkipAll)
        XCTAssertEqual(model.bulkSkippedCount, 0)
        XCTAssertTrue(model.rows.isEmpty)
    }

    @MainActor
    func testOverflowAndLoadingKeepImportDisabled() throws {
        let model = CSVImportViewModel()
        model.rows = try [CSVImportTestFixtures.row(quantity: Int.max), CSVImportTestFixtures.row(id: 3)]
        XCTAssertNil(model.readyQuantity)
        XCTAssertFalse(model.canImport)
        model.toggleSkip(3)
        XCTAssertEqual(model.readyQuantity, Int.max)
        XCTAssertTrue(model.canImport)
        model.isLoading = true
        XCTAssertFalse(model.canImport)
    }
}
