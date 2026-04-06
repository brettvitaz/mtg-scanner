import XCTest
@testable import MTGScannerKit

// MARK: - Helpers

private func makeItem(
    title: String = "Lightning Bolt",
    edition: String = "Magic 2010",
    setCode: String? = "M10",
    collectorNumber: String? = "146",
    foil: Bool = false,
    rarity: String? = "common",
    typeLine: String? = "Instant",
    colorIdentity: String? = "R",
    priceRetail: String? = nil,
    priceBuy: String? = nil,
    addedAt: Date = Date()
) -> CollectionItem {
    let item = CollectionItem(
        title: title,
        edition: edition,
        setCode: setCode,
        collectorNumber: collectorNumber,
        foil: foil,
        rarity: rarity,
        typeLine: typeLine,
        addedAt: addedAt
    )
    item.colorIdentity = colorIdentity
    item.priceRetail = priceRetail
    item.priceBuy = priceBuy
    return item
}

final class CardFilterSortTests: XCTestCase {

    // MARK: - Search

    func testSearchByTitleMatchesSubstring() {
        let items = [makeItem(title: "Lightning Bolt"), makeItem(title: "Forest")]
        let filter = CardFilterState()
        filter.searchText = "bolt"
        let result = filter.apply(to: items)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Lightning Bolt")
    }

    func testSearchByEditionMatchesSubstring() {
        let items = [makeItem(edition: "Magic 2010"), makeItem(edition: "Double Masters")]
        let filter = CardFilterState()
        filter.searchText = "double"
        let result = filter.apply(to: items)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].edition, "Double Masters")
    }

    func testSearchIsCaseInsensitive() {
        let items = [makeItem(title: "Counterspell")]
        let filter = CardFilterState()
        filter.searchText = "COUNTER"
        XCTAssertEqual(filter.apply(to: items).count, 1)
    }

    func testSearchWithNoMatchReturnsEmpty() {
        let items = [makeItem(title: "Lightning Bolt")]
        let filter = CardFilterState()
        filter.searchText = "zzznomatch"
        XCTAssertTrue(filter.apply(to: items).isEmpty)
    }

    func testEmptySearchReturnsAll() {
        let items = [makeItem(title: "A"), makeItem(title: "B")]
        let filter = CardFilterState()
        filter.searchText = ""
        XCTAssertEqual(filter.apply(to: items).count, 2)
    }

    // MARK: - Set Filter

    func testSetFilterMatchesEdition() {
        let items = [makeItem(title: "A", edition: "Set A"), makeItem(title: "B", edition: "Set B")]
        let filter = CardFilterState()
        filter.selectedSets = ["Set A"]
        let result = filter.apply(to: items)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].edition, "Set A")
    }

    func testEmptySetFilterReturnsAll() {
        let items = [makeItem(title: "A", edition: "Set A"), makeItem(title: "B", edition: "Set B")]
        let filter = CardFilterState()
        filter.selectedSets = []
        XCTAssertEqual(filter.apply(to: items).count, 2)
    }

    // MARK: - Rarity Filter

    func testRarityFilterMatchesExactRarity() {
        let items = [makeItem(rarity: "common"), makeItem(rarity: "rare"), makeItem(rarity: "mythic")]
        let filter = CardFilterState()
        filter.selectedRarities = [.rare]
        let result = filter.apply(to: items)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].rarity, "rare")
    }

    func testRarityFilterCaseInsensitive() {
        let items = [makeItem(rarity: "Common"), makeItem(rarity: "rare")]
        let filter = CardFilterState()
        filter.selectedRarities = [.common]
        XCTAssertEqual(filter.apply(to: items).count, 1)
    }

    func testRarityFilterExcludesNilRarity() {
        let items = [makeItem(rarity: nil), makeItem(rarity: "common")]
        let filter = CardFilterState()
        filter.selectedRarities = [.common]
        XCTAssertEqual(filter.apply(to: items).count, 1)
    }

    // MARK: - Foil Filter

    func testFoilFilterRetainsOnlyFoilCards() {
        let items = [makeItem(foil: true), makeItem(foil: false)]
        let filter = CardFilterState()
        filter.foilOnly = true
        let result = filter.apply(to: items)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].foil)
    }

    func testFoilFilterOffReturnsAll() {
        let items = [makeItem(foil: true), makeItem(foil: false)]
        let filter = CardFilterState()
        filter.foilOnly = false
        XCTAssertEqual(filter.apply(to: items).count, 2)
    }

    // MARK: - Color Identity Filter

    func testColorFilterMatchesCardWithColor() {
        let items = [makeItem(colorIdentity: "W,U"), makeItem(colorIdentity: "R")]
        let filter = CardFilterState()
        filter.selectedColors = [.white]
        let result = filter.apply(to: items)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].colorIdentity, "W,U")
    }

    func testColorFilterMatchesAnySelectedColor() {
        let items = [makeItem(colorIdentity: "W"), makeItem(colorIdentity: "B"), makeItem(colorIdentity: "R")]
        let filter = CardFilterState()
        filter.selectedColors = [.white, .black]
        XCTAssertEqual(filter.apply(to: items).count, 2)
    }

    func testColorFilterExcludesNilColorIdentity() {
        let items = [makeItem(colorIdentity: nil), makeItem(colorIdentity: "R")]
        let filter = CardFilterState()
        filter.selectedColors = [.red]
        let result = filter.apply(to: items)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].colorIdentity, "R")
    }

    // MARK: - Card Type Filter

    func testTypeFilterMatchesPrimaryType() {
        let items = [makeItem(typeLine: "Instant"), makeItem(typeLine: "Legendary Creature — Human Wizard")]
        let filter = CardFilterState()
        filter.selectedCardTypes = ["Creature"]
        let result = filter.apply(to: items)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].typeLine, "Legendary Creature — Human Wizard")
    }

    func testTypeFilterOtherCatchesUnknownTypes() {
        let items = [makeItem(typeLine: "Conspiracy")]
        let filter = CardFilterState()
        filter.selectedCardTypes = ["Other"]
        XCTAssertEqual(filter.apply(to: items).count, 1)
    }

    // MARK: - Price Filter

    func testPriceRetailMinFilter() {
        let cheap = makeItem(priceRetail: "$0.50")
        let expensive = makeItem(priceRetail: "$5.00")
        let filter = CardFilterState()
        filter.priceRetailMin = 1.0
        let result = filter.apply(to: [cheap, expensive])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].priceRetail, "$5.00")
    }

    func testPriceRetailMaxFilter() {
        let cheap = makeItem(priceRetail: "$0.50")
        let expensive = makeItem(priceRetail: "$5.00")
        let filter = CardFilterState()
        filter.priceRetailMax = 1.0
        let result = filter.apply(to: [cheap, expensive])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].priceRetail, "$0.50")
    }

    func testNilPricePassesThroughPriceFilter() {
        let noPrice = makeItem(priceRetail: nil)
        let filter = CardFilterState()
        filter.priceRetailMin = 1.0
        // nil treated as $0.00 — fails the min filter
        XCTAssertTrue(filter.apply(to: [noPrice]).isEmpty)
    }

    // MARK: - Combined Filters

    func testCombinedFiltersAreAnded() {
        let items = [
            makeItem(title: "Lightning Bolt", foil: false, rarity: "common"),
            makeItem(title: "Lightning Bolt", foil: false, rarity: "rare"),
            makeItem(title: "Forest", foil: true, rarity: "common")
        ]
        let filter = CardFilterState()
        filter.selectedRarities = [.common]
        filter.foilOnly = true
        let result = filter.apply(to: items)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Forest")
    }
}

