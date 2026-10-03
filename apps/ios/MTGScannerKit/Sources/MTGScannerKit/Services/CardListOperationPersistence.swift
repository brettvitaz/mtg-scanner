import Foundation
import SwiftData

struct CardListOperationReceipt {
    let plan: CardListOperationPlan
    let afterTarget: CardListSnapshot
}

@MainActor
struct CardListOperationPersistence {
    func apply(
        _ plan: CardListOperationPlan, context: ModelContext, commit: () throws -> Void
    ) throws -> CardListOperationReceipt {
        guard plan.canApply else {
            throw CardListOperationError(
                message: "No matching quantities would change. Choose another tool or operation."
            )
        }
        let target = try unchanged(plan.target, in: context, error: .stalePreview)
        if let tool = plan.tool { _ = try unchanged(tool, in: context, error: .stalePreview) }
        var after = plan.target
        after.items = plan.resultItems.sorted { $0.id.uuidString < $1.id.uuidString }
        after.updatedAt = Date()
        var writes = [ListWrite(list: target, desired: after)]
        if plan.deleteTool, let tool = plan.tool,
           let list = try CardListReference.find(tool, in: context) {
            writes.append(ListWrite(list: list, desired: nil))
        }
        try transaction(writes, context: context, commit: commit)
        return CardListOperationReceipt(plan: plan, afterTarget: target.snapshot())
    }

    func undo(
        _ receipt: CardListOperationReceipt, context: ModelContext, commit: () throws -> Void
    ) throws {
        let target = try unchanged(receipt.afterTarget, in: context, error: .staleUndo)
        var writes = [ListWrite(list: target, desired: receipt.plan.target)]
        if receipt.plan.deleteTool, let tool = receipt.plan.tool {
            guard try CardListReference.find(tool, in: context) == nil else {
                throw CardListOperationError.staleUndo
            }
            writes.append(ListWrite(list: .restored(tool), desired: tool, isNew: true))
        }
        try transaction(writes, context: context, commit: commit)
    }

    private func unchanged(
        _ snapshot: CardListSnapshot, in context: ModelContext, error: CardListOperationError
    ) throws -> CardListReference {
        guard let list = try CardListReference.find(snapshot, in: context),
              list.snapshot().hasSameInventory(as: snapshot) else {
            throw error
        }
        return list
    }

    private func transaction(_ writes: [ListWrite], context: ModelContext, commit: () throws -> Void) throws {
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            for write in writes { write.apply(in: context) }
            try commit()
        } catch {
            for write in writes.reversed() { write.restore(in: context) }
            throw error
        }
    }
}

@MainActor
private struct ListWrite {
    let list: CardListReference
    let desired: CardListSnapshot?
    let original: CardListSnapshot
    let originalItems: [CollectionItem]
    let isNew: Bool

    init(list: CardListReference, desired: CardListSnapshot?, isNew: Bool = false) {
        self.list = list
        self.desired = desired
        original = list.snapshot()
        originalItems = list.items
        self.isNew = isNew
    }

    func apply(in context: ModelContext) {
        if isNew { list.insert(in: context) }
        guard let desired else {
            remove(list.items, in: context)
            list.delete(in: context)
            return
        }
        replaceItems(with: desired, candidates: list.items, in: context)
    }

    func restore(in context: ModelContext) {
        if isNew {
            remove(list.items, in: context)
            list.delete(in: context)
            return
        }
        if list.isDeleted { list.insert(in: context) }
        replaceItems(with: original, candidates: originalItems, in: context)
    }

    private func replaceItems(
        with snapshot: CardListSnapshot, candidates: [CollectionItem], in context: ModelContext
    ) {
        let ids = Set(snapshot.items.map(\.id))
        remove(list.items.filter { !ids.contains($0.id) }, in: context)
        for entry in snapshot.items {
            let item = candidates.first(where: { $0.id == entry.id }) ?? entry.makeItem()
            if item.isDeleted || item.modelContext == nil { context.insert(item) }
            item.quantity = entry.quantity
            list.assign(item)
        }
        list.updatedAt = snapshot.updatedAt
    }

    private func remove(_ items: [CollectionItem], in context: ModelContext) {
        for item in items {
            item.collection = nil
            item.deck = nil
            context.delete(item)
        }
    }
}
