import Foundation

// MARK: - Sort

enum CardSortField: String, CaseIterable, Identifiable {
    case addedAt = "Date Added"
    case title = "Title"
    case edition = "Set"
    case collectorNumber = "Collector #"
    case rarity = "Rarity"
    case cardType = "Card Type"
    case colorIdentity = "Color Identity"
    case priceRetail = "Sell Price"
    case priceBuy = "Buy Price"

    var id: String { rawValue }
}

enum SortDirection: String, CaseIterable, Identifiable {
    case descending = "Descending"
    case ascending = "Ascending"

    var id: String { rawValue }
}

struct CardSortOption: Equatable {
    var field: CardSortField
    var direction: SortDirection

    static let `default` = CardSortOption(field: .addedAt, direction: .descending)
}

// MARK: - Color Filter

enum ColorFilter: String, CaseIterable, Identifiable {
    case white = "W"
    case blue = "U"
    case black = "B"
    case red = "R"
    case green = "G"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: return "White"
        case .blue:  return "Blue"
        case .black: return "Black"
        case .red:   return "Red"
        case .green: return "Green"
        }
    }
}

// MARK: - Rarity Filter

enum RarityFilter: String, CaseIterable, Identifiable {
    case common
    case uncommon
    case rare
    case mythic

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Primary Card Type

private let knownPrimaryTypes = [
    "Creature", "Instant", "Sorcery", "Enchantment",
    "Artifact", "Planeswalker", "Land", "Battle"
]

func primaryCardType(from typeLine: String?) -> String {
    guard let typeLine else { return "Other" }
    for known in knownPrimaryTypes where typeLine.localizedCaseInsensitiveContains(known) {
        return known
    }
    return "Other"
}

// MARK: - Rarity Sort Order

private let raritySortOrder: [String: Int] = [
    "common": 0, "uncommon": 1, "rare": 2, "mythic": 3
]

// MARK: - FilterState

@Observable
final class CardFilterState {
    var searchText: String = ""
    var selectedSets: Set<String> = []
    var selectedRarities: Set<RarityFilter> = []
    var foilOnly: Bool = false
    var selectedColors: Set<ColorFilter> = []
    var selectedCardTypes: Set<String> = []
    var priceRetailMin: Double?
    var priceRetailMax: Double?
    var priceBuyMin: Double?
    var priceBuyMax: Double?
    var sort: CardSortOption = .default

    var isActive: Bool {
        !searchText.isEmpty
            || !selectedSets.isEmpty
            || !selectedRarities.isEmpty
            || foilOnly
            || !selectedColors.isEmpty
            || !selectedCardTypes.isEmpty
            || priceRetailMin != nil || priceRetailMax != nil
            || priceBuyMin != nil || priceBuyMax != nil
            || sort != .default
    }

    func reset() {
        searchText = ""
        selectedSets = []
        selectedRarities = []
        foilOnly = false
        selectedColors = []
        selectedCardTypes = []
        priceRetailMin = nil
        priceRetailMax = nil
        priceBuyMin = nil
        priceBuyMax = nil
        sort = .default
    }

    func apply(to items: [CollectionItem]) -> [CollectionItem] {
        sorted(applyFilters(items))
    }

    private func applyFilters(_ items: [CollectionItem]) -> [CollectionItem] {
        var result = items

        if !searchText.isEmpty {
            let lowered = searchText.lowercased()
            result = result.filter { item in
                item.title.localizedCaseInsensitiveContains(lowered)
                    || item.edition.localizedCaseInsensitiveContains(lowered)
                    || (item.setCode?.localizedCaseInsensitiveContains(lowered) ?? false)
            }
        }

        if !selectedSets.isEmpty {
            result = result.filter { selectedSets.contains($0.edition) }
        }

        if !selectedRarities.isEmpty {
            let rarityValues = selectedRarities.map(\.rawValue)
            result = result.filter { rarityValues.contains($0.rarity?.lowercased() ?? "") }
        }

        if foilOnly { result = result.filter(\.foil) }

        if !selectedColors.isEmpty {
            let colorLetters = selectedColors.map(\.rawValue)
            result = result.filter { item in
                guard let identity = item.colorIdentity, !identity.isEmpty else { return false }
                let cardColors = identity.components(separatedBy: ",")
                return colorLetters.contains { cardColors.contains($0) }
            }
        }

        if !selectedCardTypes.isEmpty {
            result = result.filter { selectedCardTypes.contains(primaryCardType(from: $0.typeLine)) }
        }

        return applyPriceFilters(result)
    }

    private func applyPriceFilters(_ items: [CollectionItem]) -> [CollectionItem] {
        var result = items
        if let min = priceRetailMin { result = result.filter { parsePrice($0.priceRetail) >= min } }
        if let max = priceRetailMax { result = result.filter { parsePrice($0.priceRetail) <= max } }
        if let min = priceBuyMin { result = result.filter { parsePrice($0.priceBuy) >= min } }
        if let max = priceBuyMax { result = result.filter { parsePrice($0.priceBuy) <= max } }
        return result
    }

    private func sorted(_ items: [CollectionItem]) -> [CollectionItem] {
        let ascending = sort.direction == .ascending
        return items.sorted { a, b in
            let less: Bool
            switch sort.field {
            case .addedAt:
                less = a.addedAt < b.addedAt
            case .title:
                less = a.title.localizedCompare(b.title) == .orderedAscending
            case .edition:
                less = a.edition.localizedCompare(b.edition) == .orderedAscending
            case .collectorNumber:
                less = compareCollectorNumbers(a.collectorNumber, b.collectorNumber)
            case .rarity:
                let ra = raritySortOrder[a.rarity?.lowercased() ?? ""] ?? -1
                let rb = raritySortOrder[b.rarity?.lowercased() ?? ""] ?? -1
                less = ra < rb
            case .cardType:
                let ta = primaryCardType(from: a.typeLine)
                let tb = primaryCardType(from: b.typeLine)
                less = ta.localizedCompare(tb) == .orderedAscending
            case .colorIdentity:
                less = (a.colorIdentity ?? "").localizedCompare(b.colorIdentity ?? "") == .orderedAscending
            case .priceRetail:
                less = parsePrice(a.priceRetail) < parsePrice(b.priceRetail)
            case .priceBuy:
                less = parsePrice(a.priceBuy) < parsePrice(b.priceBuy)
            }
            return ascending ? less : !less
        }
    }
}

// MARK: - Helpers

private func parsePrice(_ value: String?) -> Double {
    guard let value else { return 0 }
    let stripped = value.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)
    return Double(stripped) ?? 0
}

private func compareCollectorNumbers(_ a: String?, _ b: String?) -> Bool {
    let numA = Int(a?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? "") ?? Int.max
    let numB = Int(b?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? "") ?? Int.max
    if numA != numB { return numA < numB }
    return (a ?? "").localizedCompare(b ?? "") == .orderedAscending
}
