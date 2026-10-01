import SwiftUI

/// Ody's body as `brand/art.mjs` draws it on its 1024 canvas; everything here is in those units, mapped onto a rect.
enum OdyGeometry {
    static let box = CGRect(x: 232, y: 250, width: 560, height: 600)
    static let aspect: CGFloat = box.width / box.height

    static func map(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (x - box.minX) / box.width * rect.width,
            y: rect.minY + (y - box.minY) / box.height * rect.height)
    }

    static func scale(in rect: CGRect) -> CGFloat { rect.width / box.width }
}

/// The gumdrop: a dome on a softly rounded base.
public struct OdyBodyShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let m = { (x: CGFloat, y: CGFloat) in OdyGeometry.map(x, y, in: rect) }
        var p = Path()
        p.move(to: m(232, 800))
        p.addCurve(to: m(512, 250), control1: m(232, 480), control2: m(330, 250))
        p.addCurve(to: m(792, 800), control1: m(694, 250), control2: m(792, 480))
        p.addCurve(to: m(730, 850), control1: m(792, 836), control2: m(770, 850))
        p.addLine(to: m(294, 850))
        p.addCurve(to: m(232, 800), control1: m(254, 850), control2: m(232, 836))
        p.closeSubpath()
        return p
    }
}

public enum OdyExpression: CaseIterable, Sendable {
    case happy, grin, sleepy, content, curious, down, away, yawn
}

/// What a face is made of, per expression — the mockup's `face-*` symbols.
struct OdyFace: Equatable {
    enum Eyes: Equatable { case open, sleepyArcs, smileArcs }
    enum Mouth: Equatable { case smile, grin, dot, ring, wide, small, smileRight }

    var eyes: Eyes
    var mouth: Mouth
    /// Where the eyes sit relative to the happy face, in art units.
    var eyeOffset: CGVector = .zero
    var eyeScale: CGFloat = 1
    /// The most the eyes open (a yawn squints).
    var opennessCap: CGFloat = 1

    static func of(_ e: OdyExpression) -> OdyFace {
        switch e {
        case .happy: OdyFace(eyes: .open, mouth: .smile)
        case .grin: OdyFace(eyes: .open, mouth: .grin, eyeOffset: CGVector(dx: 0, dy: -6), eyeScale: 1.05)
        case .sleepy: OdyFace(eyes: .sleepyArcs, mouth: .dot)
        case .content: OdyFace(eyes: .smileArcs, mouth: .smile)
        case .curious: OdyFace(eyes: .open, mouth: .ring, eyeOffset: CGVector(dx: -6, dy: -14), eyeScale: 0.82)
        case .down: OdyFace(eyes: .open, mouth: .small, eyeOffset: CGVector(dx: -12, dy: 34), eyeScale: 0.78)
        case .away: OdyFace(eyes: .open, mouth: .smileRight, eyeOffset: CGVector(dx: 38, dy: -6), eyeScale: 0.93)
        case .yawn: OdyFace(eyes: .open, mouth: .wide, opennessCap: 0.18)
        }
    }
}

/// Ody, drawn once: body, light, blush and a face. Stateless and animatable (openness and look interpolate); the
/// living behaviour is `OdyView`'s.
public struct OdyFigure: View, Animatable {
    var expression: OdyExpression
    var openness: CGFloat
    var look: CGVector

    public init(expression: OdyExpression, openness: CGFloat = 1, look: CGVector = .zero) {
        self.expression = expression
        self.openness = openness
        self.look = look
    }

