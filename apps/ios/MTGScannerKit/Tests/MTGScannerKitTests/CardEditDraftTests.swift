import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class CardEditDraftTests: XCTestCase {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func printing(_ name: String = "Lightning Bolt", finishes: String? = nil) -> CardPrinting {
        CardPrinting(
            name: name, setCode: "M10", setName: "Magic 2010", collectorNumber: "146",
            rarity: "common", typeLine: "Instant", oracleText: "Deal 3 damage.", manaCost: "{R}",
            power: nil, toughness: nil, loyalty: nil, defense: nil, scryfallId: "bolt",
            imageUrl: nil, setSymbolUrl: nil, cardKingdomUrl: "https://example.com/bolt",
            cardKingdomFoilUrl: "https://example.com/bolt-foil", colorIdentity: "R", finishes: finishes
        )
    }

    func testDraftChangesDoNotMutateStoredCard() {
        let item = CollectionItem(title: "Wrong card", edition: "Wrong set", quantity: 7)
        let draft = CardEditDraft(card: item.toRecognizedCard())
        XCTAssertEqual(draft.printing.name, "Wrong card")
        draft.select(printing(), foil: true)
        XCTAssertEqual(item.title, "Wrong card")
        XCTAssertFalse(item.foil)
        XCTAssertEqual(item.quantity, 7)
    }

    func testSelectionEnforcesFinishAvailability() {
        let draft = CardEditDraft(card: CollectionItem(title: "A", edition: "B").toRecognizedCard())
        draft.select(printing(finishes: "foil"), foil: false)
        XCTAssertTrue(draft.isFoil)
        draft.select(printing(finishes: "nonfoil"), foil: true)
        XCTAssertFalse(draft.isFoil)
    }

    func testSaveReplacesIdentityAndClearsObsoleteMetadata() throws {
        let context = try context()
        let item = CollectionItem(
            title: "Creature", edition: "Old set", power: "5", toughness: "5",
            scryfallId: "old", imageUrl: "old-image", colorIdentity: "G",
            priceRetail: "100", priceBuy: "50", quantity: 4
        )
        let collection = CardCollection(name: "Collection")
        context.insert(collection)
        item.collection = collection
        context.insert(item)
        let originalID = item.id
        let addedAt = item.addedAt
        let draft = CardEditDraft(card: item.toRecognizedCard())
        draft.select(printing(), foil: true)
        XCTAssertTrue(draft.save(item: item, context: context, merge: false))
        XCTAssertEqual(item.id, originalID)
        XCTAssertEqual(item.addedAt, addedAt)
        XCTAssertEqual(item.quantity, 4)
        XCTAssertEqual(item.collection?.id, collection.id)
        XCTAssertEqual(item.title, "Lightning Bolt")
        XCTAssertEqual(item.setCode, "M10")
        XCTAssertEqual(item.scryfallId, "bolt")
        assertReplacementMetadata(item)
    }

    private func assertReplacementMetadata(_ item: CollectionItem) {
        XCTAssertEqual(item.colorIdentity, "R")
        XCTAssertNil(item.power)
        XCTAssertNil(item.toughness)
        XCTAssertNil(item.imageUrl)
        XCTAssertNil(item.priceRetail)
        XCTAssertNil(item.priceBuy)
        XCTAssertEqual(item.cardKingdomUrl, "https://example.com/bolt-foil")
    }

    func testDuplicateRequiresConfirmationAndMergePreservesEditedRow() throws {
        let context = try context()
        let deck = Deck(name: "Deck")
        context.insert(deck)
        let item = CollectionItem(title: "Wrong", edition: "Old", quantity: 3)
        let existing = CollectionItem(from: printing(), foil: false, quantity: 5)
        for card in [item, existing] {
            card.deck = deck
            context.insert(card)
        }
        try context.save()
        let originalID = item.id
        let draft = CardEditDraft(card: item.toRecognizedCard())
        draft.select(printing(), foil: false)
        XCTAssertEqual(draft.duplicates(for: item).map(\.id), [existing.id])
        XCTAssertFalse(draft.save(item: item, context: context, merge: false))
        XCTAssertEqual(item.title, "Wrong")
        XCTAssertEqual(item.quantity, 3)
        XCTAssertTrue(draft.save(item: item, context: context, merge: true))
        XCTAssertEqual(item.id, originalID)
        XCTAssertEqual(item.quantity, 8)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionItem>()).count, 1)
        XCTAssertEqual(item.deck?.id, deck.id)
    }

    func testInboxAllowsDuplicateCards() throws {
        let context = try context()
        let item = CollectionItem(title: "Wrong", edition: "Old")
        context.insert(item)
        context.insert(CollectionItem(from: printing(), foil: false, quantity: 1))
        let draft = CardEditDraft(card: item.toRecognizedCard())
        draft.select(printing(), foil: false)
        XCTAssertTrue(draft.duplicates(for: item).isEmpty)
        XCTAssertTrue(draft.save(item: item, context: context, merge: false))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionItem>()).count, 2)
    }

    func testCorrectionSnapshotRoundTripsReplacement() throws {
        let item = CollectionItem(title: "Wrong", edition: "Old")
        let viewModel = CardDetailViewModel(card: item.toRecognizedCard(), cropImage: nil)
        viewModel.selectedPrinting = printing()
        viewModel.editTitle = "Lightning Bolt"
        var correction = CardCorrection(from: viewModel.card)
        correction.title = viewModel.editTitle
        correction.selectedPrintingSnapshot = viewModel.selectedPrinting
        let decoded = try JSONDecoder().decode(CardCorrection.self, from: JSONEncoder().encode(correction))
        let copy = CollectionItem(from: viewModel.card, correction: decoded)
        XCTAssertEqual(copy.title, "Lightning Bolt")
        XCTAssertEqual(copy.scryfallId, "bolt")
    }

    func testMissingReplacementFieldsDoNotUseOriginalCardMetadata() {
        let item = CollectionItem(title: "Creature", edition: "Old", power: "5", imageUrl: "old-image")
        let viewModel = CardDetailViewModel(card: item.toRecognizedCard(), cropImage: nil)
        viewModel.selectedPrinting = printing()
        XCTAssertNil(viewModel.displayPower)
        XCTAssertNil(viewModel.displayImageUrl)
    }

    func testPriceRequestRejectsChangedIdentityAndFinish() {
        let item = CollectionItem(title: "A", edition: "Set", scryfallId: "a")
        let request = PriceFetchRequest(item: item)
        XCTAssertTrue(request.matches(item))
        item.title = "B"
        XCTAssertFalse(request.matches(item))
        item.title = "A"
        item.scryfallId = "b"
        XCTAssertFalse(request.matches(item))
        item.scryfallId = "a"
        item.collectorNumber = "2"
        XCTAssertFalse(request.matches(item))
        item.collectorNumber = nil
        item.foil = true
        XCTAssertFalse(request.matches(item))
    }
    func testUnknownCardCanBeReplaced() throws {
        let context = try context()
        let item = CollectionItem(title: "", edition: "")
        context.insert(item)
        let draft = CardEditDraft(card: item.toRecognizedCard())
        draft.select(printing(), foil: false)
        XCTAssertTrue(draft.save(item: item, context: context, merge: false))
        XCTAssertEqual(item.title, "Lightning Bolt")
    }

    func testUnchangedIdentityPreservesPrices() {
        let item = CollectionItem(from: printing(), foil: false, quantity: 2)
        item.priceRetail = "1.50"
        item.priceBuy = "0.75"
        item.apply(printing: printing(), foil: false)
        XCTAssertEqual(item.priceRetail, "1.50")
        XCTAssertEqual(item.priceBuy, "0.75")
    }

    func testPrintingLoadFailureLeavesDraftUntouched() async {
        let appModel = AppModel()
        let originalURL = appModel.apiBaseURL
        defer { appModel.apiBaseURL = originalURL }
        appModel.apiBaseURL = "invalid://cards"
        let item = CollectionItem(title: "Original", edition: "Original set")
        let draft = CardEditDraft(card: item.toRecognizedCard())
        let picker = AddCardViewModel()
        picker.selectName("Lightning Bolt", using: appModel)
        await picker.printingTask?.value
        XCTAssertEqual(picker.errorMessage, "Failed to load printings.")
        XCTAssertFalse(picker.isLoadingPrintings)
        XCTAssertEqual(draft.printing.name, "Original")
        XCTAssertEqual(item.title, "Original")
    }

    func testSearchFailureCanBeRetried() async {
        let appModel = AppModel()
        let originalURL = appModel.apiBaseURL
        defer { appModel.apiBaseURL = originalURL }
        appModel.apiBaseURL = "invalid://cards"
        let picker = AddCardViewModel()
        picker.searchText = "Bolt"
        picker.updateSearch(using: appModel)
        await picker.searchTask?.value
        XCTAssertEqual(picker.searchError, "Could not search cards.")
        XCTAssertFalse(picker.isSearching)
        picker.updateSearch(using: appModel)
        XCTAssertNil(picker.searchError)
        await picker.searchTask?.value
        XCTAssertNotNil(picker.searchError)
    }

}
