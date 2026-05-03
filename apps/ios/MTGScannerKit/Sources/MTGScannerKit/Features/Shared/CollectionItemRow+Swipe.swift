import SwiftUI
import UIKit

// MARK: - Swipe action layers

extension CollectionItemRow {
    @ViewBuilder
    var trailingActionLayer: some View {
        if onSwipeDelete != nil {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                actionCell(
                    color: Color(red: 1, green: 0.23, blue: 0.19),
                    icon: "trash",
                    width: max(0, -swipeOffset),
                    isPrimed: crossedCommit && swipeOffset < 0
                )
            }
            .opacity(swipeOffset < 0 ? 1 : 0)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    var leadingActionLayer: some View {
        if onSwipeToggleFoil != nil {
            HStack(spacing: 0) {
                actionCell(
                    color: Color(red: 0.0, green: 0.48, blue: 1.0),
                    icon: "sparkles",
                    width: max(0, swipeOffset),
                    isPrimed: crossedCommit && swipeOffset > 0
                )
                Spacer(minLength: 0)
            }
            .opacity(swipeOffset > 0 ? 1 : 0)
            .allowsHitTesting(false)
        }
    }

    private func actionCell(color: Color, icon: String, width: CGFloat, isPrimed: Bool) -> some View {
        color
            .frame(width: width)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .scaleEffect(isPrimed ? 1.25 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPrimed)
            }
    }
}

// MARK: - Swipe gesture handlers

extension CollectionItemRow {
    func handleDragChanged(translation: CGFloat) {
        let raw = gestureBaseOffset + translation
        swipeOffset = clampOffset(raw)
        let crossed = SwipeState.hasCrossedCommit(offset: swipeOffset, rowWidth: rowWidth)
        if crossed != crossedCommit {
            crossedCommit = crossed
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func clampOffset(_ raw: CGFloat) -> CGFloat {
        if raw < 0 {
            return onSwipeDelete != nil ? max(raw, -rowWidth) : 0
        }
        if raw > 0 {
            return onSwipeToggleFoil != nil ? min(raw, rowWidth) : 0
        }
        return 0
    }

    func handleDragEnded(translation: CGFloat, velocity: CGFloat) {
        defer { crossedCommit = false }
        let outcome = SwipeState.resolve(
            offset: swipeOffset,
            rowWidth: rowWidth,
            velocity: velocity
        )
        switch outcome {
        case .close:
            closeSwipe()
        case .open(let direction):
            openSwipe(direction: direction)
        case .commit(let direction):
            commitAction(direction: direction)
        }
    }

    private func openSwipe(direction: SwipeDirection) {
        let target: CGFloat
        switch direction {
        case .trailing where onSwipeDelete != nil:
            target = -actionRevealWidth
        case .leading where onSwipeToggleFoil != nil:
            target = actionRevealWidth
        default:
            closeSwipe()
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        openRowID.wrappedValue = item.id
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            swipeOffset = target
        }
    }

    private func commitAction(direction: SwipeDirection) {
        switch direction {
        case .trailing where onSwipeDelete != nil:
            commitDelete()
        case .leading where onSwipeToggleFoil != nil:
            commitFoilToggle()
        default:
            closeSwipe()
        }
    }

    private func commitDelete() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(
            .spring(response: 0.25, dampingFraction: 0.9),
            completionCriteria: .logicallyComplete
        ) {
            swipeOffset = -rowWidth
        } completion: {
            onSwipeDelete?()
        }
    }

    private func commitFoilToggle() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        onSwipeToggleFoil?()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            swipeOffset = 0
        }
        if openRowID.wrappedValue == item.id { openRowID.wrappedValue = nil }
    }

    func closeSwipe() {
        if swipeOffset != 0 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                swipeOffset = 0
            }
        }
        if openRowID.wrappedValue == item.id { openRowID.wrappedValue = nil }
    }
}
