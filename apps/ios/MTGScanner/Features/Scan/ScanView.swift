import AudioToolbox
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ScanView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var detectionViewModel = CardDetectionViewModel()
    @StateObject private var captureCoordinator = CameraCaptureCoordinator()

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var shutterFlash = false

    var body: some View {
        ZStack {
            cameraPreview
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if shutterFlash {
                Color.white.opacity(0.7)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if appModel.isRecognizing {
                loadingOverlay
            }
        }
        .onAppear {
            detectionViewModel.requestCameraPermissionIfNeeded()
            lockOrientation(.portrait)
        }
        .onDisappear {
            lockOrientation([.portrait, .landscapeLeft, .landscapeRight])
        }
        .alert("Camera Access Required", isPresented: $detectionViewModel.cameraPermissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable camera access in Settings to use real-time card detection.")
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task { await loadPhoto(from: newValue) }
        }
    }

    // MARK: - Subviews

    private var cameraPreview: some View {
        CameraPreviewRepresentable(
            detectionMode: $detectionViewModel.detectionMode,
            onDetectedCardsChanged: { cards in
                detectionViewModel.handleDetectedCards(cards)
            },
            captureCoordinator: captureCoordinator
        )
    }

    private var topBar: some View {
        HStack {
            cardCountBadge
            Spacer()
            statusBadge
        }
    }

    private var cardCountBadge: some View {
        Text("\(detectionViewModel.detectedCardCount) card\(detectionViewModel.detectedCardCount == 1 ? "" : "s")")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private var statusBadge: some View {
        Text(appModel.statusMessage)
            .font(.caption)
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .frame(maxWidth: 180)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            photoPickerButton
            Spacer()
            CaptureButton(action: captureCard, isDisabled: appModel.isRecognizing)
            Spacer()
            modeToggle
        }
        .padding(.bottom, 8)
    }

    private var photoPickerButton: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .disabled(appModel.isRecognizing)
    }

    private var modeToggle: some View {
        Picker("Mode", selection: $detectionViewModel.detectionMode) {
            Text("Table").tag(DetectionMode.table)
            Text("Binder").tag(DetectionMode.binder)
        }
        .pickerStyle(.segmented)
        .frame(width: 130)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
                Text(appModel.statusMessage)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Actions

    private func captureCard() {
        triggerShutterFeedback()
        Task {
            guard let image = await captureCoordinator.capturePhoto() else { return }
            await handleCapturedImage(image)
        }
    }

    private func triggerShutterFeedback() {
        AudioServicesPlaySystemSound(1108)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        withAnimation(.easeIn(duration: 0.18).delay(0.08)) { shutterFlash = false }
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                appModel.statusMessage = "Could not read the selected image."
                return
            }
            guard UIImage(data: data) != nil else {
                appModel.statusMessage = "The selected file is not a supported image."
                return
            }
            let filename = item.itemIdentifier.map { "photo-\($0).jpg" } ?? "selected-image.jpg"
            let contentType = UTType.jpeg.preferredMIMEType ?? "image/jpeg"
            await appModel.recognizeImage(data: data, filename: filename, contentType: contentType)
        } catch {
            appModel.statusMessage = "Failed to load the selected photo: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func handleCapturedImage(_ image: UIImage) async {
        let filename = "camera-capture-\(UUID().uuidString.prefix(8)).jpg"
        await appModel.recognizeImage(image: image, filename: filename)
    }

    // MARK: - Orientation

    private func lockOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(prefs)
    }
}
