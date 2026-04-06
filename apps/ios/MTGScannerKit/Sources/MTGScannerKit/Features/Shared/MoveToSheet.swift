import SwiftData
import SwiftUI

/// Sheet for picking a collection or deck to move/copy items into.
/// Matches iOS Mail-style "Move" sheet with existing destinations + create new.
struct MoveToSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CardCollection.updatedAt, order: .reverse) private var collections: [CardCollection]
    @Query(sort: \Deck.updatedAt, order: .reverse) private var decks: [Deck]

    let title: String
    let onSelect: (MoveDestination) -> Void

    @State private var newName = ""
    @State private var showNewCollection = false
    @State private var showNewDeck = false

    var body: some View {
        NavigationStack {
            List {
                collectionsSection
                decksSection
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Collection", isPresented: $showNewCollection) {
                newNameAlert { name in
                    let collection = CardCollection(name: name)
                    modelContext.insert(collection)
                    onSelect(.collection(collection))
                    dismiss()
                }
            }
            .alert("New Deck", isPresented: $showNewDeck) {
                newNameAlert { name in
                    let deck = Deck(name: name)
                    modelContext.insert(deck)
                    onSelect(.deck(deck))
                    dismiss()
                }
            }
        }
    }

    // MARK: - Sections

    private var collectionsSection: some View {
        Section("Collections") {
            Button {
                newName = ""
                showNewCollection = true
            } label: {
                Label("New Collection", systemImage: "plus.circle")
            }
            ForEach(collections) { collection in
                Button {
                    onSelect(.collection(collection))
                    dismiss()
                } label: {
                    HStack {
                        Label(collection.name, systemImage: "folder")
                        Spacer()
                        Text("\(collection.items.totalQuantity)")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private var decksSection: some View {
        Section("Decks") {
            Button {
                newName = ""
                showNewDeck = true
            } label: {
                Label("New Deck", systemImage: "plus.circle")
            }
            ForEach(decks) { deck in
                Button {
                    onSelect(.deck(deck))
                    dismiss()
                } label: {
                    HStack {
                        Label(deck.name, systemImage: "rectangle.stack")
                        Spacer()
                        Text("\(deck.items.totalQuantity)")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Alert content

    @ViewBuilder
    private func newNameAlert(onCreate: @escaping (String) -> Void) -> some View {
        TextField("Name", text: $newName)
        Button("Create") {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onCreate(trimmed)
        }
        Button("Cancel", role: .cancel) {}
    }
}

enum MoveDestination {
    case collection(CardCollection)
    case deck(Deck)
}
