import Foundation
import SwiftData

enum CardTransferOperation: String, CaseIterable, Identifiable {
    case copy = "Copy"
    case move = "Move"

    var id: Self { self }
}

struct CardTransferRow: Identifiable {
    let id: UUID
    let title: String
    let printing: String
    let availableQuantity: Int
    let collectionID: UUID?
    let deckID: UUID?
    var quantity: Int

    init(item: CollectionItem) {
        id = item.id
        title = item.title
        printing = [item.edition, item.collectorNumber, item.foil ? "Foil" : "Non-foil"]
            .compactMap { $0 }.joined(separator: " · ")
        availableQuantity = max(1, item.quantity)
        quantity = availableQuantity
        collectionID = item.collection?.id
        deckID = item.deck?.id
    }
}

struct CardTransferResult {
    let operation: CardTransferOperation
    let destinationName: String
    let removedSourceIDs: Set<UUID>
}

enum CardTransferError: LocalizedError {
    case sourceChanged
    case invalidQuantity
    case sameDestination

    var errorDescription: String? {
        switch self {
        case .sourceChanged: "These cards changed or are no longer available. Review the quantities and try again."
        case .invalidQuantity: "Choose a quantity between 1 and the available number of cards."
        case .sameDestination: "Choose a different collection or deck."
        }
    }
}

@MainActor
enum CardTransfer {
    static func perform(
        rows: [CardTransferRow], operation: CardTransferOperation,
        destination: MoveDestination, context: ModelContext
    ) throws -> CardTransferResult {
        let items = try validate(rows: rows, destination: destination, context: context)
        // Persist pre-existing edits so a failed transfer only rolls back its own mutations.
        try context.save()
        var removedIDs: Set<UUID> = []
        do {
            destination.insertIfNeeded(in: context)
            for (row, item) in zip(rows, items) {
                let sourceID = item.id
                if transfer(item, quantity: row.quantity, operation: operation,
                            destination: destination, context: context) {
                    removedIDs.insert(sourceID)
                }
            }
            destination.updateTimestamp()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return CardTransferResult(operation: operation, destinationName: destination.name,
                                  removedSourceIDs: removedIDs)
    }

    private static func validate(
        rows: [CardTransferRow], destination: MoveDestination, context: ModelContext
    ) throws -> [CollectionItem] {
        guard !rows.isEmpty, Set(rows.map(\.id)).count == rows.count else {
            throw CardTransferError.invalidQuantity
        }
        return try rows.map { row in
            let sourceID = row.id
            let descriptor = FetchDescriptor<CollectionItem>(predicate: #Predicate { $0.id == sourceID })
            guard let item = try context.fetch(descriptor).first, !item.isDeleted,
                  max(1, item.quantity) == row.availableQuantity,
                  item.collection?.id == row.collectionID, item.deck?.id == row.deckID else {
                throw CardTransferError.sourceChanged
            }
            guard (1...row.availableQuantity).contains(row.quantity) else {
                throw CardTransferError.invalidQuantity
            }
            switch destination {
            case .collection(let collection):
                guard item.collection?.id != collection.id else { throw CardTransferError.sameDestination }
            case .deck(let deck):
                guard item.deck?.id != deck.id else { throw CardTransferError.sameDestination }
            }
            return item
        }
    }

    private static func transfer(
        _ item: CollectionItem, quantity: Int, operation: CardTransferOperation,
        destination: MoveDestination, context: ModelContext
    ) -> Bool {
        let available = max(1, item.quantity)
        let match = destination.items.first { $0.matches(item) }
        if operation == .move {
            item.collection?.updatedAt = Date()
            item.deck?.updatedAt = Date()
        }
        if let match {
            match.quantity += quantity
        } else if operation == .move && quantity == available {
            item.quantity = quantity
            destination.assign(item)
            return true
        } else {
            let copy = item.duplicate()
            copy.quantity = quantity
            destination.assign(copy)
            context.insert(copy)
        }
        guard operation == .move else { return false }
        if quantity == available {
            context.delete(item)
            return true
        }
        item.quantity = available - quantity
        return false
    }
}
