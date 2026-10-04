import SwiftUI

/// Shared row for Results, Collection detail, and Deck detail.
/// Pass `onSwipeDelete` / `onSwipeToggleFoil` to enable the respective swipe action.
struct CollectionItemRow: View {
    @Bindable var item: CollectionItem
    var showQuantityStepper: Bool = false
    var onTransfer: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSwipeDelete: (() -> Void)?
    var onToggleFoil: (() -> Void)?
    var onSwipeToggleFoil: (() -> Void)?
    var onNavigate: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        contextualContent
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if let onSwipeDelete {
                    Button(role: .destructive, action: onSwipeDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let onSwipeToggleFoil {
                    Button(action: onSwipeToggleFoil) {
                        Label(item.foil ? "Set as Non-Foil" : "Set as Foil", systemImage: "sparkles")
                    }
                    .tint(.blue)
                }
            }
            .accessibilityElement(children: showQuantityStepper ? .contain : .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityActions {
                if let onTransfer { Button("Copy/Move", action: onTransfer) }
                if let onToggleFoil {
                    Button(item.foil ? "Set as Non-Foil" : "Set as Foil", action: onToggleFoil)
                }
                if let onDelete { Button("Delete", role: .destructive, action: onDelete) }
            }
    }
}

// MARK: - Row content

private extension CollectionItemRow {
    var rowContent: some View {
        HStack(spacing: Spacing.sm) {
            navigationButton
            if showQuantityStepper { compactQuantityStepper }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity)
        .background(rowBackground)
        .overlay(alignment: .bottom) { hairlineDivider }
    }

    var navigationButton: some View {
        Button { onNavigate?() } label: {
            navigationContent.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var navigationContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    cardThumbnail
                    cardDetails
                    Spacer(minLength: 0)
                }
                priceColumn.frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(spacing: Spacing.md) {
                cardThumbnail
                cardDetails
                Spacer(minLength: Spacing.sm)
                priceColumn
            }
        }
    }

    var rowBackground: some View {
        ZStack {
            Color.dsSurface
            Rarity(item.rarity).map { $0.overlayColor(for: colorScheme) }
        }
    }

    var hairlineDivider: some View {
        Rectangle().fill(Color.dsBorder).frame(height: 0.5)
    }
}

// MARK: - Card info columns

private extension CollectionItemRow {
    var cardThumbnail: some View {
        Group {
            if let urlString = item.imageUrl, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: thumbnailPlaceholder
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

    var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.dsBorder)
            .overlay { Image(systemName: "photo").foregroundStyle(Color.dsTextSecondary) }
    }

    var cardDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            cardNameRow
            metaRow
        }
    }

    var cardNameRow: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Text(item.title)
                .font(.geist(.cardName))
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.tail)
            if item.foil {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(Rarity.rare.badgeColor)
                    .accessibilityHidden(true)
            }
        }
    }

    var metaRow: some View {
        HStack(spacing: 6) {
            Text(item.setCode?.uppercased() ?? item.edition)
                .font(.geistMono(.metaMono))
                .foregroundStyle(Color.dsTextSecondary)
            if let cn = item.collectorNumber {
                metaDot
                Text("#\(cn)").font(.geistMono(.metaMono)).foregroundStyle(Color.dsTextSecondary)
            }
            if let rarity = Rarity(item.rarity) {
                metaDot
                Text(rarity.shortLabel).font(.geistMono(.metaMono)).foregroundStyle(rarity.badgeColor)
            }
        }
        .lineLimit(1)
    }

    var metaDot: some View {
        Text("·").font(.geistMono(.metaMono)).foregroundStyle(Color.dsBorder).accessibilityHidden(true)
    }

    var compactQuantityStepper: some View {
        VStack(spacing: 2) {
            Button {
                item.quantity = min(item.quantity + 1, 999)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Increase quantity")
            Text("\(item.quantity)")
                .font(.geistMono(.metaMono))
                .foregroundStyle(Color.dsTextPrimary)
                .frame(minWidth: 24)
                .multilineTextAlignment(.center)
            Button {
                item.quantity = max(item.quantity - 1, 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Decrease quantity")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.dsTextSecondary)
    }

    var priceColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            priceRow(label: "Retail", value: item.priceRetail)
            priceRow(label: "Buylist", value: item.priceBuy)
            if let status = item.buyingStatusLabel {
                Text(status)
                    .font(.custom(GeistStyle.caption.family, size: 11, relativeTo: .caption))
                    .foregroundStyle(Color.dsTextSecondary)
            }
        }
    }

    func priceRow(label: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).fixedSize().font(.geistMono(.metaMono)).foregroundStyle(Color.dsTextSecondary)
            Text(value ?? "—")
                .font(.geistMono(.priceMono))
                .foregroundStyle(value != nil ? Color.dsTextPrimary : Color.dsTextSecondary)
                .monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Context menu + accessibility

extension CollectionItemRow {
    var accessibilitySummary: String { Self.accessibilitySummary(for: item) }

    static func accessibilitySummary(for item: CollectionItem) -> String {
        var parts = [item.title, item.edition]
        if let rarity = item.rarity { parts.append("\(rarity) rarity") }
        if let cn = item.collectorNumber { parts.append("collector number \(cn)") }
        if item.foil { parts.append("foil") }
        if item.quantity > 1 { parts.append("quantity \(item.quantity)") }
        if let p = item.priceRetail { parts.append("retail price \(p)") }
        if let p = item.priceBuy { parts.append("buylist price \(p)") }
        parts.append(item.buyingAccessibilitySummary)
        return parts.joined(separator: ", ")
    }
}

private extension CollectionItemRow {
    @ViewBuilder
    var contextualContent: some View {
        let actions = CardRowMenuActions(
            transfer: onTransfer, toggleFoil: onToggleFoil, delete: onDelete, navigate: onNavigate
        )
        if actions.isAvailable {
            CardRowContextMenu(content: rowContent, item: item, actions: actions)
        } else {
            rowContent
        }
    }
}
