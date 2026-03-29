import XCTest
@testable import MTGScanner

final class APIClientHealthTests: XCTestCase {
    private let client = APIClient()

    // MARK: - Invalid URL

    func testCheckHealth_emptyBaseURL_throwsInvalidBaseURL() async {
        await XCTAssertThrowsErrorAsync(try await client.checkHealth(baseURL: "")) { error in
            XCTAssertEqual(error as? APIClient.APIError, .invalidBaseURL)
        }
    }

    func testCheckHealth_malformedBaseURL_throwsInvalidBaseURL() async {
        await XCTAssertThrowsErrorAsync(try await client.checkHealth(baseURL: "not a url")) { error in
            XCTAssertEqual(error as? APIClient.APIError, .invalidBaseURL)
        }
    }
}

// MARK: - Async XCTest helper

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "",
    file: StaticString = #file,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown" + (message.isEmpty ? "" : ": \(message)"), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
