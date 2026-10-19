import SwiftUI

/// Inline anchors present applied pinch zoom or the selected preset destination.
struct ZoomPresetControl: View {
    let currentZoom: CGFloat
    var rowHeight: CGFloat = 44
    let onSelect: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ZStack(alignment: .top) {
            ForEach(1...3, id: \.self) { anchor in
                anchorButton(anchor)
                    .offset(x: horizontalOffset(anchor), y: verticalOffset(anchor))
            }
        }
        .frame(width: typeSize.isAccessibilitySize ? 240 : 264,
               height: typeSize.isAccessibilitySize ? rowHeight * 2 + 8 : rowHeight,
               alignment: .top)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: Self.family(currentZoom))
    }

    private func anchorButton(_ anchor: Int) -> some View {
        let active = anchor == Self.family(currentZoom)
        let next = Self.destination(anchor: anchor, current: currentZoom)
        return Button { onSelect(next) } label: {
            Text(active ? Self.label(currentZoom) : Self.label(CGFloat(anchor)))
                .font(.subheadline.weight(active ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(active ? Color.yellow : Color.white)
                // A crisp outline preserves unbacked numerals over bright live imagery.
                .shadow(color: .black, radius: 0, x: 1)
                .shadow(color: .black, radius: 0, x: -1)
                .shadow(color: .black, radius: 0, y: 1)
                .shadow(color: .black, radius: 0, y: -1)
                .fixedSize()
                .padding(.horizontal, 4)
                .frame(minWidth: 44, minHeight: rowHeight)
                .contentShape(Rectangle())
                .background {
                    if active { Color.clear.captureControlSurface(in: Capsule()) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture-zoom-\(anchor)")
        .accessibilityLabel("\(anchor)× zoom family")
        .accessibilityValue(active ? Self.label(currentZoom) : Self.label(CGFloat(anchor)))
        .accessibilityHint("Select \(Self.label(next))")
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityAction(named: "Select \(anchor)×") { onSelect(CGFloat(anchor)) }
        .accessibilityAction(named: "Select \(anchor).5×") { onSelect(CGFloat(anchor) + 0.5) }
        .accessibilityAdjustableAction { direction in
            onSelect(currentZoom + (direction == .increment ? 0.1 : -0.1))
        }
    }

    private func horizontalOffset(_ anchor: Int) -> CGFloat {
        let active = Self.family(currentZoom)
        guard typeSize.isAccessibilitySize else { return CGFloat(anchor - active) * 52 }
        guard anchor != active else { return 0 }
        return anchor == (1...3).first(where: { $0 != active }) ? -60 : 60
    }

    private func verticalOffset(_ anchor: Int) -> CGFloat {
        typeSize.isAccessibilitySize && anchor != Self.family(currentZoom) ? rowHeight + 8 : 0
    }

    static func family(_ applied: CGFloat) -> Int { applied < 2 ? 1 : (applied < 3 ? 2 : 3) }

    static func destination(anchor: Int, current: CGFloat) -> CGFloat {
        let base = CGFloat(anchor)
        return family(current) == anchor && current == base ? base + 0.5 : base
    }

    static func label(_ value: CGFloat) -> String {
        let family = Self.family(value)
        let roundedValue = (value * 10).rounded() / 10
        let rounded = family < 3 ? min(roundedValue, CGFloat(family) + 0.9) : roundedValue
        return rounded == rounded.rounded() ? String(format: "%.0f×", Double(rounded))
            : String(format: "%.1f×", Double(rounded))
    }
}
