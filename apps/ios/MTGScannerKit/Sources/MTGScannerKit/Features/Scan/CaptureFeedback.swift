import Foundation
import UIKit

/// Readiness is immediate; recognition speech is queued so it cannot interrupt it.
@MainActor
final class CaptureFeedback {
    var announce: (String, Bool) -> Void = { message, queued in
        let speech = NSAttributedString(string: message, attributes: [.accessibilitySpeechQueueAnnouncement: queued])
        UIAccessibility.post(notification: .announcement, argument: speech)
    }
    var haptic: () -> Void = { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    private var recognitionSpeech: Task<Void, Never>?

    func completed(ready: Bool) {
        haptic()
        announce(ready ? "Captured. Ready for the next card. Drop another card into the station." : "Captured.", false)
    }

    func recognized(_ card: IdentifiedCard, isEnabled: @escaping () -> Bool = { true }) {
        recognitionSpeech?.cancel()
        recognitionSpeech = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, isEnabled() else { return }
            self?.announce("Recognized \(card.title), \(card.setCode.uppercased()) \(card.collectorNumber)", true)
        }
    }

    func cancelRecognition() {
        recognitionSpeech?.cancel()
        recognitionSpeech = nil
    }
}
