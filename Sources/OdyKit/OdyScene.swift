import SwiftUI

/// The ten states Ody is drawn in. Art ported from the approved mockup (`ody-states-v2.html`), in a 150 × 150 space.
public enum OdyScene: String, CaseIterable, Sendable {
    case rested, tired, active, recovering, hydrating, calm, noData, writing, permission, offline

    public var background: Color {
        switch self {
        case .rested: OdyPalette.hex(0xFFF3C4)
        case .tired: OdyPalette.hex(0xE9E4FB)
        case .active: OdyPalette.hex(0xFFE6B3)
        case .recovering: OdyPalette.hex(0xFFE1E7)
        case .hydrating: OdyPalette.hex(0xDDF4F2)
        case .calm: OdyPalette.hex(0xE3F3DC)
        case .noData: OdyPalette.hex(0xF3EFE6)
        case .writing: OdyPalette.hex(0xFFF2CC)
        case .permission: OdyPalette.hex(0xFFE8E4)
        case .offline: OdyPalette.hex(0xE9EDF5)
        }
    }

    var expression: OdyExpression {
        switch self {
        case .rested, .active: .grin
        case .tired: .sleepy
        case .recovering, .writing: .down
        case .hydrating, .calm: .content
        case .noData: .curious
        case .permission: .happy
        case .offline: .away
        }
    }

    var placement: OdyPlacement {
        switch self {
        case .rested: OdyPlacement(x: 33, y: 44, w: 84, h: 90)
        case .tired: OdyPlacement(x: 40, y: 50, w: 80, h: 85, tilt: -10, pivot: CGPoint(x: 70, y: 110))
        case .active: OdyPlacement(x: 44, y: 46, w: 84, h: 90, tilt: 12, pivot: CGPoint(x: 86, y: 100))
        case .recovering: OdyPlacement(x: 30, y: 42, w: 84, h: 90)
        case .hydrating: OdyPlacement(x: 40, y: 44, w: 84, h: 90)
        case .calm: OdyPlacement(x: 33, y: 44, w: 84, h: 90)
        case .noData: OdyPlacement(x: 28, y: 44, w: 84, h: 90, tilt: -9, pivot: CGPoint(x: 70, y: 100))
        case .writing: OdyPlacement(x: 46, y: 40, w: 84, h: 90)
        case .permission: OdyPlacement(x: 44, y: 44, w: 84, h: 90)
        case .offline: OdyPlacement(x: 34, y: 44, w: 84, h: 90)
        }
    }
}

/// Where Ody stands in a scene: the mockup's `<use>` box (the symbol's viewBox is `200 220 624 660`).
struct OdyPlacement {
    var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    var tilt: Double = 0
    var pivot: CGPoint?

    var bodyRect: CGRect {
        CGRect(
            x: x + (232 - 200) / 624 * w, y: y + (250 - 220) / 660 * h,
            width: 560 / 624 * w, height: 600 / 660 * h)
    }
}

/// One drawn layer: a path, how it is painted, and whether it sits behind or in front of Ody.
struct ArtLayer {
    enum Paint {
        case fill(UInt32, Double = 1)
        /// A radial fade from 90% to clear, filling the path's bounds — the mockup's sun `glow`.
        case glow(UInt32)
        case stroke(UInt32, CGFloat, Double = 1, dash: [CGFloat] = [])
    }

    var d: String
    var paint: Paint
    var front = false
    /// Rotation in degrees about `pivot`, in scene units.
    var rotate: Double = 0
    var pivot: CGPoint = .zero
    /// A looping motion: `.float` drifts up and fades (z's, steam), `.wiggle` rocks (the pencil).
    var motion: Motion = .none

    enum Motion { case none, float, wiggle }
}

