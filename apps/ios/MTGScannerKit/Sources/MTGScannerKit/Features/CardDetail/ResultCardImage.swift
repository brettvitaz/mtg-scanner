import SwiftUI

struct ResultCardImage: View {
    let imageURL: URL?
    let scan: UIImage?
    @Binding var showingScan: Bool
    let openImage: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if scan != nil {
                Picker("Image source", selection: $showingScan) {
                    Text("Artwork").tag(false)
                    Text("Scan").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Button(action: openImage) {
                image.frame(maxWidth: .infinity).frame(height: 340)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showingScan && scan != nil ? "Captured card scan" : "Card artwork")
            .accessibilityHint("Opens the image viewer.")
        }
    }

    @ViewBuilder
    private var image: some View {
        if showingScan, let scan {
            Image(uiImage: scan).resizable().scaledToFit()
        } else if let imageURL {
            CachedAsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .failure: CardImagePlaceholder()
                default: ProgressView()
                }
            }
        } else {
            CardImagePlaceholder()
        }
    }
}
