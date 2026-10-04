import SwiftUI
import UIKit

struct CardRowPreview: View {
    let item: CollectionItem
    @Environment(\.colorScheme) private var colorScheme

    static func size(in availableSize: CGSize, hasArtwork: Bool = true) -> CGSize {
        let padding: CGFloat = Spacing.sm * 2
        let maxWidth = min(340, max(padding + 1, availableSize.width - 40))
        let maxHeight = min(520, max(padding + 1, availableSize.height * 0.58))
        guard hasArtwork else {
            let fallbackHeight = UIFontMetrics.default.scaledValue(for: 180)
            return CGSize(width: maxWidth, height: min(maxHeight, fallbackHeight))
        }
        let cardWidth = min(maxWidth - padding, (maxHeight - padding) * 63 / 88)
        return CGSize(width: cardWidth + padding, height: cardWidth * 88 / 63 + padding)
    }

    var accessibilitySummary: String {
        [item.title, item.edition, printingSummary, item.foil ? "Foil" : "Non-Foil"]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var body: some View {
        CachedAsyncImage(url: artworkURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary)
                    .accessibilityHint("Opens card details")
            case .empty:
                fallback(status: artworkURL == nil ? "Artwork unavailable" : "Loading artwork")
            case .failure:
                fallback(status: "Artwork unavailable")
            @unknown default:
                fallback(status: "Artwork unavailable")
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsSurface)
        .foregroundStyle(Color.dsTextPrimary)
    }

    private var artworkURL: URL? { item.imageUrl.flatMap(URL.init(string:)) }

    private var secondaryColor: Color {
        colorScheme == .dark ? Color.dsTextPrimary.opacity(0.75) : Color.dsTextSecondary
    }

    private var printingSummary: String {
        [item.setCode?.uppercased(), item.collectorNumber.map { "#\($0)" }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func fallback(status: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(item.title)
                    .font(.custom(GeistStyle.screenTitle.family, size: 22, relativeTo: .title2))
                Text(item.edition)
                    .font(.custom(GeistStyle.body.family, size: 13, relativeTo: .subheadline))
                if !printingSummary.isEmpty {
                    Text(printingSummary)
                        .font(.custom(GeistMonoStyle.metaMono.family, size: 11, relativeTo: .caption))
                }
                Text(status).font(.caption).foregroundStyle(secondaryColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityValue(status)
        .accessibilityHint("Opens card details")
    }
}
