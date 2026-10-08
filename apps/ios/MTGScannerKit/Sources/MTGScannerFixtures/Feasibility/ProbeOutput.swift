#if DEBUG
import Foundation

struct ProbeCard: Codable, Sendable {
    let title: String?
    let edition: String?
    let collectorNumber: String?
    let foil: Bool?
    let confidence: Double
    let notes: String?
    let editionNotes: String?
    let foilType: String?
    let foilEvidence: [String]?
    let listReprint: String?
    let listSymbolVisible: Bool?
    let borderColor: String?
    let copyrightLine: String?
    let promoText: String?
}

struct ProbeUsage: Codable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    var totalTokens: Int { inputTokens + outputTokens }
}

struct ProbeOutput: Codable, Sendable {
    let cards: [ProbeCard]
    var usage: ProbeUsage?

    static func decode(_ data: Data) throws -> ProbeOutput {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let output = try decoder.decode(ProbeOutput.self, from: data)
        for card in output.cards {
            guard card.confidence.isFinite, (0...1).contains(card.confidence) else {
                throw ProbeError.invalidPayload
            }
            try check(card.listReprint, allowed: ["yes", "no", "possible"])
            try check(card.borderColor, allowed: ["white", "black", "unknown"])
            try check(card.foilType, allowed: ["none", "rainbow_traditional", "pre_modern_shootingstar",
                "etched", "textured", "confetti", "ripple", "galaxy", "halo", "raised", "unknown"])
        }
        return output
    }

    private static func check(_ value: String?, allowed: [String]) throws {
        if let value, !allowed.contains(value) { throw ProbeError.invalidPayload }
    }
}

enum ProbeError: Error, LocalizedError {
    case invalidPayload
    case httpStatus(Int)
    case storage(String)
    case checksum
    case missingInput

    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "Invalid provider or upstream payload."
        case .httpStatus(let status): return "HTTP status \(status)."
        case .storage(let operation): return "Storage operation failed: \(operation)."
        case .checksum: return "Download checksum mismatch."
        case .missingInput: return "Required probe input is missing."
        }
    }
}
#endif
