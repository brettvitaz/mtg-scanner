import CoreGraphics
import Foundation

/// A single card-shaped region detected in a camera frame.
struct DetectedCard: Identifiable, Equatable {
    let id: UUID
    /// Bounding box in Vision normalized coordinates (origin bottom-left, values 0...1).
    let boundingBox: CGRect
    /// Four corners in Vision normalized coordinates (origin bottom-left).
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
    /// Vision confidence score (0...1).
    let confidence: Float
    /// Presentation timestamp of the source frame.
    let timestamp: TimeInterval

    init(
        id: UUID = UUID(),
        boundingBox: CGRect,
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint,
        confidence: Float,
        timestamp: TimeInterval = 0
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.confidence = confidence
        self.timestamp = timestamp
    }
}
