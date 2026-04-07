import SwiftUI

struct FullscreenImageView: View {
    let imageUrl: URL?
    let uiImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let imageUrl {
                CachedAsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .failure:
                        imagePlaceholder
                    default:
                        ProgressView().tint(.white)
                    }
                }
            } else {
                imagePlaceholder
            }
        }
        .onTapGesture { dismiss() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Full screen card image")
        .accessibilityHint("Double tap to dismiss.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { dismiss() }
        .statusBarHidden()
    }

    private var imagePlaceholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 60))
            .foregroundStyle(.white.opacity(0.5))
            .accessibilityLabel("No image available")
    }
}
