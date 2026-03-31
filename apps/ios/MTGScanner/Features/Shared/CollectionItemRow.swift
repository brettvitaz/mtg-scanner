import SwiftUI

/// Shared row view for displaying a CollectionItem in lists.
/// Used by Results, Collection detail, and Deck detail views.
struct CollectionItemRow: View {
    let item: CollectionItem

    var body: some View {
        HStack(spacing: 12) {
            cardThumbnail
            cardInfo
        }
        .padding(.vertical, 4)
    }

    private var cardThumbnail: some View {
        Group {
            if let urlString = item.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 60, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }

    private var cardInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
            }
            Text(item.edition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let cn = item.collectorNumber {
                Text("#\(cn)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
