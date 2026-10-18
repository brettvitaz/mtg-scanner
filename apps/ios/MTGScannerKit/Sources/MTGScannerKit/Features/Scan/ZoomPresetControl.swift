import SwiftUI
import UIKit

/// Native menu; the label reflects the applied, device-clamped zoom.
struct ZoomPresetControl: View {
    static let presets: [CGFloat] = [1, 1.5, 2, 3]
    let currentZoom: CGFloat
    var opensMenu = false
    let onSelect: (CGFloat) -> Void

    var body: some View {
        NativeZoomMenu(currentZoom: currentZoom, opensMenu: opensMenu, onSelect: onSelect)
            .fixedSize()
            .frame(minWidth: 80, minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
    }

    static func label(_ value: CGFloat) -> String {
        value == value.rounded() ? String(format: "%.0f×", Double(value)) : String(format: "%.1f×", Double(value))
    }

}

private struct NativeZoomMenu: UIViewRepresentable {
    let currentZoom: CGFloat
    let opensMenu: Bool
    let onSelect: (CGFloat) -> Void

    func makeUIView(context: Context) -> ZoomMenuButton { ZoomMenuButton(type: .system) }

    func updateUIView(_ button: ZoomMenuButton, context: Context) {
        var config = UIButton.Configuration.plain()
        config.title = ZoomPresetControl.label(currentZoom)
        config.image = UIImage(systemName: "chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.baseForegroundColor = .white
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .subheadline)
            return attributes
        }
        button.configuration = config
        button.accessibilityLabel = "Zoom"
        button.accessibilityValue = ZoomPresetControl.label(currentZoom)
        button.accessibilityIdentifier = "capture-zoom"
        button.menu = UIMenu(children: ZoomPresetControl.presets.map { preset in
            UIAction(title: ZoomPresetControl.label(preset)) { _ in onSelect(preset) }
        })
        button.showsMenuAsPrimaryAction = true
        button.opensMenu = opensMenu
    }
}

private final class ZoomMenuButton: UIButton {
    var opensMenu = false
    private var hasOpened = false

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width, height: max(44, size.height))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, opensMenu, !hasOpened else { return }
        hasOpened = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.performPrimaryAction() }
    }
}
