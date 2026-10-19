import SwiftUI
import UIKit

struct FlashlightButton: View {
    @Binding var torchLevel: Float
    @Binding var lastTorchLevel: Float
    @State private var showBrightnessPopover = false
    var opensBrightness = false

    private var torchIsOn: Bool { torchLevel > 0 }

    var body: some View {
        Image(systemName: torchIsOn ? "flashlight.on.fill" : "flashlight.off.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(torchIsOn ? .yellow : .white)
            .frame(width: 44, height: 44)
            .captureControlSurface(in: Circle())
            .contentShape(Circle())
            .gesture(
                ExclusiveGesture(
                    LongPressGesture(minimumDuration: 0.5),
                    TapGesture()
                )
                .onEnded { value in
                    switch value {
                    case .first:
                        ensureTorchOn()
                        showBrightnessPopover = true
                    case .second:
                        toggleTorch()
                    }
                }
            )
            .task { if opensBrightness { ensureTorchOn(); showBrightnessPopover = true } }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleTorch() }
            .accessibilityAction(named: "Adjust brightness") {
                ensureTorchOn()
                showBrightnessPopover = true
            }
            .accessibilityIdentifier("capture-torch")
            .accessibilityLabel("Flashlight")
            .accessibilityHint("Double tap to toggle. Long press to adjust brightness.")
            .accessibilityValue(accessibilityValue)
            .popover(isPresented: $showBrightnessPopover) {
                BrightnessPopover(torchLevel: $torchLevel, lastTorchLevel: $lastTorchLevel)
            }
    }

    private var accessibilityValue: String {
        guard torchIsOn else { return "Off" }
        return "On at \(Int(torchLevel * 100 + 0.5)) percent"
    }

    private func toggleTorch() {
        let state = TorchState(level: torchLevel, remembered: lastTorchLevel)
        state.toggle()
        torchLevel = state.level
        lastTorchLevel = state.remembered
    }

    private func ensureTorchOn() {
        let state = TorchState(level: torchLevel, remembered: lastTorchLevel)
        state.openBrightness()
        torchLevel = state.level
        lastTorchLevel = state.remembered
    }
}

struct BrightnessPopover: View {
    @Binding var torchLevel: Float
    @Binding var lastTorchLevel: Float
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 4) {
            header
            if dynamicTypeSize.isAccessibilitySize { percentage }
            BrightnessBar(level: $torchLevel, remembered: $lastTorchLevel)
                .frame(height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(width: sizeClass == .regular && dynamicTypeSize.isAccessibilitySize ? 420 : 300)
        .presentationCompactAdaptation(.popover)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Brightness").font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
            Spacer()
            if !dynamicTypeSize.isAccessibilitySize { percentage }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var percentage: some View {
        Text("\(Int((torchLevel * 100).rounded()))%")
            .font(.headline.monospacedDigit())
            .fixedSize()
            .accessibilityIdentifier("torch-brightness-percentage")
            .accessibilityHidden(true)
    }
}

private struct BrightnessBar: UIViewRepresentable {
    @Binding var level: Float
    @Binding var remembered: Float

    func makeUIView(context: Context) -> BrightnessBarControl { BrightnessBarControl() }

    func updateUIView(_ view: BrightnessBarControl, context: Context) {
        view.level = level
        view.onChange = { value in level = value; remembered = value }
    }
}
