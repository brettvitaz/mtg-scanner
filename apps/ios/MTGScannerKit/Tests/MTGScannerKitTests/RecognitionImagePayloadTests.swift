import UniformTypeIdentifiers
import XCTest
@testable import MTGScannerKit

final class RecognitionImagePayloadTests: XCTestCase {

    func testImportedJPEGPreservesOriginalBytes() throws {
        let image = makeImage()
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1.0))

        let payload = try XCTUnwrap(
            RecognitionImagePayload.importedPhoto(
                data: data,
                image: image,
                supportedContentTypes: [.jpeg]
            )
        )

        XCTAssertEqual(payload.uploadData, data)
        XCTAssertEqual(payload.contentType, "image/jpeg")
        XCTAssertEqual(payload.preferredFilenameExtension, "jpg")
    }

    func testImportedPNGPreservesOriginalBytes() throws {
        let image = makeImage()
        let data = try XCTUnwrap(image.pngData())

        let payload = try XCTUnwrap(
            RecognitionImagePayload.importedPhoto(
                data: data,
                image: image,
                supportedContentTypes: [.png]
            )
        )

        XCTAssertEqual(payload.uploadData, data)
        XCTAssertEqual(payload.contentType, "image/png")
        XCTAssertEqual(payload.preferredFilenameExtension, "png")
    }

    func testUnsupportedImportedTypeTranscodesOnceToJPEG() throws {
        let image = makeImage()

        let payload = try XCTUnwrap(
            RecognitionImagePayload.importedPhoto(
                data: Data("pretend-heic".utf8),
                image: image,
                supportedContentTypes: [.heic]
            )
        )

        XCTAssertEqual(payload.contentType, "image/jpeg")
        XCTAssertEqual(payload.preferredFilenameExtension, "jpg")
        XCTAssertNotEqual(payload.uploadData, Data("pretend-heic".utf8))
    }

    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
        return renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
    }
}
