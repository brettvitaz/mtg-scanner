#if DEBUG
import CryptoKit
import Foundation
import zlib

enum ProbeDownload {
    static func fetch(_ url: URL, to destination: URL, session: URLSession) async throws {
        let (temporary, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ProbeError.invalidPayload }
        guard (200...299).contains(http.statusCode) else { throw ProbeError.httpStatus(http.statusCode) }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    static func verify(_ url: URL, expected: String) throws {
        guard try digest(url) == expected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            throw ProbeError.checksum
        }
    }

    static func digest(_ url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hash = SHA256()
        while try autoreleasepool(invoking: { () throws -> Bool in
            try Task.checkCancellation()
            guard let data = try input.read(upToCount: 65_536), !data.isEmpty else { return false }
            hash.update(data: data)
            return true
        }) {}
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func decompress(_ source: URL, to destination: URL) throws {
        guard let input = gzopen(source.path, "rb") else { throw ProbeError.storage("open gzip") }
        defer { gzclose(input) }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw ProbeError.storage("create decompressed file")
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            try Task.checkCancellation()
            let count = gzread(input, &buffer, UInt32(buffer.count))
            guard count >= 0 else { throw ProbeError.invalidPayload }
            if count == 0 { break }
            try autoreleasepool { try output.write(contentsOf: Data(buffer.prefix(Int(count)))) }
        }
        var code: Int32 = 0
        _ = gzerror(input, &code)
        guard code == Z_OK || code == Z_STREAM_END else { throw ProbeError.invalidPayload }
        try output.synchronize()
    }
}
#endif
