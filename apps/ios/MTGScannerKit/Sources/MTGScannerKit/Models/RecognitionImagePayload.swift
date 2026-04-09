import Foundation
import UIKit
import UniformTypeIdentifiers

/// Image plus the exact bytes that should be uploaded for recognition.
struct RecognitionImagePayload: @unchecked Sendable {
    static let generatedJPEGQuality: CGFloat = 0.97

    let displayImage: UIImage
    let uploadData: Data
    let contentType: String
    let preferredFilenameExtension: String

    static func cameraCapture(image: UIImage, data: Data) -> RecognitionImagePayload {
        RecognitionImagePayload(
            displayImage: image,
            uploadData: data,
            contentType: "image/jpeg",
            preferredFilenameExtension: "jpg"
        )
    }

    static func importedPhoto(
        data: Data,
        image: UIImage,
        supportedContentTypes: [UTType]
    ) -> RecognitionImagePayload? {
        if supportedContentTypes.contains(where: { $0.conforms(to: .jpeg) }) || isJPEG(data) {
            return RecognitionImagePayload(
                displayImage: image,
                uploadData: data,
                contentType: "image/jpeg",
                preferredFilenameExtension: "jpg"
            )
        }

        if supportedContentTypes.contains(where: { $0.conforms(to: .png) }) || isPNG(data) {
            return RecognitionImagePayload(
                displayImage: image,
                uploadData: data,
                contentType: "image/png",
                preferredFilenameExtension: "png"
            )
        }

        return generatedJPEG(from: image)
    }

    static func generatedJPEG(from image: UIImage) -> RecognitionImagePayload? {
        guard let uploadData = image.jpegData(compressionQuality: generatedJPEGQuality) else { return nil }
        return RecognitionImagePayload(
            displayImage: image,
            uploadData: uploadData,
            contentType: "image/jpeg",
            preferredFilenameExtension: "jpg"
        )
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0xFF && data[data.startIndex + 1] == 0xD8
    }

    private static func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        guard data.count >= signature.count else { return false }
        return zip(signature.indices, signature).allSatisfy { index, byte in
            data[data.startIndex + index] == byte
        }
    }
}