enum SceneArt {
    /// An ellipse as path data (no arcs in the parser): four cubic quarters.
    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> String {
        let k: CGFloat = 0.5523
        return "M\(cx - rx) \(cy)C\(cx - rx) \(cy - ry * k) \(cx - rx * k) \(cy - ry) \(cx) \(cy - ry)"
            + "C\(cx + rx * k) \(cy - ry) \(cx + rx) \(cy - ry * k) \(cx + rx) \(cy)"
            + "C\(cx + rx) \(cy + ry * k) \(cx + rx * k) \(cy + ry) \(cx) \(cy + ry)"
            + "C\(cx - rx * k) \(cy + ry) \(cx - rx) \(cy + ry * k) \(cx - rx) \(cy)Z"
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> String { "M\(x) \(y)h\(w)v\(h)h\(-w)Z" }

    static let spark = "M0-10C1-2 2-1 10 0 2 1 1 2 0 10-1 2-2 1-10 0-2-1-1-2 0-10Z"

    /// `spark` moved to (x, y) and scaled to `size` (its box is 20 units).
    static func spark(at x: CGFloat, _ y: CGFloat, size: CGFloat) -> String {
        let s = size / 20
        return "M\(x) \(y - 10 * s)C\(x + 1 * s) \(y - 2 * s) \(x + 2 * s) \(y - 1 * s) \(x + 10 * s) \(y)"
            + "C\(x + 2 * s) \(y + 1 * s) \(x + 1 * s) \(y + 2 * s) \(x) \(y + 10 * s)"
            + "C\(x - 1 * s) \(y + 2 * s) \(x - 2 * s) \(y + 1 * s) \(x - 10 * s) \(y)"
            + "C\(x - 2 * s) \(y - 1 * s) \(x - 1 * s) \(y - 2 * s) \(x) \(y - 10 * s)Z"
    }

    static func layers(_ scene: OdyScene) -> [ArtLayer] {
        switch scene {
        case .rested:
            return [
                ArtLayer(d: ellipse(116, 38, 30, 30), paint: .glow(0xFFD84A)),
                ArtLayer(d: ellipse(116, 38, 14, 14), paint: .fill(0xFFD84A)),
                ArtLayer(d: spark(at: 26, 28, size: 12), paint: .fill(0xFFAE1A)),
                ArtLayer(d: spark(at: 37.5, 47.5, size: 7), paint: .fill(0xFFAE1A)),
                ArtLayer(d: ellipse(75, 134, 40, 6), paint: .fill(0xE9D79A)),
            ]
        case .tired:
            return [
                // A crescent: the mockup's two arcs (r 14 out, r 13 back in) as cubic quarters.
                ArtLayer(d: "M118 22C111.7 22.1 106.2 26.4 104.7 32.5C103.1 38.5 105.7 45 111.2 48.1C116.6 51.3 123.5 50.4 128 46C121.4 48.8 113.8 45.6 111 39C108.2 32.4 111.4 24.8 118 22Z", paint: .fill(0xB9AEF0)),
                ArtLayer(d: ellipse(75, 136, 46, 6), paint: .fill(0xCFC6F2)),
                ArtLayer(d: "M24 104h34c6.6 0 12 5.4 12 12v2c0 6.6-5.4 12-12 12h-34c-6.6 0-12-5.4-12-12v-2c0-6.6 5.4-12 12-12Z", paint: .fill(0xFFFFFF), rotate: -10, pivot: CGPoint(x: 70, y: 110)),
                ArtLayer(d: "M24 104h34c6.6 0 12 5.4 12 12v2c0 6.6-5.4 12-12 12h-34c-6.6 0-12-5.4-12-12v-2c0-6.6 5.4-12 12-12Z", paint: .stroke(0xD9D0F5, 2), rotate: -10, pivot: CGPoint(x: 70, y: 110)),
                ArtLayer(d: "M112 56h10l-10 12h10", paint: .stroke(0x7B6AD0, 3), front: true, motion: .float),
                ArtLayer(d: "M124 44h7l-7 8h7", paint: .stroke(0x7B6AD0, 2.4, 0.6), front: true, motion: .float),
            ]
        case .active:
            return [
                ArtLayer(d: "M14 78h22M8 94h26M18 110h18", paint: .stroke(0xFFFFFF, 5)),
                ArtLayer(d: ellipse(40, 132, 7, 7), paint: .fill(0xF4CF85)),
                ArtLayer(d: ellipse(28, 128, 5, 5), paint: .fill(0xF4CF85)),
                ArtLayer(d: ellipse(86, 136, 38, 5), paint: .fill(0xEBC77A)),
                ArtLayer(d: "M58 50c-5 8-5 13 0 13s5-5 0-13z", paint: .fill(0x7FD3FF), front: true),
            ]
        case .recovering:
            return [
                ArtLayer(d: "M24 104Q72 82 120 104L124 136H20Z", paint: .fill(0xFF9BAE), front: true),
                ArtLayer(d: "M30 112Q72 94 116 112", paint: .stroke(0xFFFFFF, 3, 0.7, dash: [6, 6]), front: true),
                ArtLayer(d: "M109 104h12c2.8 0 5 2.2 5 5v14c0 2.8-2.2 5-5 5h-12c-2.8 0-5-2.2-5-5v-14c0-2.8 2.2-5 5-5Z", paint: .fill(0xFFFFFF), front: true),
                ArtLayer(d: "M126 110c4 0 6 3 6 6s-2 6-6 6", paint: .stroke(0xFFFFFF, 4), front: true),
                ArtLayer(d: "M110 96q-4-6 0-12M118 96q-4-6 0-12", paint: .stroke(0xE7A3B1, 2.5), front: true, motion: .float),
            ]
        case .hydrating:
            return [
                ArtLayer(d: ellipse(120, 34, 4, 4), paint: .fill(0x9ADCD9), motion: .float),
                ArtLayer(d: ellipse(130, 50, 3, 3), paint: .fill(0x9ADCD9), motion: .float),
                ArtLayer(d: ellipse(112, 54, 2.5, 2.5), paint: .fill(0x9ADCD9), motion: .float),
                ArtLayer(d: ellipse(80, 136, 42, 6), paint: .fill(0xBCE4E0)),
                ArtLayer(d: "M30 84h28l-4 46H34z", paint: .fill(0xFFFFFF, 0.95), front: true),
                ArtLayer(d: "M32 98h24l-3 30H35z", paint: .fill(0x4FC1C9), front: true),
                ArtLayer(d: ellipse(42, 110, 2, 2), paint: .fill(0xFFFFFF), front: true),
                ArtLayer(d: ellipse(48, 118, 1.5, 1.5), paint: .fill(0xFFFFFF), front: true),
            ]
        case .calm:
            return [
                ArtLayer(d: ellipse(75, 136, 42, 6), paint: .fill(0xC5E2B8)),
                ArtLayer(d: "M75 48V32", paint: .stroke(0x5DAE6B, 3), front: true),
                ArtLayer(d: "M75 36c-12-2-16-12-14-14 10 0 14 6 14 14z", paint: .fill(0x6CC17A), front: true),
                ArtLayer(d: "M75 34c10-4 16-2 18 0-4 8-12 8-18 0z", paint: .fill(0x86D193), front: true),
                ArtLayer(d: "M118 66c-3-4 3-7 4-2 1-5 7-2 4 2l-4 4z", paint: .fill(0xFF7E95), front: true, motion: .float),
                ArtLayer(d: "M26 74c-2-3 2-5 3-1 1-4 5-2 3 1l-3 3z", paint: .fill(0xFF7E95, 0.7), front: true, motion: .float),
            ]
        case .noData:
            return [
                // The question mark, drawn rather than typeset so it scales with the art.
                ArtLayer(d: "M100 29c1-7 13-7 13 0 0 6-6 6-6 11M107 44.5v1", paint: .stroke(0xC9B78C, 5), rotate: 14, pivot: CGPoint(x: 104, y: 36)),
                ArtLayer(d: ellipse(70, 136, 46, 6), paint: .fill(0xE2DACB)),
                ArtLayer(d: "M96 114h32c2.2 0 4 1.8 4 4v14c0 2.2-1.8 4-4 4h-32c-2.2 0-4-1.8-4-4v-14c0-2.2 1.8-4 4-4Z", paint: .fill(0xFFFFFF), front: true, rotate: -6, pivot: CGPoint(x: 112, y: 125)),
                ArtLayer(d: "M96 114h32c2.2 0 4 1.8 4 4v14c0 2.2-1.8 4-4 4h-32c-2.2 0-4-1.8-4-4v-14c0-2.2 1.8-4 4-4ZM112 114v22", paint: .stroke(0xE2DACB, 2), front: true, rotate: -6, pivot: CGPoint(x: 112, y: 125)),
            ]
        case .writing:
            return [
                ArtLayer(d: "M23 104h52c2.8 0 5 2.2 5 5v24c0 2.8-2.2 5-5 5h-52c-2.8 0-5-2.2-5-5v-24c0-2.8 2.2-5 5-5Z", paint: .fill(0xFFFFFF), rotate: -4, pivot: CGPoint(x: 49, y: 121)),
                ArtLayer(d: "M26 114h40M26 122h32M26 130h22", paint: .stroke(0xEADDB4, 3), rotate: -4, pivot: CGPoint(x: 49, y: 121)),
                ArtLayer(d: rect(52, 74, 10, 44), paint: .fill(0xFFAE1A), front: true, rotate: -38, pivot: CGPoint(x: 60, y: 100), motion: .wiggle),
                ArtLayer(d: rect(52, 74, 10, 7), paint: .fill(0xFF7E95), front: true, rotate: -38, pivot: CGPoint(x: 60, y: 100), motion: .wiggle),
                ArtLayer(d: "M52 118h10l-5 9z", paint: .fill(0xF3D9A8), front: true, rotate: -38, pivot: CGPoint(x: 60, y: 100), motion: .wiggle),
                ArtLayer(d: "M55.5 124h3l-1.5 3z", paint: .fill(0x3A2A00), front: true, rotate: -38, pivot: CGPoint(x: 60, y: 100), motion: .wiggle),
            ]
        case .permission:
            return [
                ArtLayer(d: ellipse(80, 136, 42, 6), paint: .fill(0xF3CEC7)),
                ArtLayer(d: "M40 120c-22-16-24-34-10-38 6-2 10 2 10 6 0-4 4-8 10-6 14 4 12 22-10 38z", paint: .fill(0xE5392E), front: true),
                ArtLayer(d: ellipse(40, 98, 4, 4), paint: .fill(0xFFFFFF, 0.9), front: true),
                ArtLayer(d: "M38 100h4l1 8h-6z", paint: .fill(0xFFFFFF, 0.9), front: true),
            ]
        case .offline:
            return [
                ArtLayer(d: "M0 132Q75 122 150 132V150H0z", paint: .fill(0xD7DDEA)),
                ArtLayer(d: "M44 96L22 42", paint: .stroke(0x9C7448, 5)),
                ArtLayer(d: "M8 42c0-14 30-14 30 0 0 12-30 12-30 0z", paint: .fill(0xE5392E)),
                ArtLayer(d: "M18 34l5 6 5-6", paint: .stroke(0xB82A22, 3)),
                ArtLayer(d: "M128 92h12M124 100h16", paint: .stroke(0xFFFFFF, 3), front: true),
            ]
        }
    }
}

/// A scene, square, at any size. Ody in it is alive (breathing, blinking); looping props move unless Reduce Motion.
public struct OdySceneView: View {
    let scene: OdyScene
    let showsBackground: Bool
    let pokable: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ scene: OdyScene, showsBackground: Bool = true, pokable: Bool = false) {
        self.scene = scene
        self.showsBackground = showsBackground
        self.pokable = pokable
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let s = side / 150
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    if showsBackground { scene.background }
                    art(front: false, scale: s, time: t)
                    ody(scale: s)
                    art(front: true, scale: s, time: t)
                }
                .frame(width: side, height: side)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func ody(scale s: CGFloat) -> some View {
        let p = scene.placement
        let r = p.bodyRect
        return OdyView(expression: scene.expression, pokable: pokable, seed: UInt64(OdyScene.allCases.firstIndex(of: scene)! + 1))
            .frame(width: r.width * s, height: r.height * s)
            .rotationEffect(
                .degrees(p.tilt),
                anchor: p.pivot.map { UnitPoint(x: ($0.x - r.minX) / r.width, y: ($0.y - r.minY) / r.height) } ?? .bottom)
            .offset(x: r.minX * s, y: r.minY * s)
    }

