import SwiftUI

/// A brief completion receipt. Results remain available after the notice expires.
struct IdentifiedCardToastView: View {
    let card: IdentifiedCard
    let onDismiss: () -> Void
    @State private var shimmerOffset: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("\(card.setCode.uppercased()) #\(card.collectorNumber)")
                if card.isFoil { Label("Foil", systemImage: "sparkles") }
            }
            .font(.caption)
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .captureControlSurface(in: RoundedRectangle(cornerRadius: 12))
        .overlay(shimmerOverlay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: "Dismiss notification", onDismiss)
        .accessibilityIdentifier("capture-recognition-notice-\(card.id)")
    }

    private var accessibilityLabel: String {
        var parts = ["Recognized \(card.title)"]
        if card.isFoil { parts.append("foil") }
        parts.append("set \(card.setCode.uppercased())")
        if !card.collectorNumber.isEmpty { parts.append("collector number \(card.collectorNumber)") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var shimmerOverlay: some View {
        if card.isFoil && !reduceMotion {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [.clear, .cyan.opacity(0.12), .pink.opacity(0.12), .clear],
                    startPoint: UnitPoint(x: shimmerOffset, y: 0),
                    endPoint: UnitPoint(x: shimmerOffset + 0.7, y: 1)
                ))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.8)) { shimmerOffset = 1.5 }
                }
        }
    }
}

/// Completion notices occupy their own top overlay and never lay out capture controls.
struct IdentifiedCardToastContainer: View {
    @Bindable var viewModel: IdentifiedCardsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 6) {
            ForEach(viewModel.recentCards.prefix(dynamicTypeSize.isAccessibilitySize ? 1 : 3)) { card in
                IdentifiedCardToastView(card: card) { viewModel.removeCard(id: card.id) }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, 16)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: viewModel.recentCards.map(\.id))
    }
}
