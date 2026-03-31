import SwiftData
import SwiftUI

struct CardDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: CardDetailViewModel
    @State private var showFullscreenImage = false
    @State private var showEditionPicker = false
    @State private var showAddToSheet = false
    @State private var saved = false
    @State private var addedMessage: String?

    init(card: RecognizedCard) {
        _viewModel = StateObject(wrappedValue: CardDetailViewModel(card: card, cropImage: nil))
    }

    var body: some View {
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
        .fullScreenCover(isPresented: $showFullscreenImage) {
            FullscreenImageView(
                imageUrl: viewModel.showingCropImage ? nil : viewModel.displayImageUrl,
                uiImage: viewModel.showingCropImage ? appModel.cardCropImages[viewModel.card.id] : nil
            )
        }
        .sheet(isPresented: $showEditionPicker) {
            EditionPickerSheet(viewModel: viewModel, isPresented: $showEditionPicker)
        }
        .sheet(isPresented: $showAddToSheet) {
            MoveToSheet(title: "Add To") { destination in
                addCardTo(destination)
            }
        }
        .overlay { if saved { ToastOverlay(message: "Correction saved") } }
        .overlay { if let msg = addedMessage { ToastOverlay(message: msg, color: .blue) } }
    }

    private func initializeViewModel() {
        let correction = appModel.corrections[viewModel.card.id]
        viewModel.editTitle = correction?.title ?? viewModel.card.title ?? ""
        viewModel.editEdition = correction?.edition ?? viewModel.card.edition ?? ""
        viewModel.editCollectorNumber = correction?.collectorNumber ?? viewModel.card.collectorNumber ?? ""
        viewModel.editFoil = correction?.foil ?? viewModel.card.foil ?? false
        Task { await viewModel.loadPrintings(using: appModel) }
        Task { await viewModel.loadPrice(using: appModel) }
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
            }
            editionButton
            Toggle("Foil", isOn: $viewModel.editFoil).font(.subheadline)
            collectorRarityRow
        }
    }

    private var editionButton: some View {
        Button { showEditionPicker = true } label: {
            HStack(spacing: 6) {
                if let symbolUrl = viewModel.displaySetSymbolUrl {
                    AsyncImage(url: symbolUrl) { phase in
                        if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fit) }
                    }
                    .frame(width: 16, height: 16)
                }
                Text(viewModel.displayEdition).font(.subheadline)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(.primary)
        }
    }

    private var collectorRarityRow: some View {
        HStack(spacing: 8) {
            if !viewModel.displayCollectorNumber.isEmpty {
                Text("#\(viewModel.displayCollectorNumber)").font(.subheadline).foregroundStyle(.secondary)
            }
            if let rarity = viewModel.displayRarity {
                RarityBadge(rarity: rarity)
            }
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let typeLine = viewModel.displayTypeLine {
                Text(typeLine).font(.subheadline.italic()).foregroundStyle(.secondary)
            }
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
            Button {
                viewModel.saveCorrection(to: appModel)
                withAnimation { saved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { saved = false } }
            } label: {
                Label("Save Correction", systemImage: "checkmark.circle")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)
    }

    private func addCardTo(_ destination: MoveDestination) {
        let correction = appModel.corrections[viewModel.card.id]
        let item = CollectionItem(from: viewModel.card, correction: correction)
        switch destination {
        case .collection(let collection):
            item.collection = collection
            collection.updatedAt = Date()
            modelContext.insert(item)
            showAddedMessage("Added to \(collection.name)")
        case .deck(let deck):
            item.deck = deck
            deck.updatedAt = Date()
            modelContext.insert(item)
            showAddedMessage("Added to \(deck.name)")
        }
    }

    private func showAddedMessage(_ message: String) {
        withAnimation { addedMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { addedMessage = nil }
        }
    }
}

// MARK: - Card Image Section

private struct CardImageSection: View {
    @ObservedObject var viewModel: CardDetailViewModel
    let appModel: AppModel
    @Binding var showFullscreen: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            cardImage
                .frame(maxWidth: .infinity, maxHeight: 340)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture { showFullscreen = true }

            if appModel.cardCropImages[viewModel.card.id] != nil {
                cropToggleButton
            }
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }

    @ViewBuilder
    private var cardImage: some View {
        if viewModel.showingCropImage, let crop = appModel.cardCropImages[viewModel.card.id] {
            Image(uiImage: crop).resizable().aspectRatio(contentMode: .fit).frame(height: 340)
        } else if let url = viewModel.displayImageUrl {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fit).frame(height: 340)
                case .failure: CardImagePlaceholder()
                default: ProgressView().frame(height: 340)
                }
            }
        } else {
            CardImagePlaceholder()
        }
    }

    private var cropToggleButton: some View {
        Button { viewModel.showingCropImage.toggle() } label: {
            Image(systemName: viewModel.showingCropImage ? "photo.artframe" : "crop")
                .font(.caption)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(8)
    }
}

// MARK: - Edition Picker Sheet

private struct EditionPickerSheet: View {
    @ObservedObject var viewModel: CardDetailViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            pickerContent
                .navigationTitle("Select Edition")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresented = false }
                    }
                }
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        if viewModel.isLoadingPrintings {
            ProgressView("Loading editions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.printings.isEmpty {
            Text("No other editions found.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            printingsList
        }
    }

    private var printingsList: some View {
        List(viewModel.printings) { printing in
            Button {
                viewModel.selectPrinting(printing)
                isPresented = false
            } label: {
                PrintingRow(printing: printing)
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Extracted Subviews

private struct PrintingRow: View {
    let printing: CardPrinting

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(printing.setName ?? printing.setCode).font(.body)
                if let cn = printing.collectorNumber {
                    Text("#\(cn)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let rarity = printing.rarity {
                RarityBadge(rarity: rarity)
            }
        }
    }
}

private struct ConfidenceTag: View {
    let value: Double

    var body: some View {
        Text("\(Int(value * 100))%")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch value {
        case 0.85...: return .green
        case 0.6..<0.85: return .orange
        default: return .red
        }
    }
}

private struct PriceLabel: View {
    let title: String
    let price: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("$\(price)").font(.headline.monospacedDigit())
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CardImagePlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.15))
            .frame(height: 340)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
    }
}

private struct RarityBadge: View {
    let rarity: String

    var body: some View {
        Text(rarity.capitalized)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch rarity.lowercased() {
        case "mythic": return .orange
        case "rare": return .yellow
        case "uncommon": return .gray
        default: return Color.secondary
        }
    }
}

private struct CardStatsView: View {
    @ObservedObject var viewModel: CardDetailViewModel

    var body: some View {
        HStack(spacing: 12) {
            if let power = viewModel.displayPower, let toughness = viewModel.displayToughness {
                StatBadge(icon: "burst.fill", label: "Power", value: power)
                Text("/").font(.title3.bold()).foregroundStyle(.secondary)
                StatBadge(icon: "shield.fill", label: "Toughness", value: toughness)
            }
            if let loyalty = viewModel.displayLoyalty {
                StatBadge(icon: "diamond.fill", label: "Loyalty", value: loyalty)
            }
            if let defense = viewModel.displayDefense {
                StatBadge(icon: "shield.checkered", label: "Defense", value: defense)
            }
        }
    }
}

private struct StatBadge: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.bold().monospacedDigit())
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ToastOverlay: View {
    let message: String
    var color: Color = .green

    var body: some View {
        VStack {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(color, in: Capsule())
                .padding(.top, 12)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