    private func art(front: Bool, scale s: CGFloat, time t: TimeInterval) -> some View {
        Canvas { context, _ in
            context.scaleBy(x: s, y: s)
            for layer in SceneArt.layers(scene) where layer.front == front {
                var ctx = context
                if layer.rotate != 0 || layer.motion == .wiggle {
                    let wiggle = layer.motion == .wiggle ? sin(t * 2 * .pi / 0.6) * 4 : 0
                    ctx.translateBy(x: layer.pivot.x, y: layer.pivot.y)
                    ctx.rotate(by: .degrees(layer.rotate + wiggle))
                    ctx.translateBy(x: -layer.pivot.x, y: -layer.pivot.y)
                }
                if layer.motion == .float {
                    let phase = (t / 2).truncatingRemainder(dividingBy: 1)
                    ctx.translateBy(x: phase * 6, y: -phase * 10)
                    ctx.opacity = 1 - phase * 0.8
                }
                let path = SVGPath.path(layer.d)
                switch layer.paint {
                case .fill(let hex, let opacity):
                    ctx.fill(path, with: .color(OdyPalette.hex(hex, opacity)))
                case .glow(let hex):
                    let box = path.boundingRect
                    ctx.fill(
                        path,
                        with: .radialGradient(
                            Gradient(colors: [OdyPalette.hex(hex, 0.9), OdyPalette.hex(hex, 0)]),
                            center: CGPoint(x: box.midX, y: box.midY), startRadius: 0, endRadius: box.width / 2))
                case .stroke(let hex, let width, let opacity, let dash):
                    ctx.stroke(
                        path, with: .color(OdyPalette.hex(hex, opacity)),
                        style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
