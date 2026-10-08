#if DEBUG
import Darwin
import Foundation
import SQLite3

/// Probe connections are owned by one synchronous importer, never shared across tasks.
final class ProbeSQLite {
    private var handle: OpaquePointer?

    init(_ url: URL, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ProbeError.storage("open database")
        }
        do { try execute("PRAGMA temp_store=FILE; PRAGMA cache_size=-2048;") } catch {
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw ProbeError.storage("execute SQL") }
    }

    func run(_ sql: String, _ values: [String?]) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProbeError.storage("write row") }
    }

    func rows(_ sql: String, _ values: [String?] = []) throws -> [[String: String]] {
        var result: [[String: String]] = []
        try forEach(sql, values) { result.append($0) }
        return result
    }

    func forEach(_ sql: String, _ values: [String?] = [], body: ([String: String]) throws -> Void) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                if let name = sqlite3_column_name(statement, index), let value = sqlite3_column_text(statement, index) {
                    row[String(cString: name)] = String(cString: value)
                }
            }
            try autoreleasepool { try body(row) }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw ProbeError.storage("read row") }
    }

    private func prepare(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ProbeError.storage("prepare SQL")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let status = value.map { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }
                ?? sqlite3_bind_null(statement, Int32(index + 1))
            guard status == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw ProbeError.storage("bind SQL")
            }
        }
        return statement
    }

    static func install(to destination: URL, checkpoint: () throws -> Void,
                        build: (ProbeSQLite) throws -> Void) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stage = directory.appending(path: "stage-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: stage) }
        try buildStage(stage, checkpoint: checkpoint, build: build)
        try checkpoint()
        guard rename(stage.path, destination.path) == 0 else { throw ProbeError.storage("activate database") }
    }

    private static func buildStage(_ stage: URL, checkpoint: () throws -> Void,
                                   build: (ProbeSQLite) throws -> Void) throws {
        let database = try ProbeSQLite(stage)
        try database.execute("BEGIN TRANSACTION")
        try checkpoint()
        try build(database)
        try checkpoint()
        try database.execute("COMMIT")
        guard try database.rows("PRAGMA quick_check").first?["quick_check"] == "ok" else {
            throw ProbeError.storage("validate database")
        }
    }
}
#endif
