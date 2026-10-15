import Foundation
import Observation

@MainActor
@Observable
final class CardListSelectionState {
    var isSelecting = false
    var selectedItems: Set<UUID> = []
    var transferRequest: CardTransferRequest?
}
