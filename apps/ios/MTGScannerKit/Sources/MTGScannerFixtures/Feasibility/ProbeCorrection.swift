#if DEBUG
import Foundation

enum ProbeCorrection {
    static func matches(_ card: ProbeCard, candidates: [[String: String]]) -> Bool {
        guard let title = card.title, let edition = card.edition,
              let number = card.collectorNumber else { return false }
        return candidates.contains { row in
            ProbeNormalization.title(row["name"] ?? "") == ProbeNormalization.title(title)
                && row["set_code"]?.lowercased() == edition.lowercased()
                && ProbeNormalization.number(row["collector_number"] ?? "") == ProbeNormalization.number(number)
        }
    }

    static func prompt(_ template: String, card: ProbeCard, candidates: [[String: String]], reason: String) -> String {
        let rows = ["| Set Name | Set Code | Collector # | Rarity | Finishes |", "| --- | --- | --- | --- | --- |"]
            + candidates.map { row in
                "| \(row["set_name"] ?? "") | \(row["set_code"] ?? "") | \(row["collector_number"] ?? "") "
                + "| \(row["rarity"] ?? "") | \(row["finishes"] ?? "unknown") |"
            }
        let values = ["title": card.title ?? "", "edition": card.edition ?? "",
            "collector_number": card.collectorNumber ?? "", "foil": card.foil.map(String.init) ?? "unknown",
            "reason": reason, "candidates_table": rows.joined(separator: "\n")]
        return values.reduce(template) { text, entry in
            text.replacingOccurrences(of: "{{\(entry.key)}}", with: entry.value)
        }
    }
}

extension ProbeUsage {
    func estimatedCost(inputRate: Double, outputRate: Double) -> Double {
        (Double(inputTokens) * inputRate + Double(outputTokens) * outputRate) / 1_000_000
    }
}
#endif
