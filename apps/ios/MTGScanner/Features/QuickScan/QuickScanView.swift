import SwiftUI

/// Overlay controls displayed over the camera preview during Quick Scan mode.
///
/// The camera preview and detection overlay (YOLO bounding boxes) are rendered by
/// the underlying `CameraPreviewRepresentable` in `ScanView`. This view adds the
/// Quick Scan-specific controls: running counts, status strip, and Start/Stop button.
struct QuickScanView: View {
    @ObservedObject var viewModel: QuickScanViewModel
    @ObservedObject var recognitionQueue: RecognitionQueue
    @Binding var torchLevel: Float
    @Binding var detectionMode: DetectionMode
    let availableModes: [DetectionMode]

    var body: some View {
        VStack {
            topBar
            Spacer()
            statusStrip
            bottomBar
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack(alignment: .top) {
            scannedCountBadge
            TorchControl(level: $torchLevel)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                modeToggle
                if recognitionQueue.pendingCount > 0 {
                    pendingBadge
                }
                if recognitionQueue.failedCount > 0 {
                    failedBadge
                }
            }
        }
    }

    private var scannedCountBadge: some View {
        Text("\(recognitionQueue.completedCount) scanned")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private var pendingBadge: some View {
        HStack(spacing: 6) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(0.75)
            Text("\(recognitionQueue.pendingCount) recognizing")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var modeToggle: some View {
        Picker("Mode", selection: $detectionMode) {
            ForEach(availableModes) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var failedBadge: some View {
        Text("\(recognitionQueue.failedCount) failed")
            .font(.caption.bold())
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            stateIndicator
            Text(viewModel.statusMessage)
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var stateIndicator: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 8, height: 8)
    }

    private var stateColor: Color {
        guard viewModel.isActive else { return .gray }
        switch viewModel.captureState {
        case .watching:  return .green
        case .settling:  return .yellow
        case .capturing: return .white
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            startStopButton
            Spacer()
        }
        .padding(.bottom, 8)
    }

    private var startStopButton: some View {
        Button(action: viewModel.isActive ? viewModel.stop : viewModel.start) {
            Text(viewModel.isActive ? "Stop" : "Start")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(width: 120, height: 54)
                .background(viewModel.isActive ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                .clipShape(Capsule())
        }
    }
}
