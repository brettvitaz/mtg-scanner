import SwiftUI
import UIKit

/// Shared row for Results, Collection detail, and Deck detail.
/// Pass `onSwipeDelete` to enable the swipe-to-delete gesture.
/// Pass `openRowID` to coordinate single-open-row behaviour across a list.
struct CollectionItemRow: View {
    @Bindable var item: CollectionItem
    var showQuantityStepper: Bool = false
    var onCopy: (() -> Void)?
    var onMove: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSwipeDelete: (() -> Void)?
    var onToggleFoil: (() -> Void)?
    var openRowID: Binding<UUID?> = .constant(nil)

    @Environment(\.colorScheme) private var colorScheme
    @State private var swipeOffset: CGFloat = 0
    @State private var rowWidth: CGFloat = 390

    let deleteButtonWidth: CGFloat = 80

    var body: some View {
        swipeContent
            .background(widthReader)
            .onChange(of: openRowID.wrappedValue) { _, newID in
                guard newID != item.id, swipeOffset != 0 else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    swipeOffset = 0
                }
            }
            .modifier(ContextMenuModifier(row: self))
            .accessibilityElement(children: showQuantityStepper ? .contain : .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAction(named: Text("Delete")) { onSwipeDelete?() }
    }
}

// MARK: - Swipe structure + row content

private extension CollectionItemRow {
    @ViewBuilder
    var swipeContent: some View {
        if onSwipeDelete != nil {
            ZStack(alignment: .trailing) {
                deleteButton
                rowContent
                    .offset(x: swipeOffset)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: min(abs(swipeOffset) / 10, 8),
                            style: .continuous
                        )
                    )
                    .gesture(dragGesture)
            }
        } else {
            rowContent
        }
    }

    var rowContent: some View {
        HStack(spacing: Spacing.md) {
            cardThumbnail
            cardDetails
            Spacer(minLength: Spacing.lg)
            priceColumn
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(rowBackground)
        .overlay(alignment: .bottom) { hairlineDivider }
        .overlay { closeRowOverlay }
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

    @ViewBuilder
    var closeRowOverlay: some View {
        if openRowID.wrappedValue == item.id {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { closeSwipe() }
        }
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
            if showQuantityStepper { quantityStepper }
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

// MARK: - Swipe gesture + delete button

private extension CollectionItemRow {
    var deleteButton: some View {
        Button { commitDelete() } label: {
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: deleteButtonWidth)
                .frame(maxHeight: .infinity)
        }
        .background(Color(red: 1, green: 0.23, blue: 0.19))
        .opacity(swipeOffset < 0 ? 1 : 0)
    }

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    func handleDragChanged(_ value: DragGesture.Value) {
        let translation = value.translation.width
        if translation < 0 {
            swipeOffset = max(translation, -deleteButtonWidth * 2)
        } else if openRowID.wrappedValue == item.id {
            swipeOffset = min(0, -deleteButtonWidth + translation)
        }
    }

    func handleDragEnded(_ value: DragGesture.Value) {
        let traveled = -value.translation.width
        if traveled > rowWidth * 0.66 {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            commitDelete()
        } else if traveled > 40 {
            openRowID.wrappedValue = item.id
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { swipeOffset = -deleteButtonWidth }
        } else {
            closeSwipe()
        }
    }

    func commitDelete() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(
            .spring(response: 0.2, dampingFraction: 0.9),
            completionCriteria: .logicallyComplete
        ) {
            swipeOffset = -rowWidth
        } completion: {
            onSwipeDelete?()
        }
    }

    func closeSwipe() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { swipeOffset = 0 }
        if openRowID.wrappedValue == item.id { openRowID.wrappedValue = nil }
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
