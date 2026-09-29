import XCTest
@testable import MTGScannerKit

@MainActor
final class CardPriceRefreshTests: XCTestCase {
    func testRefreshUpdatesAlreadyPricedCardsAndBuyingQuantity() async {
        let appModel = AppModel()
        let previousURL = appModel.apiBaseURL
        appModel.apiBaseURL = "https://card-pricing.test"
        URLProtocol.registerClass(CardPricingURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(CardPricingURLProtocol.self)
            appModel.apiBaseURL = previousURL
        }
        let item = CollectionItem(title: "Available", edition: "Set", priceRetail: "$9.00",
                                  priceBuy: "$8.00", qtyBuying: 0)
        await appModel.refreshPrices(for: [item])
        XCTAssertEqual(item.priceRetail, "$2.00")
        XCTAssertEqual(item.priceBuy, "$0.50")
        XCTAssertEqual(item.qtyBuying, 12)
    }

    func testFailedRefreshPreservesCachedDataAndLeavesFirstLookupUnknown() async {
        let appModel = AppModel()
        let previousURL = appModel.apiBaseURL
        appModel.apiBaseURL = "https://card-pricing.test"
        URLProtocol.registerClass(CardPricingURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(CardPricingURLProtocol.self)
            appModel.apiBaseURL = previousURL
        }
        let cached = CollectionItem(title: "Failure", edition: "Set", priceBuy: "$0.25", qtyBuying: 2)
        let unknown = CollectionItem(title: "Failure", edition: "Set")
        await appModel.refreshPrices(for: [cached, unknown])
        XCTAssertEqual(cached.priceBuy, "$0.25")
        XCTAssertEqual(cached.qtyBuying, 2)
        XCTAssertNil(unknown.priceBuy)
        XCTAssertNil(unknown.qtyBuying)
    }
}

private class CardPricingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "card-pricing.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.query?.contains("Failure") == true {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let data = Data(#"{"price_retail":"$2.00","price_buy":"$0.50","qty_buying":12}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
