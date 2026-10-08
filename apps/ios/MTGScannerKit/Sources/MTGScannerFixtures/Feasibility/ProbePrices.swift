#if DEBUG
import Foundation

enum ProbePrices {
    static func install(from source: URL, to destination: URL,
                        checkpoint: () throws -> Void = { try Task.checkCancellation() }) throws {
        try ProbeSQLite.install(to: destination, checkpoint: checkpoint) { db in
            try db.execute("""
            CREATE TABLE ck_prices(id INTEGER PRIMARY KEY AUTOINCREMENT,scryfall_id TEXT,name TEXT NOT NULL,
            normalized_name TEXT NOT NULL,edition TEXT NOT NULL,is_foil INTEGER NOT NULL,price_retail TEXT,
            qty_retail INTEGER,price_buy TEXT,qty_buying INTEGER,url TEXT);
            CREATE INDEX idx_ck_scryfall ON ck_prices(scryfall_id,is_foil);
            CREATE INDEX idx_ck_name ON ck_prices(normalized_name,is_foil);
            """)
            try ProbeJSONStream(source).forEach { row in
                try checkpoint()
                guard let name = row["name"] as? String, let edition = row["edition"] as? String else { return }
                try db.run("INSERT INTO ck_prices(scryfall_id,name,normalized_name,edition,is_foil,"
                    + "price_retail,qty_retail,price_buy,qty_buying,url) VALUES(?,?,?,?,?,?,?,?,?,?)", [
                    row["scryfall_id"] as? String, name, ProbeNormalization.priceName(name), edition,
                    row["is_foil"] as? String == "true" ? "1" : "0", scalar(row["price_retail"]),
                    integer(row["qty_retail"]), scalar(row["price_buy"]), integer(row["qty_buying"]),
                    row["url"] as? String])
            }
            guard try db.rows("SELECT COUNT(*) AS count FROM ck_prices").first?["count"] != "0" else {
                throw ProbeError.invalidPayload
            }
        }
    }

    static func lookup(_ db: ProbeSQLite, id: String?, name: String, foil: Bool) throws -> [String: String]? {
        let fields = "price_retail,qty_retail,price_buy,qty_buying,url"
        if let id, var row = try db.rows("SELECT \(fields) FROM ck_prices WHERE scryfall_id=? AND is_foil=? LIMIT 1",
                                        [id, foil ? "1" : "0"]).first {
            expandURL(&row)
            return row
        }
        var row = try db.rows("SELECT \(fields) FROM ck_prices WHERE normalized_name=? AND is_foil=? "
            + "ORDER BY CAST(price_retail AS REAL) ASC LIMIT 1",
            [ProbeNormalization.priceName(name), foil ? "1" : "0"]).first
        if var value = row { expandURL(&value); row = value }
        return row
    }

    private static func expandURL(_ row: inout [String: String]) {
        if let url = row["url"], !url.isEmpty, !url.hasPrefix("http") {
            row["url"] = "https://www.cardkingdom.com/" + url
        }
    }

    private static func scalar(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        return (value as? NSNumber)?.stringValue
    }

    private static func integer(_ value: Any?) -> String? {
        guard let value = scalar(value), let integer = Int(value) else { return nil }
        return String(integer)
    }
}
#endif
