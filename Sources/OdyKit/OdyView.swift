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
    @State private var squash: CGFloat = 1

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

    /// A pull can't flip or collapse Ody; below half height `1 / sqrt` would also blow up.
    static func clampedStretch(_ v: CGFloat) -> CGFloat { max(v, 0.5) }
    static func clampedTiredness(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
    /// How far the eyes can open: fully tired is half-lidded, which still reads at card size.
    static func eyeCap(tiredness: CGFloat) -> CGFloat { 1 - 0.5 * clampedTiredness(tiredness) }

    public var body: some View {
        let figure = TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cap = Self.eyeCap(tiredness: tiredness)
            let open = reduceMotion ? cap : blink.openness(at: t) * cap
            let breath = reduceMotion ? 1 : Breath.scale(at: t)
            let stretch = Self.clampedStretch(stretch)
            OdyFigure(expression: expression, openness: open, look: look)
                .scaleEffect(x: 1 / sqrt(stretch), y: stretch * breath, anchor: .bottom)
        }
        .scaleEffect(x: 1 + (1 - squash) * 0.8, y: squash, anchor: .bottom)
        .accessibilityHidden(true)

        if pokable {
            figure
                .contentShape(Rectangle())
                .onTapGesture(perform: poke)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: pokes)
        } else {
            figure
        }
    }

    /// The haptic always fires; Reduce Motion only drops the squash. A new poke retargets the spring from wherever
    /// the last one is, so it never pops back to rest first.
    private func poke() {
        pokes += 1
        onPoke?()
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 0.06)) {
            squash = 0.8
        } completion: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) { squash = 1 }
        }
    }
}
