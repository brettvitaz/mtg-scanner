import XCTest
@testable import MTGScanner

final class YOLOCropHelperTests: XCTestCase {

    // MARK: - Helpers

    /// Makes a solid-color image of the given size at scale 1.
    private func makeImage(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Valid Crop

    func testCropWithValidRectProducesExpectedSize() throws {
        // 100×100 image, crop center half (no padding).
        let image = makeImage(width: 100, height: 100)
        let rect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let result = try XCTUnwrap(YOLOCropHelper.cropImage(image, toNormalizedRect: rect, padding: 0))
        XCTAssertEqual(result.size.width, 50, accuracy: 1)
        XCTAssertEqual(result.size.height, 50, accuracy: 1)
    }

    func testCropWithPaddingProducesLargerOutput() throws {
        let image = makeImage(width: 200, height: 200)
        let rect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let noPad = try XCTUnwrap(YOLOCropHelper.cropImage(image, toNormalizedRect: rect, padding: 0))
        let padded = try XCTUnwrap(YOLOCropHelper.cropImage(image, toNormalizedRect: rect, padding: 0.1))
        XCTAssertGreaterThan(padded.size.width, noPad.size.width)
        XCTAssertGreaterThan(padded.size.height, noPad.size.height)
    }

    // MARK: - Edge Cases

    func testCropWithZeroWidthRectReturnsNil() {
        let image = makeImage(width: 100, height: 100)
        let result = YOLOCropHelper.cropImage(image, toNormalizedRect: CGRect(x: 0.5, y: 0.5, width: 0, height: 0.5))
        XCTAssertNil(result)
    }

    func testCropWithZeroHeightRectReturnsNil() {
        let image = makeImage(width: 100, height: 100)
        let result = YOLOCropHelper.cropImage(image, toNormalizedRect: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0))
        XCTAssertNil(result)
    }

    func testCropClampsOutOfBoundsRectToImageBounds() throws {
        // Rect extends beyond [0,1] in both axes — result must be non-nil and within image.
        let image = makeImage(width: 100, height: 100)
        let rect = CGRect(x: 0.8, y: 0.8, width: 0.5, height: 0.5)
        let result = try XCTUnwrap(YOLOCropHelper.cropImage(image, toNormalizedRect: rect, padding: 0))
        // Cropped region is clamped to image bounds, so output is smaller than 50×50.
        XCTAssertLessThanOrEqual(result.size.width, 50)
        XCTAssertLessThanOrEqual(result.size.height, 50)
    }

    func testCropFullImageReturnsFullSizeOutput() throws {
        let image = makeImage(width: 80, height: 120)
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let result = try XCTUnwrap(YOLOCropHelper.cropImage(image, toNormalizedRect: rect, padding: 0))
        XCTAssertEqual(result.size.width, 80, accuracy: 1)
        XCTAssertEqual(result.size.height, 120, accuracy: 1)
    }

    func testDefaultPaddingIsApplied() throws {
        // Default padding (3%) should produce a crop larger than zero-padding.
        let image = makeImage(width: 200, height: 200)
        let rect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let noPad = try XCTUnwrap(YOLOCropHelper.cropImage(image, toNormalizedRect: rect, padding: 0))
        let defaultPad = try XCTUnwrap(YOLOCropHelper.cropImage(image, toNormalizedRect: rect))
        XCTAssertGreaterThan(defaultPad.size.width, noPad.size.width)
    }
}
