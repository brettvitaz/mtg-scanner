import Foundation

struct CardListPricing {
    let buylist: CardPriceTotal
    let retail: CardPriceTotal

    init(items: [CollectionItem]) {
        buylist = CardPriceTotal(items: items, price: \.priceBuy)
        retail = CardPriceTotal(items: items, price: \.priceRetail)
    }
}

struct CardPriceTotal {
    private(set) var amount: Decimal = 0
    private(set) var pricedQuantity = 0
    let totalQuantity: Int

    var isPartial: Bool { pricedQuantity > 0 && pricedQuantity < totalQuantity }

    var displayAmount: String {
        guard totalQuantity == 0 || pricedQuantity > 0 else { return "—" }
        return amount.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    init(items: [CollectionItem], price: KeyPath<CollectionItem, String?>) {
        totalQuantity = items.totalQuantity
        for item in items {
            guard let value = Self.parse(item[keyPath: price]) else { continue }
            let quantity = max(1, item.quantity)
            amount += value * Decimal(quantity)
            pricedQuantity += quantity
        }
    }

    func accessibilitySummary(label: String) -> String {
        let availability = isPartial ? ", partial total" : ""
        return "\(label) total \(displayAmount)\(availability), \(pricedQuantity) of \(totalQuantity) cards priced"
    }

    static func parse(_ price: String?) -> Decimal? {
        guard let price else { return nil }
        let trimmed = price.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\$?\s*(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let value = trimmed.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Decimal(string: value, locale: Locale(identifier: "en_US"))
    }
}

extension CollectionItem {
    var buyingStatusLabel: String? {
        guard let qtyBuying, qtyBuying >= 0 else { return "CK status unknown" }
        return qtyBuying == 0 ? "CK not buying" : nil
    }

    var buyingAccessibilitySummary: String {
        buyingStatusLabel ?? "CK buying \(qtyBuying ?? 0) copies"
    }

    func clearPrices() {
        priceRetail = nil
        priceBuy = nil
        qtyBuying = nil
    }

    @MainActor
    @discardableResult
    func apply(price: CardPrice, matching request: PriceFetchRequest) -> Bool {
        guard request.matches(self), !isDeleted else { return false }
        priceRetail = price.priceRetail
        priceBuy = price.priceBuy
        qtyBuying = price.qtyBuying
        return true
    }
}