// MARK: - Sort & State Tests

final class CardSortAndStateTests: XCTestCase {

    // MARK: - Sort

    func testSortByCollectorNumberHandlesTokenSlashFormat() {
        // "1/20" should sort as 1, not 120 — leading integer only
        let items = [
            makeItem(collectorNumber: "1/20"),
            makeItem(collectorNumber: "2/20"),
            makeItem(collectorNumber: "119")
        ]
        let filter = CardFilterState()
        filter.sort = CardSortOption(field: .collectorNumber, direction: .ascending)
        let result = filter.apply(to: items)
        XCTAssertEqual(result[0].collectorNumber, "1/20")
        XCTAssertEqual(result[1].collectorNumber, "2/20")
        XCTAssertEqual(result[2].collectorNumber, "119")
    }

    func testSortByTitleAscending() {
        let items = [makeItem(title: "Z Card"), makeItem(title: "A Card")]
        let filter = CardFilterState()
        filter.sort = CardSortOption(field: .title, direction: .ascending)
        let result = filter.apply(to: items)
        XCTAssertEqual(result[0].title, "A Card")
        XCTAssertEqual(result[1].title, "Z Card")
    }

    func testSortByTitleDescending() {
        let items = [makeItem(title: "A Card"), makeItem(title: "Z Card")]
        let filter = CardFilterState()
        filter.sort = CardSortOption(field: .title, direction: .descending)
        let result = filter.apply(to: items)
        XCTAssertEqual(result[0].title, "Z Card")
    }

