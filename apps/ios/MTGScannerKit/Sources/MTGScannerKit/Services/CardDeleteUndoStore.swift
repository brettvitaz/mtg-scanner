import Foundation
import SwiftData

enum CardDeleteUndoScope: Hashable {
    case results
    case collection(UUID)
    case deck(UUID)

    var tab: Int { self == .results ? 1 : 2 }

    @MainActor
    func destination(in context: ModelContext) throws -> CardListReference? {
        switch self {
        case .results: return nil
        case .collection(let id):
            let query = FetchDescriptor<CardCollection>(predicate: #Predicate { $0.id == id })
            if let list = try context.fetch(query).first(where: { !$0.isDeleted }) { return .collection(list) }
        case .deck(let id):
            let query = FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id })
            if let list = try context.fetch(query).first(where: { !$0.isDeleted }) { return .deck(list) }
        }
        throw CardListOperationError(message: "This list was deleted. Its cards can no longer be restored here.")
    }
}

struct PendingCardDeletion: Identifiable {
    let id = UUID()
    let items: [CardItemSnapshot]

    func message(destination: String) -> String {
        let target = destination == "Results" ? "Results" : "“\(destination)”"
        if let item = items.first, items.count == 1 {
            return "Restore “\(item.card.title ?? "Unknown")” to \(target)?"
        }
        return "Restore \(items.count) deleted entries to \(target)?"
    }
}

struct CardDeleteUndoAvailability {
    var selectedTab: Int?
    var pageVisible = true
    var blocked = false
    var sceneActive = true
    var editingText = false

    func allows(_ scope: CardDeleteUndoScope) -> Bool {
        selectedTab == scope.tab && pageVisible && !blocked && sceneActive && !editingText
    }

    func allowsShake(_ scope: CardDeleteUndoScope, shakeEnabled: Bool) -> Bool {
        shakeEnabled && allows(scope)
    }
}

@MainActor
@Observable
final class CardDeleteUndoStore {
    private var pending: [CardDeleteUndoScope: PendingCardDeletion] = [:]

    func deletion(in scope: CardDeleteUndoScope) -> PendingCardDeletion? { pending[scope] }

    func register(_ items: [CollectionItem], in scope: CardDeleteUndoScope) {
        guard !items.isEmpty else { return }
        pending[scope] = PendingCardDeletion(items: items.map(CardItemSnapshot.init))
    }

    func restore(
        in scope: CardDeleteUndoScope, deletionID: UUID, context: ModelContext,
        commit: () throws -> Void
    ) throws {
        guard let deletion = pending[scope], deletion.id == deletionID else { return }
        let destination = try scope.destination(in: context)
        // Flush the original deletes before inserting replacement objects with the same IDs.
        try context.save()
        try validate(deletion, in: context)
        try insert(deletion, into: destination, context: context, commit: commit)
        pending[scope] = nil
    }

    private func validate(_ deletion: PendingCardDeletion, in context: ModelContext) throws {
        let ids = deletion.items.map(\.id)
        var query = FetchDescriptor<CollectionItem>(predicate: #Predicate { ids.contains($0.id) })
        query.fetchLimit = 1
        if try !context.fetch(query).isEmpty {
            throw CardListOperationError(message: "These entries already exist. Undo cannot safely restore them.")
        }
    }

    private func insert(
        _ deletion: PendingCardDeletion, into destination: CardListReference?,
        context: ModelContext, commit: () throws -> Void
    ) throws {
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        let previousDate = destination?.updatedAt
        let items = deletion.items.map { $0.makeItem() }
        do {
            for item in items {
                context.insert(item)
                destination?.assign(item)
            }
            destination?.updatedAt = Date()
            try commit()
        } catch {
            for item in items {
                item.collection = nil
                item.deck = nil
                context.delete(item)
            }
            if let previousDate { destination?.updatedAt = previousDate }
            context.processPendingChanges()
            throw error
        }
    }
}
