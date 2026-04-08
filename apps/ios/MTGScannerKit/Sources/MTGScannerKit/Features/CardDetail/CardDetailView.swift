import SwiftData
import SwiftUI

struct CardDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CardDetailViewModel
    @State private var showFullscreenImage = false
    @State private var showEditionPicker = false
    @State private var showAddToSheet = false
    @State private var addedMessage: String?
    @State private var isInitialized = false
    @State private var autoSaveTask: Task<Void, Never>?

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
        .onChange(of: viewModel.editTitle) { _, _ in autoSave() }
        .onChange(of: viewModel.editEdition) { _, _ in autoSave() }
        .onChange(of: viewModel.editCollectorNumber) { _, _ in autoSave() }
        .onChange(of: viewModel.editFoil) { _, _ in
            autoSave()
            guard isInitialized else { return }
            Task { await viewModel.loadPrice(using: appModel) }
        }
        .onChange(of: viewModel.selectedPrinting) { _, _ in autoSave() }
        .onChange(of: viewModel.cardPrice) { _, _ in updateCollectionItem() }
        .fullScreenCover(isPresented: $showFullscreenImage) {
            FullscreenImageView(
                imageUrl: viewModel.showingCropImage ? nil : viewModel.displayImageUrl,
                uiImage: viewModel.showingCropImage ? appModel.cardCropImages[viewModel.card.id] : nil
            )
        }
        .sheet(isPresented: $showEditionPicker) {
            EditionPickerSheet(viewModel: viewModel, appModel: appModel, isPresented: $showEditionPicker)
        }
        .sheet(isPresented: $showAddToSheet) {
            MoveToSheet(title: "Add To") { destination in
                addCardTo(destination)
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
            editionButton
            if !viewModel.displayCollectorNumber.isEmpty {
                Text("#\(viewModel.displayCollectorNumber)").font(.subheadline).foregroundStyle(.secondary)
            }
            Toggle("Foil", isOn: $viewModel.editFoil).font(.subheadline)
        }
        .accessibilityElement(children: .contain)
    }

    private var editionButton: some View {
        Button { showEditionPicker = true } label: {
            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    if let symbolUrl = viewModel.displaySetSymbolUrl {
                        CachedAsyncImage(url: symbolUrl) { phase in
                            if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fit) }
                        }
                        .frame(width: 16, height: 16)
                    }
                    Text(viewModel.displayEdition).font(.subheadline)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundStyle(.primary)
                Spacer()
                if let rarity = viewModel.displayRarity {
                    RarityBadge(rarity: rarity)
                }
            }
        }
        .accessibilityLabel("Edition")
        .accessibilityValue(viewModel.displayEdition)
        .accessibilityHint("Choose a different printing.")
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
                        PriceLabel(title: "Sell", price: retail, detail: stockText(price.qtyRetail))
                    }
                    if let buy = price.priceBuy {
                        PriceLabel(title: "Buy", price: buy, detail: buyingText(price.qtyBuying))
                    }
                }
            }
        }
    }

    private func stockText(_ qty: Int?) -> String? {
        guard let qty else { return nil }
        return "\(qty) in stock"
    }

    private func buyingText(_ qty: Int?) -> String? {
        guard let qty else { return nil }
        return "buying \(qty)"
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
                Label("Add to Collection or Deck", systemImage: "plus.rectangle.on.folder")
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
    func initializeViewModel() {
        isInitialized = false
        let correction = appModel.corrections[viewModel.card.id]
        viewModel.editTitle = correction?.title ?? viewModel.card.title ?? ""
        viewModel.editEdition = correction?.edition ?? viewModel.card.edition ?? ""
        viewModel.editCollectorNumber = correction?.collectorNumber ?? viewModel.card.collectorNumber ?? ""
        viewModel.editFoil = correction?.foil ?? viewModel.card.foil ?? false
        viewModel.selectedPrinting = correction?.selectedPrintingSnapshot
        isInitialized = true
        Task { await viewModel.loadPrintings(using: appModel) }
        Task { await viewModel.loadPrice(using: appModel) }
    }

    func autoSave() {
        guard isInitialized else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            viewModel.saveCorrection(to: appModel)
            updateCollectionItem()
        }
    }

    func updateCollectionItem() {
        let targetId = viewModel.card.id
        var descriptor = FetchDescriptor<CollectionItem>(
            predicate: #Predicate { $0.id == targetId }
        )
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        item.title = viewModel.displayTitle
        item.edition = viewModel.displayEdition
        item.setCode = viewModel.displaySetCode.isEmpty ? item.setCode : viewModel.displaySetCode
        item.collectorNumber = viewModel.displayCollectorNumber.nonEmpty
        item.foil = viewModel.editFoil
        item.rarity = viewModel.displayRarity
        item.typeLine = viewModel.displayTypeLine
        item.oracleText = viewModel.displayOracleText
        item.manaCost = viewModel.displayManaCost
        item.power = viewModel.displayPower
        item.toughness = viewModel.displayToughness
        item.loyalty = viewModel.displayLoyalty
        item.defense = viewModel.displayDefense
        if let scryfallId = viewModel.selectedPrinting?.scryfallId {
            item.scryfallId = scryfallId
        }
        item.imageUrl = viewModel.displayImageUrl?.absoluteString
        item.setSymbolUrl = viewModel.displaySetSymbolUrl?.absoluteString
        item.cardKingdomUrl = viewModel.displayCardKingdomUrl?.absoluteString ?? item.cardKingdomUrl
        if let price = viewModel.cardPrice {
            item.priceRetail = price.priceRetail
            item.priceBuy = price.priceBuy
        }
    }

    func addCardTo(_ destination: MoveDestination) {
        let correction = appModel.corrections[viewModel.card.id]
        let item = CollectionItem(from: viewModel.card, correction: correction)
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
