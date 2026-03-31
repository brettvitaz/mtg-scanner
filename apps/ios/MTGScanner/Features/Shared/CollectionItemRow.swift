import SwiftUI

/// Shared row view for displaying a CollectionItem in lists.
/// Used by Results, Collection detail, and Deck detail views.
struct CollectionItemRow: View {
    @Bindable var item: CollectionItem
    var showQuantityStepper: Bool = false

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
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            Text(item.edition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let cn = item.collectorNumber {
                Text("#\(cn)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if showQuantityStepper {
                quantityStepper
            }
        }
    }

    private var quantityStepper: some View {
        Stepper(value: $item.quantity, in: 1...999) {
            Text("Qty: \(item.quantity)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
