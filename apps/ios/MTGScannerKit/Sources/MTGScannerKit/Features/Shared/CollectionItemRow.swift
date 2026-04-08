import SwiftUI

/// Shared row view for displaying a CollectionItem in lists.
/// Used by Results, Collection detail, and Deck detail views.
struct CollectionItemRow: View {
    @Bindable var item: CollectionItem
    var showQuantityStepper: Bool = false
    var onCopy: (() -> Void)?
    var onMove: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleFoil: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            cardThumbnail
            cardInfo
        }
        .padding(.vertical, 4)
        .modifier(ContextMenuModifier(row: self))
        .accessibilityElement(children: showQuantityStepper ? .contain : .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var hasContextMenu: Bool {
        onCopy != nil || onMove != nil || onDelete != nil || onToggleFoil != nil
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let onCopy {
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        if let onMove {
            Button(action: onMove) {
                Label("Move", systemImage: "folder")
            }
        }
        if let onToggleFoil {
            Button(action: onToggleFoil) {
                Label(item.foil ? "Set as Non-Foil" : "Set as Foil", systemImage: "sparkles")
            }
        }
        if let onDelete {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private struct ContextMenuModifier: ViewModifier {
        let row: CollectionItemRow

        @ViewBuilder
        func body(content: Content) -> some View {
            if row.hasContextMenu {
                content.contextMenu { row.contextMenu }
            } else {
                content
            }
        }
    }

    private var cardThumbnail: some View {
        Group {
            if let urlString = item.imageUrl, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 60, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }

    private var cardInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if item.foil {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color(.systemYellow))
                        .accessibilityHidden(true)
                }
            }
            HStack(spacing: 4) {
                Text(item.edition)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let rarity = item.rarity, !rarity.isEmpty {
                    RarityCircle(rarity: rarity)
                }
            }
            if let cn = item.collectorNumber {
                Text("#\(cn)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if item.priceRetail != nil || item.priceBuy != nil {
                priceLabel
            }
            if showQuantityStepper {
                quantityStepper
            }
        }
    }

    private var priceLabel: some View {
        let parts = [
            item.priceRetail.map { "Sell \($0)" },
            item.priceBuy.map { "Buy \($0)" }
        ].compactMap { $0 }
        return Text(parts.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var quantityStepper: some View {
        Stepper(value: $item.quantity, in: 1...999) {
            Text("Qty: \(item.quantity)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var accessibilitySummary: String {
        Self.accessibilitySummary(for: item)
    }

    static func accessibilitySummary(for item: CollectionItem) -> String {
        var parts = [item.title, item.edition]
        if let rarity = item.rarity {
            parts.append("\(rarity) rarity")
        }
        if let collectorNumber = item.collectorNumber {
            parts.append("collector number \(collectorNumber)")
        }
        if item.foil {
            parts.append("foil")
        }
        if item.quantity > 1 {
            parts.append("quantity \(item.quantity)")
        }
        if let priceRetail = item.priceRetail {
            parts.append("sell price \(priceRetail)")
        }
        if let priceBuy = item.priceBuy {
            parts.append("buy price \(priceBuy)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct RarityCircle: View {
    let rarity: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(String(rarity.prefix(1)).uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(textColor)
            .frame(width: 18, height: 18)
            .background(backgroundColor, in: Circle())
            .accessibilityLabel("\(rarity.capitalized) rarity")
    }

    private var isCommon: Bool { rarity.lowercased() == "common" }

    private var textColor: Color {
        isCommon ? (colorScheme == .dark ? .black : .white) : .white
    }

    private var backgroundColor: Color {
        switch rarity.lowercased() {
        case "mythic": return .orange
        case "rare": return .yellow
        case "uncommon": return .gray
        case "common": return colorScheme == .dark ? .white : .black
        default: return Color.secondary
        }
    }
}
