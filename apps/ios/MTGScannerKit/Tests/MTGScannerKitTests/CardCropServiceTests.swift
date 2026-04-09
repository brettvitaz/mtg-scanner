import UIKit
import XCTest
@testable import MTGScannerKit

final class CardCropServiceTests: XCTestCase {

    func testDetectAndCropFindsTwoCardsInTableFixture() async throws {
        let result = await makeService().detectAndCrop(image: try loadImage(named: "artifacts/two_card_table.jpg"))

        XCTAssertEqual(result.detectedCount, 2)
        XCTAssertEqual(result.crops.count, 2)
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

    private func makeService() -> CardCropService {
        CardCropService()
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
