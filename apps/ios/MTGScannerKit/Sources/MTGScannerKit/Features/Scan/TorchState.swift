import Foundation

@MainActor
final class TorchState {
    var level: Float
    var remembered: Float

    init(level: Float, remembered: Float) {
        self.level = level
        self.remembered = remembered
    }

    func toggle() {
        if level > 0 {
            remembered = Self.clamp(level)
            level = 0
        } else {
            openBrightness()
        }
    }

    func openBrightness() {
        if level <= 0 { level = Self.clamp(remembered > 0 ? remembered : 0.5) }
        remembered = level
    }

    static func clamp(_ value: Float) -> Float { min(1, max(0.01, value)) }
}
