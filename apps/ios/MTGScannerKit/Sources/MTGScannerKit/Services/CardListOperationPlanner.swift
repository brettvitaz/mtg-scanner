import Foundation

enum CardListOperation: String, CaseIterable, Identifiable {
    case add = "Add"
    case subtract = "Subtract"

    var id: Self { self }
    var pastTense: String { self == .add ? "Added" : "Removed" }
}

struct CardListOperationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static let stalePreview = Self(
        message: "A list changed. Review the updated quantities before applying again."
    )
    static let staleUndo = Self(
        message: "The changed list was edited. Undo cannot safely restore its earlier contents."
    )
}

struct CardListQuantityChange: Identifiable {
    var id: UUID { item.id }
    let item: CardItemSnapshot
    let before: Int
    let after: Int
    let requested: Int
    let unavailable: Int
}

struct CardListOperationPlan {
    let target: CardListSnapshot
    let tool: CardListSnapshot?
    let toolName: String
    let operation: CardListOperation
    let deleteTool: Bool
    let resultItems: [CardItemSnapshot]
    let changes: [CardListQuantityChange]
    let affectedQuantity: Int
    let unavailableQuantity: Int
    let beforeQuantity: Int
    let afterQuantity: Int

    var canApply: Bool { affectedQuantity > 0 }
    var buttonTitle: String { "\(operation.rawValue) \(affectedQuantity) Cards" }
    var outcome: String {
        let verb = operation == .add ? "Add" : "Remove"
        let direction = operation == .add ? "to" : "from"
        let cleanup = tool == nil ? "" : deleteTool
            ? " Delete the entire \(toolName) list, including unmatched cards." : " Keep \(toolName)."
        return "\(verb) \(affectedQuantity) cards \(direction) \(target.name).\(cleanup)"
    }
}

struct CardListOperationPlanner {
    func plan(
        target: CardListSnapshot, toolItems: [CardItemSnapshot], toolName: String,
        operation: CardListOperation, tool: CardListSnapshot? = nil, deleteTool: Bool = false
    ) throws -> CardListOperationPlan {
        guard tool?.id != target.id else {
            throw CardListOperationError(message: "Choose a different list as the tool.")
        }
        let targets = try grouped(target.items)
        let tools = try grouped(toolItems)
        var result = targets
        var changes: [CardListQuantityChange] = []
        for item in tools {
            changes.append(try apply(item, to: &result, operation: operation))
        }
        let affected = try total(changes.map { abs($0.after - $0.before) })
        return CardListOperationPlan(
            target: target, tool: tool, toolName: toolName, operation: operation,
            deleteTool: tool != nil && deleteTool, resultItems: result, changes: changes,
            affectedQuantity: affected, unavailableQuantity: try total(changes.map(\.unavailable)),
            beforeQuantity: try total(targets.map(\.quantity)), afterQuantity: try total(result.map(\.quantity))
        )
    }

    private func grouped(_ items: [CardItemSnapshot]) throws -> [CardItemSnapshot] {
        var result: [CardItemSnapshot] = []
        // Establish identified printings before matching legacy rows without IDs.
        let sorted = items.sorted {
            let lhs = $0.card.scryfallId?.nonEmpty != nil
            let rhs = $1.card.scryfallId?.nonEmpty != nil
            return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs
        }
        for var item in sorted {
            item.quantity = max(1, item.quantity)
            if let index = try match(item, in: result) {
                result[index].quantity = try adding(result[index].quantity, item.quantity)
            } else {
                result.append(item)
            }
        }
        return result
    }

    private func apply(
        _ item: CardItemSnapshot, to result: inout [CardItemSnapshot], operation: CardListOperation
    ) throws -> CardListQuantityChange {
        let index = try match(item, in: result)
        let before = index.map { result[$0].quantity } ?? 0
        let after = operation == .add ? try adding(before, item.quantity) : max(0, before - item.quantity)
        if let index {
            if after == 0 { result.remove(at: index) } else { result[index].quantity = after }
        } else if operation == .add {
            var addition = item
            addition.id = UUID()
            addition.quantity = after
            result.append(addition)
        }
        return CardListQuantityChange(
            item: item, before: before, after: after, requested: item.quantity,
            unavailable: operation == .subtract ? max(0, item.quantity - before) : 0
        )
    }

    private func match(_ item: CardItemSnapshot, in items: [CardItemSnapshot]) throws -> Int? {
        let matches = items.indices.filter { items[$0].matches(item) }
        guard matches.count < 2 else {
            throw CardListOperationError(
                message: "More than one printing matches \(item.card.title ?? "this card"). Update its printing first."
            )
        }
        return matches.first
    }

    private func total(_ quantities: [Int]) throws -> Int {
        try quantities.reduce(0) { try adding($0, $1) }
    }

    private func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let sum = lhs.addingReportingOverflow(rhs)
        guard !sum.overflow else {
            throw CardListOperationError(message: "The quantity is too large. Reduce quantities and try again.")
        }
        return sum.partialValue
    }
}
