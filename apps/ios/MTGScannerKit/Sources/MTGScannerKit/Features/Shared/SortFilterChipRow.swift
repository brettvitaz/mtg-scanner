import SwiftUI

struct SortFilterChipRow: View {
    @Bindable var filterState: CardFilterState
    @Binding var showFilterSheet: Bool
    var displayedQuantity: Int
    var totalQuantity: Int

    var body: some View {
        HStack(spacing: Spacing.sm) {
            sortChip
            filterChip
            Spacer()
            countLabel
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.dsBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder).frame(height: 0.5)
        }
    }

    private var sortChip: some View {
        Menu {
            Picker("Sort By", selection: $filterState.sort.field) {
                ForEach(CardSortField.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Direction", selection: $filterState.sort.direction) {
                ForEach(SortDirection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            chip(label: filterState.sort.field.rawValue + " " + directionArrow)
        }
        .accessibilityLabel("Sort cards")
        .accessibilityValue("\(filterState.sort.field.rawValue), \(filterState.sort.direction.rawValue)")
    }

    private var filterChip: some View {
        Button { showFilterSheet = true } label: {
            HStack(spacing: 4) {
                if filterState.isFilterActive {
                    Circle().fill(Color.dsAccent).frame(width: 6, height: 6)
                }
                Text("Filter")
                    .font(.geist(.body))
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
            .font(.geist(.caption))
            .foregroundStyle(Color.dsTextSecondary)
    }

    private var directionArrow: String {
        filterState.sort.direction == .ascending ? "↑" : "↓"
    }

    private func chip(label: String) -> some View {
        Text(label)
            .font(.geist(.body))
            .foregroundStyle(Color.dsTextPrimary)
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .background(Color.dsSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.dsBorder, lineWidth: 1)
            )
    }
}
