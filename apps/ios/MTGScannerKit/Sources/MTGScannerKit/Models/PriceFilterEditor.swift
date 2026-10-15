import Foundation
import Observation

/// Keeps native text editing independent of the numeric filter until an entry is completed.
@MainActor
@Observable
final class PriceFilterEditor {
    enum Field: String, CaseIterable, Identifiable {
        case minRetail = "Min Retail"
        case maxRetail = "Max Retail"
        case minBuylist = "Min Buylist"
        case maxBuylist = "Max Buylist"

        var id: String { rawValue }

        var bound: ReferenceWritableKeyPath<CardFilterState, Double?> {
            switch self {
            case .minRetail: return \.priceRetailMin
            case .maxRetail: return \.priceRetailMax
            case .minBuylist: return \.priceBuyMin
            case .maxBuylist: return \.priceBuyMax
            }
        }

        var previous: Field? { Self.allCases.prefix(while: { $0 != self }).last }
        var next: Field? { Self.allCases.drop(while: { $0 != self }).dropFirst().first }
    }

    var drafts: [Field: String] = [:]
    private(set) var errors: [Field: String] = [:]
    private(set) var focusedField: Field?
    private let filterState: CardFilterState
    private let locale: Locale
    private let formatter: NumberFormatter

    init(filterState: CardFilterState, locale: Locale = .current) {
        self.filterState = filterState
        self.locale = locale
        formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        for field in Field.allCases {
            drafts[field] = filterState[keyPath: field.bound].map { format($0) } ?? ""
        }
    }

    var canReset: Bool { filterState.isActive || drafts.values.contains { !$0.isEmpty } || !errors.isEmpty }
    var canMovePrevious: Bool { focusedField?.previous != nil }
    var canMoveNext: Bool { focusedField?.next != nil }

    @discardableResult
    func commit(_ field: Field) -> Bool {
        let text = (drafts[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            filterState[keyPath: field.bound] = nil
            drafts[field] = ""
            errors[field] = nil
            return true
        }
        let scanner = Scanner(string: text)
        scanner.locale = locale
        guard let value = scanner.scanDouble(), scanner.isAtEnd, value.isFinite else {
            errors[field] = "Enter a valid price."
            return false
        }
        filterState[keyPath: field.bound] = value
        drafts[field] = format(value)
        errors[field] = nil
        return true
    }

    @discardableResult
    func move(to field: Field?) -> Bool {
        guard field != focusedField else { return true }
        if let current = focusedField, !commit(current) { return false }
        focusedField = field
        return true
    }

    func previous() {
        guard let previous = focusedField?.previous else { return }
        move(to: previous)
    }

    func next() {
        guard let next = focusedField?.next else { return }
        move(to: next)
    }

    func submit() {
        if canMoveNext { next() } else { move(to: nil) }
    }

    func finish() -> Bool {
        let invalid = Field.allCases.filter { !commit($0) }
        focusedField = invalid.first
        return invalid.isEmpty
    }

    func reset() {
        filterState.reset()
        drafts = Dictionary(uniqueKeysWithValues: Field.allCases.map { ($0, "") })
        errors = [:]
        focusedField = nil
    }

    private func format(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? ""
    }
}
