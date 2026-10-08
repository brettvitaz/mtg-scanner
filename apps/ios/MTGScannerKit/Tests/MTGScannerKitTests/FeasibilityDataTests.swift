import CryptoKit
import XCTest
@testable import MTGScannerFixtures

final class FeasibilityDataTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testCatalogMergesFacesAndPreservesMetadataAndNormalization() throws {
        let dir = try directory()
        let source = try upstream(dir)
        let destination = dir.appending(path: "catalog.sqlite")
        try ProbeCatalog.install(from: source, to: destination)
        let db = try ProbeSQLite(destination, readOnly: true)
        let rows = try db.rows("SELECT * FROM cards")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["type_line"], "Instant // Instant")
        XCTAssertEqual(rows[0]["oracle_text"], "Deal damage.\n---\nTap target.")
        XCTAssertEqual(rows[0]["normalized_name"], "fire ice")
        XCTAssertEqual(rows[0]["normalized_collector_number"], "12a")
        XCTAssertEqual(rows[0]["finishes"], "nonfoil,foil")
        XCTAssertEqual(rows[0]["color_identity"], "R,U")
        XCTAssertEqual(rows[0]["scryfall_id"], "scryfall-1")
        XCTAssertEqual(rows[0]["card_kingdom_foil_url"], "https://example.com/foil")
        XCTAssertEqual(try db.rows("SELECT * FROM face_names").count, 2)
    }

    func testUpstreamEmptyOptionalFieldsBecomeNil() throws {
        let dir = try directory()
        let source = try upstream(dir)
        try ProbeSQLite(source).execute("UPDATE cards SET text='',manaCost='',colorIdentity='',finishes=''")
        let destination = dir.appending(path: "catalog.sqlite")
        try ProbeCatalog.install(from: source, to: destination)
        let row = try XCTUnwrap(ProbeSQLite(destination, readOnly: true).rows("SELECT * FROM cards").first)
        for field in ["oracle_text", "mana_cost", "color_identity", "finishes"] { XCTAssertNil(row[field], field) }
    }

    func testPriceFeedAcceptsMetadataBeforeDataAndEscapedBraces() throws {
        let dir = try directory()
        let source = dir.appending(path: "prices.json")
        let json = """
        {"meta":{"created_at":"2026-10-07"},"data":[
        {"name":"Bolt {special}","edition":"A","price_retail":"1.00"}]}
        """
        try Data(json.utf8).write(to: source)
        let destination = dir.appending(path: "prices.sqlite")
        try ProbePrices.install(from: source, to: destination)
        let db = try ProbeSQLite(destination, readOnly: true)
        let price = try ProbePrices.lookup(db, id: nil, name: "Bolt {special}", foil: false)
        XCTAssertEqual(price?["price_retail"], "1.00")
    }

    func testCancelledCatalogImportPreservesActiveDatabase() throws {
        let dir = try directory()
        let source = try upstream(dir)
        let destination = dir.appending(path: "catalog.sqlite")
        try Data("previous database".utf8).write(to: destination)
        var checkpoints = 0
        XCTAssertThrowsError(try ProbeCatalog.install(from: source, to: destination) {
            checkpoints += 1
            if checkpoints > 3 { throw CancellationError() }
        })
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "previous database")
    }

    func testActualTaskCancellationPreservesActiveDatabase() async throws {
        let dir = try directory()
        let source = try upstream(dir)
        try ProbeSQLite(source).execute("""
        WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1100)
        INSERT INTO cards(uuid,name,number,setCode,side)
        SELECT 'uuid-'||x,'Card '||x,x,'TST','a' FROM n;
        """)
        let destination = dir.appending(path: "catalog.sqlite")
        try Data("previous".utf8).write(to: destination)
        do {
            try await ProbeCancellation.catalog(source: source, destination: destination)
            XCTFail("Expected actual task cancellation")
        } catch is CancellationError {
            XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "previous")
        }
    }

    func testPriceImportPreservesFoilZeroAndCheapestNameFallback() throws {
        let dir = try directory()
        let source = dir.appending(path: "prices.json")
        let json = """
        {"data":[
        {"name":"Bolt","edition":"A","is_foil":"false","scryfall_id":"one",
         "price_retail":"2.00","qty_retail":"4","price_buy":"0.00","qty_buying":"0","url":"mtg/bolt"},
        {"name":"Bolt","edition":"B","is_foil":"false","price_retail":"1.00"},
        {"name":"Bolt","edition":"A","is_foil":"true","scryfall_id":"one","price_retail":"5.00"}]}
        """
        try Data(json.utf8).write(to: source)
        let destination = dir.appending(path: "prices.sqlite")
        try ProbePrices.install(from: source, to: destination)
        let db = try ProbeSQLite(destination, readOnly: true)
        let exact = try ProbePrices.lookup(db, id: "one", name: "Bolt", foil: false)
        XCTAssertEqual(exact?["url"], "https://www.cardkingdom.com/mtg/bolt")
        XCTAssertEqual(exact?["price_buy"], "0.00")
        XCTAssertEqual(exact?["qty_buying"], "0")
        XCTAssertEqual(try ProbePrices.lookup(db, id: "one", name: "Bolt", foil: true)?["price_retail"], "5.00")
        XCTAssertEqual(try ProbePrices.lookup(db, id: nil, name: "BOLT", foil: false)?["price_retail"], "1.00")
        XCTAssertNil(try ProbePrices.lookup(db, id: nil, name: "Missing", foil: false))
    }

    func testMalformedAndCancelledPriceRefreshRetainsPreviousDatabase() throws {
        let dir = try directory()
        let source = dir.appending(path: "prices.json")
        let destination = dir.appending(path: "prices.sqlite")
        try Data("previous".utf8).write(to: destination)
        for json in ["{\"data\":[{\"name\":\"Bolt\",\"edition\":\"A\"}", "<html>challenge</html>",
                     "{\"data\":[]}", "{\"data\":[{\"name\":\"Bolt\",\"edition\":\"A\"}]}garbage"] {
            try Data(json.utf8).write(to: source)
            XCTAssertThrowsError(try ProbePrices.install(from: source, to: destination))
            XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "previous")
        }
        try Data("{\"data\":[{\"name\":\"Bolt\",\"edition\":\"A\"}]}".utf8).write(to: source)
        XCTAssertThrowsError(try ProbePrices.install(from: source, to: destination) { throw CancellationError() })
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "previous")
    }

    func testGzipChecksumAndCorruption() throws {
        let dir = try directory()
        let source = dir.appending(path: "input.gz")
        let destination = dir.appending(path: "output")
        let zipped = try XCTUnwrap(Data(base64Encoded: "H4sIAAAAAAACA8tIzcnJVyjPL8pJAQCFEUoNCwAAAA=="))
        try zipped.write(to: source)
        let hash = SHA256.hash(data: zipped).map { String(format: "%02x", $0) }.joined()
        try ProbeDownload.verify(source, expected: hash)
        XCTAssertThrowsError(try ProbeDownload.verify(source, expected: String(repeating: "0", count: 64)))
        try ProbeDownload.decompress(source, to: destination)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "hello world")
        try zipped.dropLast(4).write(to: source)
        XCTAssertThrowsError(try ProbeDownload.decompress(source, to: destination))
    }

    private func upstream(_ dir: URL) throws -> URL {
        let source = dir.appending(path: "upstream.sqlite")
        let db = try ProbeSQLite(source)
        try db.execute("""
        CREATE TABLE sets(code TEXT, name TEXT, releaseDate TEXT, keyruneCode TEXT);
        INSERT INTO sets VALUES('TST','Test Set','2026-01-01','test');
        CREATE TABLE cards(uuid TEXT,name TEXT,asciiName TEXT,number TEXT,setCode TEXT,side TEXT,
        type TEXT,text TEXT,manaCost TEXT,finishes TEXT,colorIdentity TEXT,layout TEXT,language TEXT,
        isPromo INTEGER,rarity TEXT,power TEXT,toughness TEXT,loyalty TEXT,defense TEXT);
        INSERT INTO cards VALUES('b','Fire // Ice',NULL,'0012a','TST','b','Instant','Tap target.','{1}{U}',
        'nonfoil, foil','R, U','split','English',0,'rare',NULL,NULL,NULL,NULL);
        INSERT INTO cards VALUES('a','Fire // Ice',NULL,'0012a','TST','a','Instant','Deal damage.','{1}{R}',
        'nonfoil, foil','R, U','split','English',0,'rare',NULL,NULL,NULL,NULL);
        CREATE TABLE cardIdentifiers(uuid TEXT,scryfallId TEXT);
        INSERT INTO cardIdentifiers VALUES('a','scryfall-1');
        CREATE TABLE cardPurchaseUrls(uuid TEXT,cardKingdom TEXT,cardKingdomFoil TEXT);
        INSERT INTO cardPurchaseUrls VALUES('a','https://example.com/plain','https://example.com/foil');
        """)
        return source
    }
}
