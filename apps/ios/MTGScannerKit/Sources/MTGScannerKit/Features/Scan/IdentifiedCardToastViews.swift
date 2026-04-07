import SwiftUI
import UIKit

/// Displays a single identified card toast notification.
///
/// Slides in from the trailing edge with a semi-transparent background.
/// Shows the card title, foil indicator, set code, and collector number.
struct IdentifiedCardToastView: View {
    let card: IdentifiedCard
    let onDismiss: () -> Void
    @State private var shimmerOffset: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            cardLabels
            Spacer()
            dismissButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .opacity(0.85)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .overlay(shimmerOverlay)
        .accessibilityElement(children: .contain)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        var parts = ["Recognized \(card.title)"]
        if card.isFoil {
            parts.append("foil")
        }
        parts.append("set \(card.setCode.uppercased())")
        if !card.collectorNumber.isEmpty {
            parts.append("collector number \(card.collectorNumber)")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var cardLabels: some View {
        HStack(spacing: 8) {
            Text(card.title)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
            if card.isFoil {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
            }
            Text(card.setCode.uppercased())
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            if !card.collectorNumber.isEmpty {
                Text("#\(card.collectorNumber)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Recently recognized card.")
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .background(Circle().fill(Color.white.opacity(0.3)).frame(width: 24, height: 24))
        }
        .accessibilityLabel("Dismiss")
        .accessibilityHint("Dismisses this recognized card notification.")
    }

    @ViewBuilder
    private var shimmerOverlay: some View {
        if card.isFoil {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.3),
                            Color.orange.opacity(0.3),
                            Color.yellow.opacity(0.3),
                            Color.green.opacity(0.3),
                            Color.blue.opacity(0.3),
                            Color.purple.opacity(0.3),
                            Color.red.opacity(0.3)
                        ],
                        startPoint: UnitPoint(x: shimmerOffset, y: 0),
                        endPoint: UnitPoint(x: shimmerOffset + 1, y: 1)
                    )
                )
                .blendMode(.overlay)
                .allowsHitTesting(false)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                        shimmerOffset = 1.0
                    }
                }
        }
    }
}

/// Container view that displays multiple card toasts stacked vertically.
struct IdentifiedCardToastContainer: View {
    @Bindable var viewModel: IdentifiedCardsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.recentCards) { card in
                IdentifiedCardToastView(card: card) {
                    viewModel.removeCard(id: card.id)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .animation(animation, value: viewModel.recentCards.count)
    }
}
