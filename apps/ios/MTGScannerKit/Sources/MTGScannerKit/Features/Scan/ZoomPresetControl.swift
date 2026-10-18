import SwiftUI

/// Inline magnification anchors. Selection always follows the unrounded applied factor.
struct ZoomPresetControl: View {
    let currentZoom: CGFloat
    let onSelect: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var diameter = 56.0

    @ScaledMetric(relativeTo: .subheadline) private var inactiveFontSize = 17.0

    var inactiveHeight: CGFloat { max(44, inactiveFontSize * 1.2 + 8) }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(1...3, id: \.self) { anchor in
                anchorButton(anchor)
                    .offset(x: horizontalOffset(anchor), y: verticalOffset(anchor))
            }
        }
        .frame(width: typeSize.isAccessibilitySize ? 240 : 264,
               height: typeSize.isAccessibilitySize ? diameter + inactiveHeight + 8 : diameter,
               alignment: .top)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: Self.family(currentZoom))
    }

    private func anchorButton(_ anchor: Int) -> some View {
        let active = anchor == Self.family(currentZoom)
        let next = Self.destination(anchor: anchor, current: currentZoom)
        return Button { onSelect(next) } label: {
            Text(active ? Self.label(currentZoom) : Self.label(CGFloat(anchor)))
                .font(active ? .title3.weight(.semibold) : .subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(active ? Color.yellow : Color.white)
                .frame(minWidth: active ? diameter : 44,
                       minHeight: typeSize.isAccessibilitySize && !active ? inactiveHeight : diameter)
                .contentShape(Rectangle())
                .background {
                    if active {
                        Circle().fill(.ultraThinMaterial)
                            .overlay { Circle().fill(.black.opacity(0.65)) }
                            .environment(\.colorScheme, .dark)
                    }
                }
                .shadow(color: .black.opacity(0.9), radius: 1, y: 1)
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
        typeSize.isAccessibilitySize && anchor != Self.family(currentZoom) ? diameter + 8 : 0
    }

    static func family(_ applied: CGFloat) -> Int { applied < 2 ? 1 : (applied < 3 ? 2 : 3) }

    static func destination(anchor: Int, current: CGFloat) -> CGFloat {
        let base = CGFloat(anchor)
        return family(current) == anchor && current == base ? base + 0.5 : base
    }

    static func label(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(format: "%.0f×", Double(rounded))
            : String(format: "%.1f×", Double(rounded))
    }
}
