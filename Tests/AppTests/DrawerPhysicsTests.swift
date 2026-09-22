import CoreGraphics
import Testing

// The app target ships as `Exodus`, so that — not `App` — is the module name to import.
@testable import Exodus

/// A phone-sized drawer: 402 pt wide screen × 0.78.
private let width: CGFloat = 313

@Suite("DrawerPhysics.project")
struct DrawerPhysicsProjectionTests {
    @Test("a still finger projects nowhere")
    func zeroVelocityProjectsNothing() {
        #expect(DrawerPhysics.project(velocity: 0) == 0)
    }

    @Test("the projection is Apple's exponential decay, not the textbook one")
    func projectionMatchesTheDecayFormula() {
        // (1000/1000) × 0.998 / 0.002 = 499 pt for one point per millisecond.
        #expect(abs(DrawerPhysics.project(velocity: 1000) - 499) < 0.001)
        #expect(abs(DrawerPhysics.project(velocity: -1000) + 499) < 0.001)
    }

    @Test("a slower deceleration rate throws further")
    func decelerationRateOrdersTheProjection() {
        #expect(DrawerPhysics.project(velocity: 800, decelerationRate: 0.998)
            > DrawerPhysics.project(velocity: 800, decelerationRate: 0.99))
    }
}

@Suite("DrawerPhysics.endsOpen")
struct DrawerPhysicsReleaseTests {
    @Test("a flick opens the drawer from a travel that would never reach the midpoint")
    func aFlickOpensFromAShortTravel() {
        // 30 pt of travel, a tenth of the way, but thrown at 1200 pt/s.
        #expect(DrawerPhysics.endsOpen(offset: 30, velocity: 1200, drawerWidth: width))
    }

    @Test("a slow drag 40% of the way falls back closed")
    func aSlowFortyPercentDragCloses() {
        #expect(!DrawerPhysics.endsOpen(offset: width * 0.4, velocity: 0, drawerWidth: width))
    }

    @Test("a slow drag past the midpoint opens")
    func aSlowDragPastTheMidpointOpens() {
        #expect(DrawerPhysics.endsOpen(offset: width * 0.6, velocity: 0, drawerWidth: width))
    }

    @Test("a leftward flick closes even from past the midpoint")
    func aLeftwardVelocityBeatsPosition() {
        #expect(!DrawerPhysics.endsOpen(offset: width * 0.8, velocity: -900, drawerWidth: width))
    }

    @Test("a rightward flick opens even from short of the midpoint, closed or open")
    func aRightwardVelocityBeatsPosition() {
        #expect(DrawerPhysics.endsOpen(offset: width * 0.2, velocity: 900, drawerWidth: width))
    }

    @Test("a release at the open position stays open")
    func aReleaseAtTheOpenPositionStaysOpen() {
        #expect(DrawerPhysics.endsOpen(offset: width, velocity: 0, drawerWidth: width))
    }

    @Test("exactly on the midpoint, at rest, the drawer falls closed")
    func theMidpointItselfBelongsToClosed() {
        // The rule is strictly past the midpoint, not at it: a card let go of at dead centre has
        // not been taken half-way *and* a bit, so it goes back.
        #expect(!DrawerPhysics.endsOpen(offset: width / 2, velocity: 0, drawerWidth: width))
        #expect(DrawerPhysics.endsOpen(offset: width / 2 + 0.01, velocity: 0, drawerWidth: width))
    }
}

@Suite("DrawerPhysics.handoffVelocity")
struct DrawerPhysicsHandoffTests {
    @Test("inside the travel the finger's velocity is handed over untouched")
    func insideTheTravelNothingIsSuppressed() {
        #expect(DrawerPhysics.handoffVelocity(1200, at: 100, drawerWidth: width) == 1200)
        #expect(DrawerPhysics.handoffVelocity(-1200, at: 100, drawerWidth: width) == -1200)
        #expect(DrawerPhysics.handoffVelocity(1200, at: 0, drawerWidth: width) == 1200)
        #expect(DrawerPhysics.handoffVelocity(1200, at: width, drawerWidth: width) == 1200)
    }

