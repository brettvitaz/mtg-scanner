import SwiftUI
import UIKit

struct FlashlightButton: View {
    @Binding var torchLevel: Float
    @Binding var lastTorchLevel: Float
    @State private var showBrightnessPopover = false

    private var torchIsOn: Bool { torchLevel > 0 }

    var body: some View {
        Image(systemName: torchIsOn ? "flashlight.on.fill" : "flashlight.off.fill")
            .font(.system(size: 24))
            .foregroundStyle(torchIsOn ? .yellow : .white)
            .frame(width: 54, height: 54)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
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
            .popover(isPresented: $showBrightnessPopover) {
                BrightnessPopover(torchLevel: $torchLevel, lastTorchLevel: $lastTorchLevel)
            }
            .accessibilityLabel("Flashlight")
            .accessibilityHint("Double tap to toggle. Long press to adjust brightness.")
            .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard torchIsOn else { return "Off" }
        return "On at \(Int(torchLevel * 100 + 0.5)) percent"
    }

    private func toggleTorch() {
        if torchIsOn {
            lastTorchLevel = clampedLevel(torchLevel)
            torchLevel = 0
        } else {
            torchLevel = restoreLevel
            lastTorchLevel = torchLevel
        }
    }

    private func ensureTorchOn() {
        if !torchIsOn {
            torchLevel = restoreLevel
        }
        lastTorchLevel = torchLevel
    }

    private var restoreLevel: Float {
        clampedLevel(lastTorchLevel > 0 ? lastTorchLevel : 0.5)
    }
}

private struct BrightnessPopover: View {
    @Binding var torchLevel: Float
    @Binding var lastTorchLevel: Float
    @Environment(\.dismiss) private var dismiss
    @State private var snappedAnchor: Float?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Brightness")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
            HStack {
                Button {
                    setLevel(torchLevel - 0.05)
                } label: {
                    Image(systemName: "sun.min")
                }
                .accessibilityLabel("Decrease brightness")
                Slider(value: sliderValue, in: 0.01...1.0)
                    .accessibilityLabel("Flashlight brightness")
                    .accessibilityValue("\(Int(torchLevel * 100 + 0.5)) percent")
                Button {
                    setLevel(torchLevel + 0.05)
                } label: {
                    Image(systemName: "sun.max.fill")
                }
                .accessibilityLabel("Increase brightness")
            }
            Text("\(Int(torchLevel * 100 + 0.5))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
    }

    private var sliderValue: Binding<Float> {
        Binding(
            get: { torchLevel > 0 ? torchLevel : 0.5 },
            set: { setLevel($0) }
        )
    }

    private func setLevel(_ value: Float) {
        let snapped = snapLevel(clampedLevel(value))
        if snapped.anchor != snappedAnchor {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            snappedAnchor = snapped.anchor
        }
        torchLevel = snapped.level
        lastTorchLevel = snapped.level
    }
}

private func clampedLevel(_ level: Float) -> Float {
    min(1.0, max(0.01, level))
}

private func snapLevel(_ level: Float) -> (level: Float, anchor: Float?) {
    let anchors: [Float] = [0.01, 0.10, 0.25, 0.50, 0.75, 1.0]
    let threshold: Float = 0.03
    guard let anchor = anchors.min(by: { abs($0 - level) < abs($1 - level) }),
          abs(anchor - level) <= threshold else {
        return (level, nil)
    }
    return (anchor, anchor)
}
