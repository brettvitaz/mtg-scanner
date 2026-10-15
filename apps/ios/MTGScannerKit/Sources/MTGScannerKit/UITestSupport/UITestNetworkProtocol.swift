#if DEBUG
import Foundation

/// Installed before shared sessions are opened. Every HTTP request stays in-process.
public final class UITestNetworkProtocol: URLProtocol, @unchecked Sendable {
    public static func install() {
        guard URLProtocol.registerClass(UITestNetworkProtocol.self) else {
            fatalError("Unable to install UI-test network fixtures")
        }
    }

    public override static func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "http" || request.url?.scheme == "https"
    }

    public override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        guard let url = request.url, let data = Self.priceFixture(for: request),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else {
            // A crash fails the UI workflow and retains the unexpected URL in diagnostics.
            let address = request.url?.absoluteString ?? "nil"
            fatalError("Unexpected UI-test request: \(request.httpMethod ?? "GET") \(address)")
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {}

    private static func priceFixture(for request: URLRequest) -> Data? {
        guard request.httpMethod == "GET", let url = request.url,
              url.path == "/api/v1/cards/price",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.first(where: { $0.name == "name" })?.value == "Lightning Bolt",
              let foil = components.queryItems?.first(where: { $0.name == "is_foil" })?.value,
              ["true", "false"].contains(foil) else { return nil }
        let retail = foil == "true" ? "3.00" : "1.50"
        return Data("""
        {"price_retail":"\(retail)","qty_retail":8,"price_buy":"0.50","qty_buying":4,"url":null}
        """.utf8)
    }
}
#endif
