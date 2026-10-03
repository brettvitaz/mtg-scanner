import XCTest
@testable import MTGScannerKit

final class CSVImportViewModelTests: XCTestCase {
    @MainActor
    func testCardKingdomEditionAliasesResolveWithoutManualSelection() async throws {
        let csv = """
        quantity,title,edition,set_code,collector_number,foil,scryfall_id
        1,"Ajani, Mentor of Heroes",Masterpiece Series: Mythic Edition,MED,RA5,true,596f6812-2cee-4f0b-b1e5-ddf1f57c3f95
        1,Alhammarret's Archive,Mystery Booster/The List,PLST,ORI-221,false,810c91b8-6b2f-469f-8fd1-568885178c9b
        """
        let data = Data("""
        {"printings":[
          {"name":"Ajani, Mentor of Heroes","set_code":"MED","set_name":"Mythic Edition",
           "collector_number":"RA5","scryfall_id":"596f6812-2cee-4f0b-b1e5-ddf1f57c3f95","finishes":"foil"},
          {"name":"Alhammarret's Archive","set_code":"PLST","set_name":"The List",
           "collector_number":"ORI-221","scryfall_id":"810c91b8-6b2f-469f-8fd1-568885178c9b","finishes":"nonfoil"}
        ]}
        """.utf8)
        let printings = try JSONDecoder().decode(CardPrintingsResponse.self, from: data).printings
        let model = CSVImportViewModel()
        model.rows = try CSVImportService().parse(data: Data(csv.utf8))
        await model.resolve { title in printings.filter { $0.name == title } }
        XCTAssertEqual(model.rows.map { $0.printing?.scryfallId }, printings.map(\.scryfallId))
        XCTAssertTrue(model.rows.allSatisfy { $0.issue == nil })
        XCTAssertTrue(model.canImport)
        XCTAssertEqual(model.totalQuantity, 2)
    }

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
