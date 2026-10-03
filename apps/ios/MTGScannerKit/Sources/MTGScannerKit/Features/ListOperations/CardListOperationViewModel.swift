import Foundation
import SwiftData

@MainActor
@Observable
final class CardListOperationViewModel {
    var target: CardListReference
    var tool: CardListReference?
    var operation: CardListOperation = .add
    var deleteTool = false
    private(set) var plan: CardListOperationPlan?
    private(set) var receipt: CardListOperationReceipt?
    private(set) var isApplying = false
    private(set) var wasUndone = false
    var errorMessage: String?
    private let csvItems: [CardItemSnapshot]?
    private let csvName: String?

    init(
        target: CardListReference, csvItems: [CardItemSnapshot]? = nil,
        csvName: String? = nil, operation: CardListOperation = .add
    ) {
        self.target = target
        self.csvItems = csvItems
        self.csvName = csvName
        self.operation = operation
        if csvItems != nil { refresh() }
    }

    var isCSV: Bool { csvItems != nil }
    var canApply: Bool { plan?.canApply == true && !isApplying && receipt == nil }

    func chooseTarget(_ list: CardListReference) {
        target = list
        tool = nil
        plan = nil
        errorMessage = nil
    }

    func chooseTool(_ list: CardListReference) {
        tool = list
        refresh()
    }

    func refresh() {
        plan = nil
        errorMessage = nil
        guard !target.isDeleted else {
            errorMessage = "The target list no longer exists. Choose another target."
            return
        }
        guard let items = csvItems ?? tool?.items.map(CardItemSnapshot.init) else { return }
        if let tool, tool.isDeleted {
            errorMessage = "The tool list no longer exists. Choose another tool."
            return
        }
        do {
            plan = try CardListOperationPlanner().plan(
                target: target.snapshot(), toolItems: items, toolName: csvName ?? tool?.name ?? "Tool",
                operation: operation, tool: tool?.snapshot(), deleteTool: deleteTool
            )
        } catch { errorMessage = error.localizedDescription }
    }

    func apply(context: ModelContext, commit: () throws -> Void) {
        guard canApply, let plan else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            receipt = try CardListOperationPersistence().apply(plan, context: context, commit: commit)
            errorMessage = nil
        } catch {
            refresh()
            errorMessage = error.localizedDescription
        }
    }

    func undo(context: ModelContext, commit: () throws -> Void) {
        guard !isApplying, !wasUndone, let receipt else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            try CardListOperationPersistence().undo(receipt, context: context, commit: commit)
            wasUndone = true
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
