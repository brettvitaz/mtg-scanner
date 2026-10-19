import UIKit

/// Native adjustable control. Gesture classification happens before preset selection.
final class BrightnessBarControl: UIControl {
    static let presets: [Float] = [0.01, 0.1, 0.25, 0.5, 0.75, 1]
    var level: Float = 0.5 {
        didSet {
            accessibilityValue = "\(Int((level * 100).rounded())) percent"
            setNeedsDisplay()
        }
    }
    var onChange: ((Float) -> Void)?
    var haptic: () -> Void = { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    private var startX: CGFloat?
    private var startLevel: Float = 0.5
    private var isDragging = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "Flashlight brightness"
        accessibilityIdentifier = "torch-brightness-bar"
        accessibilityTraits = .adjustable
        accessibilityCustomActions = Self.presets.map { preset in
            UIAccessibilityCustomAction(name: "\(Int((preset * 100).rounded())) percent") { [weak self] _ in
                self?.selectPreset(preset)
                return true
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    func begin(at position: CGFloat) {
        startX = position
        startLevel = level
        isDragging = false
    }

    func move(to position: CGFloat) {
        guard let startX else { return }
        let delta = position - startX
        if abs(delta) >= 6 { isDragging = true }
        guard isDragging, bounds.width > 0 else { return }
        change(((startLevel + Float(delta / bounds.width)) * 100).rounded() / 100)
    }

    func end(at position: CGFloat) {
        guard startX != nil else { return }
        defer { cancel() }
        guard !isDragging, bounds.width > 0 else { return }
        let fraction = Float(position / bounds.width)
        guard let preset = Self.presets.min(by: { abs($0 - fraction) < abs($1 - fraction) }) else { return }
        selectPreset(preset)
    }

    func cancel() {
        startX = nil
        isDragging = false
    }

    private func selectPreset(_ preset: Float) {
        change(preset)
        haptic()
    }

    private func change(_ value: Float) {
        level = TorchState.clamp(value)
        onChange?(level)
    }

    override func accessibilityIncrement() { change((level * 100 + 1).rounded() / 100) }
    override func accessibilityDecrement() { change((level * 100 - 1).rounded() / 100) }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        becomeFirstResponder()
        begin(at: touch.location(in: self).x)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        guard point.y > -30, point.y < bounds.height + 30 else { cancel(); return false }
        move(to: point.x)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard let touch else { cancel(); return }
        end(at: touch.location(in: self).x)
    }

    override func cancelTracking(with event: UIEvent?) { cancel() }

    override var canBecomeFirstResponder: Bool { true }
    override var canBecomeFocused: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(decrease)),
         UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(increase))]
    }
    @objc private func decrease() { accessibilityDecrement() }
    @objc private func increase() { accessibilityIncrement() }

    override func draw(_ rect: CGRect) {
        let track = CGRect(x: 0, y: bounds.midY - 6, width: bounds.width, height: 8)
        UIColor.secondarySystemFill.setFill()
        UIBezierPath(roundedRect: track, cornerRadius: 4).fill()
        UIColor.systemYellow.setFill()
        let fill = CGRect(x: 0, y: track.minY, width: bounds.width * CGFloat(level), height: track.height)
        UIBezierPath(roundedRect: fill, cornerRadius: 4).fill()
        UIColor.secondaryLabel.setStroke()
        for preset in Self.presets {
            let x = min(bounds.width - 1, max(1, bounds.width * CGFloat(preset)))
            let mark = UIBezierPath()
            mark.move(to: CGPoint(x: x, y: track.maxY + 5))
            mark.addLine(to: CGPoint(x: x, y: track.maxY + 9))
            mark.lineWidth = 1
            mark.stroke()
        }
        let thumbX = min(bounds.width - 7, max(7, bounds.width * CGFloat(level)))
        let thumb = UIBezierPath(ovalIn: CGRect(x: thumbX - 7, y: track.midY - 7, width: 14, height: 14))
        UIColor.white.setFill()
        thumb.fill()
        UIColor.tertiaryLabel.setStroke()
        thumb.lineWidth = 0.5
        thumb.stroke()
    }
}
