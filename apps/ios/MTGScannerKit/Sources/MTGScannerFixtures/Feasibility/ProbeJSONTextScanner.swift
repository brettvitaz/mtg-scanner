#if DEBUG
import Foundation

struct ProbeJSONTextScanner {
    private var buffer = ""
    private var depth = 0
    private var quoted = false
    private var escaped = false

    mutating func append(_ char: Character) -> String? {
        if depth == 0 {
            guard char == "{" else { return nil }
            buffer = "{"
            depth = 1
            return nil
        }
        buffer.append(char)
        if quoted { updateQuote(char); return nil }
        switch char {
        case "\"": quoted = true
        case "{": depth += 1
        case "}": depth -= 1
        default: break
        }
        return depth == 0 ? buffer : nil
    }

    private mutating func updateQuote(_ char: Character) {
        if escaped { escaped = false; return }
        if char == "\\" { escaped = true; return }
        if char == "\"" { quoted = false }
    }
}
#endif
