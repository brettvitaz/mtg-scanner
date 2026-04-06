import SwiftUI

/// Overlay controls displayed over the camera preview during Auto Scan mode.
///
/// The camera preview and detection overlay (YOLO bounding boxes) are rendered by
/// the underlying `CameraPreviewRepresentable` in `ScanView`. This view adds the
/// Auto Scan-specific controls: running counts, status strip, and Start/Stop button.
struct AutoScanView: View {
    @Bindable var viewModel: AutoScanViewModel
    @Bindable var recognitionQueue: RecognitionQueue
    @Binding var torchLevel: Float
    @Binding var lastTorchLevel: Float

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
            cropPreview
            Spacer()
            RecognitionBadgeView(recognitionQueue: recognitionQueue, onCancel: viewModel.cancelRecognition)
        }
    }

    @ViewBuilder
    private var cropPreview: some View {
        if let image = viewModel.lastCroppedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.6), lineWidth: 1))
                .shadow(radius: 4)
        }
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
        HStack(alignment: .center) {
            Color.clear.frame(width: 54, height: 54)
            Spacer()
            startStopButton
            Spacer()
            FlashlightButton(torchLevel: $torchLevel, lastTorchLevel: $lastTorchLevel)
        }
        .padding(.bottom, 8)
    }

    private var startStopButton: some View {
        Button {
            if viewModel.isActive { viewModel.stop() } else { viewModel.start() }
        } label: {
            Text(viewModel.isActive ? "Stop" : "Start")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(width: 120, height: 54)
                .background(viewModel.isActive ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                .clipShape(Capsule())
        }
    }
}
