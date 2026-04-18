import Foundation

/// Manages the queue of recently identified cards for toast display.
///
/// Maintains up to `maxCards` recent identifications, auto-dismissing
/// each card after `displayDuration` seconds.
@MainActor
@Observable
final class IdentifiedCardsViewModel {

    // MARK: - Published State

    private(set) var recentCards: [IdentifiedCard] = []

    // MARK: - Configuration

    let maxCards = 10
    let displayDuration: TimeInterval = 3.0

    // MARK: - Private State

    private var removalTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Public API

    /// Adds a newly identified card to the queue.
    /// If the queue exceeds `maxCards`, the oldest card is removed immediately.
    /// The card will be automatically removed after `displayDuration` seconds.
    func addCard(_ card: IdentifiedCard) {
        recentCards.insert(card, at: 0)

        if recentCards.count > maxCards {
            let removed = recentCards.removeLast()
            cancelRemovalTask(for: removed.id)
        }

        scheduleRemoval(for: card)
    }

    /// Manually removes a card from the queue (e.g., user dismissal).
    func removeCard(id: UUID) {
        cancelRemovalTask(for: id)
        recentCards.removeAll { $0.id == id }
    }

    /// Clears all cards and cancels pending removal tasks.
    func clearAll() {
        for task in removalTasks.values {
            task.cancel()
        }
        removalTasks.removeAll()
        recentCards.removeAll()
    }

    // MARK: - Private Helpers

    private func scheduleRemoval(for card: IdentifiedCard) {
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.displayDuration ?? 3.0))
            guard !Task.isCancelled else { return }
            await self?.removeCard(id: card.id)
        }
        removalTasks[card.id] = task
    }

    private func cancelRemovalTask(for id: UUID) {
        removalTasks[id]?.cancel()
        removalTasks.removeValue(forKey: id)
    }
}
