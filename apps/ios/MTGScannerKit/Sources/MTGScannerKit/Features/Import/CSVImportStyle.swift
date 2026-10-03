import SwiftUI

// Import roles use the card-list families while preserving native text scaling.
enum CSVImportStyle {
    static let heading = Font.custom(GeistStyle.sectionHeading.family, size: 17, relativeTo: .headline)
    static let cardName = Font.custom(GeistStyle.cardName.family, size: 15, relativeTo: .body)
    static let body = Font.custom(GeistStyle.body.family, size: 17, relativeTo: .body)
    static let metadata = Font.custom(GeistStyle.body.family, size: 13, relativeTo: .subheadline)
    static let quantity = Font.custom(GeistMonoStyle.priceMono.family, size: 15, relativeTo: .body)
    static let secondaryText = Color.dsTextPrimary.opacity(0.72)
    static let contentWidth: CGFloat = 620
}

struct CSVImportListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .listSectionSpacing(Spacing.lg)
            .scrollContentBackground(.hidden)
            .font(CSVImportStyle.body)
            .tint(Color.dsAccent)
            .frame(maxWidth: CSVImportStyle.contentWidth)
            .frame(maxWidth: .infinity)
            .background(Color.dsBackground)
    }
}
