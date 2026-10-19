import SwiftUI

/// Framing controls share the torch's scale and keep a clear shutter axis.
struct CaptureFramingControls: View {
    let currentZoom: CGFloat
    let isEnabled: Bool
    @Binding var torchLevel: Float
    @Binding var lastTorchLevel: Float
    var opensBrightness = false
    let onSelect: (CGFloat) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var labelLineHeight = 20.0
    @State private var compactWidth = false

    private var liftTorch: Bool { compactWidth || dynamicTypeSize.isAccessibilitySize }
    private var rowHeight: CGFloat { max(44, labelLineHeight + 12) }
    private var railHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? rowHeight * 2 + 8 : rowHeight }

    var body: some View {
        ZStack(alignment: .top) {
            ZoomPresetControl(currentZoom: currentZoom, rowHeight: rowHeight, onSelect: onSelect)
                .disabled(!isEnabled)
                .padding(.top, liftTorch ? 52 : 0)
            HStack {
                Spacer()
                FlashlightButton(torchLevel: $torchLevel,
                                 lastTorchLevel: $lastTorchLevel, opensBrightness: opensBrightness)
            }
        }
        .frame(height: railHeight + (liftTorch ? 52 : 0))
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { compactWidth = geometry.size.width < 360 }
                    .onChange(of: geometry.size.width) { _, width in compactWidth = width < 360 }
            }
        }
    }
}
