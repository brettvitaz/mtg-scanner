import SwiftUI

struct CardListOverflowMenu: View {
    @AppStorage("showCardListTotals") private var showTotals = true

    let items: [CollectionItem]
    let name: String
    @Binding var exportFile: ExportActivityItem?
    let onSelect: () -> Void
    var onImport: (() -> Void)?
    var onListOperation: (() -> Void)?

    var body: some View {
        Menu {
            Button {
                onSelect()
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
            if let onImport {
                Button(action: onImport) {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
            }
            if let onListOperation {
                Button(action: onListOperation) {
                    Label("Add or Subtract Cards", systemImage: "plus.forwardslash.minus")
                }
            }
            Toggle(isOn: $showTotals) {
                Label("Show price totals", systemImage: "dollarsign.circle")
            }
            Divider()
            ExportMenuContent(items: items, name: name, exportFile: $exportFile)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More options")
    }
}
