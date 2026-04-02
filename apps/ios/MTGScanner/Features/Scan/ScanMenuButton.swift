import SwiftUI

struct ScanMenuButton: View {
    @Binding var detectionMode: DetectionMode
    @Binding var torchLevel: Float

    private var torchIsOn: Bool { torchLevel > 0 }

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

            if torchIsOn {
                Section("Brightness") {
                    Button { torchLevel = 0.25 } label: {
                        Label("Low", systemImage: "sun.min")
                    }
                    Button { torchLevel = 0.5 } label: {
                        Label("Medium", systemImage: "sun.max")
                    }
                    Button { torchLevel = 1.0 } label: {
                        Label("High", systemImage: "sun.max.fill")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
}
