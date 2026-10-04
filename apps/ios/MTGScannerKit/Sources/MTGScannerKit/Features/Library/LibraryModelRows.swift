import SwiftUI

struct LibraryCollectionRow: View {
    let collection: CardCollection

    var body: some View {
        LibraryItemRow(
            iconSystemName: "folder.fill",
            name: collection.name,
            cardCount: collection.items.totalQuantity,
            updatedAt: collection.updatedAt
        )
    }
}

struct LibraryDeckRow: View {
    let deck: Deck

    var body: some View {
        LibraryItemRow(
            iconSystemName: "rectangle.stack.fill",
            name: deck.name,
            cardCount: deck.items.totalQuantity,
            updatedAt: deck.updatedAt
        )
    }
}
