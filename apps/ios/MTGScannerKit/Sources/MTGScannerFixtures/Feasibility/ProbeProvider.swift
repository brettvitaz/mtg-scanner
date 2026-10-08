#if DEBUG
import Foundation

struct ProbeProvider: Sendable {
    enum Kind: String, Codable, Sendable { case openai, moonshot, anthropic }
    enum Mode: String, Codable, Sendable { case schema, json, raw }
    let kind: Kind
    let model: String
    let mode: Mode

    private var endpoint: String {
        switch kind {
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .moonshot: return "https://api.moonshot.ai/v1/chat/completions"
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        }
    }

    func request(key: String, image: Data, corner: Data?, prompt: String,
                 schema: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: endpoint), !key.isEmpty else { throw ProbeError.missingInput }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(kind == .anthropic ? key : "Bearer \(key)",
                         forHTTPHeaderField: kind == .anthropic ? "x-api-key" : "Authorization")
        if kind == .anthropic { request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body(
            image: image, corner: corner, prompt: prompt, schema: schema))
        return request
    }

    func recognize(key: String, image: Data, corner: Data?, prompt: String,
                   schemaData: Data, session: URLSession) async throws -> ProbeOutput {
        guard let schema = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
            throw ProbeError.invalidPayload
        }
        let request = try request(key: key, image: image, corner: corner, prompt: prompt, schema: schema)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ProbeError.invalidPayload }
        guard (200...299).contains(http.statusCode) else { throw ProbeError.httpStatus(http.statusCode) }
        return try decode(data)
    }

    private func body(image: Data, corner: Data?, prompt: String, schema: [String: Any]) -> [String: Any] {
        let blocks = imageBlocks(image: image, corner: corner)
        if kind == .anthropic { return anthropicBody(blocks: blocks, prompt: prompt, schema: schema) }
        var body: [String: Any] = ["model": model, "messages": [
            ["role": "system", "content": prompt], ["role": "user", "content": blocks]]]
        if mode == .schema && kind != .moonshot {
            body["response_format"] = ["type": "json_schema", "json_schema": [
                "name": "recognition_response", "schema": schema]]
        } else if mode != .raw { body["response_format"] = ["type": "json_object"] }
        return body
    }

    private func anthropicBody(blocks: [[String: Any]], prompt: String,
                               schema: [String: Any]) -> [String: Any] {
        var body: [String: Any] = ["model": model, "max_tokens": 4096, "system": prompt,
                                  "messages": [["role": "user", "content": blocks]]]
        if mode == .schema {
            body["tools"] = [["name": "card_recognition", "input_schema": schema,
                              "description": "Extract structured information from a Magic: The Gathering card image"]]
            body["tool_choice"] = ["type": "tool", "name": "card_recognition"]
        }
        return body
    }

    private func imageBlocks(image: Data, corner: Data?) -> [[String: Any]] {
        var blocks: [[String: Any]] = [["type": "text", "text":
            kind == .anthropic
            ? "Analyze this Magic: The Gathering card image and extract the card information."
            : "Analyze this Magic: The Gathering card image."], imageBlock(image)]
        if let corner {
            blocks.append(["type": "text", "text": Self.cornerPresent])
            blocks.append(imageBlock(corner))
        } else { blocks.append(["type": "text", "text": Self.cornerAbsent]) }
        return blocks
    }

    private func imageBlock(_ data: Data) -> [String: Any] {
        if kind == .anthropic {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                              "data": data.base64EncodedString()]]
        }
        return ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())",
                                                  "detail": "high"]]
    }

    static let cornerPresent = "Close-up of the bottom-left corner of the same card. "
        + "Use this close-up for two purposes: "
        + "1) Look at the far LEFT edge for the Planeswalker icon (five-tined glyph) to determine list_reprint. "
        + "2) Read the separator character between the set code and language code "
        + "(e.g., 'WAR • EN' or 'WAR ★ EN') to determine foil status. "
        + "The separator is either a bullet (•) for non-foil or a star (★) for foil."
    static let cornerAbsent = "No close-up image is provided. Make the List/Mystery Booster "
        + "determination from the full card image alone. If the planeswalker "
        + "icon is not clearly visible at that resolution, set list_reprint "
        + "to \"possible\" rather than guessing."
}
#endif
