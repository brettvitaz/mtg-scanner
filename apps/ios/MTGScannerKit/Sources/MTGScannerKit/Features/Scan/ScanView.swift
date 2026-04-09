import AudioToolbox
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ScanView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Binding var detectionMode: DetectionMode
    let isActive: Bool
    @State private var detectionViewModel = CardDetectionViewModel()
    @State private var captureCoordinator = CameraCaptureCoordinator()
    @State private var autoScanViewModel = AutoScanViewModel()

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var shutterFlash = false
    @State private var photoLoadError: String?

    var body: some View {
        ZStack {
            cameraPreview
                .ignoresSafeArea()

            cameraOverlay

            if shutterFlash {
                Color.white.opacity(0.7)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            detectionViewModel.requestCameraPermissionIfNeeded()
            lockOrientation([.portrait, .landscapeLeft, .landscapeRight])
            configureAutoScan()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            lockOrientation([.portrait, .landscapeLeft, .landscapeRight])
            UIApplication.shared.isIdleTimerDisabled = false
            storeAndTurnOffTorch()
            autoScanViewModel.stop()
        }
        .onChange(of: appModel.apiBaseURL) { _, url in
            autoScanViewModel.apiBaseURL = url
        }
        .onChange(of: appModel.modelContext) { _, ctx in
            autoScanViewModel.modelContext = ctx
        }
        .onChange(of: appModel.autoScanCaptureDelay) { _, delay in
            autoScanViewModel.captureDelay = delay
        }
        .onChange(of: appModel.autoScanConfidenceThreshold) { _, conf in
            autoScanViewModel.presenceTracker.confidenceThreshold = Float(conf)
        }
        .onChange(of: appModel.maxConcurrentUploads) { _, count in
            autoScanViewModel.recognitionQueue.maxConcurrent = count
        }
        .onChange(of: detectionMode) { _, mode in
            if mode != .auto {
                autoScanViewModel.stop()
            }
        }
        .onChange(of: isActive) { _, active in
            handleScanActivityChange(active)
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        .alert("Camera Access Required", isPresented: $detectionViewModel.cameraPermissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable camera access in Settings to use real-time card detection.")
        }
        .alert("Photo Load Error", isPresented: Binding(
            get: { photoLoadError != nil },
            set: { if !$0 { photoLoadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoLoadError ?? "")
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task { await loadPhoto(from: newValue) }
        }
    }

    // MARK: - Setup

    private func configureAutoScan() {
        autoScanViewModel.captureCoordinator = captureCoordinator
        autoScanViewModel.modelContext = appModel.modelContext
        autoScanViewModel.apiBaseURL = appModel.apiBaseURL
        autoScanViewModel.captureDelay = appModel.autoScanCaptureDelay
        autoScanViewModel.presenceTracker.confidenceThreshold = Float(appModel.autoScanConfidenceThreshold)
        autoScanViewModel.recognitionQueue.maxConcurrent = appModel.maxConcurrentUploads
    }

    private var isAutoScanMode: Bool {
        detectionMode == .auto
    }

    // MARK: - Subviews

    @ViewBuilder
    private var cameraOverlay: some View {
        ZStack {
            if isAutoScanMode {
                AutoScanView(
                    viewModel: autoScanViewModel,
                    recognitionQueue: autoScanViewModel.recognitionQueue,
                    torchLevel: $detectionViewModel.torchLevel,
                    lastTorchLevel: lastTorchLevelBinding
                )
            } else {
                standardOverlay
            }

            VStack {
                IdentifiedCardToastContainer(viewModel: autoScanViewModel.identifiedCardsViewModel)
                    .padding(.top, 60)
                Spacer()
            }
        }
    }

    private var standardOverlay: some View {
        VStack {
            HStack {
                Spacer()
                RecognitionBadgeView(
                    recognitionQueue: autoScanViewModel.recognitionQueue,
                    onCancel: autoScanViewModel.cancelRecognition,
                    onRetryFailed: autoScanViewModel.recognitionQueue.retryFailed,
                    onClearFailed: autoScanViewModel.recognitionQueue.clearFailed
                )
            }
            Spacer()
            ZoomPresetControl(currentZoom: detectionViewModel.zoomFactor) { preset in
                detectionViewModel.zoomFactor = preset
            }
            .padding(.bottom, 12)
            bottomBar
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var cameraPreview: some View {
        CameraPreviewRepresentable(
            detectionMode: $detectionMode,
            zoomFactor: detectionViewModel.zoomFactor,
            onDetectedCardsChanged: { cards in
                detectionViewModel.handleDetectedCards(cards)
            },
            captureCoordinator: captureCoordinator,
            onZoomFactorChanged: { factor in
                detectionViewModel.zoomFactor = factor
            },
            onAutoScanFrame: isAutoScanMode
                ? { [weak autoScanViewModel] buffer in
                    Task { @MainActor in
                        autoScanViewModel?.processFrame(buffer)
                    }
                }
                : nil,
            torchLevel: detectionViewModel.torchLevel
        )
        .accessibilityHidden(true)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            photoPickerButton
            Spacer()
            CaptureButton(action: captureCard, isDisabled: false)
            Spacer()
            FlashlightButton(
                torchLevel: $detectionViewModel.torchLevel,
                lastTorchLevel: lastTorchLevelBinding
            )
        }
        .padding(.bottom, 8)
    }

    private var lastTorchLevelBinding: Binding<Float> {
        Binding(
            get: { appModel.lastTorchLevel },
            set: { appModel.lastTorchLevel = $0 }
        )
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
        .accessibilityLabel("Choose photo")
        .accessibilityHint("Selects an existing image for card recognition.")
    }

    // MARK: - Actions

    private func captureCard() {
        triggerShutterFeedback()
        Task {
            guard let payload = await captureCoordinator.capturePhoto() else { return }
            await enqueueForRecognition(payload)
        }
    }
}

// MARK: - Helpers

private extension ScanView {

    func triggerShutterFeedback() {
        AudioServicesPlaySystemSound(1306)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        withAnimation(.easeIn(duration: 0.18).delay(0.08)) { shutterFlash = false }
    }

    @MainActor
    func loadPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoLoadError = "Could not read the selected image."
                return
            }
            guard let uiImage = UIImage(data: data) else {
                photoLoadError = "The selected file is not a supported image."
                return
            }
            guard let payload = RecognitionImagePayload.importedPhoto(
                data: data,
                image: uiImage,
                supportedContentTypes: item.supportedContentTypes
            ) else {
                photoLoadError = "Failed to prepare the selected image for upload."
                return
            }
            await enqueueForRecognition(payload)
        } catch {
            photoLoadError = "Failed to load the selected photo: \(error.localizedDescription)"
        }
    }

    @MainActor
    func enqueueForRecognition(_ payload: RecognitionImagePayload) async {
        await autoScanViewModel.enqueueCapturedImage(payload, cropEnabled: appModel.onDeviceCropEnabled)
    }

    func lockOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(prefs)
    }

    private func storeAndTurnOffTorch() {
        if detectionViewModel.torchLevel > 0 {
            appModel.lastTorchLevel = detectionViewModel.torchLevel
        }
        detectionViewModel.torchLevel = 0
    }

    private func handleScanActivityChange(_ active: Bool) {
        if !active {
            storeAndTurnOffTorch()
            autoScanViewModel.stop()
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .background else { return }
        storeAndTurnOffTorch()
    }
}
