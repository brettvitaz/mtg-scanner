import SwiftUI

struct EditCardView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: CardEditDraft
    let onSave: (CardEditDraft, Bool) -> Bool
    let requiresMerge: (CardEditDraft) -> Bool
    @State private var picker: CardEditPicker?
    @State private var showMergeConfirmation = false

    var body: some View {
        @Bindable var draft = draft
        NavigationStack {
            List {
                Section { CardPrintingImage(printing: draft.printing) }
                Section("Card") {
                    Text(draft.printing.name).font(.headline)
                    PrintingRow(printing: draft.printing)
                    Button("Change Card") { picker = .name }
                    Button("Change Printing") { picker = .printing }
                }
                Section("Options") {
                    Toggle("Foil", isOn: $draft.isFoil)
                        .disabled(draft.printing.isFoilOnly || draft.printing.isNonFoilOnly)
                }
                if let error = draft.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
        }
        .sheet(item: $picker) { selection in
            AddCardView(
                confirmTitle: "Use Card",
                initialName: selection == .printing ? draft.printing.name : nil, initialFoil: draft.isFoil,
                onPick: { draft.select($0, foil: $1) }, onAdd: { _ in }
            )
        }
        .alert("Merge with existing card?", isPresented: $showMergeConfirmation) {
            Button("Merge") { save(merge: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This printing and finish already exist here. Merge will combine their quantities.")
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                if requiresMerge(draft) {
                    showMergeConfirmation = true
                } else {
                    save(merge: false)
                }
            }
            .fontWeight(.semibold)
        }
    }

    private func save(merge: Bool) {
        if onSave(draft, merge) { dismiss() }
    }
}

private enum CardEditPicker: String, Identifiable {
    case name, printing
    var id: String { rawValue }
}
