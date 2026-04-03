import SwiftUI

/// Shared row view for displaying a CollectionItem in lists.
/// Used by Results, Collection detail, and Deck detail views.
struct CollectionItemRow: View {
    @Bindable var item: CollectionItem
    var showQuantityStepper: Bool = false
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleFoil: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            cardThumbnail
            cardInfo
        }
        .padding(.vertical, 4)
        .modifier(ContextMenuModifier(row: self))
    }

    private var hasContextMenu: Bool {
        onCopy != nil || onDelete != nil || onToggleFoil != nil
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let onCopy {
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
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
                        .accessibilityLabel("Foil")
                }
            }
            Text(item.edition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
}
