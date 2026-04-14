import Foundation

/// States for the motion burst detection state machine.
///
/// Tracks the temporal progression of motion events to distinguish
/// card arrivals (burst then settle) from shadows (step change or sustained drift).
enum BurstDetectionState: Equatable, Sendable {
    /// No motion detected, waiting for burst pattern.
    case idle

    /// A burst of motion has been detected, watching for settlement.
    /// - Parameter burstStartFrame: Frame index when burst was first detected.
    case burstDetected(burstStartFrame: Int)

    /// Sustained motion without settlement (hovering/dragging).
    /// Reference frame is locked to pre-burst state.
    /// - Parameter burstStartFrame: Frame index when burst was first detected.
    case hovering(burstStartFrame: Int)

    /// Settlement confirmed after burst - card is at rest.
    case settled
}

extension BurstDetectionState {
    /// Human-readable description for debug overlay.
    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .burstDetected:
            return "Burst"
        case .hovering:
            return "Hovering"
        case .settled:
            return "Settled"
        }
    }

    /// Whether the state indicates motion is in progress.
    var isActive: Bool {
        switch self {
        case .idle, .settled:
            return false
        case .burstDetected, .hovering:
            return true
        }
    }
}
