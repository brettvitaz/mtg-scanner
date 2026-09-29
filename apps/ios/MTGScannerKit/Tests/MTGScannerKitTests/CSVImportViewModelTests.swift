import XCTest
@testable import MTGScannerKit

final class CSVImportViewModelTests: XCTestCase {
    @MainActor
    func testResolutionCachesTitlesAndEnablesImport() async throws {
        let model = CSVImportViewModel()
        model.rows = try [CSVImportTestFixtures.row(), CSVImportTestFixtures.row(id: 3, quantity: 3)]
        for index in model.rows.indices { model.rows[index].printing = nil }
        var calls = 0
        let printing = try CSVImportTestFixtures.printing()
        await model.resolve { _ in calls += 1; return [printing] }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.processedRows, 2)
        XCTAssertEqual(model.totalQuantity, 5)
        XCTAssertTrue(model.canImport)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testFailureRetriedAndResolvedRowsPreserved() async throws {
        let model = CSVImportViewModel()
        model.rows = try [CSVImportTestFixtures.row(), CSVImportTestFixtures.row(id: 3)]
        model.rows[1].printing = nil
        await model.resolve { _ in throw CSVImportError(message: "Offline") }
        XCTAssertNotNil(model.rows[0].printing)
        XCTAssertNotNil(model.rows[1].issue)
        XCTAssertFalse(model.canImport)
        let printing = try CSVImportTestFixtures.printing()
        await model.resolve { _ in [printing] }
        XCTAssertTrue(model.canImport)
        XCTAssertNil(model.rows[1].issue)
    }

    @MainActor
    func testChoosePrintingAndExplicitSkipControlReadiness() throws {
        let model = CSVImportViewModel()
        model.rows = [
            CSVImportRow(id: 2, title: "Bolt", record: CSVImportTestFixtures.record(), issue: "Ambiguous"),
            CSVImportRow(id: 3, title: "Invalid", record: nil, issue: "Invalid quantity")
        ]
        model.choose(try CSVImportTestFixtures.printing(), for: 2)
        XCTAssertFalse(model.canImport)
        model.toggleSkip(3)
        XCTAssertTrue(model.canImport)
        XCTAssertEqual(model.skippedCount, 1)
        model.toggleSkip(2)
        XCTAssertFalse(model.canImport)
        model.toggleSkip(3)
        XCTAssertFalse(model.canImport)
    }

    @MainActor
    func testUnsupportedFinishCannotBeChosen() throws {
        let model = CSVImportViewModel()
        model.rows = [CSVImportRow(id: 2, title: "Bolt", record: CSVImportTestFixtures.record(foil: true))]
        model.choose(try CSVImportTestFixtures.printing(finishes: "nonfoil"), for: 2)
        XCTAssertNil(model.rows[0].printing)
        XCTAssertFalse(model.canImport)
    }

    @MainActor
    func testCancelledResolutionDoesNotApplyLateResult() async throws {
        let model = CSVImportViewModel()
        model.rows = [CSVImportRow(id: 2, title: "Bolt", record: CSVImportTestFixtures.record())]
        let printing = try CSVImportTestFixtures.printing()
        let task = Task {
            await model.resolve { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return [printing]
            }
        }
        await task.value
        XCTAssertNil(model.rows[0].printing)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testOverflowDisablesImport() throws {
        let model = CSVImportViewModel()
        model.rows = try [CSVImportTestFixtures.row(quantity: Int.max), CSVImportTestFixtures.row(id: 3)]
        XCTAssertNil(model.totalQuantity)
        XCTAssertFalse(model.canImport)
    }
}
