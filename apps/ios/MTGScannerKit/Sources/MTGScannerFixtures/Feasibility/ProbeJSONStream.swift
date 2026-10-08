#if DEBUG
import Foundation

/// Reads one catalog entry at a time; never materializes the complete JSON feed.
final class ProbeJSONStream {
    private let input: FileHandle
    private var buffer = Data()
    private var index = 0

    init(_ url: URL) throws { input = try FileHandle(forReadingFrom: url) }
    deinit { try? input.close() }

    func forEach(_ body: ([String: Any]) throws -> Void) throws {
        try readHeader()
        var next = try nonWhitespace()
        if next == 93 { try readEnd(); return }
        while next == 123 {
            let data = try objectData()
            try autoreleasepool {
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ProbeError.invalidPayload
                }
                try body(object)
            }
            let separator = try nonWhitespace()
            if separator == 93 { try readEnd(); return }
            guard separator == 44 else { throw ProbeError.invalidPayload }
            next = try nonWhitespace()
        }
        throw ProbeError.invalidPayload
    }

    private func readHeader() throws {
        var header = Data()
        while let byte = try readByte() {
            header.append(byte)
            guard header.count <= 65_536 else { throw ProbeError.invalidPayload }
            if byte == 91 {
                guard let text = String(data: header, encoding: .utf8) else { throw ProbeError.invalidPayload }
                let envelope = try JSONSerialization.jsonObject(with: Data((text + "]}").utf8))
                guard let object = envelope as? [String: Any], object["data"] is [Any] else {
                    throw ProbeError.invalidPayload
                }
                return
            }
        }
        throw ProbeError.invalidPayload
    }

    private func objectData() throws -> Data {
        var data = Data([123])
        var depth = 1
        var quoted = false
        var escaped = false
        while let byte = try readByte() {
            data.append(byte)
            guard data.count <= 1_048_576 else { throw ProbeError.invalidPayload }
            if escaped { escaped = false; continue }
            if quoted && byte == 92 { escaped = true; continue }
            if byte == 34 { quoted.toggle(); continue }
            if quoted { continue }
            if byte == 123 { depth += 1 }
            if byte == 125 { depth -= 1 }
            if depth == 0 { return data }
        }
        throw ProbeError.invalidPayload
    }

    private func readEnd() throws {
        guard try nonWhitespace() == 125, try nonWhitespace() == nil else { throw ProbeError.invalidPayload }
    }

    private func nonWhitespace() throws -> UInt8? {
        while let byte = try readByte() {
            if ![9, 10, 13, 32].contains(byte) { return byte }
        }
        return nil
    }

    private func readByte() throws -> UInt8? {
        if index == buffer.count {
            buffer = try input.read(upToCount: 65_536) ?? Data()
            index = 0
        }
        guard index < buffer.count else { return nil }
        defer { index += 1 }
        return buffer[index]
    }
}
#endif
