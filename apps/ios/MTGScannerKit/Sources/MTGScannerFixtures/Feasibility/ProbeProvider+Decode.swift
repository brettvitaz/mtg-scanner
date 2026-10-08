#if DEBUG
import Foundation

extension ProbeProvider {
    func decode(_ data: Data) throws -> ProbeOutput {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProbeError.invalidPayload
        }
        let content = try outputContent(payload)
        let raw = try JSONSerialization.data(withJSONObject: content)
        var output = try ProbeOutput.decode(raw)
        if let usage = payload["usage"] as? [String: Any] {
            let input = usage[kind == .anthropic ? "input_tokens" : "prompt_tokens"] as? Int ?? 0
            let tokens = usage[kind == .anthropic ? "output_tokens" : "completion_tokens"] as? Int ?? 0
            guard input >= 0, tokens >= 0, input <= Int.max - tokens else { throw ProbeError.invalidPayload }
            output.usage = ProbeUsage(inputTokens: input, outputTokens: tokens)
        }
        return output
    }

    private func outputContent(_ payload: [String: Any]) throws -> [String: Any] {
        if kind == .anthropic { return try anthropicContent(payload) }
        guard let choices = payload["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { throw ProbeError.invalidPayload }
        if let parsed = message["parsed"] as? [String: Any] { return parsed }
        if let text = message["content"] as? String { return try textContent(text) }
        let blocks = message["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { ["text", "output_text"].contains($0["type"] as? String ?? "") }
            .compactMap { $0["text"] as? String }.joined()
        return try textContent(text)
    }

    private func anthropicContent(_ payload: [String: Any]) throws -> [String: Any] {
        guard let blocks = payload["content"] as? [[String: Any]] else { throw ProbeError.invalidPayload }
        for block in blocks {
            if mode == .schema, block["type"] as? String == "tool_use",
               block["name"] as? String == "card_recognition" {
                if let object = block["input"] as? [String: Any] { return object }
                if let text = block["input"] as? String { return try textContent(text) }
            }
            if mode == .raw, block["type"] as? String == "text", let text = block["text"] as? String {
                return try textContent(text)
            }
        }
        throw ProbeError.invalidPayload
    }

    private func textContent(_ text: String) throws -> [String: Any] {
        if mode != .raw {
            guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                throw ProbeError.invalidPayload
            }
            return object
        }
        var scanner = ProbeJSONTextScanner()
        for char in text {
            guard let candidate = scanner.append(char) else { continue }
            if let object = try? JSONSerialization.jsonObject(with: Data(candidate.utf8)) as? [String: Any] {
                return object
            }
        }
        throw ProbeError.invalidPayload
    }
}
#endif
