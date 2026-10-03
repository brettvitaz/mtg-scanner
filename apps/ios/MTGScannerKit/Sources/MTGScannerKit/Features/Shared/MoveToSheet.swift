import SwiftData
import SwiftUI

struct MoveToSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSelect: (MoveDestination) -> Void

    var body: some View {
        NavigationStack {
            List {
                CardDestinationSections { destination in
                    destination.insertIfNeeded(in: modelContext)
                    onSelect(destination)
                    dismiss()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

enum MoveDestination {
    case collection(CardCollection)
    case deck(Deck)

    var name: String {
        switch self {
        case .collection(let collection): collection.name
        case .deck(let deck): deck.name
        }
    }

    var items: [CollectionItem] {
        switch self {
        case .collection(let collection): collection.items
        case .deck(let deck): deck.items
        }
    }

    func insertIfNeeded(in context: ModelContext) {
        switch self {
        case .collection(let collection):
            if collection.modelContext == nil { context.insert(collection) }
        case .deck(let deck):
            if deck.modelContext == nil { context.insert(deck) }
        }
    }

    func assign(_ item: CollectionItem) {
        item.collection = nil
        item.deck = nil
        switch self {
        case .collection(let collection): item.collection = collection
        case .deck(let deck): item.deck = deck
        }
    }

    func updateTimestamp() {
        switch self {
        case .collection(let collection): collection.updatedAt = Date()
        case .deck(let deck): deck.updatedAt = Date()
        }
    }
}
