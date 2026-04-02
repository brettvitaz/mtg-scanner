import SwiftUI

/// Sort menu and filter button for embedding inside a ToolbarItemGroup.
struct FilterSortToolbar: View {
    @Binding var filterState: CardFilterState
    @Binding var showFilterSheet: Bool

    var body: some View {
        sortMenu
        filterButton
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $filterState.sort.field) {
                ForEach(CardSortField.allCases) { field in
                    Text(field.rawValue).tag(field)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Direction", selection: $filterState.sort.direction) {
                ForEach(SortDirection.allCases) { direction in
                    Text(direction.rawValue).tag(direction)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var filterButton: some View {
        let icon = filterState.isActive
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
        return Button { showFilterSheet = true } label: { Image(systemName: icon) }
    }
}
