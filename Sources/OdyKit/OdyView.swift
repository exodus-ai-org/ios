import SwiftUI

/// When Ody blinks: once in each 3.7 s cell, at a seeded offset, for 0.24 s (closing, then opening).
public struct BlinkSchedule: Sendable {
    public static let cell: TimeInterval = 3.7
    public static let duration: TimeInterval = 0.24
    let seed: UInt64

    public init(seed: UInt64) { self.seed = seed }

    public func openness(at t: TimeInterval) -> CGFloat {
        let index = Int((t / Self.cell).rounded(.down))
        for k in [index - 1, index] {
            let start = Double(k) * Self.cell + 0.3 + unit(k) * (Self.cell - 0.3 - Self.duration)
            let d = t - start
            if d >= 0, d < Self.duration { return CGFloat(abs(d - Self.duration / 2) / (Self.duration / 2)) }
        }
        return 1
    }

    /// SplitMix64 of the seed and the cell, as 0..<1.
    private func unit(_ k: Int) -> Double {
        var z = seed &+ UInt64(bitPattern: Int64(k)) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

/// A slow, small breath: 1 ± 1.2 % over four seconds.
public enum Breath {
    public static func scale(at t: TimeInterval) -> CGFloat { 1 + 0.012 * CGFloat(sin(2 * .pi * t / 4)) }
}

/// Ody, alive: breathes and blinks while on screen, follows `look`, and squashes and springs back when poked (with a
/// soft haptic). Under Reduce Motion it holds still, eyes open. `stretch` lets a pull gesture elongate it from the feet.
public struct OdyView: View {
    var expression: OdyExpression
    var look: CGVector
    var tiredness: CGFloat
    var stretch: CGFloat
    var pokable: Bool
    var onPoke: (() -> Void)?
    private let blink: BlinkSchedule

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pokes = 0

    public init(
        expression: OdyExpression, look: CGVector = .zero, tiredness: CGFloat = 0, stretch: CGFloat = 1,
        pokable: Bool = true, seed: UInt64 = 1, onPoke: (() -> Void)? = nil
    ) {
        self.expression = expression
        self.look = look
        self.tiredness = tiredness
        self.stretch = stretch
        self.pokable = pokable
        self.onPoke = onPoke
        self.blink = BlinkSchedule(seed: seed)
    }

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cap = 1 - 0.38 * tiredness
            let open = reduceMotion ? cap : blink.openness(at: t) * cap
            let breath = reduceMotion ? 1 : Breath.scale(at: t)
            OdyFigure(expression: expression, openness: open, look: look)
                .scaleEffect(x: 1 / sqrt(stretch), y: stretch * breath, anchor: .bottom)
        }
        .keyframeAnimator(initialValue: CGFloat(1), trigger: pokes) { content, squash in
            content.scaleEffect(x: 1 + (1 - squash) * 0.8, y: squash, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.8, duration: 0.06)
                SpringKeyframe(1, duration: 0.7, spring: Spring(response: 0.4, dampingRatio: 0.45))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard pokable else { return }
            if !reduceMotion { pokes += 1 }
            onPoke?()
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: pokes)
        .accessibilityHidden(true)
    }
}
