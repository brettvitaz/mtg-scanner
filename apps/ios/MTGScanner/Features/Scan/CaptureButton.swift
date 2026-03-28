import SwiftUI

struct CaptureButton: View {
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                Circle()
                    .fill(isDisabled ? Color.white.opacity(0.4) : Color.white)
                    .frame(width: 60, height: 60)
            }
        }
        .disabled(isDisabled)
        .buttonStyle(CaptureButtonStyle())
    }
}

private struct CaptureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
