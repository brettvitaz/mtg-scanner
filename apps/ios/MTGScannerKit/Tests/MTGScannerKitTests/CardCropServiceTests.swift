import UIKit
import XCTest
@testable import MTGScannerKit

final class CardCropServiceTests: XCTestCase {

    func testDetectAndCropFindsTwoCardsInTableFixture() async throws {
        let result = await makeService().detectAndCrop(image: try loadImage(named: "artifacts/two_card_table.jpg"))

        XCTAssertEqual(result.detectedCount, 2)
        XCTAssertEqual(result.crops.count, 2)
        XCTAssertTrue(result.crops.allSatisfy { $0.size.width < $0.size.height })
        for crop in result.crops {
            XCTAssertEqual(crop.size.width / crop.size.height, 63.0 / 88.0, accuracy: 0.02)
        }
    }

    func testDetectAndCropRejectsBadCropFixture() async throws {
        let result = await makeService().detectAndCrop(image: try loadImage(named: "bad_crop.jpg"))

        XCTAssertEqual(result.detectedCount, 0)
        XCTAssertEqual(result.crops.count, 0)
    }

    func testDetectAndCropRejectsSecondBadCropFixture() async throws {
        let result = await makeService().detectAndCrop(image: try loadImage(named: "bad_crop2.jpg"))

        XCTAssertEqual(result.detectedCount, 0)
        XCTAssertEqual(result.crops.count, 0)
    }

    func testDetectAndCropFallsBackToYoloHintWhenVisionFindsNoRectangle() async throws {
        let image = makeSolidImage(width: 200, height: 300)
        let hint = CardCropHint(
            yoloBoxTopLeft: CGRect(x: 0.25, y: 0.20, width: 0.50, height: 0.60),
            preferSingleCrop: true
        )

        let result = await makeService().detectAndCrop(image: image, hint: hint)

        XCTAssertEqual(result.detectedCount, 0)
        XCTAssertEqual(result.crops.count, 1)
        let crop = try XCTUnwrap(result.crops.first)
        XCTAssertLessThan(crop.size.width, crop.size.height)
        XCTAssertEqual(crop.size.width / crop.size.height, 63.0 / 88.0, accuracy: 0.02)
    }

    private func makeService() -> CardCropService {
        CardCropService()
    }

    private func makeSolidImage(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func loadImage(named relativePath: String) throws -> UIImage {
        let url = try samplesDirectory().appendingPathComponent(relativePath)
        guard let image = UIImage(contentsOfFile: url.path) else {
            XCTFail("Failed to load fixture image at \(url.path)")
            throw FixtureError.imageLoadFailed
        }
        return image
    }

    private func samplesDirectory() throws -> URL {
        let fileManager = FileManager.default
        var currentURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()

        for _ in 0..<8 {
            let candidate = currentURL.appendingPathComponent("samples/test", isDirectory: true)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            currentURL.deleteLastPathComponent()
        }

        throw FixtureError.samplesDirectoryNotFound
    }

    private enum FixtureError: Error {
        case imageLoadFailed
        case samplesDirectoryNotFound
    }
}
