import SwiftUI

/// A compact torch toggle + brightness slider for the camera view.
///
/// - Tap the flashlight icon to toggle the torch on/off.
/// - When on, a brightness slider expands inline to the right.
/// - The slider range is 0.1 (dim) – 1.0 (full) to avoid accidentally
///   setting the hardware level to zero through the slider.
struct TorchControl: View {
    @Binding var level: Float

    @State private var lastActiveLevel: Float = 0.5

    private var isOn: Bool { level > 0 }

    var body: some View {
        HStack(spacing: 8) {
            toggleButton
            if isOn {
                brightnessSlider
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isOn)
    }

    private var toggleButton: some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 20))
                .foregroundStyle(isOn ? .yellow : .white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }

    private var brightnessSlider: some View {
        Slider(
            value: Binding(
                get: { level },
                set: { newValue in
                    level = newValue
                    lastActiveLevel = newValue
                }
            ),
            in: 0.1...1.0
        )
        .frame(width: 110)
        .tint(.yellow)
    }

    private func toggle() {
        level = isOn ? 0 : lastActiveLevel
    }
}
