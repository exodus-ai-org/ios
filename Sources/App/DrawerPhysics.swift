import CoreGraphics

/// The drawer's physics, with no SwiftUI and no UIKit in it, so the numbers can be read, reasoned
/// about and tested on their own. Everything here is a pure function of its arguments.
///
/// The model: the card's offset runs from 0 (closed) to `drawerWidth` (open). The closed end is a
/// hard wall — there is nothing to the left of a full-screen card, so the offset never goes
/// negative. The open end is soft: the finger may carry on, and the card follows with progressively
/// less of the travel, the way a scroll view resists past its last page.
enum DrawerPhysics {
    /// UIScrollView's own deceleration rate, and the one Apple's *Designing Fluid Interfaces*
    /// sample uses to project where a flick is heading. 0.99 would make the projection shorter and
    /// the drawer harder to flick open.
    static let decelerationRate: CGFloat = 0.998

    /// The distance a release at `velocity` (points per second) would still travel before friction
    /// stopped it. Exponential decay, not the textbook `v² / 2a`: this is the form iOS ships, and
    /// it is what makes a short flick throw the card the whole way.
    static func project(velocity: CGFloat, decelerationRate rate: CGFloat = decelerationRate) -> CGFloat {
        (velocity / 1000) * rate / (1 - rate)
    }

    /// How far past a boundary something follows the finger: all of the first point, less and less
    /// after that, never more than `dimension` in total however hard the finger pulls.
    static func rubberBand(overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        guard dimension > 0 else { return 0 }
        return (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }

    /// The card's offset for the offset the finger asks for: 1:1 between the two ends, a hard stop
    /// at the closed end, rubber-banding past the open one.
    static func resistedOffset(_ wanted: CGFloat, drawerWidth: CGFloat) -> CGFloat {
        guard drawerWidth > 0 else { return 0 }
        if wanted <= 0 { return 0 }
        if wanted <= drawerWidth { return wanted }
        return drawerWidth + rubberBand(overshoot: wanted - drawerWidth, dimension: drawerWidth)
    }

    /// Where a release lands. Velocity decides, not distance: the finger's momentum is projected
    /// forward and the nearer of the two resting places wins, so a quick flick from 10 pt opens the
    /// drawer and a slow drag two thirds of the way back falls closed.
    static func endsOpen(offset: CGFloat, velocity: CGFloat, drawerWidth: CGFloat) -> Bool {
        offset + project(velocity: velocity) > drawerWidth / 2
    }

    /// The velocity to hand the settle's spring, which is not always the velocity the finger had.
    ///
    /// Past a boundary the card is only there because the rubber band let it be: the band is already
    /// stretched and already pulling back, so a finger that lets go while still dragging outward
    /// hands over no outward momentum — it hands over a band that snaps home, which is what a
    /// stretched thing does. Without this the spring is told to keep going the way the finger was:
    /// a release 27 pt past the open position at 1200 pt/s asks it to travel that 27 pt backwards
    /// forty-three times a second, and the card is thrown most of a screen further out before it
    /// comes back.
    ///
    /// Only that direction is suppressed. A release *inside* the travel moving away from where the
    /// projection says it is going — let go drifting left, but fast enough earlier that the drawer
    /// still opens — is a real handoff and keeps working; it is negative too, which is why the sign
    /// alone cannot be the test.
    static func handoffVelocity(_ velocity: CGFloat, at offset: CGFloat, drawerWidth: CGFloat) -> CGFloat {
        if offset > drawerWidth, velocity > 0 { return 0 }
        if offset < 0, velocity < 0 { return 0 }
        return velocity
    }

    /// `Animation.interpolatingSpring(_:initialVelocity:)` wants the release velocity as a fraction
    /// of the distance left to travel, so that handing it 1 means "one journey per second". Dividing
    /// by the distance also gets the sign right for free: a velocity pointing at the target is
    /// positive whichever way the card is going.
    ///
    /// Near zero distance the division explodes and the spring would fling the card across the
    /// screen to cover half a point, so under a point the handoff is dropped — nothing the eye
    /// could have seen is lost with it.
    static func normalisedVelocity(_ velocity: CGFloat, from current: CGFloat, to target: CGFloat) -> Double {
        let distance = target - current
        guard abs(distance) >= 1 else { return 0 }
        return Double(velocity / distance)
    }
}
