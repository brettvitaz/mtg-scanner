import SwiftUI

struct SortFilterChipRow: View {
    @Bindable var filterState: CardFilterState
    @Binding var showFilterSheet: Bool
    @AppStorage("showCardListTotals") private var showTotals = true
    var displayedItems: [CollectionItem]

    private var displayedQuantity: Int { displayedItems.totalQuantity }
    var totalQuantity: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                controls
                Spacer(minLength: Spacing.sm)
                trailingSummary
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Spacer(minLength: 0)
                    trailingSummary
                }
                controls
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.xs)
        .background(Color.dsBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder).frame(height: 0.5)
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                sortChip
                filterChip
                if showTotals { countLabel }
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sortChip
                HStack(alignment: .bottom, spacing: Spacing.sm) {
                    filterChip
                    if showTotals { countLabel }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trailingSummary: some View {
        if showTotals {
            CardListSummaryView(pricing: CardListPricing(items: displayedItems))
        } else {
            countLabel
        }
    }

    private var sortChip: some View {
        Menu {
            Picker("Sort By", selection: $filterState.sort.field) {
                ForEach(CardSortField.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Direction", selection: $filterState.sort.direction) {
                ForEach(SortDirection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            chip(label: filterState.sort.field.displayName + " " + directionArrow)
        }
        .accessibilityLabel("Sort cards")
        .accessibilityValue("\(filterState.sort.field.displayName), \(filterState.sort.direction.rawValue)")
    }

    private var filterChip: some View {
        Button { showFilterSheet = true } label: {
            HStack(spacing: 4) {
                if filterState.isFilterActive {
                    Circle().fill(Color.dsAccent).frame(width: 6, height: 6)
                }
                Text("Filter")
                    .font(.custom(GeistStyle.body.family, size: 13, relativeTo: .body))
                    .foregroundStyle(Color.dsTextPrimary)
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .background(Color.dsSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.dsBorder, lineWidth: 1)
            )
            .frame(minHeight: 44, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter cards")
        .accessibilityValue(filterState.isFilterActive ? "Filters active" : "No filters")
    }

    private var countLabel: some View {
        let text = displayedQuantity < totalQuantity
            ? "\(displayedQuantity) of \(totalQuantity)"
            : "\(totalQuantity) cards"
        return Text(text)
            .font(.custom(GeistStyle.caption.family, size: 11, relativeTo: .caption))
            .foregroundStyle(Color.dsTextSecondary)
            .padding(.bottom, Spacing.xs)
    }

    private var directionArrow: String {
        filterState.sort.direction == .ascending ? "↑" : "↓"
    }

    private func chip(label: String) -> some View {
        Text(label)
            .font(.custom(GeistStyle.body.family, size: 13, relativeTo: .body))
            .foregroundStyle(Color.dsTextPrimary)
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .background(Color.dsSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.dsBorder, lineWidth: 1)
            )
            .frame(minHeight: 44, alignment: .bottom)
            .contentShape(Rectangle())
    }
}
