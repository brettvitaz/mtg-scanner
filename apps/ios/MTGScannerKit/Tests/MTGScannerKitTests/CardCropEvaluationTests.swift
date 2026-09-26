import CoreGraphics
import UIKit
import XCTest
@testable import MTGScannerKit

final class CardCropEvaluationTests: XCTestCase {

    func testLabeledCropOutputsClassifyByExpectedFailure() throws {
        let fixtures = try loadManifest()
        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let image = try loadImage(for: fixture)
            let result = try CropOutputEvaluator.evaluate(image)

            switch fixture.expectedFailure {
            case .none:
                XCTAssertTrue(
                    result.passes,
                    "\(fixture.id) should pass, metrics: \(result.debugSummary)"
                )
            case .underCrop:
                XCTAssertTrue(
                    result.isUnderCrop,
                    "\(fixture.id) should fail under-crop, metrics: \(result.debugSummary)"
                )
            case .overCrop:
                XCTAssertTrue(
                    result.isOverCrop,
                    "\(fixture.id) should fail over-crop, metrics: \(result.debugSummary)"
                )
            case .skewed:
                XCTAssertTrue(
                    result.isSkewed,
                    "\(fixture.id) should fail skewed, metrics: \(result.debugSummary)"
                )
            }
        }
    }

    func testAutoScanRegressionBadOutputsClassifyAsFailures() throws {
        let fixtures = [
            "IMG_1956-crop",
            "IMG_1957-crop",
            "IMG_1960-crop"
        ]

        for fixture in fixtures {
            let image = try loadImage(resourceName: fixture)
            let result = try CropOutputEvaluator.evaluate(image)
            XCTAssertFalse(result.passes, "\(fixture) should fail, metrics: \(result.debugSummary)")
        }
    }

    func testTableScanRegressionOutputsClassifyByExpectedQuality() throws {
        let fixtures: [(name: String, shouldPass: Bool)] = [
            ("IMG_1968-crop1", false),
            ("IMG_1968-crop2", false),
            ("IMG_1968-crop3", true),
            ("IMG_1969-crop1", false),
            ("IMG_1969-crop2", true),
            ("IMG_1969-crop3", false),
            ("IMG_1969-crop4", false),
            ("IMG_1973-crop1", false),
            ("IMG_1973-crop2", false),
            ("IMG_1979-crop1", false),
            ("IMG_1979-crop2", true),
            ("IMG_1980-crop1", false)
        ]

        for fixture in fixtures {
            let image = try loadImage(resourceName: fixture.name)
            let result = try CropOutputEvaluator.evaluate(image)
            XCTAssertEqual(
                result.passes,
                fixture.shouldPass,
                "\(fixture.name) metrics: \(result.debugSummary)"
            )
        }
    }

    private func loadManifest() throws -> [CropEvaluationFixture] {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "labeled-output-manifest",
                withExtension: "json"
            )
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([CropEvaluationFixture].self, from: data)
    }

    private func loadImage(for fixture: CropEvaluationFixture) throws -> UIImage {
        try loadImage(
            resourceName: fixture.resourceName,
            message: "Missing fixture image for \(fixture.id): \(fixture.path)"
        )
    }

    private func loadImage(
        resourceName: String,
        subdirectory: String? = nil,
        message: String? = nil
    ) throws -> UIImage {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: resourceName,
                withExtension: "jpg",
                subdirectory: subdirectory
            ),
            message ?? "Missing fixture image for \(resourceName)"
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(UIImage(data: data), "Could not decode fixture image for \(resourceName)")
    }
}

private struct CropEvaluationFixture: Decodable {
    let id: String
    let mode: String
    let path: String
    let sourcePath: String
    let expectedFailure: ExpectedCropFailure

    var resourceDirectory: String {
        (path as NSString).deletingLastPathComponent
    }

    var resourceName: String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    var resourceExtension: String {
        (path as NSString).pathExtension
    }
}

private enum ExpectedCropFailure: String, Decodable {
    case none
    case underCrop
    case overCrop
    case skewed
}

private enum CropOutputEvaluator {
    static func evaluate(_ image: UIImage) throws -> CropEvaluationResult {
        let quality = CropQualityEvaluator.evaluate(image)
        let edgeMetrics = try XCTUnwrap(quality.edgeMetrics)
        let printedLayoutMetrics = try XCTUnwrap(quality.layoutMetrics)

        let isUnderCrop =
            quality.isUnderCrop

        let isOverCrop = quality.isOverCrop

        let isSkewed =
            !isUnderCrop &&
            !isOverCrop &&
            quality.isSkewed

        return CropEvaluationResult(
            isUnderCrop: isUnderCrop,
            isOverCrop: isOverCrop,
            isSkewed: isSkewed,
            edgeMetrics: edgeMetrics,
            printedLayoutMetrics: printedLayoutMetrics
        )
    }
}

private struct CropEvaluationResult {
    let isUnderCrop: Bool
    let isOverCrop: Bool
    let isSkewed: Bool
    let edgeMetrics: EdgeMetrics
    let printedLayoutMetrics: PrintedLayoutMetrics

    var passes: Bool {
        !isUnderCrop && !isOverCrop && !isSkewed
    }

    var debugSummary: String {
        String(
            format: """
            under=%@ over=%@ skewed=%@ lightEdge=%.3f darkEdge=%.3f \
            meanEdgeBrightness=%.3f printedHorizontalAngle=%.2f printedLineScore=%.0f
            """,
            String(isUnderCrop),
            String(isOverCrop),
            String(isSkewed),
            edgeMetrics.lightBackgroundEdgeFraction,
            edgeMetrics.darkEdgeFraction,
            edgeMetrics.meanEdgeBrightness,
            printedLayoutMetrics.horizontalAngleDegrees,
            printedLayoutMetrics.score
        )
    }
}