    @Test("past the open edge, still moving outward, hands over nothing")
    func pastTheOpenEdgeMovingOutIsSuppressed() {
        #expect(DrawerPhysics.handoffVelocity(1200, at: width + 27, drawerWidth: width) == 0)
        #expect(DrawerPhysics.handoffVelocity(2000, at: width + 1, drawerWidth: width) == 0)
    }

    @Test("past the open edge, coming back, keeps its velocity")
    func pastTheOpenEdgeComingBackIsKept() {
        #expect(DrawerPhysics.handoffVelocity(-900, at: width + 27, drawerWidth: width) == -900)
    }

    @Test("the closed end is mirrored")
    func theClosedEndIsMirrored() {
        #expect(DrawerPhysics.handoffVelocity(-1200, at: -5, drawerWidth: width) == 0)
        #expect(DrawerPhysics.handoffVelocity(900, at: -5, drawerWidth: width) == 900)
    }

    @Test("the case the suppression must not eat: let go drifting back, but the drawer still opens")
    func aReleaseDriftingAwayInsideTheTravelKeepsItsHandoff() {
        // 280 pt along, moving left at 200 pt/s: the projection lands at 180, still past the
        // midpoint, so the drawer opens — and the card really is drifting the other way as it does.
        let offset: CGFloat = 280
        let velocity: CGFloat = -200
        #expect(DrawerPhysics.endsOpen(offset: offset, velocity: velocity, drawerWidth: width))
        let handoff = DrawerPhysics.handoffVelocity(velocity, at: offset, drawerWidth: width)
        #expect(handoff == velocity)
        #expect(DrawerPhysics.normalisedVelocity(handoff, from: offset, to: width) < 0)
    }

    @Test("a fast release past the open edge asks the spring for no motion at all")
    func theWholeChainIsSafePastTheOpenEdge() {
        // What used to happen: 27 pt past open at 1200 pt/s normalised to -43.8, which is "cross
        // the remaining gap backwards forty-three times a second".
        let offset = width + 27
        #expect(DrawerPhysics.normalisedVelocity(1200, from: offset, to: width) < -40)
        let handoff = DrawerPhysics.handoffVelocity(1200, at: offset, drawerWidth: width)
        #expect(DrawerPhysics.normalisedVelocity(handoff, from: offset, to: width) == 0)
    }
}

@Suite("DrawerPhysics.velocityIsFresh")
struct DrawerPhysicsStalenessTests {
    @Test("a release in the same breath as the last touch event keeps its velocity")
    func aPromptReleaseIsFresh() {
        #expect(DrawerPhysics.velocityIsFresh(lastEvent: 10, release: 10))
        #expect(DrawerPhysics.velocityIsFresh(lastEvent: 10, release: 10.05))
    }

    @Test("a release after a pause does not")
    func aPausedReleaseIsStale() {
        #expect(!DrawerPhysics.velocityIsFresh(lastEvent: 10, release: 10.2))
        // The 599 ms that opened a drawer nobody had thrown.
        #expect(!DrawerPhysics.velocityIsFresh(lastEvent: 10, release: 10.599))
    }

    @Test("the window is the named constant, either side of it")
    func theWindowIsTheNamedConstant() {
        // Not asserted at the boundary itself: 10 + 0.1 - 10 is 0.09999999999999964 in binary
        // floating point, so the exact edge is a fact about doubles, not about the drawer.
        let window = DrawerPhysics.velocityStaleAfter
        #expect(DrawerPhysics.velocityIsFresh(lastEvent: 10, release: 10 + window - 0.001))
        #expect(!DrawerPhysics.velocityIsFresh(lastEvent: 10, release: 10 + window + 0.001))
    }
}

