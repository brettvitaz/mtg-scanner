import SwiftUI

/// Compact Station feedback within the shared capture controls.
struct AutoScanView: View {
    let viewModel: AutoScanViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label(viewModel.stationStatus.rawValue, systemImage: viewModel.stationStatus.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
            .captureControlSurface(in: Capsule())
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                .captureControlSurface(in: RoundedRectangle(cornerRadius: 16))
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
            Image(systemName: viewModel.isActive ? "stop.fill" : "play.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .captureControlSurface(in: Circle())
        }
        .disabled(!viewModel.isActive && viewModel.isZoomMoving)
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isActive ? "Stop Station" : "Start Station")
        .accessibilityHint("Controls automatic card capture.")
        .accessibilityIdentifier("station-start-stop")
    }
}
