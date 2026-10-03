import SwiftData
import SwiftUI

struct CardDestinationSections: View {
    @Query(sort: \CardCollection.updatedAt, order: .reverse) private var collections: [CardCollection]
    @Query(sort: \Deck.updatedAt, order: .reverse) private var decks: [Deck]
    @State private var newName = ""
    @State private var showNewCollection = false
    @State private var showNewDeck = false

    var excludedCollections: Set<UUID> = []
    var excludedDecks: Set<UUID> = []
    let onSelect: (MoveDestination) -> Void

    var body: some View {
        Group {
            Section("Collections") {
                Button {
                    newName = ""
                    showNewCollection = true
                } label: {
                    Label("New Collection", systemImage: "plus.circle")
                }
                ForEach(collections.filter { !excludedCollections.contains($0.id) }) { collection in
                    destinationButton(.collection(collection), symbol: "folder")
                }
            }
            Section("Decks") {
                Button {
                    newName = ""
                    showNewDeck = true
                } label: {
                    Label("New Deck", systemImage: "plus.circle")
                }
                ForEach(decks.filter { !excludedDecks.contains($0.id) }) { deck in
                    destinationButton(.deck(deck), symbol: "rectangle.stack")
                }
            }
        }
        .alert("New Collection", isPresented: $showNewCollection) {
            newNameAlert { onSelect(.collection(CardCollection(name: $0))) }
        }
        .alert("New Deck", isPresented: $showNewDeck) {
            newNameAlert { onSelect(.deck(Deck(name: $0))) }
        }
    }

    private func destinationButton(_ destination: MoveDestination, symbol: String) -> some View {
        Button { onSelect(destination) } label: {
            HStack {
                Label(destination.name, systemImage: symbol)
                Spacer()
                Text("\(destination.items.totalQuantity)").foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("\(destination.name), \(destination.items.totalQuantity) cards")
    }

    @ViewBuilder
    private func newNameAlert(onCreate: @escaping (String) -> Void) -> some View {
        TextField("Name", text: $newName)
        Button("Create") {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onCreate(trimmed)
        }
        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Cancel", role: .cancel) {}
    }
}
