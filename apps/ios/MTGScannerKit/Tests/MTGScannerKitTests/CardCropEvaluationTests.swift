import CoreGraphics
import UIKit
import Vision
import XCTest

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
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: fixture.resourceName,
                withExtension: fixture.resourceExtension
            ),
            "Missing fixture image for \(fixture.id): \(fixture.path)"
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(UIImage(data: data), "Could not decode fixture image for \(fixture.id)")
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
        let edgeMetrics = try EdgeMetrics(image: image)
        let outerStraightnessDegrees = Self.straightnessDegrees(in: image)
        let printedLayoutMetrics = try PrintedLayoutMetrics(image: image)

        let isUnderCrop =
            edgeMetrics.darkEdgeFraction < 0.20 ||
            edgeMetrics.lightBackgroundEdgeFraction > 0.50 ||
            edgeMetrics.meanEdgeBrightness > 0.55

        let isOverCrop =
            !isUnderCrop &&
            edgeMetrics.lightBackgroundEdgeFraction < 0.10 &&
            edgeMetrics.darkEdgeFraction < 0.65 &&
            edgeMetrics.meanEdgeBrightness > 0.20

        let isSkewed =
            !isUnderCrop &&
            !isOverCrop &&
            printedLayoutMetrics.horizontalAngleDegrees > 0.20

        return CropEvaluationResult(
            isUnderCrop: isUnderCrop,
            isOverCrop: isOverCrop,
            isSkewed: isSkewed,
            edgeMetrics: edgeMetrics,
            outerStraightnessDegrees: outerStraightnessDegrees,
            printedLayoutMetrics: printedLayoutMetrics
        )
    }

    private static func straightnessDegrees(in image: UIImage) -> CGFloat {
        guard let cgImage = image.cgImage else { return 0 }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 6
        request.minimumConfidence = 0.20
        request.minimumAspectRatio = 0.30
        request.maximumAspectRatio = 3.30
        request.quadratureTolerance = 45.0

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform([request])

        let observations = request.results ?? []
        guard let observation = observations.max(by: { $0.confidence < $1.confidence }) else {
            return 0
        }

        let topAngle = horizontalResidualDegrees(from: observation.topLeft, to: observation.topRight)
        let bottomAngle = horizontalResidualDegrees(from: observation.bottomLeft, to: observation.bottomRight)
        let leftAngle = verticalResidualDegrees(from: observation.bottomLeft, to: observation.topLeft)
        let rightAngle = verticalResidualDegrees(from: observation.bottomRight, to: observation.topRight)

        return max(topAngle, bottomAngle, leftAngle, rightAngle)
    }

    private static func horizontalResidualDegrees(from a: CGPoint, to b: CGPoint) -> CGFloat {
        let angle = abs(atan2(b.y - a.y, b.x - a.x) * 180 / .pi)
        return min(angle, abs(180 - angle))
    }

    private static func verticalResidualDegrees(from a: CGPoint, to b: CGPoint) -> CGFloat {
        let angle = abs(atan2(b.y - a.y, b.x - a.x) * 180 / .pi)
        return abs(90 - angle)
    }
}

private struct CropEvaluationResult {
    let isUnderCrop: Bool
    let isOverCrop: Bool
    let isSkewed: Bool
    let edgeMetrics: EdgeMetrics
    let outerStraightnessDegrees: CGFloat
    let printedLayoutMetrics: PrintedLayoutMetrics

    var passes: Bool {
        !isUnderCrop && !isOverCrop && !isSkewed
    }

    var debugSummary: String {
        String(
            format: "under=%@ over=%@ skewed=%@ lightEdge=%.3f darkEdge=%.3f meanEdgeBrightness=%.3f outerStraightness=%.2f printedHorizontalAngle=%.2f printedLineScore=%.0f",
            String(isUnderCrop),
            String(isOverCrop),
            String(isSkewed),
            edgeMetrics.lightBackgroundEdgeFraction,
            edgeMetrics.darkEdgeFraction,
            edgeMetrics.meanEdgeBrightness,
            outerStraightnessDegrees,
            printedLayoutMetrics.horizontalAngleDegrees,
            printedLayoutMetrics.score
        )
    }
}

private struct PrintedLayoutMetrics {
    let horizontalAngleDegrees: CGFloat
    let score: CGFloat

