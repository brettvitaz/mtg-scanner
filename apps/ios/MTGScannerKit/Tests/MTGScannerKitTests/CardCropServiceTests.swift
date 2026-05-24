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

    func testAutoScanRegressionFixturesAvoidInteriorCrops() async throws {
        let fixtures: [(name: String, hint: CGRect)] = [
            ("IMG_1955", CGRect(x: 0.29, y: 0.43, width: 0.45, height: 0.42)),
            ("IMG_1956", CGRect(x: 0.28, y: 0.48, width: 0.46, height: 0.43)),
            ("IMG_1957", CGRect(x: 0.27, y: 0.43, width: 0.48, height: 0.44)),
            ("IMG_1960", CGRect(x: 0.27, y: 0.42, width: 0.49, height: 0.45))
        ]

        for fixture in fixtures {
            let image = try loadCropEvaluationImage(named: fixture.name, extension: "jpeg")
            let hint = CardCropHint(yoloBoxTopLeft: fixture.hint, preferSingleCrop: true)
            let result = await makeService().detectAndCrop(image: image, hint: hint)

            XCTAssertEqual(result.crops.count, 1, fixture.name)
            let crop = try XCTUnwrap(result.crops.first)
            let quality = CropQualityEvaluator.evaluate(crop, maxHorizontalSkewDegrees: 0.70)
            XCTAssertTrue(quality.passes, "\(fixture.name) metrics: \(debugSummary(quality))")
            XCTAssertGreaterThan(crop.size.width, 250, fixture.name)
            XCTAssertGreaterThan(crop.size.height, 350, fixture.name)
        }
    }

    func testTableScanRegressionFixturesReturnExpectedCropCounts() async throws {
        let fixtures: [(name: String, expectedCount: Int)] = [
            ("IMG_1968", 4),
            ("IMG_1969", 4),
            ("IMG_1973", 1),
            ("IMG_1979", 1),
            ("IMG_1980", 1),
            ("IMG_1981", 1)
        ]

        for fixture in fixtures {
            let image = try loadCropEvaluationImage(
                named: fixture.name,
                extension: "jpeg"
            )
            let result = await makeService().detectAndCrop(image: image)

            XCTAssertEqual(
                result.crops.count,
                fixture.expectedCount,
                "\(fixture.name) detected=\(result.detectedCount) sizes=\(result.crops.map { $0.size })"
            )
            XCTAssertTrue(result.crops.allSatisfy { $0.size.width < $0.size.height }, fixture.name)
        }
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

    private func loadCropEvaluationImage(
        named name: String,
        extension fileExtension: String,
        subdirectory: String? = nil
    ) throws -> UIImage {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: subdirectory
            )
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(UIImage(data: data), "Could not decode crop fixture \(name)")
    }

    private func debugSummary(_ result: CropQualityResult) -> String {
        guard let edgeMetrics = result.edgeMetrics, let layoutMetrics = result.layoutMetrics else {
            return "missing metrics"
        }
        return String(
            format: """
            under=%@ over=%@ skewed=%@ lightEdge=%.3f darkEdge=%.3f \
            meanEdgeBrightness=%.3f printedHorizontalAngle=%.2f
            """,
            String(result.isUnderCrop),
            String(result.isOverCrop),
            String(result.isSkewed),
            edgeMetrics.lightBackgroundEdgeFraction,
            edgeMetrics.darkEdgeFraction,
            edgeMetrics.meanEdgeBrightness,
            layoutMetrics.horizontalAngleDegrees
        )
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
