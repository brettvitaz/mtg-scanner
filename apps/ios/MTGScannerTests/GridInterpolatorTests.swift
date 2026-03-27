import XCTest
@testable import MTGScanner

final class GridInterpolatorTests: XCTestCase {

    // MARK: - interpolate

    func testInterpolateAtOriginReturnsTopLeft() {
        let tl = CGPoint(x: 0, y: 1)
        let tr = CGPoint(x: 1, y: 1)
        let br = CGPoint(x: 1, y: 0)
        let bl = CGPoint(x: 0, y: 0)
        let p = GridInterpolator.interpolate(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, u: 0, v: 0)
        XCTAssertEqual(p.x, tl.x, accuracy: 0.0001)
        XCTAssertEqual(p.y, tl.y, accuracy: 0.0001)
    }

    func testInterpolateAtU1V0ReturnsTopRight() {
        let tl = CGPoint(x: 0, y: 1)
        let tr = CGPoint(x: 1, y: 1)
        let br = CGPoint(x: 1, y: 0)
        let bl = CGPoint(x: 0, y: 0)
        let p = GridInterpolator.interpolate(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, u: 1, v: 0)
        XCTAssertEqual(p.x, tr.x, accuracy: 0.0001)
        XCTAssertEqual(p.y, tr.y, accuracy: 0.0001)
    }

    func testInterpolateAtU0V1ReturnsBottomLeft() {
        let tl = CGPoint(x: 0, y: 1)
        let tr = CGPoint(x: 1, y: 1)
        let br = CGPoint(x: 1, y: 0)
        let bl = CGPoint(x: 0, y: 0)
        let p = GridInterpolator.interpolate(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, u: 0, v: 1)
        XCTAssertEqual(p.x, bl.x, accuracy: 0.0001)
        XCTAssertEqual(p.y, bl.y, accuracy: 0.0001)
    }

    func testInterpolateAtU1V1ReturnsBottomRight() {
        let tl = CGPoint(x: 0, y: 1)
        let tr = CGPoint(x: 1, y: 1)
        let br = CGPoint(x: 1, y: 0)
        let bl = CGPoint(x: 0, y: 0)
        let p = GridInterpolator.interpolate(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, u: 1, v: 1)
        XCTAssertEqual(p.x, br.x, accuracy: 0.0001)
        XCTAssertEqual(p.y, br.y, accuracy: 0.0001)
    }

    func testInterpolateAtCenterReturnsCenter() {
        let tl = CGPoint(x: 0, y: 10)
        let tr = CGPoint(x: 10, y: 10)
        let br = CGPoint(x: 10, y: 0)
        let bl = CGPoint(x: 0, y: 0)
        let p = GridInterpolator.interpolate(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, u: 0.5, v: 0.5)
        XCTAssertEqual(p.x, 5.0, accuracy: 0.0001)
        XCTAssertEqual(p.y, 5.0, accuracy: 0.0001)
    }

    func testInterpolateTrapezoidProducesCorrectPoint() {
        // A trapezoid: wider at the top than the bottom (perspective effect).
        // TL=(0,4), TR=(8,4), BR=(6,0), BL=(2,0)
        // At u=0.5, v=0.5: midpoint of top edge = (4,4), midpoint of bottom edge = (4,0)
        // Bilinear midpoint = (4,2)
        let tl = CGPoint(x: 0, y: 4)
        let tr = CGPoint(x: 8, y: 4)
        let br = CGPoint(x: 6, y: 0)
        let bl = CGPoint(x: 2, y: 0)
        let p = GridInterpolator.interpolate(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, u: 0.5, v: 0.5)
        XCTAssertEqual(p.x, 4.0, accuracy: 0.0001)
        XCTAssertEqual(p.y, 2.0, accuracy: 0.0001)
    }

    // MARK: - subdivide

