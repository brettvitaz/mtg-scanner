import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
public final class LibraryViewModel {
    public var modelContext: ModelContext?

    public init() {}

    func createCollection(name: String) {
        guard let modelContext else { return }
        let collection = CardCollection(name: name)
        modelContext.insert(collection)
    }

    func createDeck(name: String) {
        guard let modelContext else { return }
        let deck = Deck(name: name)
        modelContext.insert(deck)
    }

    func renameCollection(_ collection: CardCollection, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collection.name = trimmed
        collection.updatedAt = Date()
    }

    func renameDeck(_ deck: Deck, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        deck.name = trimmed
        deck.updatedAt = Date()
    }

    func deleteCollections(at offsets: IndexSet, from collections: [CardCollection]) {
        let targets = offsets.map { collections[$0] }
        for collection in targets {
            deleteCollection(collection)
        }
    }

    func deleteDecks(at offsets: IndexSet, from decks: [Deck]) {
        let targets = offsets.map { decks[$0] }
        for deck in targets {
            deleteDeck(deck)
        }
    }

    func deleteCollection(_ collection: CardCollection) {
        guard let modelContext else { return }
        modelContext.delete(collection)
    }

    func deleteDeck(_ deck: Deck) {
        guard let modelContext else { return }
        modelContext.delete(deck)
    }
}
