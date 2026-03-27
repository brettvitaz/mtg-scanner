import SwiftUI
import UIKit

struct CardDetectionView: View {
    @StateObject private var viewModel = CardDetectionViewModel()

    var body: some View {
        ZStack {
            cameraPreview
                .ignoresSafeArea()
            VStack {
                Spacer()
                controlBar
            }
        }
        .onAppear {
            viewModel.requestCameraPermissionIfNeeded()
            lockOrientation(.portrait)
        }
        .onDisappear {
            lockOrientation([.portrait, .landscapeLeft, .landscapeRight])
        }
        .alert("Camera Access Required", isPresented: $viewModel.cameraPermissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable camera access in Settings to use real-time card detection.")
        }
    }

    // MARK: - Subviews

    private var cameraPreview: some View {
        CameraPreviewRepresentable(
            detectionMode: $viewModel.detectionMode,
            onDetectedCardsChanged: { cards in
                viewModel.handleDetectedCards(cards)
            }
        )
    }

    private var controlBar: some View {
        HStack {
            cardCountBadge
            Spacer()
            modeToggle
        }
        .padding()
    }

    private var cardCountBadge: some View {
        Text("\(viewModel.detectedCardCount) card\(viewModel.detectedCardCount == 1 ? "" : "s")")
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private var modeToggle: some View {
        Picker("Mode", selection: $viewModel.detectionMode) {
            Text("Table").tag(DetectionMode.table)
            Text("Binder").tag(DetectionMode.binder)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Orientation

    private func lockOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(prefs)
    }
}
