import SwiftData
import SwiftUI

@MainActor
@Observable
final class CardTransferViewModel {
    enum Screen: Hashable { case destinations, quantities }

    let operation: CardTransferOperation
    private(set) var rows: [CardTransferRow]
    private(set) var destination: MoveDestination?
    private(set) var isDismissed = false
    var path: [Screen] = []
    var errorMessage: String?

    init(items: [CollectionItem], operation: CardTransferOperation) {
        self.operation = operation
        rows = items.map { CardTransferRow(item: $0) }
    }

    var canSubmit: Bool { destination != nil && !rows.isEmpty && !isDismissed }

    var summary: String {
        let quantity = rows.reduce(0) { $0 + $1.quantity }
        let cards = quantity == 1 ? "card" : "cards"
        let selectedRows = rows.count == 1 ? "selected row" : "selected rows"
        return "\(quantity) \(cards) across \(rows.count) \(selectedRows)"
    }

    var destinationFilter: CardDestinationFilter {
        CardDestinationFilter(collectionIDs: Set(rows.compactMap(\.collectionID)),
                              deckIDs: Set(rows.compactMap(\.deckID)))
    }

    func showDestinations() { path.append(.destinations) }

    func select(_ destination: MoveDestination) {
        guard destinationFilter.includes(destination) else { return }
        self.destination = destination
        path = []
    }

    func setQuantity(_ quantity: Int, for id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].quantity = min(max(1, quantity), rows[index].availableQuantity)
    }

    func cancel() { isDismissed = true }

    func submit(
        in context: ModelContext, save: (() throws -> Void)? = nil, onComplete: (CardTransferResult) -> Void
    ) {
        guard canSubmit, let destination else { return }
        do {
            let result = try CardTransfer.perform(rows: rows, operation: operation,
                                                  destination: destination, context: context, save: save)
            isDismissed = true
            onComplete(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reviewQuantities(in context: ModelContext) {
        do {
            let items = try context.fetch(FetchDescriptor<CollectionItem>())
            rows = rows.compactMap { row in
                guard let item = items.first(where: { $0.id == row.id && !$0.isDeleted }) else { return nil }
                var refreshed = CardTransferRow(item: item)
                refreshed.quantity = min(max(1, row.quantity), refreshed.availableQuantity)
                return refreshed
            }
            errorMessage = nil
            if let destination, !destinationFilter.includes(destination) { self.destination = nil }
            if rows.isEmpty {
                isDismissed = true
            } else {
                path = [.quantities]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CardDestinationFilter {
    var collectionIDs: Set<UUID> = []
    var deckIDs: Set<UUID> = []

    func includes(_ destination: MoveDestination) -> Bool {
        switch destination {
        case .collection(let collection): !collectionIDs.contains(collection.id)
        case .deck(let deck): !deckIDs.contains(deck.id)
        }
    }
}
