import SwiftUI

struct LibraryItemRow: View {
    let iconSystemName: String
    let name: String
    let cardCount: Int
    let updatedAt: Date

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: Spacing.md) {
            iconTile
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(name)
                    .font(.geist(.cardName))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                Text(metaText)
                    .font(.geist(.body))
                    .foregroundStyle(Color.dsTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.dsSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsBorder).frame(height: 0.5)
        }
    }

    private var iconTile: some View {
        Image(systemName: iconSystemName)
            .font(.system(size: 18))
            .foregroundStyle(Color.dsTextSecondary)
            .frame(width: 44, height: 44)
            .background(Color.dsBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.dsBorder, lineWidth: 1)
            )
    }

    private var metaText: String {
        let rel = Self.relativeDateFormatter.localizedString(for: updatedAt, relativeTo: Date())
        return "\(cardCount) card(s) · \(rel)"
    }
}
