import SwiftUI

struct CardDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var viewModel: CardDetailViewModel
    @State private var showFullscreenImage = false
    @State private var showEditionPicker = false
    @State private var saved = false

    init(card: RecognizedCard) {
        _viewModel = StateObject(wrappedValue: CardDetailViewModel(card: card, cropImage: nil))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CardImageSection(viewModel: viewModel, appModel: appModel, showFullscreen: $showFullscreenImage)
                identitySection
                detailsSection
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
        .overlay { if saved { SavedOverlay() } }
    }

    private func initializeViewModel() {
        let correction = appModel.corrections[viewModel.card.id]
        viewModel.editTitle = correction?.title ?? viewModel.card.title ?? ""
        viewModel.editEdition = correction?.edition ?? viewModel.card.edition ?? ""
        viewModel.editCollectorNumber = correction?.collectorNumber ?? viewModel.card.collectorNumber ?? ""
        viewModel.editFoil = correction?.foil ?? viewModel.card.foil ?? false
        Task { await viewModel.loadPrintings(using: appModel) }
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.displayTitle).font(.title2.bold())
            editionButton
            Toggle("Foil", isOn: $viewModel.editFoil).font(.subheadline)
            collectorRarityRow
            ConfidenceBadge(value: viewModel.card.confidence)
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
            if let stats = viewModel.statsText {
                Text(stats).font(.headline.monospacedDigit()).padding(.top, 4)
            }
        }
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

private struct SavedOverlay: View {
    var body: some View {
        VStack {
            Label("Correction saved", systemImage: "checkmark.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.green, in: Capsule())
                .padding(.top, 12)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
