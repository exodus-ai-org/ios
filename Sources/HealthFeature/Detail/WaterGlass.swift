import CoreMotion
import OdyKit
import SwiftUI

enum WaterSurface {
    /// The water's top edge across a glass: its level, a gentle wave, and a slope that follows the phone's tilt.
    static func points(width: CGFloat, height: CGFloat, level: CGFloat, tilt: CGFloat, amplitude: CGFloat, phase: CGFloat)
        -> [CGPoint]
    {
        let base = height * (1 - min(max(level, 0), 1))
        return stride(from: CGFloat(0), through: width, by: 2).map { x in
            let wave = sin(x * 0.22 + phase) * amplitude
            // tilt > 0 is the phone leaning right (gravity.x > 0): the right edge goes down, so the water stands higher there.
            let slope = -tilt * (x - width / 2) * 0.32
            return CGPoint(x: x, y: min(height, max(0, base + wave + slope)))
        }
    }
}

/// How far the phone leans left or right, from Core Motion's gravity, smoothed. Needs no permission.
@MainActor
@Observable
final class TiltSource {
    private(set) var tilt: Double = 0
    @ObservationIgnored private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            self.tilt += (max(-1, min(1, g.x * 1.6)) - self.tilt) * 0.2
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

/// Tap to log a cup (250 ml to Apple Health). The water rises with a splash and leans as the phone leans.
struct WaterGlassView: View {
    let cups: Int
    let goal: Int
    let onLog: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = TiltSource()
    @State private var splash: Date = .distantPast
    @State private var logs = 0
    @State private var goalHits = 0
    /// The level the water is rising from, and when the rise began, so the Canvas can follow a spring per frame.
    @State private var levelFrom: CGFloat
    @State private var levelSince: Date = .distantPast

    private static let outline = "M0 0h34l-4 54H4z"
    private static let glass = SVGPath.path(outline)

    init(cups: Int, goal: Int = 8, onLog: @escaping () -> Void) {
        self.cups = cups
        self.goal = goal
        self.onLog = onLog
        _levelFrom = State(initialValue: Self.level(cups: cups, goal: goal))
    }

    private static func level(cups: Int, goal: Int) -> CGFloat {
        goal > 0 ? min(max(CGFloat(cups) / CGFloat(goal), 0), 1) : 0
    }

    /// An under-damped spring (response 0.5 s, damping 0.7) from 0 to 1.
    static func spring(_ t: Double) -> CGFloat {
        guard t > 0 else { return 0 }
        let w = 2 * Double.pi / 0.5, z = 0.7
        let wd = w * (1 - z * z).squareRoot()
        return CGFloat(1 - exp(-z * w * t) * (cos(wd * t) + z * w / wd * sin(wd * t)))
    }

    var body: some View {
        Button(action: log) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let since = timeline.date.timeIntervalSince(splash)
                let amplitude = reduceMotion ? 0 : 1.2 + 6 * CGFloat(exp(-since * 1.4))
                let target = Self.level(cups: cups, goal: goal)
                let level =
                    reduceMotion
                    ? target : levelFrom + (target - levelFrom) * Self.spring(timeline.date.timeIntervalSince(levelSince))
                Canvas { context, size in
                    let glass = Self.glass.applying(CGAffineTransform(scaleX: size.width / 34, y: size.height / 54))
                    context.fill(glass, with: .color(.white.opacity(0.55)))
                    var water = Path()
                    let pts = WaterSurface.points(
                        width: size.width, height: size.height, level: level,
                        tilt: reduceMotion ? 0 : CGFloat(tilt.tilt), amplitude: amplitude, phase: CGFloat(t * 4))
                    water.move(to: CGPoint(x: 0, y: size.height))
                    pts.forEach { water.addLine(to: $0) }
                    water.addLine(to: CGPoint(x: size.width, y: size.height))
                    water.closeSubpath()
                    context.clip(to: glass)
                    context.fill(water, with: .color(OdyPalette.hex(0x2A9BA6)))
                }
                .overlay {
                    SVGPathShape(d: Self.outline, box: CGSize(width: 34, height: 54)).stroke(.white, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(34.0 / 54.0, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: logs)
        .sensoryFeedback(.success, trigger: goalHits)
        .onChange(of: cups) { old, _ in
            // Rise from wherever the surface is now, not from the old target, so quick taps don't jump.
            let now = Date()
            let from = levelFrom + (Self.level(cups: old, goal: goal) - levelFrom) * Self.spring(now.timeIntervalSince(levelSince))
            levelFrom = from
            levelSince = now
        }
        .onAppear { if !reduceMotion { tilt.start() } }
        .onDisappear { tilt.stop() }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { tilt.stop() } else { tilt.start() }
        }
        .accessibilityLabel(Text("ios:health.water.log"))
        .accessibilityValue(Text(verbatim: CategoryValue.cups(cups)))
    }

    private func log() {
        splash = Date()
        logs += 1
        if cups < goal, cups + 1 >= goal { goalHits += 1 }
        onLog()
    }
}

/// A path-data string as a `Shape`, scaled from its design box to the frame.
struct SVGPathShape: Shape {
    let d: String
    let box: CGSize

    func path(in rect: CGRect) -> Path {
        SVGPath.path(d).applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / box.width, y: rect.height / box.height))
    }
}
