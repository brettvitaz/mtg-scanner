import SwiftUI

struct CardListSummaryView: View {
    let pricing: CardListPricing

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            totalRow("Buylist", total: pricing.buylist)
            totalRow("Retail", total: pricing.retail)
        }
    }

    private func totalRow(_ label: String, total: CardPriceTotal) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                totalLabel(label, total: total)
                totalAmount(total)
            }
            VStack(alignment: .trailing, spacing: 2) {
                totalLabel(label, total: total)
                totalAmount(total)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total.accessibilitySummary(label: label))
    }

    private func totalLabel(_ label: String, total: CardPriceTotal) -> some View {
        HStack(spacing: 4) {
            Text(label)
            if total.isPartial { Text("Partial") }
        }
        .font(.custom(GeistStyle.caption.family, size: 11, relativeTo: .caption))
        .foregroundStyle(Color.dsTextSecondary)
        .fixedSize()
    }

    private func totalAmount(_ total: CardPriceTotal) -> some View {
        Text(total.displayAmount)
            .font(.custom(GeistMonoStyle.priceMono.family, size: 13, relativeTo: .body))
            .monospacedDigit()
            .foregroundStyle(Color.dsTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

}

struct CardListNoMatchesView: View {
    @Bindable var filterState: CardFilterState

    var body: some View {
        ContentUnavailableView {
            Label("No cards match your filters", systemImage: "line.3.horizontal.decrease.circle")
        } actions: {
            Button("Reset filters") { filterState.reset() }
                .buttonStyle(.bordered)
        }
    }
}
