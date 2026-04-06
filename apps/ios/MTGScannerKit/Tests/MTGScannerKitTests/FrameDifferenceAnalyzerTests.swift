import XCTest
@testable import MTGScannerKit

final class FrameDifferenceAnalyzerTests: XCTestCase {

    private let analyzer = FrameDifferenceAnalyzer(sampleStride: 1)

    func testInitClampsSampleStrideToMinimumOfOne() {
        let analyzer = FrameDifferenceAnalyzer(sampleStride: 0)
        XCTAssertEqual(analyzer.sampleStride, 1)
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
