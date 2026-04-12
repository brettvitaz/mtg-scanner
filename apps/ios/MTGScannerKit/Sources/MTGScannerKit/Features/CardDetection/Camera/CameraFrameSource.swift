import CoreMedia
import CoreVideo

/// Abstracts the source of raw video frames for card detection.
///
/// Production code uses ``CameraSessionManager`` (AVFoundation camera).
/// Preview/simulator builds use ``FixtureFrameSource`` (static images on a timer).
public protocol CameraFrameSource: AnyObject {
    /// Called on a background queue for each delivered pixel buffer.
    var onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)? { get set }
    func start()
    func stop()
}