@Suite("DrawerPhysics.rubberBand and resistedOffset")
struct DrawerPhysicsResistanceTests {
    @Test("before the open edge the card is exactly where the finger is")
    func theCardIsOneToOneBeforeTheEdge() {
        for wanted in stride(from: CGFloat(0), through: width, by: 20) {
            #expect(DrawerPhysics.resistedOffset(wanted, drawerWidth: width) == wanted)
        }
    }

    @Test("the closed end is a hard wall: never a negative offset")
    func theClosedEndDoesNotRubberBand() {
        #expect(DrawerPhysics.resistedOffset(-1, drawerWidth: width) == 0)
        #expect(DrawerPhysics.resistedOffset(-400, drawerWidth: width) == 0)
    }

    @Test("past the open edge the card keeps moving, but always less than the finger")
    func pastTheEdgeTheCardResists() {
        let past = DrawerPhysics.resistedOffset(width + 100, drawerWidth: width)
        #expect(past > width)
        #expect(past < width + 100)
    }

    @Test("resistance is monotonic: more finger is always more card")
    func resistanceIsMonotonic() {
        var previous = DrawerPhysics.resistedOffset(0, drawerWidth: width)
        for wanted in stride(from: CGFloat(1), through: width * 3, by: 3) {
            let next = DrawerPhysics.resistedOffset(wanted, drawerWidth: width)
            #expect(next > previous)
            previous = next
        }
    }

    @Test("resistance is bounded: the card cannot be pulled a second drawer width out")
    func resistanceIsBounded() {
        // A thousand screens of pull still buys less than one more drawer width of card.
        #expect(DrawerPhysics.resistedOffset(width * 1000, drawerWidth: width) < width * 2)
        // The whole of a 402 pt screen is only ~90 pt past the open position: about 42 pt of card.
        #expect(DrawerPhysics.resistedOffset(width + 90, drawerWidth: width) < width + 50)
    }

    @Test("the first point past the edge still follows the finger almost exactly")
    func theResistanceStartsGently() {
        let slack = DrawerPhysics.resistedOffset(width + 1, drawerWidth: width) - width
        #expect(slack > 0.5)
        #expect(slack < 1)
    }

    @Test("a zero-width drawer resists everything")
    func aZeroWidthDrawerIsSafe() {
        #expect(DrawerPhysics.resistedOffset(100, drawerWidth: 0) == 0)
        #expect(DrawerPhysics.rubberBand(overshoot: 100, dimension: 0) == 0)
    }
}

@Suite("DrawerPhysics.normalisedVelocity")
struct DrawerPhysicsVelocityHandoffTests {
    @Test("the velocity is measured in journeys per second")
    func theVelocityIsAFractionOfTheDistanceLeft() {
        #expect(DrawerPhysics.normalisedVelocity(600, from: 100, to: 400) == 2)
    }

    @Test("moving toward the target is positive whichever way the card is going")
    func theSignFollowsTheDirectionOfTravel() {
        // Opening: card at 100, target 313, finger moving right.
        #expect(DrawerPhysics.normalisedVelocity(900, from: 100, to: width) > 0)
        // Closing: card at 200, target 0, finger moving left — still travelling toward the target.
        #expect(DrawerPhysics.normalisedVelocity(-900, from: 200, to: 0) > 0)
    }

    @Test("a velocity away from the target is negative")
    func aVelocityAwayFromTheTargetIsNegative() {
        // Released moving left, but the projection still put the drawer open.
        #expect(DrawerPhysics.normalisedVelocity(-300, from: 200, to: width) < 0)
    }

    @Test("a distance under a point hands off no velocity at all")
    func aTinyDistanceIsGuarded() {
        #expect(DrawerPhysics.normalisedVelocity(2000, from: width, to: width) == 0)
        #expect(DrawerPhysics.normalisedVelocity(2000, from: width - 0.4, to: width) == 0)
        #expect(DrawerPhysics.normalisedVelocity(2000, from: width - 1, to: width) == 2000)
    }
}
