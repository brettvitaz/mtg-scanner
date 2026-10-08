import XCTest
@testable import MTGScannerKit

final class APIClientHealthTests: XCTestCase {
    // MARK: - Invalid URL

    func testCheckHealth_emptyBaseURL_throwsInvalidBaseURL() async {
        await XCTAssertThrowsErrorAsync(try await APIClient(baseURL: "").checkHealth()) { error in
            XCTAssertEqual(error as? APIClient.APIError, .invalidBaseURL)
        }
    }

    func testCheckHealth_malformedBaseURL_throwsInvalidBaseURL() async {
        await XCTAssertThrowsErrorAsync(try await APIClient(baseURL: "not a url").checkHealth()) { error in
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
