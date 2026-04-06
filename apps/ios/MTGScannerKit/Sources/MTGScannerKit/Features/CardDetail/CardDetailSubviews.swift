import SwiftUI

// MARK: - Card Image Section

struct CardImageSection: View {
    @Bindable var viewModel: CardDetailViewModel
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
            CachedAsyncImage(url: url) { phase in
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

struct EditionPickerSheet: View {
    @Bindable var viewModel: CardDetailViewModel
    let appModel: AppModel
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
                viewModel.selectPrinting(printing, using: appModel)
                isPresented = false
            } label: {
                PrintingRow(printing: printing)
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Supporting Subviews

struct PrintingRow: View {
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

struct ConfidenceTag: View {
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

struct PriceLabel: View {
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

struct CardImagePlaceholder: View {
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

struct RarityBadge: View {
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

struct CardStatsView: View {
    @Bindable var viewModel: CardDetailViewModel

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

struct StatBadge: View {
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

struct ToastOverlay: View {
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
