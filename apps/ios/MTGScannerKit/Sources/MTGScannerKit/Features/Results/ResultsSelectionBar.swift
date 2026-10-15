import SwiftUI

struct ResultsSelectionBar: View {
    let hasSelection: Bool
    let onTransfer: () -> Void
    let onToggleFoil: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            actionButton("doc.on.doc", "Copy/Move", action: onTransfer)
            Spacer()
            actionButton("sparkles", "Toggle Foil", action: onToggleFoil)
            Spacer()
            actionButton("trash", "Delete", role: .destructive, action: onDelete)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func actionButton(
        _ icon: String, _ label: String, role: ButtonRole? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(role: role) {
            guard hasSelection else { return }
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                Text(label).font(.caption2)
            }
        }
        .disabled(!hasSelection)
    }
}
