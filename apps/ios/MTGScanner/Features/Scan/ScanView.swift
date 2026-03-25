import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ScanView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var selectedUIImage: UIImage?
    @State private var isShowingCamera = false
    @State private var isShowingCameraUnavailableAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Capture or pick a card photo, upload it to the FastAPI service, and review the mocked recognition result.")
                        .font(.body)

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
                            Task {
                                await loadPhoto(from: newValue)
                            }
                        }
                    }

                    Button("Use sample recognition result") {
                        appModel.loadSampleResult()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.isRecognizing)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status")
                            .font(.headline)
                        Text(appModel.statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let filename = appModel.lastUploadedFilename {
                        Text("Last upload: \(filename)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("MTG Scanner")
            .sheet(isPresented: $isShowingCamera) {
                CameraPicker(image: $selectedUIImage) { image in
                    Task {
                        await handleCapturedImage(image)
                    }
                }
            }
            .alert("Camera Unavailable", isPresented: $isShowingCameraUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Camera capture is only available on devices with an accessible camera. Use Photo Library instead.")
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        GroupBox("Selected Image") {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 220)

                if let selectedImage {
                    selectedImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(10)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No image selected yet")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
        selectedUIImage = image
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

private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                picker.dismiss(animated: true)
                return
            }

            parent.image = image
            picker.dismiss(animated: true)
            parent.onImagePicked(image)
        }
    }
}
