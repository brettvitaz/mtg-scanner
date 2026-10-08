#if DEBUG
import Foundation

extension ProbeRunner {
    func correction(_ config: ProbeConfiguration) async {
        let start = Date()
        var evidence: [String: Any] = ["status": "Unverified", "seededInvalidEdition": true]
        do {
            guard let spec = config.providers.first(where: { $0.kind == .openai }),
                  let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else { throw ProbeError.missingInput }
            let original = try ProbeOutput.decode(Data(contentsOf: root.appending(path: "correction-card.json")))
            guard let card = original.cards.first, let title = card.title else { throw ProbeError.invalidPayload }
            let db = try ProbeSQLite(root.appending(path: "catalog.sqlite"), readOnly: true)
            let candidates = try db.rows("SELECT * FROM cards WHERE normalized_name=? "
                + "ORDER BY release_date DESC,set_code ASC,collector_number ASC", [ProbeNormalization.title(title)])
            guard !candidates.isEmpty else { throw ProbeError.invalidPayload }
            let template = try String(contentsOf: root.appending(path: "card-correction.md"), encoding: .utf8)
            let reason = "Phase 1 deliberately seeded an invalid edition to exercise constrained correction."
            let prompt = ProbeCorrection.prompt(template, card: card, candidates: candidates, reason: reason)
            let image = try Data(contentsOf: root.appending(path: "samples/ordinary.jpg"))
            let schema = try Data(contentsOf: root.appending(path: "llm-output.schema.json"))
            let result = try await ProbeProvider(kind: spec.kind, model: spec.model, mode: spec.mode).recognize(
                key: key, image: image, corner: Self.corner(image), prompt: prompt,
                schemaData: schema, session: session)
            evidence["result"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result))
            evidence["candidateCount"] = candidates.count
            evidence["estimatedCostUSD"] = cost(result.usage, model: spec.model)
            evidence["model"] = spec.model
            evidence["seconds"] = Date().timeIntervalSince(start)
            let valid = result.cards.count == 1 && result.cards.allSatisfy {
                ProbeCorrection.matches($0, candidates: candidates)
            }
            evidence["selectedCatalogCandidate"] = valid
            evidence["status"] = valid ? "Pass" : "Fail"
        } catch { evidence["status"] = "Fail"; evidence["error"] = safeError(error) }
        record("correction", evidence)
    }

    func cost(_ usage: ProbeUsage?, model: String) -> Double? {
        guard let usage,
              let data = try? Data(contentsOf: root.appending(path: "model_prices.json")),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = payload["models"] as? [String: [String: Any]],
              let entry = models[model], let input = entry["input_mtok"] as? Double,
              let output = entry["output_mtok"] as? Double else { return nil }
        return usage.estimatedCost(inputRate: input, outputRate: output)
    }
}
#endif
