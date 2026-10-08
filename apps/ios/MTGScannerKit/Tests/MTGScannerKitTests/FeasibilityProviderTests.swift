import XCTest
@testable import MTGScannerFixtures

final class FeasibilityProviderTests: XCTestCase {
    func testRequestsMatchPythonProviderFixtures() throws {
        for kind in [ProbeProvider.Kind.openai, .moonshot, .anthropic] {
            for mode in [ProbeProvider.Mode.schema, .json, .raw] where kind != .anthropic || mode != .json {
                let url = try XCTUnwrap(Bundle.module.url(forResource: "\(kind.rawValue)-\(mode.rawValue)",
                                                         withExtension: "json"))
                let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary
                let request = try ProbeProvider(kind: kind, model: "fixture", mode: mode).request(
                    key: "fixture", image: Data([1]), corner: Data([2]), prompt: "prompt", schema: ["type": "object"])
                let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? NSDictionary
                XCTAssertEqual(body, expected, "\(kind.rawValue) \(mode.rawValue)")
            }
        }
    }

    func testOpenAIRequestIncludesFullAndCornerImagesAndSchema() throws {
        let provider = ProbeProvider(kind: .openai, model: "fixture", mode: .schema)
        let request = try provider.request(key: "test-secret", image: Data([1]), corner: Data([2]),
                                           prompt: "prompt", schema: ["type": "object"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let blocks = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.filter { $0["type"] as? String == "image_url" }.count, 2)
        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-secret")
    }

    func testMoonshotDowngradesSchemaAndAnthropicUsesTool() throws {
        for kind in [ProbeProvider.Kind.moonshot, .anthropic] {
            let request = try ProbeProvider(kind: kind, model: "fixture", mode: .schema).request(
                key: "key", image: Data([1]), corner: nil, prompt: "prompt", schema: ["type": "object"])
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            if kind == .moonshot {
                XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
            } else {
                XCTAssertEqual((body["tool_choice"] as? [String: String])?["name"], "card_recognition")
                XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            }
        }
    }

    func testResponsePreservesFoilAndListEvidenceAndUsage() throws {
        let card: [String: Any] = ["confidence": 0.8, "title": "Fire // Ice", "foil_type": "etched",
                                  "foil_evidence": ["star"], "list_reprint": "possible", "list_symbol_visible": false]
        let payload: [String: Any] = ["choices": [["message": ["parsed": ["cards": [card]]]]],
                                     "usage": ["prompt_tokens": 12, "completion_tokens": 3, "total_tokens": 15,
                                               "prompt_tokens_details": ["cached_tokens": 0],
                                               "completion_tokens_details": ["reasoning_tokens": 0]]]
        let result = try ProbeProvider(kind: .openai, model: "fixture", mode: .schema).decode(
            JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(result.cards[0].foilType, "etched")
        XCTAssertEqual(result.cards[0].listReprint, "possible")
        XCTAssertEqual(result.cards[0].foilEvidence, ["star"])
        XCTAssertEqual(result.usage?.totalTokens, 15)
    }

    func testHTTPAndTimeoutErrorsAndCancellationDoNotExposeSecrets() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProbeNetworkFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let provider = ProbeProvider(kind: .openai, model: "fixture", mode: .schema)
        for key in ["unauthorized", "timeout"] {
            do {
                _ = try await provider.recognize(key: key, image: Data([1]), corner: nil, prompt: "prompt",
                                                schemaData: Data("{}".utf8), session: session)
                XCTFail("Expected network failure")
            } catch {
                if key == "unauthorized" {
                    XCTAssertEqual((error as? ProbeError)?.localizedDescription, "HTTP status 401.")
                } else { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
                XCTAssertFalse(error.localizedDescription.contains("secret-body"))
            }
        }
        let task = Task {
            try await provider.recognize(key: "cancel", image: Data([1]), corner: nil, prompt: "prompt",
                                        schemaData: Data("{}".utf8), session: session)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled request must not succeed")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }

    func testAuthenticatedRedirectIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "https://api.openai.com/v1/chat/completions"))
        var request = URLRequest(url: url)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil))
        let redirect = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/collect")))
        ProbeSessionDelegate().urlSession(session, task: session.dataTask(with: request),
                                         willPerformHTTPRedirection: response, newRequest: redirect) { forwarded in
            XCTAssertNil(forwarded)
        }
    }

    func testRawResponseFindsObjectAndRejectsInvalidConfidenceAndEnums() throws {
        let provider = ProbeProvider(kind: .anthropic, model: "fixture", mode: .raw)
        let payload: [String: Any] = ["content": [["type": "text", "text":
            "Result: ```json\n{\"cards\":[{\"confidence\":0.5,\"title\":\"Bolt\"}]}\n```"]]]
        XCTAssertEqual(try provider.decode(JSONSerialization.data(withJSONObject: payload)).cards[0].title, "Bolt")
        for json in ["{\"cards\":[{\"confidence\":2}]}",
                     "{\"cards\":[{\"confidence\":true}]}",
                     "{\"cards\":[{\"confidence\":0.5,\"list_reprint\":\"maybe\"}]}"] {
            XCTAssertThrowsError(try ProbeOutput.decode(Data(json.utf8)))
        }
    }
}

private class ProbeNetworkFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer cancel" { return }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("secret-body".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
