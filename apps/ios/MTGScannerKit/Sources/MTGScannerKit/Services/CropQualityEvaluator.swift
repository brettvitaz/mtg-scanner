import CoreGraphics
import UIKit

struct CropQualityEvaluator {
    static func evaluate(
        _ image: UIImage,
        cropBox: CGRect? = nil,
        hintBox: CGRect? = nil,
        maxHorizontalSkewDegrees: CGFloat = 0.20
    ) -> CropQualityResult {
        guard let edgeMetrics = EdgeMetrics(image: image),
              let layoutMetrics = PrintedLayoutMetrics(image: image) else {
            return CropQualityResult(
                passes: false,
                isUnderCrop: true,
                isOverCrop: false,
                isSkewed: false,
                edgeMetrics: nil,
                layoutMetrics: nil
            )
        }

        let isUnderCrop = Self.isUnderCrop(edgeMetrics, cropBox: cropBox, hintBox: hintBox)
        let isOverCrop = !isUnderCrop && Self.isOverCrop(edgeMetrics, layoutMetrics: layoutMetrics)
        let isSkewed =
            !isUnderCrop &&
            !isOverCrop &&
            layoutMetrics.horizontalAngleDegrees > maxHorizontalSkewDegrees

        return CropQualityResult(
            passes: !isUnderCrop && !isOverCrop && !isSkewed,
            isUnderCrop: isUnderCrop,
            isOverCrop: isOverCrop,
            isSkewed: isSkewed,
            edgeMetrics: edgeMetrics,
            layoutMetrics: layoutMetrics
        )
    }

    private static func isCrop(_ cropBox: CGRect, tooSmallFor hintBox: CGRect?) -> Bool {
        guard let hintBox else { return false }
        let cropArea = cropBox.width * cropBox.height
        let hintArea = hintBox.width * hintBox.height
        guard cropArea > 0, hintArea > 0 else { return true }
        return cropArea / hintArea < 0.65
    }

    private static func isUnderCrop(
        _ edgeMetrics: EdgeMetrics,
        cropBox: CGRect?,
        hintBox: CGRect?
    ) -> Bool {
        cropBox.map { Self.isCrop($0, tooSmallFor: hintBox) } ?? false ||
            edgeMetrics.darkEdgeFraction < 0.20 ||
            edgeMetrics.lightBackgroundEdgeFraction > 0.50 ||
            edgeMetrics.meanEdgeBrightness > 0.55
    }

    private static func isOverCrop(
        _ edgeMetrics: EdgeMetrics,
        layoutMetrics: PrintedLayoutMetrics
    ) -> Bool {
        isLightOverCrop(edgeMetrics) || isDarkOverCrop(edgeMetrics, layoutMetrics: layoutMetrics)
    }

    private static func isLightOverCrop(_ edgeMetrics: EdgeMetrics) -> Bool {
        edgeMetrics.lightBackgroundEdgeFraction < 0.10 &&
            edgeMetrics.darkEdgeFraction < 0.35 &&
            edgeMetrics.meanEdgeBrightness > 0.35
    }

    private static func isDarkOverCrop(
        _ edgeMetrics: EdgeMetrics,
        layoutMetrics: PrintedLayoutMetrics
    ) -> Bool {
        edgeMetrics.lightBackgroundEdgeFraction > 0.02 &&
            edgeMetrics.lightBackgroundEdgeFraction < 0.06 &&
            edgeMetrics.darkEdgeFraction > 0.55 &&
            edgeMetrics.darkEdgeFraction < 0.70 &&
            edgeMetrics.meanEdgeBrightness > 0.20 &&
            edgeMetrics.meanEdgeBrightness < 0.30 &&
            layoutMetrics.horizontalAngleDegrees < 0.50
    }
}

struct CropQualityResult {
    let passes: Bool
    let isUnderCrop: Bool
    let isOverCrop: Bool
    let isSkewed: Bool
    let edgeMetrics: EdgeMetrics?
    let layoutMetrics: PrintedLayoutMetrics?
}

struct PrintedLayoutMetrics {
    let horizontalAngleDegrees: CGFloat
    let score: CGFloat

    init?(image: UIImage) {
        guard let sample = EdgeSample(image: image, width: 240, height: 336) else { return nil }
        let edgePoints = Self.horizontalEdgePoints(in: sample)
        guard !edgePoints.isEmpty else {
            horizontalAngleDegrees = 0
            score = 0
            return
        }

        let best = Self.bestHorizontalAngle(edgePoints: edgePoints)
        horizontalAngleDegrees = abs(best.angleDegrees)
        score = best.score
    }

