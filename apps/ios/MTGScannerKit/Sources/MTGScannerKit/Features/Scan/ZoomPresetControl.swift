import SwiftUI

/// A horizontal row of preset zoom level buttons styled as pill-shaped controls.
///
/// The active preset (nearest to `currentZoom` within ±0.12) is highlighted
/// with a white fill and dark text. Tapping a button calls `onSelect` with the
/// preset value.
struct ZoomPresetControl: View {

    static let presets: [CGFloat] = [1, 2, 3, 5]

    let currentZoom: CGFloat
    let onSelect: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.presets, id: \.self) { preset in
                presetButton(for: preset)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func presetButton(for preset: CGFloat) -> some View {
        let active = isActive(preset)
        return Button { onSelect(preset) } label: {
            Text("\(Int(preset))×")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? Color.black : Color.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(active ? Color.white : Color.clear, in: Capsule())
                .scaleEffect(active ? 1.1 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.65), value: active)
        }
        .buttonStyle(.plain)
    }

    static func isActive(_ preset: CGFloat, currentZoom: CGFloat) -> Bool {
        abs(currentZoom - preset) < 0.12
    }

    private func isActive(_ preset: CGFloat) -> Bool {
        Self.isActive(preset, currentZoom: currentZoom)
    }
}
