import SwiftUI

struct FullscreenImageView: View {
    let imageUrl: URL?
    let uiImage: UIImage?
    var initialZoom: CGFloat = 1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let uiImage {
                ZoomableScanImage(image: uiImage, initialZoom: initialZoom)
                    .ignoresSafeArea()
            } else if let imageUrl {
                CachedAsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .failure: imagePlaceholder
                    default: ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                imagePlaceholder.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)
                .background(.black.opacity(0.85), in: Capsule())
                .padding()
        }
        .statusBarHidden()
    }

    private var imagePlaceholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 60))
            .foregroundStyle(.white.opacity(0.5))
            .accessibilityLabel("No image available")
    }
}
