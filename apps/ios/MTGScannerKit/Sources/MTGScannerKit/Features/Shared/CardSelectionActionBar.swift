import SwiftUI

struct CardTransferRequest: Identifiable {
    let id = UUID()
    let items: [CollectionItem]
    let operation: CardTransferOperation
    var isBulk = false
}

struct CardSelectionActionBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isEmpty: Bool
    let onTransfer: (CardTransferOperation) -> Void
    var onToggleFoil: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            action("Copy…", symbol: "doc.on.doc") { onTransfer(.copy) }
            action("Move…", symbol: "folder") { onTransfer(.move) }
            if let onToggleFoil { action("Toggle Foil", symbol: "sparkles", perform: onToggleFoil) }
            action("Delete", symbol: "trash", role: .destructive, perform: onDelete)
        }
        .disabled(isEmpty)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func action(
        _ title: String, symbol: String, role: ButtonRole? = nil, perform: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: perform) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Label(title, systemImage: symbol)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: symbol)
                        Text(title).font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}
