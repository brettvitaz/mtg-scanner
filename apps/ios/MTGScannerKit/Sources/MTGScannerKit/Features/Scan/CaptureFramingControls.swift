import SwiftUI

/// Shared framing rail owns compact-width and accessibility placement in both modes.
struct CaptureFramingControls: View {
    let currentZoom: CGFloat
    let isEnabled: Bool
    @Binding var torchLevel: Float
    @Binding var lastTorchLevel: Float
    var opensBrightness = false
    let onSelect: (CGFloat) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            let liftTorch = geometry.size.width < 360 || dynamicTypeSize.isAccessibilitySize
            ZStack(alignment: .top) {
                ZoomPresetControl(currentZoom: currentZoom) { preset in
                    onSelect(preset)
                }
                .disabled(!isEnabled)
                .padding(.top, 52)
                HStack {
                    Spacer()
                    FlashlightButton(torchLevel: $torchLevel,
                                     lastTorchLevel: $lastTorchLevel, opensBrightness: opensBrightness)
                }
                .padding(.top, liftTorch ? 0 : 56)
            }
        }
        .frame(height: framingHeight)
    }

    @ScaledMetric(relativeTo: .title3) private var zoomDiameter = 56.0

    @ScaledMetric(relativeTo: .subheadline) private var zoomInactiveFont = 17.0

    private var framingHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return zoomDiameter + max(44, zoomInactiveFont * 1.2 + 8) + 60 }
        // Compact devices reserve a separate torch row without moving the active zoom axis.
        return zoomDiameter + 52
    }

}
