import XCTest
@testable import MTGScannerKit

final class AddCardViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makePrinting(
        name: String = "Lightning Bolt",
        setCode: String = "M10",
        setName: String? = "Magic 2010",
        collectorNumber: String? = "146"
    ) -> CardPrinting {
        CardPrinting(
            name: name,
            setCode: setCode,
            setName: setName,
            collectorNumber: collectorNumber,
            rarity: "common",
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            manaCost: "{R}",
            power: nil,
            toughness: nil,
            loyalty: nil,
            defense: nil,
            scryfallId: "abc-123",
            imageUrl: nil,
            setSymbolUrl: nil,
            cardKingdomUrl: "https://ck.com/bolt",
            cardKingdomFoilUrl: "https://ck.com/bolt-foil",
            colorIdentity: "R"
        )
    }

    // MARK: - filteredPrintings

    @MainActor
    func testFilteredPrintingsReturnsAllWhenFilterIsEmpty() {
        let vm = AddCardViewModel()
        vm.printings = [makePrinting(setCode: "M10"), makePrinting(setCode: "2XM")]
        vm.printingFilterText = ""

        XCTAssertEqual(vm.filteredPrintings.count, 2)
    }

    @MainActor
    func testFilteredPrintingsMatchesSetCode() {
        let vm = AddCardViewModel()
        vm.printings = [makePrinting(setCode: "M10"), makePrinting(setCode: "2XM")]
        vm.printingFilterText = "m10"

        let results = vm.filteredPrintings
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].setCode, "M10")
    }

    @MainActor
    func testFilteredPrintingsMatchesSetName() {
        let vm = AddCardViewModel()
        vm.printings = [
            makePrinting(setCode: "M10", setName: "Magic 2010"),
            makePrinting(setCode: "2XM", setName: "Double Masters")
        ]
        vm.printingFilterText = "double"

        let results = vm.filteredPrintings
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].setCode, "2XM")
    }

    @MainActor
    func testFilteredPrintingsMatchesCollectorNumber() {
        let vm = AddCardViewModel()
        vm.printings = [makePrinting(collectorNumber: "146"), makePrinting(collectorNumber: "200")]
        vm.printingFilterText = "146"

        let results = vm.filteredPrintings
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].collectorNumber, "146")
    }

    @MainActor
    func testFilteredPrintingsIsCaseInsensitive() {
        let vm = AddCardViewModel()
        vm.printings = [makePrinting(setCode: "M10", setName: "Magic 2010")]
        vm.printingFilterText = "MAGIC"

        XCTAssertEqual(vm.filteredPrintings.count, 1)
    }

    @MainActor
    func testFilteredPrintingsReturnsEmptyWhenNoMatch() {
        let vm = AddCardViewModel()
        vm.printings = [makePrinting(setCode: "M10", setName: "Magic 2010")]
        vm.printingFilterText = "zzz"

        XCTAssertTrue(vm.filteredPrintings.isEmpty)
    }

    // MARK: - buildCollectionItem

    @MainActor
    func testBuildCollectionItemReflectsViewModelState() {
        let vm = AddCardViewModel()
        vm.quantity = 3
        vm.isFoil = true

        let printing = makePrinting()
        let item = vm.buildCollectionItem(from: printing)

        XCTAssertEqual(item.title, "Lightning Bolt")
        XCTAssertEqual(item.setCode, "M10")
        XCTAssertEqual(item.quantity, 3)
        XCTAssertTrue(item.foil)
    }

    @MainActor
    func testBuildCollectionItemDefaultsToNonFoilQuantityOne() {
        let vm = AddCardViewModel()
        let item = vm.buildCollectionItem(from: makePrinting())

        XCTAssertEqual(item.quantity, 1)
        XCTAssertFalse(item.foil)
    }
}