    func testSortByRarityAscending() {
        let items = [makeItem(rarity: "mythic"), makeItem(rarity: "common"), makeItem(rarity: "rare")]
        let filter = CardFilterState()
        filter.sort = CardSortOption(field: .rarity, direction: .ascending)
        let result = filter.apply(to: items)
        XCTAssertEqual(result[0].rarity, "common")
        XCTAssertEqual(result[1].rarity, "rare")
        XCTAssertEqual(result[2].rarity, "mythic")
    }

    func testSortByPriceRetailAscending() {
        let items = [makeItem(priceRetail: "$5.00"), makeItem(priceRetail: "$1.00"), makeItem(priceRetail: nil)]
        let filter = CardFilterState()
        filter.sort = CardSortOption(field: .priceRetail, direction: .ascending)
        let result = filter.apply(to: items)
        XCTAssertNil(result[0].priceRetail)
        XCTAssertEqual(result[1].priceRetail, "$1.00")
        XCTAssertEqual(result[2].priceRetail, "$5.00")
    }

    func testSortByAddedAtDescendingIsDefault() {
        let older = makeItem(addedAt: Date(timeIntervalSinceNow: -100))
        let newer = makeItem(addedAt: Date(timeIntervalSinceNow: 0))
        let filter = CardFilterState()
        XCTAssertEqual(filter.sort, .default)
        let result = filter.apply(to: [older, newer])
        XCTAssertEqual(result[0].addedAt, newer.addedAt)
    }

    // MARK: - isActive and reset

    func testIsActiveIsFalseByDefault() {
        XCTAssertFalse(CardFilterState().isActive)
    }

    func testIsActiveOnSearch() {
        let filter = CardFilterState()
        filter.searchText = "bolt"
        XCTAssertTrue(filter.isActive)
    }

    func testIsActiveOnFoilOnly() {
        let filter = CardFilterState()
        filter.foilOnly = true
        XCTAssertTrue(filter.isActive)
    }

    func testIsActiveOnSort() {
        let filter = CardFilterState()
        filter.sort = CardSortOption(field: .title, direction: .ascending)
        XCTAssertTrue(filter.isActive)
        XCTAssertFalse(filter.isFilterActive)
    }

    func testIsFilterActiveIsFalseOnSortOnly() {
        let filter = CardFilterState()
        filter.sort = CardSortOption(field: .rarity, direction: .descending)
        XCTAssertFalse(filter.isFilterActive)
    }

    func testIsFilterActiveIsTrueOnSearchText() {
        let filter = CardFilterState()
        filter.searchText = "bolt"
        XCTAssertTrue(filter.isFilterActive)
    }

    func testResetClearsAll() {
        let filter = CardFilterState()
        filter.searchText = "bolt"
        filter.foilOnly = true
        filter.selectedRarities = [.mythic]
        filter.selectedColors = [.blue]
        filter.sort = CardSortOption(field: .title, direction: .ascending)
        filter.reset()
        XCTAssertFalse(filter.isActive)
        XCTAssertTrue(filter.searchText.isEmpty)
        XCTAssertFalse(filter.foilOnly)
        XCTAssertTrue(filter.selectedRarities.isEmpty)
        XCTAssertTrue(filter.selectedColors.isEmpty)
        XCTAssertEqual(filter.sort, .default)
    }

    // MARK: - Edge Cases

    func testApplyToEmptyListReturnsEmpty() {
        XCTAssertTrue(CardFilterState().apply(to: []).isEmpty)
    }

    func testAllFiltersActiveNoMatchReturnsEmpty() {
        let items = [makeItem(title: "Forest", foil: false, rarity: "common", colorIdentity: "G")]
        let filter = CardFilterState()
        filter.selectedRarities = [.mythic]
        filter.selectedColors = [.blue]
        XCTAssertTrue(filter.apply(to: items).isEmpty)
    }

    // MARK: - primaryCardType helper

    func testPrimaryCardTypeRecognizesKnownTypes() {
        XCTAssertEqual(primaryCardType(from: "Instant"), "Instant")
        XCTAssertEqual(primaryCardType(from: "Legendary Creature — Human"), "Creature")
        XCTAssertEqual(primaryCardType(from: "Basic Land — Forest"), "Land")
        XCTAssertEqual(primaryCardType(from: "Artifact Creature — Golem"), "Creature")
    }

    func testPrimaryCardTypeReturnsOtherForUnknown() {
        XCTAssertEqual(primaryCardType(from: "Conspiracy"), "Other")
        XCTAssertEqual(primaryCardType(from: nil), "Other")
    }
}
