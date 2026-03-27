import AudioToolbox
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ScanView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var isShowingCamera = false
    @State private var isShowingCameraUnavailableAlert = false
    @State private var shutterFlash = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewSection

                    HStack(spacing: 12) {
                        Button {
                            presentCamera()
                        } label: {
                            Label("Use Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appModel.isRecognizing)

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose Photo", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(appModel.isRecognizing)
                        .onChange(of: selectedPhoto) { _, newValue in
                            guard let newValue else { return }
                            Task { await loadPhoto(from: newValue) }
                        }
                    }

                    Button("Use sample recognition result") {
                        appModel.loadSampleResult()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.isRecognizing)

                    cropsPreviewSection

                    statusSection
                }
                .padding()
            }
            .navigationTitle("MTG Scanner")
            .overlay { if appModel.isRecognizing { loadingOverlay } }
            .sheet(isPresented: $isShowingCamera) {
                CameraPicker { image in
                    triggerShutterFeedback()
                    Task { await handleCapturedImage(image) }
                }
            }
            .alert("Camera Unavailable", isPresented: $isShowingCameraUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Camera capture is only available on devices with an accessible camera. Use Photo Library instead.")
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var previewSection: some View {
        GroupBox("Selected Image") {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 240)

                if let selectedImage {
                    selectedImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(shutterFlash ? 0.7 : 0))
                                .padding(10)
                        )
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No image selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Brief post-capture preview of detected crops (informational only).
    @ViewBuilder
    private var cropsPreviewSection: some View {
        let crops = appModel.lastDetectedCrops
        if !crops.isEmpty {
            GroupBox {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(crops.enumerated()), id: \.offset) { _, crop in
                            Image(uiImage: crop)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.vertical, 4)
                }
            } label: {
                Label("Detected crops (\(crops.count))", systemImage: "rectangle.dashed")
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.headline)
            Text(appModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let filename = appModel.lastUploadedFilename {
                Text("Last upload: \(filename)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
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

    private func triggerShutterFeedback() {
        AudioServicesPlaySystemSound(1108) // shutter click
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
            guard let uiImage = UIImage(data: data) else {
                appModel.statusMessage = "The selected file is not a supported image."
                return
            }
            setPreviewImage(uiImage)
            let filename = item.itemIdentifier.map { "photo-\($0).jpg" } ?? "selected-image.jpg"
            let contentType = UTType.jpeg.preferredMIMEType ?? "image/jpeg"
            await appModel.recognizeImage(data: data, filename: filename, contentType: contentType)
        } catch {
            appModel.statusMessage = "Failed to load the selected photo: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func handleCapturedImage(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            appModel.statusMessage = "Failed to prepare the captured photo."
            return
        }
        setPreviewImage(image)
        let filename = "camera-capture-\(UUID().uuidString.prefix(8)).jpg"
        let contentType = UTType.jpeg.preferredMIMEType ?? "image/jpeg"
        await appModel.recognizeImage(data: data, filename: filename, contentType: contentType)
    }

    @MainActor
    private func setPreviewImage(_ image: UIImage) {
        selectedImage = Image(uiImage: image)
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            isShowingCameraUnavailableAlert = true
            return
        }
        isShowingCamera = true
    }
}

// MARK: - CameraPicker

private struct CameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                picker.dismiss(animated: true)
                return
            }
            picker.dismiss(animated: true)
            parent.onImagePicked(image)
        }
    }
}
