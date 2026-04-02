import SwiftUI

struct ScanMenuButton: View {
    @Binding var detectionMode: DetectionMode
    @Binding var torchLevel: Float
    @State private var showBrightnessPopover = false

    private var torchIsOn: Bool { torchLevel > 0 }

    @ViewBuilder private var brightnessSection: some View {
        if torchIsOn {
            Section("Brightness") {
                Button { torchLevel = 0.1 } label: { Label("Very Low", systemImage: "sun.min") }
                Button { torchLevel = 0.25 } label: { Label("Low", systemImage: "sun.min") }
                Button { torchLevel = 0.5 } label: { Label("Medium", systemImage: "sun.max") }
                Button { torchLevel = 1.0 } label: { Label("High", systemImage: "sun.max.fill") }
            }
        }
    }

    var body: some View {
        Menu {
            Picker("Scan Mode", selection: $detectionMode) {
                ForEach(DetectionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button {
                torchLevel = torchIsOn ? 0 : 0.5
            } label: {
                Label(
                    torchIsOn ? "Turn Off Flashlight" : "Turn On Flashlight",
                    systemImage: torchIsOn ? "flashlight.on.fill" : "flashlight.off.fill"
                )
            }

            brightnessSection
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                if !torchIsOn { torchLevel = 0.5 }
                showBrightnessPopover = true
            }
        )
        .popover(isPresented: $showBrightnessPopover) {
            BrightnessPopover(torchLevel: $torchLevel)
        }
    }
}

private struct BrightnessPopover: View {
    @Binding var torchLevel: Float

    var body: some View {
        VStack(spacing: 16) {
            Text("Brightness")
                .font(.headline)
            HStack {
                Image(systemName: "sun.min")
                Slider(value: $torchLevel, in: 0.01...1.0)
                Image(systemName: "sun.max.fill")
            }
            Text("\(Int(torchLevel * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
    }
}
