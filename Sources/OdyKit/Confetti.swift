import SwiftUI

/// A burst of little bindles, stars and squares thrown up and pulled down by gravity — the goal celebration.
public struct ConfettiSystem: Sendable {
    public enum Kind: Hashable, Sendable { case bindle, star, square }

    public struct Particle: Sendable {
        public var x, y, vx, vy, angle, spin, scale: Double
        public var kind: Kind
        public var color: UInt32

        /// Where this particle is `t` seconds after launch — the closed form of `step`, so the view can
        /// draw any instant from the burst's start time without carrying mutable state between frames.
        func at(_ t: Double) -> Particle {
            var p = self
            let k = ConfettiSystem.drag
            p.x = x + vx * (pow(k, t) - 1) / log(k)
            p.y = y + vy * t + 0.5 * ConfettiSystem.gravity * t * t
            p.vx = vx * pow(k, t)
            p.vy = vy + ConfettiSystem.gravity * t
            p.angle = angle + spin * t
            return p
        }
    }

    static let gravity = 900.0
    /// Fraction of horizontal speed left after one second.
    static let drag = 0.6
    static let colors: [UInt32] = [0xE5392E, 0xFFD84A, 0xFFAE1A, 0xFF7E95, 0x4FC1C9]
    public private(set) var particles: [Particle]

    public static func burst(count: Int, origin: CGPoint, seed: UInt64) -> ConfettiSystem {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        let kinds: [Kind] = [.bindle, .star, .star, .square]
        let particles = (0..<count).map { i -> Particle in
            let angle = -Double.pi / 2 + (next() - 0.5) * 1.6
            let speed = 420 + next() * 420
            return Particle(
                x: origin.x + (next() - 0.5) * 40, y: origin.y, vx: cos(angle) * speed, vy: sin(angle) * speed,
                angle: next() * 6, spin: (next() - 0.5) * 10, scale: 0.7 + next() * 0.6, kind: kinds[i % kinds.count],
                color: colors[i % colors.count])
        }
        return ConfettiSystem(particles: particles)
    }

    public mutating func step(_ dt: Double, floor: Double) {
        let drag = pow(Self.drag, dt)
        for i in particles.indices {
            particles[i].vy += Self.gravity * dt
            particles[i].vx *= drag
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].angle += particles[i].spin * dt
        }
        particles.removeAll { $0.y > floor + 40 }
    }

    public var isFinished: Bool { particles.isEmpty }

    /// Seconds until the last particle has fallen below the floor (where `step` would drop it).
    func flightTime(floor: Double) -> Double {
        particles.reduce(0) { latest, p in
            let drop = floor + 40 - p.y
            let t = (-p.vy + (p.vy * p.vy + 2 * Self.gravity * drop).squareRoot()) / Self.gravity
            return max(latest, t)
        }
    }
}

/// Plays a burst each time `trigger` changes. Draws nothing under Reduce Motion.
///
/// The canvas computes each frame from the burst's start time, and the timeline's schedule ends when the
/// last particle has fallen away, so nothing keeps ticking once the confetti is gone.
public struct ConfettiView: View {
    let trigger: Int
    let origin: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst: Burst?

    private struct Burst: Equatable {
        let start: Date
        let seed: UInt64
    }

    /// One date per frame from `start` until `end`, then the timeline stops.
    private struct FrameSchedule: TimelineSchedule {
        let start: Date
        let end: Date

        func entries(from startDate: Date, mode: Mode) -> some Sequence<Date> {
            let first = max(start, startDate)
            return sequence(first: first) { $0.addingTimeInterval(1.0 / 60) }.prefix { $0 < end }
        }
    }

    public init(trigger: Int, origin: UnitPoint = UnitPoint(x: 0.5, y: 0.45)) {
        self.trigger = trigger
        self.origin = origin
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let system = burst.map {
                ConfettiSystem.burst(
                    count: 46, origin: CGPoint(x: origin.x * size.width, y: origin.y * size.height), seed: $0.seed)
            }
            let schedule: FrameSchedule = {
                guard let burst, let system else { return FrameSchedule(start: .distantFuture, end: .distantFuture) }
                return FrameSchedule(
                    start: burst.start, end: burst.start.addingTimeInterval(system.flightTime(floor: size.height)))
            }()
            TimelineView(schedule) { timeline in
                Canvas { context, size in
                    guard let burst, let system else { return }
                    let t = timeline.date.timeIntervalSince(burst.start)
                    guard t >= 0 else { return }
                    for p in system.particles {
                        let now = p.at(t)
                        if now.y <= size.height + 40 { draw(now, in: &context) }
                    }
                }
            }
            .onChange(of: trigger) {
                guard !reduceMotion else { return }
                burst = Burst(start: .now, seed: UInt64(truncatingIfNeeded: trigger))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ p: ConfettiSystem.Particle, in context: inout GraphicsContext) {
        var c = context
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(p.angle))
        c.scaleBy(x: p.scale, y: p.scale)
        switch p.kind {
        case .bindle:
            c.fill(Path(ellipseIn: CGRect(x: -7, y: -5.5, width: 14, height: 11)), with: .color(OdyPalette.bindle))
            c.stroke(SVGPath.path("M-2-5L0-3L2-5"), with: .color(OdyPalette.bindleDark), lineWidth: 1.5)
        case .star:
            c.fill(SVGPath.path("M0-7L1.7-1.7 7 0 1.7 1.7 0 7-1.7 1.7-7 0-1.7-1.7Z"), with: .color(OdyPalette.hex(p.color)))
        case .square:
            c.fill(Path(CGRect(x: -3, y: -3, width: 6, height: 6)), with: .color(OdyPalette.hex(p.color)))
        }
    }
}
