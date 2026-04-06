import AudioToolbox
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ScanView: View {
    @Environment(AppModel.self) private var appModel
    @State private var detectionViewModel = CardDetectionViewModel()
    @State private var captureCoordinator = CameraCaptureCoordinator()
    @State private var quickScanViewModel = QuickScanViewModel()

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
            configureQuickScan()
            UIApplication.shared.isIdleTimerDisabled = true
            restoreTorchLevel()
        }
        .onDisappear {
            lockOrientation([.portrait, .landscapeLeft, .landscapeRight])
            UIApplication.shared.isIdleTimerDisabled = false
            appModel.lastTorchLevel = detectionViewModel.torchLevel
            detectionViewModel.torchLevel = 0
            quickScanViewModel.stop()
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
        .onChange(of: appModel.maxConcurrentUploads) { _, count in
            quickScanViewModel.recognitionQueue.maxConcurrent = count
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

    private func configureQuickScan() {
        quickScanViewModel.captureCoordinator = captureCoordinator
        quickScanViewModel.modelContext = appModel.modelContext
        quickScanViewModel.apiBaseURL = appModel.apiBaseURL
        quickScanViewModel.captureDelay = appModel.quickScanCaptureDelay
        quickScanViewModel.presenceTracker.confidenceThreshold = Float(appModel.quickScanConfidenceThreshold)
        quickScanViewModel.recognitionQueue.maxConcurrent = appModel.maxConcurrentUploads
    }

    private var isQuickScanMode: Bool {
        detectionViewModel.detectionMode == .quickScan
    }

    // MARK: - Subviews

    @ViewBuilder
    private var cameraOverlay: some View {
        ZStack {
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

            VStack {
                IdentifiedCardToastContainer(viewModel: quickScanViewModel.identifiedCardsViewModel)
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
                    recognitionQueue: quickScanViewModel.recognitionQueue,
                    onCancel: quickScanViewModel.cancelRecognition
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
            await enqueueForRecognition(uiImage)
        } catch {
            photoLoadError = "Failed to load the selected photo: \(error.localizedDescription)"
        }
    }

    @MainActor
    func enqueueForRecognition(_ image: UIImage) async {
        await quickScanViewModel.enqueueCapturedImage(image, cropEnabled: appModel.onDeviceCropEnabled)
    }

    func lockOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(prefs)
    }

    private func restoreTorchLevel() {
        let savedLevel = appModel.lastTorchLevel
        guard savedLevel > 0 else { return }
        detectionViewModel.torchLevel = savedLevel
    }
}

// MARK: - Identified Card Toast Views

/// Displays a single identified card toast notification.
///
/// Slides in from the trailing edge with a semi-transparent background.
/// Shows the card title, foil indicator, set code, and collector number.
struct IdentifiedCardToastView: View {
    let card: IdentifiedCard
    let onDismiss: () -> Void
    @State private var shimmerOffset: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Text(card.title)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)

            if card.isFoil {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow)
            }

            Text(card.setCode.uppercased())
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)

            if !card.collectorNumber.isEmpty {
                Text("#\(card.collectorNumber)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 24, height: 24)
                    )
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .opacity(0.85)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .overlay(
            Group {
                if card.isFoil {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(0.3),
                                    Color.orange.opacity(0.3),
                                    Color.yellow.opacity(0.3),
                                    Color.green.opacity(0.3),
                                    Color.blue.opacity(0.3),
                                    Color.purple.opacity(0.3),
                                    Color.red.opacity(0.3)
                                ],
                                startPoint: UnitPoint(x: shimmerOffset, y: 0),
                                endPoint: UnitPoint(x: shimmerOffset + 1, y: 1)
                            )
                        )
                        .blendMode(.overlay)
                        .allowsHitTesting(false)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(
                                .linear(duration: 2.0)
                                .repeatForever(autoreverses: false)
                            ) {
                                shimmerOffset = 1.0
                            }
                        }
                }
            }
        )
    }
}

/// Container view that displays multiple card toasts stacked vertically.
struct IdentifiedCardToastContainer: View {
    @Bindable var viewModel: IdentifiedCardsViewModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.recentCards) { card in
                IdentifiedCardToastView(card: card) {
                    viewModel.removeCard(id: card.id)
                }
                .transition(
                    .move(edge: .trailing)
                    .combined(with: .opacity)
                )
            }
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.recentCards.count)
    }
}
