import Foundation

enum CameraCaptureFailure: Error, Sendable {
    case unavailable
    case focusConfigurationFailed

    var message: String {
        switch self {
        case .unavailable: return "Capture failed — tap Capture to retry."
        case .focusConfigurationFailed: return "Could not configure focus — tap Capture to retry."
        }
    }
}

typealias CameraCaptureResult = Result<RecognitionImagePayload, CameraCaptureFailure>

enum CameraFocus {
    /// Presence signals contain YOLO boxes in native sensor coordinates, with a top-left origin.
    static func point(fromYOLOBox box: CGRect?) -> CGPoint {
        guard let box, box.width > 0, box.height > 0,
              box.minX.isFinite, box.minY.isFinite, box.maxX.isFinite, box.maxY.isFinite,
              box.minX >= 0, box.minY >= 0, box.maxX <= 1, box.maxY <= 1 else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return CGPoint(x: box.midX, y: box.midY)
    }

    static func needsRetargeting(from current: CGPoint, to target: CGPoint) -> Bool {
        abs(current.x - target.x) > 0.02 || abs(current.y - target.y) > 0.02
    }
}

struct FocusSettlingState {
    enum Decision { case waiting, settled, captureAtDeadline }

    let startedAt: TimeInterval
    private var idleSince: TimeInterval?

    init(startedAt: TimeInterval) {
        self.startedAt = startedAt
    }

    mutating func recordAdjustment() {
        idleSince = nil
    }

    mutating func record(isAdjusting: Bool, at now: TimeInterval) {
        if isAdjusting {
            recordAdjustment()
        } else if idleSince == nil {
            idleSince = now
        }
    }

    mutating func evaluate(isAdjusting: Bool, at now: TimeInterval, deadline: TimeInterval) -> Decision {
        record(isAdjusting: isAdjusting, at: now)
        guard now < deadline else { return .captureAtDeadline }
        guard let idleSince, now - startedAt >= 0.1, now - idleSince >= 0.05 else { return .waiting }
        return .settled
    }
}
