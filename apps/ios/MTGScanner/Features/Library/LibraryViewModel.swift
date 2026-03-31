import Foundation
import SwiftData
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    var modelContext: ModelContext?

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

    func deleteCollection(_ collection: CardCollection) {
        guard let modelContext else { return }
        modelContext.delete(collection)
    }

    func deleteDeck(_ deck: Deck) {
        guard let modelContext else { return }
        modelContext.delete(deck)
    }
}
