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
    let cameraSession: CameraSessionManager
    @State private var detectionViewModel: CardDetectionViewModel
    @State private var captureCoordinator = CameraCaptureCoordinator()
    @State private var autoScanViewModel: AutoScanViewModel

    private let previewContent: ((CameraPreviewRepresentable) -> AnyView)?
    private let opensBrightness: Bool
    private let onConfigured: (() -> Void)?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var shutterFlash = false
    @State private var photoLoadError: String?
    @State private var captureError: String?
    @State private var needsZoomRestore = true
    @State private var savedZoom: CGFloat = 1
    @ScaledMetric(relativeTo: .caption) private var feedbackHeight = 20.0

    init(
        detectionMode: Binding<DetectionMode>, isActive: Bool,
        autoScanViewModel: AutoScanViewModel = AutoScanViewModel(),
        detectionViewModel: CardDetectionViewModel = CardDetectionViewModel(),
        captureCoordinator: CameraCaptureCoordinator = CameraCaptureCoordinator(),
        previewContent: ((CameraPreviewRepresentable) -> AnyView)? = nil,
        opensBrightness: Bool = false,
        onConfigured: (() -> Void)? = nil,
        cameraSession: CameraSessionManager = CameraSessionManager()
    ) {
        _detectionMode = detectionMode
        self.isActive = isActive
        self.cameraSession = cameraSession
        self.previewContent = previewContent
        self.onConfigured = onConfigured
        self.opensBrightness = opensBrightness
        _captureCoordinator = State(initialValue: captureCoordinator)
        _autoScanViewModel = State(initialValue: autoScanViewModel)
        _detectionViewModel = State(initialValue: detectionViewModel)
    }

    var body: some View {
        captureContent
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onAppear(perform: onAppearHandler)
        .onDisappear(perform: onDisappearHandler)
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
#if DEBUG
        .onChange(of: appModel.debugSaveRawCapturesToPhotoLibrary) { _, isEnabled in
            autoScanViewModel.debugSaveRawCapturesToPhotoLibrary = isEnabled
        }
#endif
        .onChange(of: cameraPreviewID) { _, _ in
            captureCoordinator.cancelZoom()
            autoScanViewModel.pauseForNavigation()
            needsZoomRestore = true
        }
        .onChange(of: autoScanViewModel.canChangeZoom) { _, available in
            if available && isActive { synchronizeCameraZoom() }
        }
        .onChange(of: captureCoordinator.controller != nil) { _, connected in
            if connected && isActive { synchronizeCameraZoom() }
        }
        .onChange(of: appModel.showRecognitionNotifications) { _, enabled in
            autoScanViewModel.updateNotificationPreference(enabled)
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
        .alert("Capture Failed", isPresented: Binding(
            get: { captureError != nil }, set: { if !$0 { captureError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(captureError ?? "")
        }
        .alert("Photo Load Error", isPresented: photoLoadErrorBinding) {
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

    private var captureContent: some View {
        ZStack {
            cameraPreview.ignoresSafeArea()
            cameraOverlay
            if shutterFlash {
                Color.white.opacity(0.7).ignoresSafeArea().allowsHitTesting(false)
            }
        }
    }

    private func configureAutoScan() {
        autoScanViewModel.appModel = appModel
        autoScanViewModel.captureCoordinator = captureCoordinator
        autoScanViewModel.modelContext = appModel.modelContext
        autoScanViewModel.apiBaseURL = appModel.apiBaseURL
        autoScanViewModel.captureDelay = appModel.autoScanCaptureDelay
        autoScanViewModel.presenceTracker.confidenceThreshold = Float(appModel.autoScanConfidenceThreshold)
        autoScanViewModel.recognitionQueue.maxConcurrent = appModel.maxConcurrentUploads
        autoScanViewModel.updateMotionBurstConfiguration(motionBurstConfiguration)
#if DEBUG
        autoScanViewModel.debugSaveRawCapturesToPhotoLibrary = appModel.debugSaveRawCapturesToPhotoLibrary
#endif
    }

    private var motionBurstConfiguration: MotionBurstConfiguration {
        let baseConfig = appModel.motionBurstPreset.configuration
        if appModel.motionBurstPreset == .custom {
            var config = baseConfig
            config.motionThreshold = Float(appModel.motionBurstMotionThreshold)
            config.minPeakThreshold = Float(appModel.motionBurstMinPeakThreshold)
            return config
        }
        return baseConfig
    }

    private var isAutoScanMode: Bool {
        detectionMode == .auto
    }

    // MARK: - Subviews

    private var cameraOverlay: some View {
        VStack(spacing: 0) {
            if appModel.showRecognitionNotifications, !autoScanViewModel.identifiedCardsViewModel.recentCards.isEmpty {
                IdentifiedCardToastContainer(viewModel: autoScanViewModel.identifiedCardsViewModel)
                    .padding(.top, 8)
            }
            HStack {
                Spacer()
                RecognitionBadgeView(
                    recognitionQueue: autoScanViewModel.recognitionQueue,
                    onCancel: autoScanViewModel.cancelRecognition,
                    onRetryFailed: autoScanViewModel.recognitionQueue.retryFailed,
                    onClearFailed: autoScanViewModel.recognitionQueue.clearFailed
                )
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
            captureControls
        }
    }

    private var captureControls: some View {
        VStack(spacing: 24) {
            if isAutoScanMode, let failure = autoScanViewModel.captureFailure {
                StationCaptureFailureView(message: failure, retry: autoScanViewModel.captureManually)
            }
            if let failure = captureCoordinator.zoomFailure {
                Button(action: captureCoordinator.retryZoom) {
                    Label(failure, systemImage: "arrow.clockwise").font(.caption)
                        .padding(10).frame(minHeight: 44).captureControlSurface(in: Capsule())
                }
                .foregroundStyle(.white)
                .accessibilityIdentifier("capture-zoom-retry")
            }
            VStack(spacing: 8) {
                AutoScanView(viewModel: autoScanViewModel)
                    .frame(maxWidth: .infinity, minHeight: feedbackHeight)
                    .opacity(isAutoScanMode ? 1 : 0)
                    .accessibilityHidden(!isAutoScanMode)
                framingControls
            }
            bottomBar
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    private var framingControls: some View {
        CaptureFramingControls(currentZoom: captureCoordinator.presetZoom ?? detectionViewModel.zoomFactor,
                               isEnabled: autoScanViewModel.canChangeZoom,
                               torchLevel: $detectionViewModel.torchLevel,
                               lastTorchLevel: lastTorchLevelBinding, opensBrightness: opensBrightness,
                               onSelect: captureCoordinator.setZoom)
    }

    private var cameraPreviewID: String {
        "\(detectionMode.rawValue)-\(detectionViewModel.cameraPermissionGranted)"
    }

    private var cameraPreview: some View {
        let preview = CameraPreviewRepresentable(
            detectionMode: $detectionMode,
            camera: .automatic,
            sessionManager: cameraSession,
            onDetectedCardsChanged: { cards in
                detectionViewModel.handleDetectedCards(cards)
            },
            captureCoordinator: captureCoordinator,
            onZoomFactorChanged: { factor in
                detectionViewModel.zoomFactor = factor
                if isActive && !needsZoomRestore { savedZoom = factor }
                restoreCameraZoomIfNeeded()
            },
            willChangeZoom: { factor in
                autoScanViewModel.prepareForZoomChange(from: detectionViewModel.zoomFactor, to: factor)
            },
            onZoomMotionChanged: { if isActive { autoScanViewModel.isZoomMoving = $0 } },
            onZoomFailure: captureCoordinator.reportZoomFailure,
            onZoomPresetChanged: { captureCoordinator.presetZoom = $0 },
            shouldChangeZoom: { _ in autoScanViewModel.canChangeZoom },
            onAutoScanFrame: isAutoScanMode
                ? { [weak autoScanViewModel] buffer in
                    Task { @MainActor in
                        autoScanViewModel?.processFrame(buffer)
                    }
                }
                : nil,
            torchLevel: detectionViewModel.torchLevel,
            exposureBias: Float(appModel.exposureBias)
        )
        return Group {
            if let previewContent { previewContent(preview) } else { AnyView(preview) }
        }
        .id(cameraPreviewID)
        .accessibilityHidden(hidesPreviewFromAccessibility)
    }

    private var hidesPreviewFromAccessibility: Bool {
#if DEBUG
        if CameraViewController.livePreviewTestEnabled { return false }
#endif
        return previewContent == nil
    }

    private var bottomBar: some View {
        ZStack {
            manualShutter
            HStack {
                thumbnail.frame(width: 48, height: 48)
                Spacer()
                if isAutoScanMode { StationStartStopButton(viewModel: autoScanViewModel) } else { photoPickerButton }
            }
        }
        .frame(height: 76)
    }

    private var manualShutter: some View {
        CaptureButton(action: isAutoScanMode ? autoScanViewModel.captureManually : captureCard,
                      isDisabled: !autoScanViewModel.canCaptureManually)
            .accessibilityIdentifier("capture-shutter")
    }

    private var thumbnail: some View {
        Group {
            if let image = autoScanViewModel.lastCroppedImage {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: 36, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("Last captured card")
            } else {
                Color.clear.frame(width: 36, height: 48).accessibilityHidden(true)
            }
        }
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
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .captureControlSurface(in: Circle())
        }
        .accessibilityLabel("Choose photo")
        .accessibilityHint("Selects an existing image for card recognition.")
    }

    // MARK: - Actions

    private func captureCard() {
        guard autoScanViewModel.canCaptureManually else { return }
        triggerShutterFeedback()
        Task {
            captureError = await autoScanViewModel.captureTablePhoto(cropEnabled: appModel.onDeviceCropEnabled)
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

    private func storeAndTurnOffTorch() {
        if detectionViewModel.torchLevel > 0 {
            appModel.lastTorchLevel = detectionViewModel.torchLevel
        }
        detectionViewModel.torchLevel = 0
    }

    private func handleScanActivityChange(_ active: Bool) {
        if !active {
            storeAndTurnOffTorch()
            captureCoordinator.cancelZoom()
            autoScanViewModel.isZoomMoving = false
            autoScanViewModel.pauseForNavigation()
            needsZoomRestore = true
        } else {
            synchronizeCameraZoom()
        }
    }

    private func synchronizeCameraZoom() { captureCoordinator.controller?.synchronizeZoom() }

    private func restoreCameraZoomIfNeeded() {
        guard isActive, needsZoomRestore, autoScanViewModel.canChangeZoom,
              let controller = captureCoordinator.controller else { return }
        needsZoomRestore = false
        controller.setZoom(savedZoom)
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .background else { return }
        storeAndTurnOffTorch()
    }

    private var photoLoadErrorBinding: Binding<Bool> {
        Binding(
            get: { photoLoadError != nil },
            set: { if !$0 { photoLoadError = nil } }
        )
    }

    private func onAppearHandler() {
        if previewContent == nil { detectionViewModel.requestCameraPermissionIfNeeded() }
        configureAutoScan()
        if isActive { synchronizeCameraZoom() }
        onConfigured?()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func onDisappearHandler() {
        UIApplication.shared.isIdleTimerDisabled = false
        storeAndTurnOffTorch()
        captureCoordinator.cancelZoom()
        autoScanViewModel.pauseForNavigation()
    }
}
