import SwiftUI

struct CardPrintingImage: View {
    let printing: CardPrinting

    var body: some View {
        HStack {
            Spacer()
            if let imageUrl = printing.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .empty:
                        ProgressView().frame(height: 200)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
            Spacer()
        }
        .accessibilityLabel("Card image for \(printing.name)")
        .listRowBackground(Color.clear)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 143, height: 200)
            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
    }
}
