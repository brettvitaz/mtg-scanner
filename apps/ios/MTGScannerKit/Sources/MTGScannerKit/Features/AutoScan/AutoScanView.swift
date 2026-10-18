import SwiftUI

/// Compact Station feedback within the shared capture controls.
struct AutoScanView: View {
    let viewModel: AutoScanViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label(viewModel.stationStatus.rawValue, systemImage: viewModel.stationStatus.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Station status")
            .accessibilityValue(viewModel.stationStatus.rawValue)
            .accessibilityIdentifier("station-status")
            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : viewModel.completionSequence)
    }
}

struct StationCaptureFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            Text(message).font(.caption).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel("Capture failed. \(message) Retry capture")
    }
}

struct StationStartStopButton: View {
    let viewModel: AutoScanViewModel

    var body: some View {
        Button {
            if viewModel.isActive { viewModel.stop() } else { viewModel.start() }
        } label: {
            Text(viewModel.isActive ? "Stop" : "Start")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minWidth: 64, minHeight: 48)
                .captureControlSurface(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isActive ? "Stop Station" : "Start Station")
        .accessibilityHint("Controls automatic card capture.")
        .accessibilityIdentifier("station-start-stop")
    }
}
