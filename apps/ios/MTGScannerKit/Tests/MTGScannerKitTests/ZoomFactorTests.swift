import XCTest
@testable import MTGScannerKit

final class ZoomFactorTests: XCTestCase {

    func testClampedAtMinimum() {
        XCTAssertEqual(CameraViewController.clampedZoom(start: 1.0, scale: 0.1, max: 5.0), 1.0, accuracy: 0.001)
    }

    func testClampedAtMaximum() {
        XCTAssertEqual(CameraViewController.clampedZoom(start: 4.0, scale: 2.0, max: 5.0), 5.0, accuracy: 0.001)
    }

    func testWithinRangeIsUnmodified() {
        XCTAssertEqual(CameraViewController.clampedZoom(start: 2.0, scale: 1.5, max: 5.0), 3.0, accuracy: 0.001)
    }

    func testAtExactMinBoundary() {
        XCTAssertEqual(CameraViewController.clampedZoom(start: 1.0, scale: 1.0, max: 5.0), 1.0, accuracy: 0.001)
    }

    func testAtExactMaxBoundary() {
        XCTAssertEqual(CameraViewController.clampedZoom(start: 1.0, scale: 5.0, max: 5.0), 5.0, accuracy: 0.001)
    }
}
