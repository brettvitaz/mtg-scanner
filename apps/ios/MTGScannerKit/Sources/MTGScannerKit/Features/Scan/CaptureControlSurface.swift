import SwiftUI

extension View {
    /// Local system material keeps camera imagery visible between independent controls.
    nonisolated func captureControlSurface(in shape: some InsettableShape) -> some View {
        background(.ultraThinMaterial, in: shape)
            .environment(\.colorScheme, .dark)
    }
}
