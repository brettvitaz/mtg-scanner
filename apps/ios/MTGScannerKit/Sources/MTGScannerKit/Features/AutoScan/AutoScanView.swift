import SwiftUI

/// Compact Station feedback within the shared capture controls.
struct AutoScanView: View {
    let viewModel: AutoScanViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Label(viewModel.stationStatus.rawValue, systemImage: viewModel.stationStatus.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Station status")
                .accessibilityValue(viewModel.stationStatus.rawValue)
                .accessibilityIdentifier("station-status")
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : viewModel.completionSequence)
            if let failure = viewModel.captureFailure {
                Button { viewModel.captureManually() } label: {
                    Text(failure).font(.caption).multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Capture failed. \(failure) Retry capture")
            }
        }
    }
}

struct StationStartStopButton: View {
    let viewModel: AutoScanViewModel

    var body: some View {
        Button {
            if viewModel.isActive { viewModel.stop() } else { viewModel.start() }
        } label: {
            Text(viewModel.isActive ? "Stop" : "Start")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(minWidth: 64, minHeight: 54)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel(viewModel.isActive ? "Stop Station" : "Start Station")
        .accessibilityHint("Controls automatic card capture.")
        .accessibilityIdentifier("station-start-stop")
    }
}
