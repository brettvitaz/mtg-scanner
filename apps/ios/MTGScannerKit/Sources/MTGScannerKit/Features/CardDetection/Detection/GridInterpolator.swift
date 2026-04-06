import CoreGraphics

/// Subdivides a detected quadrilateral (e.g., a binder page) into a grid of smaller quads.
///
/// Uses bilinear interpolation so that perspective-distorted quadrilaterals produce
/// correctly proportioned sub-cells rather than simple rectangular divisions.
struct GridInterpolator {

    // MARK: - Public API

    /// Subdivides a quadrilateral into a `rows × cols` grid of sub-quads.
    ///
    /// Points are in any consistent coordinate space (e.g., Vision normalized or screen pixels).
    /// The quad corners follow Vision convention: `topLeft` has the largest Y, `bottomLeft` has
    /// the smallest Y (origin bottom-left).
    ///
    /// - Returns: An array of `rows × cols` sub-quads in row-major order (left-to-right,
    ///   top-to-bottom of the quad).
    static func subdivide(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint,
        rows: Int,
        cols: Int
    ) -> [GridCell] {
        guard rows > 0, cols > 0 else { return [] }

        var cells: [GridCell] = []
        for row in 0..<rows {
            for col in 0..<cols {
                let u0 = CGFloat(col) / CGFloat(cols)
                let u1 = CGFloat(col + 1) / CGFloat(cols)
                let v0 = CGFloat(row) / CGFloat(rows)
                let v1 = CGFloat(row + 1) / CGFloat(rows)

                let tl = interpolate(topLeft: topLeft, topRight: topRight,
                                     bottomRight: bottomRight, bottomLeft: bottomLeft,
                                     u: u0, v: v0)
                let tr = interpolate(topLeft: topLeft, topRight: topRight,
                                     bottomRight: bottomRight, bottomLeft: bottomLeft,
                                     u: u1, v: v0)
                let br = interpolate(topLeft: topLeft, topRight: topRight,
                                     bottomRight: bottomRight, bottomLeft: bottomLeft,
                                     u: u1, v: v1)
                let bl = interpolate(topLeft: topLeft, topRight: topRight,
                                     bottomRight: bottomRight, bottomLeft: bottomLeft,
                                     u: u0, v: v1)
                cells.append(GridCell(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl))
            }
        }
        return cells
    }

    /// Bilinear interpolation within a quadrilateral.
    ///
    /// `u` in [0, 1] maps from the left edge (topLeft/bottomLeft) to the right edge (topRight/bottomRight).
    /// `v` in [0, 1] maps from the top edge (topLeft/topRight) to the bottom edge (bottomLeft/bottomRight).
    ///
    /// Formula: `P(u,v) = (1-v)*[(1-u)*TL + u*TR] + v*[(1-u)*BL + u*BR]`
    static func interpolate(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint,
        u: CGFloat,
        v: CGFloat
    ) -> CGPoint {
        let x = (1 - v) * ((1 - u) * topLeft.x + u * topRight.x)
                + v * ((1 - u) * bottomLeft.x + u * bottomRight.x)
        let y = (1 - v) * ((1 - u) * topLeft.y + u * topRight.y)
                + v * ((1 - u) * bottomLeft.y + u * bottomRight.y)
        return CGPoint(x: x, y: y)
    }
}

/// A single cell produced by grid subdivision — four corner points in the same coordinate space.
struct GridCell: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
}
