import SwiftUI
import UIKit

/// UIKit-backed pan gesture that takes exclusive control of a touch on horizontal intent.
///
/// `gestureRecognizerShouldBegin` only allows the pan to start when the initial translation
/// is dominated by horizontal motion; vertical drags let the surrounding `List`'s pan win.
/// `shouldRecognizeSimultaneouslyWith` returns `false` so that once this pan claims the
/// touch, competing gestures (list scroll, navigation-controller back-swipe, the row's tap)
/// are forced to fail — preventing scroll-while-swiping, accidental page pops, and taps
/// firing at the end of a long commit.
struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void
    var onCancelled: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard
                let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let view = pan.view
            else { return false }
            let translation = pan.translation(in: view)
            return abs(translation.x) > abs(translation.y)
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard let view = recognizer.view else { return }
        switch recognizer.state {
        case .began:
            onBegan()
        case .changed:
            let translation = recognizer.translation(in: view)
            onChanged(translation.x)
        case .ended:
            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)
            onEnded(translation.x, velocity.x)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }
}
