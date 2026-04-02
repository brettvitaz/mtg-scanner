import AudioToolbox
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ScanView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var detectionViewModel = CardDetectionViewModel()
    @StateObject private var captureCoordinator = CameraCaptureCoordinator()
    @StateObject private var quickScanViewModel = QuickScanViewModel()

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var shutterFlash = false

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
            configureQuickScan()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            lockOrientation([.portrait, .landscapeLeft, .landscapeRight])
            UIApplication.shared.isIdleTimerDisabled = false
            detectionViewModel.torchLevel = 0
        }
        .onChange(of: appModel.apiBaseURL) { _, url in
            quickScanViewModel.apiBaseURL = url
        }
        .onChange(of: appModel.modelContext) { _, ctx in
            quickScanViewModel.modelContext = ctx
        }
        .onChange(of: appModel.quickScanCaptureDelay) { _, delay in
            quickScanViewModel.captureDelay = delay
        }
        .onChange(of: appModel.quickScanConfidenceThreshold) { _, conf in
            quickScanViewModel.presenceTracker.confidenceThreshold = Float(conf)
        }
        .onChange(of: detectionViewModel.detectionMode) { _, mode in
            if mode != .quickScan {
                quickScanViewModel.stop()
            }
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

    // MARK: - Setup

    private func configureQuickScan() {
        quickScanViewModel.captureCoordinator = captureCoordinator
        quickScanViewModel.modelContext = appModel.modelContext
        quickScanViewModel.apiBaseURL = appModel.apiBaseURL
        quickScanViewModel.captureDelay = appModel.quickScanCaptureDelay
        quickScanViewModel.presenceTracker.confidenceThreshold = Float(appModel.quickScanConfidenceThreshold)
    }

    private var isQuickScanMode: Bool {
        detectionViewModel.detectionMode == .quickScan
    }

    // MARK: - Subviews

    @ViewBuilder
    private var cameraOverlay: some View {
        if isQuickScanMode {
            QuickScanView(
                viewModel: quickScanViewModel,
                recognitionQueue: quickScanViewModel.recognitionQueue,
                torchLevel: $detectionViewModel.torchLevel,
                detectionMode: $detectionViewModel.detectionMode
            )
        } else {
            standardOverlay
        }
    }

    private var standardOverlay: some View {
        VStack {
            HStack {
                Spacer()
                RecognitionBadgeView(recognitionQueue: quickScanViewModel.recognitionQueue)
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
            detectionMode: $detectionViewModel.detectionMode,
            zoomFactor: detectionViewModel.zoomFactor,
            onDetectedCardsChanged: { cards in
                detectionViewModel.handleDetectedCards(cards)
            },
            captureCoordinator: captureCoordinator,
            onZoomFactorChanged: { factor in
                detectionViewModel.zoomFactor = factor
            },
            onQuickScanFrame: isQuickScanMode
                ? { [weak quickScanViewModel] buffer in
                    Task { @MainActor in
                        quickScanViewModel?.processFrame(buffer)
                    }
                }
                : nil,
            torchLevel: detectionViewModel.torchLevel
        )
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            photoPickerButton
            Spacer()
            CaptureButton(action: captureCard, isDisabled: false)
            Spacer()
            ScanMenuButton(
                detectionMode: $detectionViewModel.detectionMode,
                torchLevel: $detectionViewModel.torchLevel
            )
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
    }

    // MARK: - Actions

    private func captureCard() {
        triggerShutterFeedback()
        Task {
            guard let image = await captureCoordinator.capturePhoto() else { return }
            await enqueueForRecognition(image)
        }
    }
}

// MARK: - Helpers

private extension ScanView {

    func triggerShutterFeedback() {
        AudioServicesPlaySystemSound(1108)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        withAnimation(.easeIn(duration: 0.18).delay(0.08)) { shutterFlash = false }
    }

    @MainActor
    func loadPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                appModel.statusMessage = "Could not read the selected image."
                return
            }
            guard let uiImage = UIImage(data: data) else {
                appModel.statusMessage = "The selected file is not a supported image."
                return
            }
            await enqueueForRecognition(uiImage)
        } catch {
            appModel.statusMessage = "Failed to load the selected photo: \(error.localizedDescription)"
        }
    }

    @MainActor
    func enqueueForRecognition(_ image: UIImage) async {
        do {
            try await APIClient().checkHealth(baseURL: appModel.apiBaseURL)
        } catch {
            appModel.connectionAlertMessage =
                "Cannot reach the server at \(appModel.apiBaseURL). Check your connection and API settings."
            appModel.showConnectionAlert = true
            return
        }

        if appModel.onDeviceCropEnabled {
            let cropResult = await CardCropService().detectAndCrop(image: image)
            let images = cropResult.crops.isEmpty ? [(image, false)] : cropResult.crops.map { ($0, true) }
            for (img, cropped) in images {
                enqueue(img, isCropped: cropped)
            }
        } else {
            enqueue(image, isCropped: false)
        }
    }

    func enqueue(_ image: UIImage, isCropped: Bool) {
        quickScanViewModel.recognitionQueue.enqueue(
            image: image,
            isCropped: isCropped,
            apiBaseURL: appModel.apiBaseURL,
            modelContext: appModel.modelContext
        )
    }

    func lockOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(prefs)
    }
}
