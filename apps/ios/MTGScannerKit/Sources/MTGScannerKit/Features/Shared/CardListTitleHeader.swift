import SwiftUI

struct CardListTitleHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .foregroundStyle(Color.dsTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.md)
            .background(Color.dsBackground)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }
}