    public nonisolated var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(openness, AnimatablePair(look.dx, look.dy)) }
        set {
            openness = newValue.first
            look = CGVector(dx: newValue.second.first, dy: newValue.second.second)
        }
    }

    public var body: some View {
        Canvas { context, size in
            let rect = Self.fit(size)
            draw(in: &context, rect: rect)
        }
        .aspectRatio(OdyGeometry.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }

    static func fit(_ size: CGSize) -> CGRect {
        let w = min(size.width, size.height * OdyGeometry.aspect)
        let h = w / OdyGeometry.aspect
        return CGRect(x: (size.width - w) / 2, y: size.height - h, width: w, height: h)
    }

    private func draw(in context: inout GraphicsContext, rect: CGRect) {
        let m = { (x: CGFloat, y: CGFloat) in OdyGeometry.map(x, y, in: rect) }
        let k = OdyGeometry.scale(in: rect)
        func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
            let c = m(cx, cy)
            return Path(ellipseIn: CGRect(x: c.x - rx * k, y: c.y - ry * k, width: 2 * rx * k, height: 2 * ry * k))
        }

        let body = OdyBodyShape().path(in: rect)
        context.fill(
            body,
            with: .radialGradient(
                Gradient(stops: OdyPalette.bodyStops),
                center: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.26),
                startRadius: 0, endRadius: max(rect.width, rect.height) * 0.85))
        context.fill(
            body,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: OdyPalette.hex(0x7A5A2A, 0), location: 0.5),
                    .init(color: OdyPalette.hex(0x7A5A2A, 0.3), location: 1),
                ]), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        // The soft highlight up-left.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10 * k))
            layer.opacity = 0.8
            let c = m(398, 372)
            layer.translateBy(x: c.x, y: c.y)
            layer.rotate(by: .degrees(-38))
            layer.fill(Path(ellipseIn: CGRect(x: -84 * k, y: -42 * k, width: 168 * k, height: 84 * k)), with: .color(.white))
        }
        context.fill(ellipse(345, 592, 46, 36), with: .color(OdyPalette.hex(0xF1EBE2)))
        context.fill(ellipse(520, 640, 36, 17), with: .color(OdyPalette.blush))
        context.fill(ellipse(742, 634, 30, 16), with: .color(OdyPalette.blush))

        let face = OdyFace.of(expression)
        let ink = GraphicsContext.Shading.color(OdyPalette.ink)
        func stroke(_ d: String, width: CGFloat) {
            var t = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: k, y: k)
            t = t.translatedBy(x: -OdyGeometry.box.minX, y: -OdyGeometry.box.minY)
            context.stroke(
                SVGPath.path(d).applying(t), with: ink,
                style: StrokeStyle(lineWidth: width * k, lineCap: .round))
        }

        switch face.eyes {
        case .open:
            let open = max(0.06, min(openness, face.opennessCap))
            let dx = face.eyeOffset.dx + look.dx * 22
            let dy = face.eyeOffset.dy + look.dy * 14
            let rx = 31 * face.eyeScale, ry = 60 * face.eyeScale
            // A lid comes down over the eye rather than the eye squashing: half open is a flat-topped half oval,
            // which reads sleepy; a squashed oval at half height is a round, wide-awake dot.
            let lid = 522 + dy - ry + 2 * ry * (1 - open)
            for x in [578.0, 696.0] {
                context.drawLayer { eye in
                    let top = m(x + dx - rx - 2, lid), bottom = m(x + dx + rx + 2, 522 + dy + ry + 2)
                    eye.clip(to: Path(CGRect(x: top.x, y: top.y, width: bottom.x - top.x, height: bottom.y - top.y)))
                    eye.fill(ellipse(x + dx, 522 + dy, rx, ry), with: ink)
                }
                if open > 0.4 {
                    let shine = max(494 + dy, lid + 14 * face.eyeScale)
                    context.fill(ellipse(x + 10 + dx, shine, 10 * face.eyeScale, 10 * face.eyeScale), with: .color(.white))
                }
            }
        case .sleepyArcs:
            stroke("M548 536Q578 516 608 536", width: 13)
            stroke("M666 536Q696 516 726 536", width: 13)
        case .smileArcs:
            stroke("M548 530Q578 498 608 530", width: 13)
            stroke("M666 530Q696 498 726 530", width: 13)
        }

        switch face.mouth {
        case .smile: stroke("M614 608Q640 628 664 608", width: 12)
        case .smileRight: stroke("M660 606Q682 620 704 606", width: 11)
        case .small: stroke("M604 630Q624 642 644 630", width: 11)
        case .dot: context.fill(ellipse(640, 612, 14, 10), with: ink)
        case .ring:
            context.stroke(ellipse(636, 604, 13, 13), with: ink, lineWidth: 11 * k)
        case .wide: context.fill(ellipse(640, 618, 18, 26), with: ink)
        case .grin:
            var t = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: k, y: k)
            t = t.translatedBy(x: -OdyGeometry.box.minX, y: -OdyGeometry.box.minY)
            context.fill(SVGPath.path("M606 600Q640 650 676 600Z").applying(t), with: ink)
            context.fill(SVGPath.path("M622 622Q640 640 660 622").applying(t), with: .color(OdyPalette.hex(0xFF7E95)))
        }
    }
}
