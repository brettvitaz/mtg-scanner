import XCTest
@testable import MTGScannerKit

final class APIClientRequestTests: XCTestCase {
    private let client = APIClient(baseURL: "https://api-client-request.test")

    override func setUp() {
        super.setUp()
        RequestCapturingURLProtocol.lastRequest = nil
        URLProtocol.registerClass(RequestCapturingURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(RequestCapturingURLProtocol.self)
        super.tearDown()
    }

    func testSearchCardNamesSendsQueryAndDefaultLimit() async throws {
        RequestCapturingURLProtocol.responseBody = Data(#"{"names":["Lightning Bolt"]}"#.utf8)
        let names = try await client.searchCardNames(query: "Bolt")
        XCTAssertEqual(names, ["Lightning Bolt"])
        let url = try XCTUnwrap(RequestCapturingURLProtocol.lastRequest?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/v1/cards/search")
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "q", value: "Bolt"),
            URLQueryItem(name: "limit", value: "20")
        ])
    }

    func testRecognizeBatchSendsPromptVersionAndContentType() async throws {
        RequestCapturingURLProtocol.responseBody = Data(#"{"cards":[]}"#.utf8)
        _ = try await client.recognizeBatch(
            crops: [(data: Data([0x01]), filename: "crop-0.jpg")],
            contentType: "image/jpeg"
        )
        let request = try XCTUnwrap(RequestCapturingURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/recognitions/batch")
        let body = try XCTUnwrap(RequestCapturingURLProtocol.lastBody)
        let text = try XCTUnwrap(String(bytes: body, encoding: .utf8))
        XCTAssertTrue(text.contains("name=\"prompt_version\"\r\n\r\ncard-recognition.md\r\n"))
        XCTAssertTrue(text.contains("filename=\"crop-0.jpg\"\r\nContent-Type: image/jpeg\r\n"))
    }
}

private final class RequestCapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var responseBody = Data()

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api-client-request.test"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        stream.open()
        defer { stream.close() }
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
