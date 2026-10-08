#if DEBUG
import Foundation

enum ProbeNormalization {
    static func title(_ value: String) -> String {
        let spaces = Set("-‐‑‒–—−•:,./")
        let dropped = Set("'‘’´`\"“”")
        let normalized = value.precomposedStringWithCompatibilityMapping.lowercased()
        let text = normalized.filter { !dropped.contains($0) }.map { spaces.contains($0) ? " " : String($0) }.joined()
        return text.replacingOccurrences(of: "[^0-9a-z\\s]+", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func number(_ value: String) -> String {
        let text = value.precomposedStringWithCompatibilityMapping.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        var digits = ""
        var suffix = ""
        var seenNonDigit = false
        for char in text {
            if char.isNumber && !seenNonDigit {
                digits.append(char)
            } else if char.isLetter || char.isNumber {
                seenNonDigit = true
                suffix.append(char)
            }
        }
        let prefix = digits.drop(while: { $0 == "0" })
        return (prefix.isEmpty && !digits.isEmpty ? "0" : String(prefix)) + suffix
    }

    static func priceName(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func list(_ value: String?) -> String? {
        value?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
    }
}
#endif
