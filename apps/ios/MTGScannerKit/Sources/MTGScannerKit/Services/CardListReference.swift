import Foundation
import SwiftData

@MainActor
enum CardListReference {
    case collection(CardCollection)
    case deck(Deck)

    var id: UUID {
        switch self {
        case .collection(let list): list.id
        case .deck(let list): list.id
        }
    }

    var kind: CardListKind {
        switch self {
        case .collection: .collection
        case .deck: .deck
        }
    }

    var name: String {
        switch self {
        case .collection(let list): list.name
        case .deck(let list): list.name
        }
    }

    var items: [CollectionItem] {
        switch self {
        case .collection(let list): list.items
        case .deck(let list): list.items
        }
    }

    var quantitySummary: String {
        var quantity = 0
        for item in items {
            let sum = quantity.addingReportingOverflow(max(1, item.quantity))
            guard !sum.overflow else { return "Quantity too large" }
            quantity = sum.partialValue
        }
        return "\(quantity) cards"
    }

    var updatedAt: Date {
        get {
            switch self {
            case .collection(let list): list.updatedAt
            case .deck(let list): list.updatedAt
            }
        }
        nonmutating set {
            switch self {
            case .collection(let list): list.updatedAt = newValue
            case .deck(let list): list.updatedAt = newValue
            }
        }
    }

    var isDeleted: Bool {
        switch self {
        case .collection(let list): list.isDeleted || list.modelContext == nil
        case .deck(let list): list.isDeleted || list.modelContext == nil
        }
    }

    func snapshot() -> CardListSnapshot {
        let createdAt: Date
        switch self {
        case .collection(let list): createdAt = list.createdAt
        case .deck(let list): createdAt = list.createdAt
        }
        return CardListSnapshot(
            id: id, kind: kind, name: name, createdAt: createdAt, updatedAt: updatedAt,
            items: items.map(CardItemSnapshot.init).sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    func assign(_ item: CollectionItem) {
        item.collection = nil
        item.deck = nil
        switch self {
        case .collection(let list): item.collection = list
        case .deck(let list): item.deck = list
        }
    }

    func insert(in context: ModelContext) {
        switch self {
        case .collection(let list): context.insert(list)
        case .deck(let list): context.insert(list)
        }
    }

    func delete(in context: ModelContext) {
        switch self {
        case .collection(let list): context.delete(list)
        case .deck(let list): context.delete(list)
        }
    }

    static func restored(_ snapshot: CardListSnapshot) -> Self {
        switch snapshot.kind {
        case .collection:
            let list = CardCollection(name: snapshot.name)
            list.id = snapshot.id
            list.createdAt = snapshot.createdAt
            list.updatedAt = snapshot.updatedAt
            return .collection(list)
        case .deck:
            let list = Deck(name: snapshot.name)
            list.id = snapshot.id
            list.createdAt = snapshot.createdAt
            list.updatedAt = snapshot.updatedAt
            return .deck(list)
        }
    }

    static func find(_ snapshot: CardListSnapshot, in context: ModelContext) throws -> Self? {
        let id = snapshot.id
        switch snapshot.kind {
        case .collection:
            let query = FetchDescriptor<CardCollection>(predicate: #Predicate { $0.id == id })
            return try context.fetch(query).first(where: { !$0.isDeleted }).map(Self.collection)
        case .deck:
            let query = FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id })
            return try context.fetch(query).first(where: { !$0.isDeleted }).map(Self.deck)
        }
    }
}
