import SwiftUI

/// One heartbeat's trace as a sum of bumps: P, a small Q dip, the R spike, S, and T. Mirrored in `HeartbeatWave.metal`.
public enum ECG {
    static func bump(_ x: Double, _ center: Double, _ width: Double, _ height: Double) -> Double {
        height * exp(-pow((x - center) / width, 2))
    }

    public static func value(phase: Double) -> Double {
        let x = phase - phase.rounded(.down)
        return bump(x, 0.18, 0.025, 0.12) + bump(x, 0.275, 0.008, -0.12) + bump(x, 0.3, 0.012, 1.0)
            + bump(x, 0.325, 0.01, -0.22) + bump(x, 0.5, 0.05, 0.25)
    }
}

/// The recovery page's living line: a glowing trace that beats at the user's resting heart rate.
public struct HeartbeatWave: View {
    let bpm: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(bpm: Double, color: Color) {
        self.bpm = bpm
        self.color = color
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : Float(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
            if let library = HeartbeatShader.library {
                Rectangle()
                    .fill(color)
                    .visualEffect { content, proxy in
                        content.colorEffect(library.heartbeatWave(.float2(proxy.size), .float(time), .float(Float(bpm))))
                    }
            } else {
                Canvas { context, size in
                    var path = Path()
                    let beats = 2.5
                    for i in 0...Int(size.width) {
                        let x = Double(i)
                        let phase = x / size.width * beats + Double(time) * bpm / 60
                        let y = size.height * (0.6 - 0.45 * ECG.value(phase: phase))
                        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

enum HeartbeatShader {
    private final class Marker {}

    /// `ExodusIos_OdyKit.bundle`, looked up by hand as `ImageFormingShader` does: no bundle, the Canvas fallback.
    static let library: ShaderLibrary? = {
        let name = "ExodusIos_OdyKit.bundle"
        for base in [Bundle.main.resourceURL, Bundle(for: Marker.self).resourceURL] {
            guard let url = base?.appendingPathComponent(name), let bundle = Bundle(url: url),
                bundle.url(forResource: "default", withExtension: "metallib") != nil
            else { continue }
            return ShaderLibrary.bundle(bundle)
        }
        return nil
    }()
}
