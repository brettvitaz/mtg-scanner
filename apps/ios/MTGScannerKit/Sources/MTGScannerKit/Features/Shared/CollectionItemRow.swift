import SwiftUI
import UIKit

/// Shared row for Results, Collection detail, and Deck detail.
/// Pass `onSwipeDelete` / `onSwipeToggleFoil` to enable the respective swipe action.
/// Pass `openRowID` to coordinate single-open-row behaviour across a list.
struct CollectionItemRow: View {
    @Bindable var item: CollectionItem
    var showQuantityStepper: Bool = false
    var onCopy: (() -> Void)?
    var onMove: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSwipeDelete: (() -> Void)?
    var onToggleFoil: (() -> Void)?
    var onSwipeToggleFoil: (() -> Void)?
    var onNavigate: (() -> Void)?
    var openRowID: Binding<UUID?> = .constant(nil)

    @Environment(\.colorScheme) private var colorScheme
    @State var swipeOffset: CGFloat = 0
    @State var rowWidth: CGFloat = 390
    @State var gestureBaseOffset: CGFloat = 0
    @State var crossedCommit = false

    let actionRevealWidth: CGFloat = 80

    var body: some View {
        swipeContent
            .background(widthReader)
            .onChange(of: openRowID.wrappedValue) { _, newID in
                guard newID != item.id, swipeOffset != 0 else { return }
                closeSwipe()
            }
            .modifier(ContextMenuModifier(row: self))
            .accessibilityElement(children: showQuantityStepper ? .contain : .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAction(named: Text("Delete")) { onSwipeDelete?() }
            .accessibilityAction(named: Text("Toggle Foil")) { onSwipeToggleFoil?() }
    }
}

// MARK: - Swipe structure + row content

private extension CollectionItemRow {
    var hasSwipeAction: Bool { onSwipeDelete != nil || onSwipeToggleFoil != nil }

    @ViewBuilder
    var swipeContent: some View {
        if hasSwipeAction {
            ZStack {
                trailingActionLayer
                leadingActionLayer
                rowContent
                    .offset(x: swipeOffset)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: min(abs(swipeOffset) / 10, 8),
                            style: .continuous
                        )
                    )
            }
            .gesture(
                HorizontalPanGesture(
                    onBegan: { gestureBaseOffset = swipeOffset },
                    onChanged: { translation in handleDragChanged(translation: translation) },
                    onEnded: { translation, velocity in
                        handleDragEnded(translation: translation, velocity: velocity)
                    },
                    onCancelled: closeSwipe
                )
            )
        } else {
            rowContent
        }
    }

    var rowContent: some View {
        HStack(spacing: Spacing.md) {
            navigationButton
            if showQuantityStepper { quantityStepper.fixedSize() }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(rowBackground)
        .overlay(alignment: .bottom) { hairlineDivider }
    }

    var navigationButton: some View {
        Button {
            if swipeOffset != 0 { closeSwipe() } else { onNavigate?() }
        } label: {
            HStack(spacing: Spacing.md) {
                cardThumbnail
                cardDetails
                Spacer(minLength: Spacing.lg)
                priceColumn
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.onAppear { rowWidth = proxy.size.width }
        }
    }
}

// MARK: - Card info columns

private extension CollectionItemRow {
    var cardThumbnail: some View {
        Group {
            if let urlString = item.imageUrl, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
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
                .lineLimit(2)
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
    }

    var metaDot: some View {
        Text("·").font(.geistMono(.metaMono)).foregroundStyle(Color.dsBorder).accessibilityHidden(true)
    }

    var quantityStepper: some View {
        Stepper(value: $item.quantity, in: 1...999) {
            Text("Qty: \(item.quantity)").font(.geist(.caption)).foregroundStyle(Color.dsTextSecondary)
        }
        .labelsHidden()
        .buttonStyle(.borderless)
    }

    var priceColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            priceRow(label: "sell", value: item.priceRetail)
            priceRow(label: "buy", value: item.priceBuy)
        }
    }

    func priceRow(label: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.geistMono(.metaMono)).foregroundStyle(Color.dsTextSecondary)
            Text(value ?? "—")
                .font(.geistMono(.priceMono))
                .foregroundStyle(value != nil ? Color.dsTextPrimary : Color.dsTextSecondary)
                .monospacedDigit()
        }
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
        if let p = item.priceRetail { parts.append("sell price \(p)") }
        if let p = item.priceBuy { parts.append("buy price \(p)") }
        return parts.joined(separator: ", ")
    }
}

private extension CollectionItemRow {
    var hasContextMenu: Bool { onCopy != nil || onMove != nil || onDelete != nil || onToggleFoil != nil }

    @ViewBuilder
    var contextMenu: some View {
        if let onCopy { Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") } }
        if let onMove { Button(action: onMove) { Label("Move", systemImage: "folder") } }
        if let onToggleFoil {
            Button(action: onToggleFoil) {
                Label(item.foil ? "Set as Non-Foil" : "Set as Foil", systemImage: "sparkles")
            }
        }
        if let onDelete {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }

    struct ContextMenuModifier: ViewModifier {
        let row: CollectionItemRow

        @ViewBuilder
        func body(content: Content) -> some View {
            if row.hasContextMenu { content.contextMenu { row.contextMenu } } else { content }
        }
    }
}
