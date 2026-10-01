// Sources/HealthFeature/UI/ScrubPan.swift
import OdyKit
import SwiftUI
import UIKit

/// The hero's horizontal drag, as a UIKit pan so it can claim the touch from the drawer (see `OdyGestures`) and leave
/// vertical drags to the scroll view.
struct ScrubPan: UIGestureRecognizerRepresentable {
    let onBegin: () -> Void
    /// Horizontal translation, and the finger's location in the hero.
    let onChange: (CGFloat, CGPoint) -> Void
    /// Final translation and horizontal velocity (pt/s).
    let onEnd: (CGFloat, CGFloat) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Intent is judged once, from the whole movement since touch-down: `translation` has UIKit's ~10 pt of
        /// hysteresis taken out of it and is mostly noise at this moment. Either way is ours — a drag forward
        /// from now rubber-bands, which says "there is no more".
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? ScrubPanRecognizer else { return false }
            let movement = pan.movementSinceTouchDown
            return abs(movement.x) > abs(movement.y)
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> ScrubPanRecognizer {
        let pan = ScrubPanRecognizer()
        pan.name = OdyGestures.claimsHorizontal
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: ScrubPanRecognizer, context: Context) {
        let t = recognizer.translation(in: recognizer.view).x
        // The recognizer sits on the hosting view; the converter puts the finger in the hero's own space.
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began:
            onBegin()
            onChange(t, location)
        case .changed: onChange(t, location)
        case .ended: onEnd(t, recognizer.releaseVelocity)
        // Taken away, not let go: no throw, just land where it is.
        case .cancelled, .failed: onEnd(t, 0)
        default: break
        }
    }
}

/// A pan that remembers where the finger landed and when it last moved.
final class ScrubPanRecognizer: UIPanGestureRecognizer {
    private var touchDown: CGPoint?
    private var lastMove: CFTimeInterval = 0

    var movementSinceTouchDown: CGPoint {
        guard let touchDown, let view else { return .zero }
        let now = location(in: view)
        return CGPoint(x: now.x - touchDown.x, y: now.y - touchDown.y)
    }

    /// A finger that stopped before letting go sends no more events, and `velocity(in:)` goes on reporting its last
    /// speed; past a short pause the release is a placement, not a throw.
    var releaseVelocity: CGFloat {
        CACurrentMediaTime() - lastMove < 0.1 ? velocity(in: view).x : 0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touchDown == nil, let first = touches.first { touchDown = first.location(in: view) }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        lastMove = CACurrentMediaTime()
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        touchDown = nil
        lastMove = 0
    }
}
