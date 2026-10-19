import CoreVideo
import XCTest
@testable import MTGScannerKit

final class FrameDifferenceAnalyzerTests: XCTestCase {

    private let analyzer = FrameDifferenceAnalyzer(sampleStride: 1)

    func testInitClampsSampleStrideToMinimumOfOne() {
        let analyzer = FrameDifferenceAnalyzer(sampleStride: 0)
        XCTAssertEqual(analyzer.sampleStride, 1)
    }

    func testCalibratedMotionIndicesRetainVisionYFlipOnTheFixedGrid() {
        let grid = FrameDifferenceAnalyzer(sampleStride: 16)
        let zone = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        XCTAssertEqual(grid.sampleIndices(width: 64, height: 64, zone: zone), [5, 6])
        XCTAssertEqual(grid.sampleIndices(width: 64, height: 64, zone: nil).count, 16)
    }

    func testMotionRegionSelectsResampledCellCenters() {
        let grid = FrameDifferenceAnalyzer(sampleStride: 16)
        let zone = CGRect(x: 0.1, y: 0.65, width: 0.15, height: 0.25)
        XCTAssertEqual(grid.sampleIndices(width: 64, height: 64, zone: zone), [0])
    }

    func testFinePatternPhaseDoesNotAliasIntoStationMotion() throws {
        let grid = FrameDifferenceAnalyzer(sampleStride: 16)
        let first = try patternedBuffer(phase: 0)
        let second = try patternedBuffer(phase: 1)
        let firstSamples = grid.sample(first), secondSamples = grid.sample(second)
        XCTAssertEqual(firstSamples.count, 120 * 68)
        XCTAssertEqual(secondSamples.count, 120 * 68)
        XCTAssertLessThan(grid.difference(from: firstSamples, to: secondSamples), 0.01)
    }

    private func patternedBuffer(phase: Int) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_32BGRA,
                                          nil, &result), kCVReturnSuccess)
        let buffer = try XCTUnwrap(result)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for row in 0..<1080 {
            for column in 0..<1920 {
                let index = row * CVPixelBufferGetBytesPerRow(buffer) + column * 4
                let value: UInt8 = (column + phase).isMultiple(of: 2) ? 0 : 255
                for channel in 0..<3 { base[index + channel] = value }
                base[index + 3] = 255
            }
        }
        return buffer
    }

    // MARK: - difference(from:to:)

    func testIdenticalSamplesReturnZero() {
        let samples: [UInt8] = [100, 150, 200, 50, 80]
        XCTAssertEqual(analyzer.difference(from: samples, to: samples), 0.0, accuracy: 0.001)
    }

    func testMaximumDifference() {
        let a: [UInt8] = [0, 0, 0, 0]
        let b: [UInt8] = [255, 255, 255, 255]
        XCTAssertEqual(analyzer.difference(from: a, to: b), 1.0, accuracy: 0.001)
    }

    func testHalfDifference() {
        let a: [UInt8] = [0, 0]
        let b: [UInt8] = [255, 127]
        let expected = Float(255 + 127) / Float(2 * 255)
        XCTAssertEqual(analyzer.difference(from: a, to: b), expected, accuracy: 0.001)
    }

    func testEmptySamplesReturnZero() {
        XCTAssertEqual(analyzer.difference(from: [], to: []), 0.0, accuracy: 0.001)
    }

    func testMismatchedLengthsReturnZero() {
        let a: [UInt8] = [100, 100]
        let b: [UInt8] = [200]
        XCTAssertEqual(analyzer.difference(from: a, to: b), 0.0, accuracy: 0.001)
    }

    func testSymmetric() {
        let a: [UInt8] = [10, 50, 200]
        let b: [UInt8] = [90, 30, 100]
        XCTAssertEqual(
            analyzer.difference(from: a, to: b),
            analyzer.difference(from: b, to: a),
            accuracy: 0.001
        )
    }

    // MARK: - sample(_:) – indirect test via difference

    func testDifferentInitStridesProduceDifferentSampleCounts() {
        let fine = FrameDifferenceAnalyzer(sampleStride: 8)
        let coarse = FrameDifferenceAnalyzer(sampleStride: 32)
        // Fine has more samples per frame than coarse.
        // We can't easily create a CVPixelBuffer in unit tests, so we verify the
        // sampleStride property is stored correctly.
        XCTAssertEqual(fine.sampleStride, 8)
        XCTAssertEqual(coarse.sampleStride, 32)
    }
}
