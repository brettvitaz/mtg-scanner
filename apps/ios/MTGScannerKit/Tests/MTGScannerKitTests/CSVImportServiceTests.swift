import XCTest
@testable import MTGScannerKit

final class CSVImportServiceTests: XCTestCase {
    private func parse(_ text: String) throws -> [CSVImportRow] {
        try CSVImportService().parse(data: Data(text.utf8))
    }

    func testExportRoundTripPreservesIdentityAndQuantity() throws {
        let item = CollectionItem(
            title: "Chandra, Awakened Inferno", edition: "Core Set 2020", setCode: "M20",
            collectorNumber: "127", foil: true, scryfallId: "chandra", quantity: 3
        )
        let file = try XCTUnwrap(ExportService().export(items: [item], format: .csv, name: "Deck"))
        let record = try XCTUnwrap(CSVImportService().parse(data: file.data).first?.record)
        XCTAssertEqual(record.title, item.title)
        XCTAssertEqual(record.edition, item.edition)
        XCTAssertEqual(record.collectorNumber, "127")
        XCTAssertEqual(record.quantity, 3)
        XCTAssertTrue(record.foil)
        XCTAssertEqual(record.scryfallId, "chandra")
    }

    func testBOMReorderedColumnsAndAbsentCollectorNumber() throws {
        let text = "\u{FEFF}foil,edition,title,quantity,extra\r\n"
            + "false,Magic 2010,Lightning Bolt,4,ignored\r\n"
        let rows = try parse(text)
        let record = try XCTUnwrap(rows.first?.record)
        XCTAssertNil(record.collectorNumber)
        XCTAssertNil(record.setCode)
        XCTAssertEqual(record.quantity, 4)
        XCTAssertEqual(rows.first?.id, 2)
    }

    func testQuotedCommasEscapedQuotesMultilineAndUnicode() throws {
        let text = "quantity,title,edition,foil,collector_number\n"
            + "1,\"Æther, \"\"Test\"\"\nCard\",Test,true,CSP-78\n"
        let record = try XCTUnwrap(parse(text).first?.record)
        XCTAssertEqual(record.title, "Æther, \"Test\"\nCard")
        XCTAssertEqual(record.collectorNumber, "CSP-78")
    }

    func testBlankRecordsAreIgnoredButRecordNumbersPreserved() throws {
        let rows = try parse("title,edition,quantity,foil\n\nLightning Bolt,Magic 2010,1,false\n,,,\n")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 3)
    }

    func testBlankCollectorNumberIsOptional() throws {
        let row = try XCTUnwrap(parse("title,edition,quantity,foil,collector_number\nBolt,M10,1,false,\n").first)
        XCTAssertNotNil(row.record)
        XCTAssertNil(row.record?.collectorNumber)
    }

    func testMissingAndDuplicateHeadersRejectFile() {
        for text in ["title,quantity\nBolt,1", "title,edition,quantity,foil,title\n"] {
            XCTAssertThrowsError(try parse(text))
        }
    }

    func testMalformedQuotedFieldsRejectFile() {
        for value in ["\"Bolt", "Bo\"lt", "\"Bolt\"extra"] {
            XCTAssertThrowsError(try parse("title,edition,quantity,foil\n\(value),M10,1,false"))
        }
    }

    func testInvalidRowsHaveIssuesAndCannotResolve() throws {
        let text = "title,edition,quantity,foil\n"
            + ",M10,1,false\nBolt,,1,false\nBolt,M10,0,false\nBolt,M10,-1,false\n"
            + "Bolt,M10,1.5,false\nBolt,M10,1,yes\nBolt,M10,1\n"
        let rows = try parse(text)
        XCTAssertEqual(rows.count, 7)
        XCTAssertTrue(rows.allSatisfy { $0.issue != nil && $0.record == nil })
    }

    func testEmptyAndInvalidEncodingRejectFile() {
        XCTAssertThrowsError(try parse(""))
        XCTAssertThrowsError(try CSVImportService().parse(data: Data([0xFF])))
    }

    func testFileReadReturnsParsedRows() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("title,edition,quantity,foil\nBolt,M10,1,false".utf8).write(to: url)
        let rows = try await CSVImportService().read(url: url)
        XCTAssertEqual(rows.first?.record?.title, "Bolt")
    }
}