    init(image: UIImage) throws {
        let sample = try EdgeSample(image: image, width: 240, height: 336)
        var edgePoints: [WeightedPoint] = []

        let minX = Int(CGFloat(sample.width) * 0.10)
        let maxX = Int(CGFloat(sample.width) * 0.90)
        let minY = Int(CGFloat(sample.height) * 0.10)
        let maxY = Int(CGFloat(sample.height) * 0.90)

        for y in minY..<maxY {
            for x in minX..<maxX {
                let left = sample.luminance(x: x - 1, y: y)
                let right = sample.luminance(x: x + 1, y: y)
                let up = sample.luminance(x: x, y: y - 1)
                let down = sample.luminance(x: x, y: y + 1)
                let gx = right - left
                let gy = down - up
                let magnitude = abs(gx) + abs(gy)

                // Printed layout bars are horizontal intensity edges. Ignore mostly vertical
                // strokes from text and art, and ignore the outer crop border via the inset.
                if magnitude > 0.18, abs(gy) > abs(gx) * 1.30 {
                    edgePoints.append(WeightedPoint(x: x, y: y, weight: magnitude))
                }
            }
        }

        guard !edgePoints.isEmpty else {
            horizontalAngleDegrees = 0
            score = 0
            return
        }

        let best = Self.bestHorizontalAngle(edgePoints: edgePoints)
        horizontalAngleDegrees = abs(best.angleDegrees)
        score = best.score
    }

    private static func bestHorizontalAngle(edgePoints: [WeightedPoint]) -> (angleDegrees: CGFloat, score: CGFloat) {
        var bestAngle: CGFloat = 0
        var bestScore: CGFloat = 0

        for step in -100...100 {
            let angleDegrees = CGFloat(step) / 20
            let slope = tan(angleDegrees * .pi / 180)
            var bins: [Int: CGFloat] = [:]

            for point in edgePoints {
                let intercept = Int(round(CGFloat(point.y) - slope * CGFloat(point.x)))
                bins[intercept, default: 0] += point.weight
            }

            let score = bins.values.sorted(by: >).prefix(8).reduce(0, +)
            if score > bestScore {
                bestScore = score
                bestAngle = angleDegrees
            }
        }

        return (bestAngle, bestScore)
    }

    private struct WeightedPoint {
        let x: Int
        let y: Int
        let weight: CGFloat
    }
}

private struct EdgeMetrics {
    let lightBackgroundEdgeFraction: CGFloat
    let darkEdgeFraction: CGFloat
    let meanEdgeBrightness: CGFloat

    init(image: UIImage) throws {
        let sample = try EdgeSample(image: image, width: 180, height: 252)
        let strip = max(3, Int(CGFloat(min(sample.width, sample.height)) * 0.035))

        var total = 0
        var lightBackground = 0
        var dark = 0
        var brightnessSum: CGFloat = 0

        func accumulate(x: Int, y: Int) {
            let pixel = sample.pixel(x: x, y: y)
            let maxChannel = max(pixel.red, pixel.green, pixel.blue)
            let minChannel = min(pixel.red, pixel.green, pixel.blue)
            let saturation = maxChannel == 0 ? 0 : (maxChannel - minChannel) / maxChannel

            if maxChannel > 0.70 && saturation < 0.28 {
                lightBackground += 1
            }
            if maxChannel < 0.22 {
                dark += 1
            }
            brightnessSum += maxChannel
            total += 1
        }

        for x in 0..<sample.width {
            for y in 0..<strip {
                accumulate(x: x, y: y)
            }
            for y in (sample.height - strip)..<sample.height {
                accumulate(x: x, y: y)
            }
        }

        for y in 0..<sample.height {
            for x in 0..<strip {
                accumulate(x: x, y: y)
            }
            for x in (sample.width - strip)..<sample.width {
                accumulate(x: x, y: y)
            }
        }

        guard total > 0 else {
            throw CropEvaluationError.emptySample
        }

        lightBackgroundEdgeFraction = CGFloat(lightBackground) / CGFloat(total)
        darkEdgeFraction = CGFloat(dark) / CGFloat(total)
        meanEdgeBrightness = brightnessSum / CGFloat(total)
    }
}

private struct EdgeSample {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    private static let bytesPerPixel = 4

    init(image: UIImage, width: Int, height: Int) throws {
        guard let cgImage = image.cgImage else {
            throw CropEvaluationError.missingCGImage
        }

        self.width = width
        self.height = height

        let bytesPerRow = width * Self.bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CropEvaluationError.contextCreateFailed
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = data
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let offset = ((height - 1 - y) * width + x) * Self.bytesPerPixel
        return Pixel(
            red: CGFloat(bytes[offset]) / 255,
            green: CGFloat(bytes[offset + 1]) / 255,
            blue: CGFloat(bytes[offset + 2]) / 255
        )
    }

    func luminance(x: Int, y: Int) -> CGFloat {
        let clampedX = max(0, min(width - 1, x))
        let clampedY = max(0, min(height - 1, y))
        let pixel = pixel(x: clampedX, y: clampedY)
        return 0.299 * pixel.red + 0.587 * pixel.green + 0.114 * pixel.blue
    }
}

private struct Pixel {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
}

private enum CropEvaluationError: Error {
    case missingCGImage
    case contextCreateFailed
    case emptySample
}
