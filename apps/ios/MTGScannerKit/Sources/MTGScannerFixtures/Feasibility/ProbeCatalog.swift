#if DEBUG
import Foundation

enum ProbeCatalog {
    static let columns = ["uuid", "name", "ascii_name", "normalized_name", "set_code", "set_name",
        "collector_number", "normalized_collector_number", "language", "layout", "release_date", "is_promo",
        "rarity", "type_line", "oracle_text", "mana_cost", "power", "toughness", "loyalty", "defense",
        "scryfall_id", "card_kingdom_url", "card_kingdom_foil_url", "finishes", "color_identity"]

    static func install(from source: URL, to destination: URL,
                        checkpoint: () throws -> Void = { try Task.checkCancellation() }) throws {
        let upstream = try ProbeSQLite(source, readOnly: true)
        try ProbeSQLite.install(to: destination, checkpoint: checkpoint) { db in
            try createSchema(db)
            try importSets(upstream, into: db, checkpoint: checkpoint)
            try upstream.forEach(sourceQuery) { raw in
                try checkpoint()
                try importCard(raw, into: db)
            }
            guard try db.rows("SELECT COUNT(*) AS count FROM cards").first?["count"] != "0" else {
                throw ProbeError.invalidPayload
            }
        }
    }

    private static func createSchema(_ db: ProbeSQLite) throws {
        let fields = columns.map { "\($0) TEXT" }.joined(separator: ",")
        try db.execute("""
        CREATE TABLE cards(\(fields), PRIMARY KEY(uuid));
        CREATE UNIQUE INDEX idx_card_key ON cards(normalized_name,set_code,normalized_collector_number);
        CREATE INDEX idx_cards_set_number ON cards(set_code,normalized_collector_number);
        CREATE TABLE sets(set_code TEXT PRIMARY KEY,set_name TEXT,normalized_set_name TEXT,
                          release_date TEXT,keyrune_code TEXT);
        CREATE INDEX idx_sets_name ON sets(normalized_set_name);
        CREATE TABLE face_names(face_name TEXT,normalized_face_name TEXT,full_card_uuid TEXT,
                                UNIQUE(normalized_face_name,full_card_uuid));
        CREATE INDEX idx_face_names ON face_names(normalized_face_name);
        """)
    }

    private static func importSets(_ source: ProbeSQLite, into db: ProbeSQLite,
                                   checkpoint: () throws -> Void) throws {
        try source.forEach("SELECT code,name,releaseDate,keyruneCode FROM sets") { row in
            try checkpoint()
            guard let code = row["code"], let name = row["name"], !code.isEmpty, !name.isEmpty else { return }
            try db.run("INSERT INTO sets VALUES(?,?,?,?,?)", [code.uppercased(), name,
                ProbeNormalization.title(name), row["releaseDate"], row["keyruneCode"]])
        }
    }

    private static func importCard(_ raw: [String: String], into db: ProbeSQLite) throws {
        guard let uuid = raw["uuid"], let name = raw["name"], !uuid.isEmpty, !name.isEmpty else { return }
        let row = project(raw)
        let key = [row["normalized_name"], row["set_code"], row["normalized_collector_number"]]
        let prior = try db.rows("SELECT uuid FROM cards WHERE normalized_name=? AND set_code=? "
            + "AND normalized_collector_number=? LIMIT 1", key)
        if !prior.isEmpty { try mergeFace(row, key: key, into: db); return }
        let placeholders = columns.map { _ in "?" }.joined(separator: ",")
        try db.run("INSERT INTO cards VALUES(\(placeholders))", columns.map { row[$0] })
        guard ["split", "aftermath", "fuse"].contains(raw["layout"] ?? ""), name.contains(" // ") else { return }
        for face in name.components(separatedBy: " // ") {
            let trimmed = face.trimmingCharacters(in: .whitespaces)
            try db.run("INSERT OR IGNORE INTO face_names VALUES(?,?,?)",
                       [trimmed, ProbeNormalization.title(trimmed), uuid])
        }
    }

    private static func project(_ raw: [String: String]) -> [String: String] {
        let mappings = ["number": "collector_number", "setCode": "set_code", "asciiName": "ascii_name",
            "setName": "set_name", "releaseDate": "release_date", "isPromo": "is_promo", "type": "type_line",
            "text": "oracle_text", "manaCost": "mana_cost", "scryfallId": "scryfall_id",
            "cardKingdom": "card_kingdom_url", "cardKingdomFoil": "card_kingdom_foil_url"]
        let present = raw.filter { !$0.value.isEmpty }
        var row = Dictionary(uniqueKeysWithValues: present.map { (mappings[$0.key] ?? $0.key, $0.value) })
        row["normalized_name"] = ProbeNormalization.title(present["asciiName"] ?? present["name"] ?? "")
        row["normalized_collector_number"] = ProbeNormalization.number(raw["number"] ?? "")
        row["finishes"] = ProbeNormalization.list(present["finishes"])
        row["color_identity"] = ProbeNormalization.list(present["colorIdentity"])
        return row
    }

    private static func mergeFace(_ row: [String: String], key: [String?], into db: ProbeSQLite) throws {
        for (field, separator) in [("type_line", " // "), ("oracle_text", "\n---\n"), ("mana_cost", " // ")] {
            guard let value = row[field], !value.isEmpty else { continue }
            try db.run("UPDATE cards SET \(field)=CASE WHEN \(field) IS NULL THEN ? ELSE \(field)||?||? END "
                + "WHERE normalized_name=? AND set_code=? AND normalized_collector_number=?",
                [value, separator, value] + key)
        }
    }

    private static let sourceQuery = """
    SELECT c.*,s.name AS setName,s.releaseDate,i.scryfallId,p.cardKingdom,p.cardKingdomFoil
    FROM cards c JOIN sets s ON s.code=c.setCode
    LEFT JOIN cardIdentifiers i ON i.uuid=c.uuid LEFT JOIN cardPurchaseUrls p ON p.uuid=c.uuid
    ORDER BY c.setCode,c.number,c.name,COALESCE(c.side,''),c.rowid
    """
}
#endif
