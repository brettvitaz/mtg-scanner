import XCTest
@testable import MTGScanner

final class ExportServiceTests: XCTestCase {
    private let service = ExportService()

    // MARK: - JSON Export

    func testExportJSONProducesValidJSON() throws {
        let items = [makeSampleItem(title: "Lightning Bolt", edition: "M10")]
        let file = try XCTUnwrap(service.export(items: items, format: .json, name: "test"))

        XCTAssertEqual(file.filename, "test.json")
        XCTAssertEqual(file.mimeType, "application/json")

        let rawParsed = try JSONSerialization.jsonObject(with: file.data)
        let parsed = try XCTUnwrap(rawParsed as? [[String: Any]])
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0]["title"] as? String, "Lightning Bolt")
        XCTAssertEqual(parsed[0]["edition"] as? String, "M10")
        XCTAssertEqual(parsed[0]["quantity"] as? Int, 1)
    }

    func testExportJSONMultipleItems() throws {
        let items = [
            makeSampleItem(title: "Lightning Bolt", edition: "M10"),
            makeSampleItem(title: "Counterspell", edition: "DMR")
        ]
        let file = try XCTUnwrap(service.export(items: items, format: .json, name: "multi"))

        let rawParsed = try JSONSerialization.jsonObject(with: file.data)
        let parsed = try XCTUnwrap(rawParsed as? [[String: Any]])
        XCTAssertEqual(parsed.count, 2)
    }

    func testExportJSONEmptyItems() throws {
        let file = try XCTUnwrap(service.export(items: [], format: .json, name: "empty"))

        XCTAssertEqual(file.filename, "empty.json")
        let text = try XCTUnwrap(String(data: file.data, encoding: .utf8))
        XCTAssertTrue(text.contains("[]") || text.contains("[\n\n]"))
    }

    // MARK: - CSV Export

    func testExportCSVProducesValidCSV() throws {
        let items = [makeSampleItem(title: "Lightning Bolt", edition: "M10", setCode: "M10", collectorNumber: "146")]
        let file = try XCTUnwrap(service.export(items: items, format: .csv, name: "test"))

        XCTAssertEqual(file.filename, "test.csv")
        XCTAssertEqual(file.mimeType, "text/csv")

        let text = try XCTUnwrap(String(data: file.data, encoding: .utf8))
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2) // header + 1 data row
        XCTAssertTrue(lines[0].contains("quantity"))
        XCTAssertTrue(lines[0].contains("title"))
        XCTAssertTrue(lines[1].contains("1"))
        XCTAssertTrue(lines[1].contains("Lightning Bolt"))
        XCTAssertTrue(lines[1].contains("M10"))
        XCTAssertTrue(lines[1].contains("146"))
    }

    func testExportCSVEscapesCommasInValues() throws {
        let items = [makeSampleItem(title: "Teferi, Hero of Dominaria", edition: "DOM")]
        let file = try XCTUnwrap(service.export(items: items, format: .csv, name: "escape"))

        let text = try XCTUnwrap(String(data: file.data, encoding: .utf8))
        let lines = text.components(separatedBy: "\n")
        // Title with comma should be quoted
        XCTAssertTrue(lines[1].contains("\"Teferi, Hero of Dominaria\""))
    }

    func testExportCSVEscapesQuotesInValues() throws {
        let items = [makeSampleItem(title: "Lim-Dûl\"s Vault", edition: "ALL")]
        let file = try XCTUnwrap(service.export(items: items, format: .csv, name: "quotes"))

        let text = try XCTUnwrap(String(data: file.data, encoding: .utf8))
        // Double-quotes inside should be escaped as ""
        XCTAssertTrue(text.contains("\"\""))
    }

    func testExportCSVEmptyItems() throws {
        let file = try XCTUnwrap(service.export(items: [], format: .csv, name: "empty"))

        let text = try XCTUnwrap(String(data: file.data, encoding: .utf8))
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 1) // header only
    }

    // MARK: - Helpers

    private func makeSampleItem(
        title: String,
        edition: String,
        setCode: String? = nil,
        collectorNumber: String? = nil
    ) -> CollectionItem {
        CollectionItem(
            title: title,
            edition: edition,
            setCode: setCode,
            collectorNumber: collectorNumber,
            foil: false
        )
    }
}
