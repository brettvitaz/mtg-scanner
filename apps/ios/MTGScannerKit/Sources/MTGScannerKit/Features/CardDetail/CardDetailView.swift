import SwiftData
import SwiftUI

struct CardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CardDetailViewModel
    @State private var showFullscreenImage = false
    @State private var showEditor = false
    @State private var showAddToSheet = false
    @State private var addedMessage: String?

    init(card: RecognizedCard) {
        _viewModel = State(wrappedValue: CardDetailViewModel(card: card, cropImage: nil))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CardImageSection(viewModel: viewModel, appModel: appModel, showFullscreen: $showFullscreenImage)
                identitySection
                detailsSection
                priceSection
                actionsSection
            }
            .padding()
        }
        .navigationTitle(viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { initializeViewModel() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }
            }
        }
        .fullScreenCover(isPresented: $showFullscreenImage) {
            FullscreenImageView(
                imageUrl: viewModel.showingCropImage ? nil : viewModel.displayImageUrl,
                uiImage: viewModel.showingCropImage ? appModel.cardCropImages[viewModel.card.id] : nil
            )
        }
        .sheet(isPresented: $showEditor) {
            EditCardView(
                draft: CardEditDraft(card: currentCard, printing: viewModel.selectedPrinting),
                onSave: saveEdit,
                requiresMerge: { draft in
                    guard let item = storedItem else { return false }
                    return !draft.duplicates(for: item).isEmpty
                }
            )
        }
        .sheet(isPresented: $showAddToSheet) {
            if let item = storedItem {
                let sourceID = item.id
                CopyMoveSheet(items: [item]) { result in
                    if result.removedSourceIDs.contains(sourceID) {
                        dismiss()
                    } else {
                        viewModel.card = item.toRecognizedCard()
                        let verb = result.operation == .copy ? "Copied" : "Moved"
                        showAddedMessage("\(verb) to \(result.destinationName)")
                    }
                }
            } else {
                MoveToSheet(title: "Add To") { destination in
                    addCardTo(destination)
                }
            }
        }
        .overlay { if let msg = addedMessage { ToastOverlay(message: msg, color: .blue) } }
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.displayTitle).font(.title2.bold())
                Spacer()
                ConfidenceTag(value: viewModel.card.confidence)
            }
            if let manaCost = viewModel.displayManaCost {
                Text(manaCost).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    .accessibilityLabel("Mana cost \(manaCost)")
            }
            if let typeLine = viewModel.displayTypeLine {
                Text(typeLine).font(.subheadline.italic()).foregroundStyle(.secondary)
            }
            editionRow
            if !viewModel.displayCollectorNumber.isEmpty {
                Text("#\(viewModel.displayCollectorNumber)").font(.subheadline).foregroundStyle(.secondary)
            }
            LabeledContent("Finish", value: viewModel.editFoil ? "Foil" : "Non-foil")
                .font(.subheadline)
        }
        .accessibilityElement(children: .contain)
    }

    private var editionRow: some View {
        HStack(spacing: 6) {
            if let symbolUrl = viewModel.displaySetSymbolUrl {
                CachedAsyncImage(url: symbolUrl) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFit() }
                }
                .frame(width: 16, height: 16)
            }
            Text(viewModel.displayEdition).font(.subheadline)
            Spacer()
            if let rarity = viewModel.displayRarity { RarityBadge(rarity: rarity) }
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let oracleText = viewModel.displayOracleText {
                Text(oracleText).font(.body).padding(.top, 2)
            }
            if viewModel.hasStats {
                CardStatsView(viewModel: viewModel).padding(.top, 4)
            }
        }
    }

    // MARK: - Prices

    @ViewBuilder
    private var priceSection: some View {
        if viewModel.isLoadingPrice {
            HStack {
                ProgressView()
                Text("Loading prices...").font(.subheadline).foregroundStyle(.secondary)
            }
        } else if let price = viewModel.cardPrice,
                  price.priceRetail != nil || price.priceBuy != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Card Kingdom Prices").font(.subheadline.bold())
                HStack(spacing: 16) {
                    if let retail = price.priceRetail {
                        PriceLabel(title: "Retail", price: retail, detail: stockText(price.qtyRetail))
                    }
                    if let buy = price.priceBuy {
                        PriceLabel(title: "Buylist", price: buy, detail: buyingText(price.qtyBuying))
                    }
                }
                Text("Retail is CK’s selling price. Buylist is CK’s offer to buy your card.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stockText(_ qty: Int?) -> String? {
        guard let qty else { return nil }
        return "\(qty) in stock"
    }

    private func buyingText(_ qty: Int?) -> String? {
        guard let qty, qty >= 0 else { return "CK status unknown" }
        return qty == 0 ? "CK not buying" : "CK buying \(qty)"
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        VStack(spacing: 12) {
            if let ckUrl = viewModel.displayCardKingdomUrl {
                Link(destination: ckUrl) {
                    Label("Buy on Card Kingdom", systemImage: "cart")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
            Button { showAddToSheet = true } label: {
                Label(storedItem == nil ? "Add to Collection or Deck" : "Copy/Move",
                      systemImage: "plus.rectangle.on.folder")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)
    }

}

// MARK: - Actions

extension CardDetailView {
    private var storedItem: CollectionItem? {
        let targetID = viewModel.card.id
        var descriptor = FetchDescriptor<CollectionItem>(predicate: #Predicate { $0.id == targetID })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private var currentCard: RecognizedCard {
        storedItem?.toRecognizedCard() ?? viewModel.card
    }

    func initializeViewModel() {
        let card = currentCard
        viewModel.card = card
        let correction = appModel.corrections[card.id]
        viewModel.editTitle = card.title ?? ""
        viewModel.editEdition = card.edition ?? ""
        viewModel.editCollectorNumber = card.collectorNumber ?? ""
        viewModel.editFoil = card.foil ?? false
        viewModel.selectedPrinting = correction?.selectedPrintingSnapshot
        Task { await refreshPrice() }
    }

    private func saveEdit(_ draft: CardEditDraft, merge: Bool) -> Bool {
        guard let item = storedItem else {
            draft.errorMessage = "This card is no longer available."
            return false
        }
        guard draft.save(item: item, context: modelContext, merge: merge) else { return false }
        viewModel.card = item.toRecognizedCard()
        viewModel.selectedPrinting = draft.printing
        viewModel.editTitle = item.title
        viewModel.editEdition = item.edition
        viewModel.editCollectorNumber = item.collectorNumber ?? ""
        viewModel.editFoil = item.foil
        viewModel.cardPrice = nil
        viewModel.saveCorrection(to: appModel)
        Task { await refreshPrice() }
        return true
    }

    private func refreshPrice() async {
        guard let item = storedItem else {
            await viewModel.loadPrice(using: appModel)
            return
        }
        let request = PriceFetchRequest(item: item)
        await viewModel.loadPrice(using: appModel)
        guard let price = viewModel.cardPrice else { return }
        item.apply(price: price, matching: request)
    }

    func addCardTo(_ destination: MoveDestination) {
        let item = storedItem?.duplicate() ?? CollectionItem(from: viewModel.card)
        item.quantity = 1
        switch destination {
        case .collection(let collection):
            mergeOrInsert(item, into: collection.items, context: modelContext) {
                $0.collection = collection
            }
            collection.updatedAt = Date()
            showAddedMessage("Added to \(collection.name)")
        case .deck(let deck):
            mergeOrInsert(item, into: deck.items, context: modelContext) {
                $0.deck = deck
            }
            deck.updatedAt = Date()
            showAddedMessage("Added to \(deck.name)")
        }
    }

    func showAddedMessage(_ message: String) {
        withAnimation { addedMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { addedMessage = nil }
        }
    }
}
