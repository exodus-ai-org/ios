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
            let slope = tilt * (x - width / 2) * 0.32
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
    var goal = 8
    let onLog: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = TiltSource()
    @State private var splash: Date = .distantPast

    var body: some View {
        Button(action: log) {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let since = timeline.date.timeIntervalSince(splash)
                let amplitude = reduceMotion ? 0 : 1.2 + 6 * CGFloat(exp(-since * 1.4))
                Canvas { context, size in
                    let glass = SVGPath.path("M0 0h34l-4 54H4z")
                        .applying(CGAffineTransform(scaleX: size.width / 34, y: size.height / 54))
                    context.fill(glass, with: .color(.white.opacity(0.55)))
                    var water = Path()
                    let pts = WaterSurface.points(
                        width: size.width, height: size.height, level: CGFloat(cups) / CGFloat(goal),
                        tilt: reduceMotion ? 0 : CGFloat(tilt.tilt), amplitude: amplitude, phase: CGFloat(t * 4))
                    water.move(to: CGPoint(x: 0, y: size.height))
                    pts.forEach { water.addLine(to: $0) }
                    water.addLine(to: CGPoint(x: size.width, y: size.height))
                    water.closeSubpath()
                    context.clip(to: glass)
                    context.fill(water, with: .color(OdyPalette.hex(0x2A9BA6)))
                }
                .overlay {
                    SVGPathShape(d: "M0 0h34l-4 54H4z", box: CGSize(width: 34, height: 54)).stroke(.white, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(34.0 / 54.0, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: cups)
        .sensoryFeedback(.success, trigger: cups >= goal) { old, new in !old && new }
        .onAppear { if !reduceMotion { tilt.start() } }
        .onDisappear { tilt.stop() }
        .accessibilityLabel(Text("ios:health.water.log"))
        .accessibilityValue(Text(verbatim: CategoryValue.cups(cups)))
    }

    private func log() {
        splash = Date()
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