    private static func horizontalEdgePoints(in sample: EdgeSample) -> [WeightedPoint] {
        let xRange = Int(CGFloat(sample.width) * 0.10)..<Int(CGFloat(sample.width) * 0.90)
        let yRange = Int(CGFloat(sample.height) * 0.10)..<Int(CGFloat(sample.height) * 0.90)
        var edgePoints: [WeightedPoint] = []

        for y in yRange {
            for x in xRange {
                let gx = sample.luminance(x: x + 1, y: y) - sample.luminance(x: x - 1, y: y)
                let gy = sample.luminance(x: x, y: y + 1) - sample.luminance(x: x, y: y - 1)
                let magnitude = abs(gx) + abs(gy)
                if magnitude > 0.18, abs(gy) > abs(gx) * 1.30 {
                    edgePoints.append(WeightedPoint(x: x, y: y, weight: magnitude))
                }
            }
        }

        return edgePoints
    }

    private static func bestHorizontalAngle(edgePoints: [WeightedPoint]) -> (angleDegrees: CGFloat, score: CGFloat) {
        var bestAngle: CGFloat = 0
        var bestScore: CGFloat = 0

        for step in -100...100 {
            let angleDegrees = CGFloat(step) / 20
            let score = score(edgePoints: edgePoints, angleDegrees: angleDegrees)
            if score > bestScore {
                bestScore = score
                bestAngle = angleDegrees
            }
        }

        return (bestAngle, bestScore)
    }

    private static func score(edgePoints: [WeightedPoint], angleDegrees: CGFloat) -> CGFloat {
        let slope = tan(angleDegrees * .pi / 180)
        var bins: [Int: CGFloat] = [:]
        for point in edgePoints {
            let intercept = Int(round(CGFloat(point.y) - slope * CGFloat(point.x)))
            bins[intercept, default: 0] += point.weight
        }
        return bins.values.sorted(by: >).prefix(8).reduce(0, +)
    }

    private struct WeightedPoint {
        let x: Int
        let y: Int
        let weight: CGFloat
    }
}

struct EdgeMetrics {
    let lightBackgroundEdgeFraction: CGFloat
    let darkEdgeFraction: CGFloat
    let meanEdgeBrightness: CGFloat

    init?(image: UIImage) {
        guard let sample = EdgeSample(image: image, width: 180, height: 252) else { return nil }
        let strip = max(3, Int(CGFloat(min(sample.width, sample.height)) * 0.035))
        let counters = EdgeCounters(sample: sample, strip: strip)
        guard counters.total > 0 else { return nil }

        lightBackgroundEdgeFraction = CGFloat(counters.lightBackground) / CGFloat(counters.total)
        darkEdgeFraction = CGFloat(counters.dark) / CGFloat(counters.total)
        meanEdgeBrightness = counters.brightnessSum / CGFloat(counters.total)
    }
}

private struct EdgeCounters {
    let total: Int
    let lightBackground: Int
    let dark: Int
    let brightnessSum: CGFloat

    init(sample: EdgeSample, strip: Int) {
        var mutable = MutableEdgeCounters()
        for x in 0..<sample.width {
            for y in 0..<strip { mutable.accumulate(sample.pixel(x: x, y: y)) }
            for y in (sample.height - strip)..<sample.height { mutable.accumulate(sample.pixel(x: x, y: y)) }
        }
        for y in 0..<sample.height {
            for x in 0..<strip { mutable.accumulate(sample.pixel(x: x, y: y)) }
            for x in (sample.width - strip)..<sample.width { mutable.accumulate(sample.pixel(x: x, y: y)) }
        }
        total = mutable.total
        lightBackground = mutable.lightBackground
        dark = mutable.dark
        brightnessSum = mutable.brightnessSum
    }
}

private struct MutableEdgeCounters {
    var total = 0
    var lightBackground = 0
    var dark = 0
    var brightnessSum: CGFloat = 0

    mutating func accumulate(_ pixel: Pixel) {
        let maxChannel = max(pixel.red, pixel.green, pixel.blue)
        let minChannel = min(pixel.red, pixel.green, pixel.blue)
        let saturation = maxChannel == 0 ? 0 : (maxChannel - minChannel) / maxChannel

        if maxChannel > 0.70, saturation < 0.28 {
            lightBackground += 1
        }
        if maxChannel < 0.22 {
            dark += 1
        }
        brightnessSum += maxChannel
        total += 1
    }
}

struct EdgeSample {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    private static let bytesPerPixel = 4

    init?(image: UIImage, width: Int, height: Int) {
        guard let cgImage = image.cgImage else { return nil }
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
            return nil
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

struct Pixel {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
}
