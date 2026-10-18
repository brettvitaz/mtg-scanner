import SwiftUI

struct CaptureButton: View {
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(isDisabled ? Color.white.opacity(0.4) : Color.white)
                    .frame(width: 64, height: 64)
            }
            .background(.ultraThinMaterial, in: Circle())
            .environment(\.colorScheme, .dark)
        }
        .disabled(isDisabled)
        .buttonStyle(CaptureButtonStyle())
        .accessibilityLabel("Capture card")
        .accessibilityHint("Takes a photo and sends it for recognition.")
    }
}

private struct CaptureButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1.0)
            .animation(animation, value: configuration.isPressed)
    }

    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6)
    }
}