    func testSubdivideUnitSquareInto1x1ProducesOneCell() {
        let tl = CGPoint(x: 0, y: 1)
        let tr = CGPoint(x: 1, y: 1)
        let br = CGPoint(x: 1, y: 0)
        let bl = CGPoint(x: 0, y: 0)
        let cells = GridInterpolator.subdivide(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, rows: 1, cols: 1)
        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0].topLeft.x, 0, accuracy: 0.0001)
        XCTAssertEqual(cells[0].topRight.x, 1, accuracy: 0.0001)
        XCTAssertEqual(cells[0].bottomRight.y, 0, accuracy: 0.0001)
        XCTAssertEqual(cells[0].bottomLeft.y, 0, accuracy: 0.0001)
    }

    func testSubdivideUnitSquareInto3x3Produces9Cells() {
        let tl = CGPoint(x: 0, y: 3)
        let tr = CGPoint(x: 3, y: 3)
        let br = CGPoint(x: 3, y: 0)
        let bl = CGPoint(x: 0, y: 0)
        let cells = GridInterpolator.subdivide(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, rows: 3, cols: 3)
        XCTAssertEqual(cells.count, 9)
    }

    func testSubdivideUnitSquareProducesEvenlySpacedGrid() {
        // A 2×2 grid of a [0,2]×[0,2] square should produce 4 unit cells.
        let tl = CGPoint(x: 0, y: 2)
        let tr = CGPoint(x: 2, y: 2)
        let br = CGPoint(x: 2, y: 0)
        let bl = CGPoint(x: 0, y: 0)
        let cells = GridInterpolator.subdivide(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, rows: 2, cols: 2)
        XCTAssertEqual(cells.count, 4)
        // Top-left cell (row=0, col=0): topLeft=(0,2), topRight=(1,2), bottomRight=(1,1), bottomLeft=(0,1)
        let topLeftCell = cells[0]
        XCTAssertEqual(topLeftCell.topLeft.x, 0, accuracy: 0.0001)
        XCTAssertEqual(topLeftCell.topLeft.y, 2, accuracy: 0.0001)
        XCTAssertEqual(topLeftCell.topRight.x, 1, accuracy: 0.0001)
        XCTAssertEqual(topLeftCell.bottomRight.x, 1, accuracy: 0.0001)
        XCTAssertEqual(topLeftCell.bottomRight.y, 1, accuracy: 0.0001)
        // Top-right cell (row=0, col=1): topLeft=(1,2), topRight=(2,2), bottomRight=(2,1), bottomLeft=(1,1)
        let topRightCell = cells[1]
        XCTAssertEqual(topRightCell.topLeft.x, 1, accuracy: 0.0001)
        XCTAssertEqual(topRightCell.topRight.x, 2, accuracy: 0.0001)
    }

    func testSubdivideTrapezoidCellCornersAreContiguous() {
        // Adjacent cells must share edge points (no gaps or overlaps).
        let tl = CGPoint(x: 0, y: 4)
        let tr = CGPoint(x: 8, y: 4)
        let br = CGPoint(x: 6, y: 0)
        let bl = CGPoint(x: 2, y: 0)
        let cells = GridInterpolator.subdivide(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl, rows: 2, cols: 2)
        XCTAssertEqual(cells.count, 4)
        // Cell at (row=0, col=0) topRight.x should equal cell at (row=0, col=1) topLeft.x
        XCTAssertEqual(cells[0].topRight.x, cells[1].topLeft.x, accuracy: 0.0001)
        XCTAssertEqual(cells[0].topRight.y, cells[1].topLeft.y, accuracy: 0.0001)
        // Cell at (row=0, col=0) bottomRight should equal cell at (row=1, col=0) topRight
        XCTAssertEqual(cells[0].bottomLeft.x, cells[2].topLeft.x, accuracy: 0.0001)
        XCTAssertEqual(cells[0].bottomLeft.y, cells[2].topLeft.y, accuracy: 0.0001)
    }

    func testSubdivideWithZeroRowsReturnsEmpty() {
        let p = CGPoint(x: 0, y: 0)
        let cells = GridInterpolator.subdivide(topLeft: p, topRight: p, bottomRight: p, bottomLeft: p, rows: 0, cols: 3)
        XCTAssertEqual(cells.count, 0)
    }

    func testSubdivideWithZeroColsReturnsEmpty() {
        let p = CGPoint(x: 0, y: 0)
        let cells = GridInterpolator.subdivide(topLeft: p, topRight: p, bottomRight: p, bottomLeft: p, rows: 3, cols: 0)
        XCTAssertEqual(cells.count, 0)
    }
}
