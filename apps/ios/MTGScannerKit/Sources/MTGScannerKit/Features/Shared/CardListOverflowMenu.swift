import SwiftUI

struct CardListOverflowMenu: View {
    let items: [CollectionItem]
    let name: String
    @Binding var exportFile: ExportActivityItem?
    let onSelect: () -> Void

    var body: some View {
        Menu {
            Button {
                onSelect()
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
            Divider()
            ExportMenuContent(items: items, name: name, exportFile: $exportFile)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More options")
    }
}
