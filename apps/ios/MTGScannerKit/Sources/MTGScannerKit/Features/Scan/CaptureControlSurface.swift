import SwiftUI

extension View {
    /// Camera controls keep the same contrast over both bright and dark scenes.
    nonisolated func captureControlSurface(in shape: some InsettableShape) -> some View {
        background(.black.opacity(0.5), in: shape)
            .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
    }
}
