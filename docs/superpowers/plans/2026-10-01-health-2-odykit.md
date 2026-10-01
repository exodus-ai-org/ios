# Health 2 — OdyKit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ody as a living SwiftUI character (breathes, blinks, looks, squashes when poked, eight expressions), the ten state scenes, the day sky, confetti, and the heartbeat wave — all drawn in code, matching the approved mockups.

**Architecture:** Pure, tested math (`SVGPath`, `BlinkSchedule`, `DaySky`, `ConfettiSystem`, `ECG`) feeds thin SwiftUI views. Ody's body is the desktop's `brand/art.mjs` curve. Scene art is ported **verbatim** from the approved mockup `.superpowers/brainstorm/83696-1790821334/content/ody-states-v2.html` through a small SVG path parser, drawn in a 150 × 150 design space and scaled.

**Tech Stack:** SwiftUI (Canvas, TimelineView, keyframeAnimator, sensoryFeedback), Metal stitchable shader, Swift Testing. iOS 27.

**Spec:** `docs/superpowers/specs/2026-10-01-health-workspace-design.md` §6 (and §5 for motion rules)

**Series:** plan 2 of 3. Requires plan 1 Task 3 (the `OdyKit` target exists). Plan 3 consumes this module.

## Global Constraints

- Module `OdyKit` has **no dependencies** (not even `Models`); everything public that plan 3 uses is listed in each task's Interfaces.
- Every animation stops under Reduce Motion (`@Environment(\.accessibilityReduceMotion)`): idle breathing/blinking off, scene loops off, confetti draws nothing, the heartbeat wave freezes.
- Ody is decorative: every Ody view is `accessibilityHidden(true)`; callers supply the spoken state.
- Springs follow the spec: poke `response 0.4, dampingFraction 0.45`.
- Haptics only through `.sensoryFeedback`; no sounds.
- Palette (from `brand/art.mjs`): body `#FFFFFF → #F6F2EC → #D3C8B8`, rim `#7A5A2A` at 0–0.3 opacity, ink `#1B1B1F`, blush `#FF7E95` @ 0.55, bindle `#E5392E`, sun `#FFD84A`, marigold `#FFAE1A`.
- Same repo rules as plan 1: stage only named files, `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, never push. `Sources/App/ExodusApp.swift` has unrelated uncommitted edits — stage your hunk only (`git add -p`).
- Test command: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme OdyKit -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:OdyKitTests/<Type>`; confirm the `Test run with N tests` line. `tuist generate --no-open` after adding files.

## Review Focus

- A scene drawn at 44 pt (a card corner) and at 300 pt (a detail header) → same composition, no clipped props, strokes scale with the art.
- Reduce Motion switched on while a scene is animating → it settles to its still frame, no frozen mid-blink eyes (openness 1).
- Dark mode → scene backgrounds keep their pastel (they are illustrations), but the gallery/background around them follows the system.
- Rapid repeated pokes → each restarts the squash from the current value (keyframes restart; no stacking past 0.8).
- `SVGPath` given the mockup's implicit-repeat commands (`c0-13 28-13 28 0 0 11-28 11-28 0z`) → parsed as two curves, not one.

---

## File Structure

- `Sources/OdyKit/OdyKit.swift` — (exists) module doc; add `OdyPalette`.
- `Sources/OdyKit/SVGPath.swift` — SVG path-data → `Path` (M L H V C S Q Z, absolute + relative, implicit repeats).
- `Sources/OdyKit/OdyFigure.swift` — `OdyGeometry`, `OdyBodyShape`, `OdyExpression`, `OdyFace`, `OdyFigure` (stateless drawing).
- `Sources/OdyKit/OdyView.swift` — `BlinkSchedule`, `Breath`, `OdyView` (idle, poke, haptic, stretch).
- `Sources/OdyKit/OdyScene.swift` — `OdyScene` enum + `OdySceneView`, `Stage150`, `SceneArt` (ported paths).
- `Sources/OdyKit/DaySky.swift` — `RGB`, `DaySky` math, `DaySkyView`.
- `Sources/OdyKit/Confetti.swift` — `ConfettiSystem`, `ConfettiView`.
- `Sources/OdyKit/HeartbeatWave.swift`, `Sources/OdyKit/HeartbeatWave.metal` — `ECG` math, shader, view with fallback.
- `Sources/App/OdyGallery.swift` — DEBUG `-OdyGallery`.
- Modify `Sources/App/ExodusApp.swift` — show the gallery for the launch argument.
- Tests: `Tests/OdyKitTests/{SVGPathTests,OdyFaceTests,BlinkScheduleTests,DaySkyTests,ConfettiTests,ECGTests}.swift`.

---

### Task 1: SVG path parser and palette

**Files:**
- Create: `Sources/OdyKit/SVGPath.swift`
- Modify: `Sources/OdyKit/OdyKit.swift`
- Test: `Tests/OdyKitTests/SVGPathTests.swift`

**Interfaces:**
- Produces: `public enum SVGPath { public static func path(_ data: String) -> Path }` (unsupported command → stops parsing there, returns what it has); `public enum OdyPalette { static let ink, blush, bindle, bindleDark, stick, sun, marigold: Color; static let bodyStops: [Gradient.Stop]; static func hex(_ v: UInt32, _ opacity: Double = 1) -> Color }`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/OdyKitTests/SVGPathTests.swift
import SwiftUI
import Testing

@testable import OdyKit

struct SVGPathTests {
    @Test func absoluteSquare() {
        let r = SVGPath.path("M0 0L10 0V10H0Z").boundingRect
        #expect(r == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test func relativeCommands() {
        let r = SVGPath.path("m5 5l10 0v4h-10z").boundingRect
        #expect(r == CGRect(x: 5, y: 5, width: 10, height: 4))
    }

    @Test func compactNumbersAndImplicitRepeats() {
        // The bindle's bag from the mockup: two relative curves in one `c`, negative numbers with no separators.
        let p = SVGPath.path("M58 138c0-13 28-13 28 0 0 11-28 11-28 0z")
        var curves = 0
        p.forEach { if case .curve = $0 { curves += 1 } }
        #expect(curves == 2)
        let r = p.boundingRect
        #expect(abs(r.minX - 58) < 0.01 && abs(r.maxX - 86) < 0.01)
    }

    @Test func implicitLineAfterMove() {
        let r = SVGPath.path("M0 0 10 0 10 10").boundingRect
        #expect(r == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test func smoothCurveReflectsTheLastControl() {
        // The sweat drop: `s` after `c`.
        let p = SVGPath.path("M58 50c-5 8-5 13 0 13s5-5 0-13z")
        var curves = 0
        p.forEach { if case .curve = $0 { curves += 1 } }
        #expect(curves == 2)
        #expect(p.boundingRect.maxY <= 63.01)
    }

    @Test func quadraticAndDecimals() {
        let p = SVGPath.path("M55.5 124h3l-1.5 3zM30 112Q72 94 116 112")
        #expect(abs(p.boundingRect.minX - 30) < 0.01)
    }

    @Test func unsupportedCommandStopsThere() {
        let p = SVGPath.path("M0 0L10 0A5 5 0 0 1 20 0L30 0")
        #expect(p.boundingRect.maxX == 10)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `tuist generate --no-open && xcodebuild test -workspace ExodusIos.xcworkspace -scheme OdyKit -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:OdyKitTests/SVGPathTests`
Expected: build failure — `SVGPath` not found.

- [ ] **Step 3: Write the parser**

```swift
// Sources/OdyKit/SVGPath.swift
import SwiftUI

/// SVG path data → `Path`, for the art ported from the approved mockups: M L H V C S Q Z, absolute and relative, with
/// implicit repeats and compact numbers ("0-13"). Arcs are not used by the art; parsing stops at anything unknown.
public enum SVGPath {
    public static func path(_ data: String) -> Path {
        var path = Path()
        var scanner = Tokens(data)
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCubicControl: CGPoint?
        var command: Character?

        while let next = scanner.peekCommand() ?? command {
            if scanner.peekCommand() != nil { scanner.skipCommand() }
            let relative = next.isLowercase
            let base = relative ? current : .zero
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return CGPoint(x: base.x + x, y: base.y + y)
            }
            var reflected: CGPoint?
            switch next.uppercased().first! {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                start = p
                command = relative ? "l" : "L"  // further pairs are lines
                continue
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                path.addLine(to: current)
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                path.addLine(to: current)
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                reflected = c2
                current = p
            case "S":
                let c1 = lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                reflected = c2
                current = p
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                current = p
            case "Z":
                path.closeSubpath()
                current = start
                command = nil
                lastCubicControl = nil
                continue
            default:
                return path
            }
            lastCubicControl = reflected
            command = next
            if scanner.atEnd { break }
        }
        return path
    }

    /// Reads commands and numbers from path data.
    struct Tokens {
        private let chars: [Character]
        private var i = 0

        init(_ s: String) { chars = Array(s) }

        var atEnd: Bool {
            var j = i
            while j < chars.count, chars[j] == " " || chars[j] == "," || chars[j] == "\n" { j += 1 }
            return j >= chars.count
        }

        mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }

        mutating func peekCommand() -> Character? {
            skipSeparators()
            guard i < chars.count, chars[i].isLetter else { return nil }
            return chars[i]
        }

        mutating func skipCommand() { i += 1 }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var j = i
            if j < chars.count, chars[j] == "-" || chars[j] == "+" { j += 1 }
            var sawDot = false
            var sawDigit = false
            while j < chars.count {
                if chars[j].isNumber {
                    sawDigit = true
                } else if chars[j] == "." && !sawDot {
                    sawDot = true
                } else {
                    break
                }
                j += 1
            }
            guard sawDigit, let value = Double(String(chars[i..<j])) else { return nil }
            i = j
            return CGFloat(value)
        }
    }
}
```

Note: `M` followed by a lowercase command letter is handled because `peekCommand()` is checked before the implicit command each loop.

- [ ] **Step 4: Add the palette to `OdyKit.swift`**

```swift
// Sources/OdyKit/OdyKit.swift
import SwiftUI

/// Ody, the Exodus mascot, as a living SwiftUI character and the scenes it appears in. The body curve and palette
/// come from the desktop's `brand/art.mjs` — keep them in sync.
public enum OdyKit {
    static let version = 1
}

public enum OdyPalette {
    public static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255, opacity: opacity)
    }

    public static let ink = hex(0x1B1B1F)
    public static let blush = hex(0xFF7E95, 0.55)
    public static let bindle = hex(0xE5392E)
    public static let bindleDark = hex(0xB82A22)
    public static let stick = hex(0x9C7448)
    public static let sun = hex(0xFFD84A)
    public static let marigold = hex(0xFFAE1A)
    public static let bodyStops: [Gradient.Stop] = [
        .init(color: hex(0xFFFFFF), location: 0), .init(color: hex(0xF6F2EC), location: 0.5),
        .init(color: hex(0xD3C8B8), location: 1),
    ]
}
```

- [ ] **Step 5: Run to verify they pass**

Run: Step 2's command. Expected: `Test run with 7 tests … passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/OdyKit/SVGPath.swift Sources/OdyKit/OdyKit.swift Tests/OdyKitTests/SVGPathTests.swift
git commit -m "feat(ody): SVG path parser and the brand palette

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/OdyKit/SVGPath.swift Sources/OdyKit/OdyKit.swift Tests/OdyKitTests/SVGPathTests.swift
```

---

### Task 2: Ody's body and faces (stateless)

**Files:**
- Create: `Sources/OdyKit/OdyFigure.swift`
- Test: `Tests/OdyKitTests/OdyFaceTests.swift`

**Interfaces:**
- Produces:
  - `enum OdyGeometry { static let box: CGRect /* (232,250,560,600) in art.mjs units */; static let aspect: CGFloat; static func map(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint }`
  - `public struct OdyBodyShape: Shape`
  - `public enum OdyExpression: CaseIterable, Sendable { case happy, grin, sleepy, content, curious, down, away, yawn }`
  - `struct OdyFace: Equatable { enum Eyes { case open, sleepyArcs, smileArcs }; enum Mouth { case smile, grin, dot, ring, wide, small, smileRight }; var eyes: Eyes; var mouth: Mouth; var eyeOffset: CGVector; var eyeScale: CGFloat; var opennessCap: CGFloat; static func of(_ e: OdyExpression) -> OdyFace }`
  - `public struct OdyFigure: View, Animatable { init(expression: OdyExpression, openness: CGFloat = 1, look: CGVector = .zero) }` — fills its frame at `OdyGeometry.aspect`; `look` components in −1…1.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/OdyKitTests/OdyFaceTests.swift
import SwiftUI
import Testing

@testable import OdyKit

struct OdyFaceTests {
    @Test func everyExpressionHasAFace() {
        for e in OdyExpression.allCases { _ = OdyFace.of(e) }
        #expect(OdyFace.of(.sleepy).eyes == .sleepyArcs)
        #expect(OdyFace.of(.content).eyes == .smileArcs)
        #expect(OdyFace.of(.yawn).mouth == .wide)
        #expect(OdyFace.of(.yawn).opennessCap < 0.3)
        #expect(OdyFace.of(.curious).eyeScale < 1)
    }

    @Test func geometryMapsTheBodyBoxOntoTheRect() {
        let rect = CGRect(x: 0, y: 0, width: 56, height: 60)
        #expect(OdyGeometry.map(232, 250, in: rect) == .zero)
        #expect(OdyGeometry.map(792, 850, in: rect) == CGPoint(x: 56, y: 60))
        #expect(abs(OdyGeometry.aspect - 560.0 / 600.0) < 1e-9)
    }

    @Test func bodyFillsItsRect() {
        let r = OdyBodyShape().path(in: CGRect(x: 0, y: 0, width: 56, height: 60)).boundingRect
        #expect(abs(r.minX) < 0.01 && abs(r.maxX - 56) < 0.01)
        #expect(abs(r.minY) < 0.01 && abs(r.maxY - 60) < 0.01)
    }

    @Test @MainActor func rendersEveryExpression() {
        for e in OdyExpression.allCases {
            let renderer = ImageRenderer(content: OdyFigure(expression: e).frame(width: 56, height: 60))
            #expect(renderer.uiImage != nil)
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test … -scheme OdyKit … -only-testing:OdyKitTests/OdyFaceTests`
Expected: build failure — `OdyFace` not found.

- [ ] **Step 3: Write the figure**

```swift
// Sources/OdyKit/OdyFigure.swift
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

    public var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
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
            let dy = face.eyeOffset.dy + look.dy * 14 + (1 - open) * 18
            for x in [578.0, 696.0] {
                context.fill(ellipse(x + dx, 522 + dy, 31 * face.eyeScale, 60 * face.eyeScale * open), with: ink)
                if open > 0.4 {
                    context.fill(ellipse(x + 10 + dx, 494 + dy + (1 - open) * 12, 10 * face.eyeScale, 10 * face.eyeScale), with: .color(.white))
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
```

- [ ] **Step 4: Run to verify they pass**

Run: Step 2's command. Expected: `Test run with 4 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OdyKit/OdyFigure.swift Tests/OdyKitTests/OdyFaceTests.swift
git commit -m "feat(ody): Ody's body and eight faces

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/OdyKit/OdyFigure.swift Tests/OdyKitTests/OdyFaceTests.swift
```

---

### Task 3: The living Ody — blink, breath, poke, stretch

**Files:**
- Create: `Sources/OdyKit/OdyView.swift`
- Test: `Tests/OdyKitTests/BlinkScheduleTests.swift`

**Interfaces:**
- Consumes: `OdyFigure`, `OdyExpression` (Task 2).
- Produces:
  - `public struct BlinkSchedule: Sendable { init(seed: UInt64); func openness(at t: TimeInterval) -> CGFloat; static let cell: TimeInterval = 3.7; static let duration: TimeInterval = 0.24 }`
  - `public enum Breath { static func scale(at t: TimeInterval) -> CGFloat }` (1 ± 0.012, 4 s period)
  - `public struct OdyView: View { init(expression: OdyExpression, look: CGVector = .zero, tiredness: CGFloat = 0, stretch: CGFloat = 1, pokable: Bool = true, seed: UInt64 = 1, onPoke: (() -> Void)? = nil) }` — `tiredness` 0…1 caps openness at `1 - 0.38 * tiredness`; `stretch` > 1 elongates from the feet (pull-to-refresh), < 1 squashes.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/OdyKitTests/BlinkScheduleTests.swift
import Testing

@testable import OdyKit

struct BlinkScheduleTests {
    @Test func opennessStaysInRange() {
        let s = BlinkSchedule(seed: 7)
        for i in 0..<2000 {
            let o = s.openness(at: Double(i) * 0.013)
            #expect(o >= 0 && o <= 1)
        }
    }

    @Test func blinksAtLeastOncePerTwoCells() {
        let s = BlinkSchedule(seed: 3)
        let samples = stride(from: 0.0, to: 2 * BlinkSchedule.cell, by: 0.01).map { s.openness(at: $0) }
        #expect(samples.contains { $0 < 0.2 })
    }

    @Test func mostlyOpen() {
        let s = BlinkSchedule(seed: 11)
        let samples = stride(from: 0.0, to: 60, by: 0.01).map { s.openness(at: $0) }
        let closedShare = Double(samples.filter { $0 < 1 }.count) / Double(samples.count)
        #expect(closedShare < 0.1)
    }

    @Test func deterministicPerSeed() {
        #expect(BlinkSchedule(seed: 5).openness(at: 12.34) == BlinkSchedule(seed: 5).openness(at: 12.34))
    }

    @Test func breathIsSmall() {
        for t in stride(from: 0.0, to: 8, by: 0.1) {
            #expect(abs(Breath.scale(at: t) - 1) <= 0.0121)
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test … -scheme OdyKit … -only-testing:OdyKitTests/BlinkScheduleTests`
Expected: build failure — `BlinkSchedule` not found.

- [ ] **Step 3: Write the view**

```swift
// Sources/OdyKit/OdyView.swift
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
```

- [ ] **Step 4: Run to verify they pass**

Run: Step 2's command. Expected: `Test run with 5 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OdyKit/OdyView.swift Tests/OdyKitTests/BlinkScheduleTests.swift
git commit -m "feat(ody): a living Ody — breath, blink, poke and stretch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/OdyKit/OdyView.swift Tests/OdyKitTests/BlinkScheduleTests.swift
```

---

### Task 4: The ten scenes

**Files:**
- Create: `Sources/OdyKit/OdyScene.swift`
- Test: `Tests/OdyKitTests/OdySceneTests.swift`

**Interfaces:**
- Consumes: `SVGPath`, `OdyView`, `OdyPalette`.
- Produces:
  - `public enum OdyScene: String, CaseIterable, Sendable { case rested, tired, active, recovering, hydrating, calm, noData, writing, permission, offline; public var background: Color; var expression: OdyExpression }`
  - `public struct OdySceneView: View { init(_ scene: OdyScene, showsBackground: Bool = true, pokable: Bool = false) }` — square, scales from any size.
  - `struct OdyPlacement { x, y, w, h: CGFloat; tilt: Double; pivot: CGPoint? }` with `bodyRect` converting the mockup's `<use x y width height>` (symbol viewBox `200 220 624 660`) into the body's rect.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/OdyKitTests/OdySceneTests.swift
import SwiftUI
import Testing

@testable import OdyKit

struct OdySceneTests {
    @Test func placementConvertsTheMockupsUseElement() {
        // <use href="#ody-body" x="33" y="44" width="84" height="90"/> in the 150-unit scene.
        let r = OdyPlacement(x: 33, y: 44, w: 84, h: 90).bodyRect
        #expect(abs(r.minX - (33 + 32.0 / 624 * 84)) < 0.001)
        #expect(abs(r.width - 560.0 / 624 * 84) < 0.001)
        #expect(abs(r.minY - (44 + 30.0 / 660 * 90)) < 0.001)
        #expect(abs(r.height - 600.0 / 660 * 90) < 0.001)
    }

    @Test func everySceneHasArtThatParses() {
        for scene in OdyScene.allCases {
            for layer in SceneArt.layers(scene) {
                #expect(!SVGPath.path(layer.d).isEmpty, "\(scene) has an empty path")
            }
        }
    }

    @Test @MainActor func everySceneRendersSmallAndLarge() {
        for scene in OdyScene.allCases {
            for side in [44.0, 300.0] {
                let r = ImageRenderer(content: OdySceneView(scene).frame(width: side, height: side))
                #expect(r.uiImage != nil)
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test … -scheme OdyKit … -only-testing:OdyKitTests/OdySceneTests`
Expected: build failure — `OdyScene` not found.

- [ ] **Step 3: Write the scenes**

All paths and colours are copied from `ody-states-v2.html`; the moon and the mug handle replace arcs (`a`) with curves, since the parser has no arcs.

```swift
// Sources/OdyKit/OdyScene.swift
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
                ArtLayer(d: ellipse(116, 38, 30, 30), paint: .fill(0xFFD84A, 0.35)),
                ArtLayer(d: ellipse(116, 38, 14, 14), paint: .fill(0xFFD84A)),
                ArtLayer(d: spark(at: 26, 28, size: 12), paint: .fill(0xFFAE1A)),
                ArtLayer(d: spark(at: 37.5, 47.5, size: 7), paint: .fill(0xFFAE1A)),
                ArtLayer(d: ellipse(75, 134, 40, 6), paint: .fill(0xE9D79A)),
            ]
        case .tired:
            return [
                // A crescent: an outer circle with a bite taken by a second curve.
                ArtLayer(d: "M118 22C106 22 100 32 100 40C100 50 108 58 118 58C124 58 128 55 130 52C120 52 112 46 112 36C112 30 115 25 118 22Z", paint: .fill(0xB9AEF0)),
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
                ArtLayer(d: "M98 28c2-8 18-8 18 2 0 7-8 8-8 15M108 52v1", paint: .stroke(0xC9B78C, 5), rotate: 14, pivot: CGPoint(x: 104, y: 36)),
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
```

- [ ] **Step 4: Run to verify they pass**

Run: Step 2's command. Expected: `Test run with 3 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OdyKit/OdyScene.swift Tests/OdyKitTests/OdySceneTests.swift
git commit -m "feat(ody): the ten state scenes, ported from the approved art

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/OdyKit/OdyScene.swift Tests/OdyKitTests/OdySceneTests.swift
```

---

### Task 5: The day sky

**Files:**
- Create: `Sources/OdyKit/DaySky.swift`
- Test: `Tests/OdyKitTests/DaySkyTests.swift`

**Interfaces:**
- Produces:
  - `public struct RGB: Equatable, Sendable { r, g, b: Double; init(hex: UInt32); func mixed(with: RGB, _ t: Double) -> RGB; var color: Color }`
  - `public enum DaySky { static func gradient(atClockHour h: Double) -> (top: RGB, bottom: RGB); static func night(atClockHour h: Double) -> Double; static func sun(atClockHour h: Double) -> CGPoint?; static func moon(atClockHour h: Double) -> CGPoint? }` — clock hour wraps mod 24; points are unit coordinates (0…1) in the sky's frame.
  - `public struct DaySkyView: View { init(clockHour: Double) }` — gradient, stars (opacity = night), sun with glow, crescent moon, ground ellipse tinted toward night.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/OdyKitTests/DaySkyTests.swift
import Testing

@testable import OdyKit

struct DaySkyTests {
    @Test func nightAndDayColours() {
        #expect(DaySky.gradient(atClockHour: 0).top == RGB(hex: 0x141235))
        #expect(DaySky.gradient(atClockHour: 13).top == RGB(hex: 0xFFE27A))
        #expect(DaySky.gradient(atClockHour: 13).bottom == RGB(hex: 0xFFF0BE))
    }

    @Test func wrapsAroundMidnight() {
        #expect(DaySky.gradient(atClockHour: 24) == DaySky.gradient(atClockHour: 0))
        #expect(DaySky.gradient(atClockHour: -2) == DaySky.gradient(atClockHour: 22))
        #expect(DaySky.gradient(atClockHour: 27.5) == DaySky.gradient(atClockHour: 3.5))
    }

    @Test func dawnIsBetweenNightAndMorning() {
        let dawn = DaySky.gradient(atClockHour: 5.5).top
        #expect(dawn != RGB(hex: 0x141235) && dawn != RGB(hex: 0xFFE9A0))
    }

    @Test func nightFactor() {
        #expect(DaySky.night(atClockHour: 2) == 1)
        #expect(DaySky.night(atClockHour: 12) == 0)
        let dawn = DaySky.night(atClockHour: 5.9)
        #expect(dawn > 0 && dawn < 1)
    }

    @Test func sunAndMoonPaths() {
        let noon = try! #require(DaySky.sun(atClockHour: 12))
        #expect(abs(noon.x - 0.5) < 0.001 && noon.y < 0.2)
        #expect(DaySky.sun(atClockHour: 2) == nil)
        let midnight = try! #require(DaySky.moon(atClockHour: 0))
        #expect(abs(midnight.x - 0.5) < 0.001)
        #expect(DaySky.moon(atClockHour: 12) == nil)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test … -scheme OdyKit … -only-testing:OdyKitTests/DaySkyTests`
Expected: build failure — `DaySky` not found.

- [ ] **Step 3: Write the sky**

```swift
// Sources/OdyKit/DaySky.swift
import SwiftUI

public struct RGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double

    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    public var color: Color { Color(red: r, green: g, blue: b) }
}

/// The hero's sky by the clock: night indigo, a peach dawn, the brand's warm yellow by day, an orange sunset and a
/// violet dusk. Hours wrap, so a scrub from 18:00 yesterday to now reads straight through midnight.
public enum DaySky {
    /// (clock hour, top, bottom) — 0 and 24 are the same night.
    static let keys: [(Double, RGB, RGB)] = [
        (0, RGB(hex: 0x141235), RGB(hex: 0x3D3480)),
        (5, RGB(hex: 0x1D1A4A), RGB(hex: 0x4A3F99)),
        (6, RGB(hex: 0xF59E7B), RGB(hex: 0xFFD9A0)),
        (8, RGB(hex: 0xFFE9A0), RGB(hex: 0xFFF4D0)),
        (12, RGB(hex: 0xFFE27A), RGB(hex: 0xFFF0BE)),
        (16.5, RGB(hex: 0xFFE27A), RGB(hex: 0xFFF0BE)),
        (18, RGB(hex: 0xF58B6B), RGB(hex: 0xFFC98A)),
        (19.5, RGB(hex: 0x3B2F7A), RGB(hex: 0x7A5FA8)),
        (21, RGB(hex: 0x141235), RGB(hex: 0x3D3480)),
        (24, RGB(hex: 0x141235), RGB(hex: 0x3D3480)),
    ]

    static func wrap(_ h: Double) -> Double {
        let m = h.truncatingRemainder(dividingBy: 24)
        return m < 0 ? m + 24 : m
    }

    public static func gradient(atClockHour hour: Double) -> (top: RGB, bottom: RGB) {
        let h = wrap(hour)
        for i in 0..<(keys.count - 1) where h <= keys[i + 1].0 {
            let (a, t1, b1) = keys[i]
            let (b, t2, b2) = keys[i + 1]
            let t = b > a ? (h - a) / (b - a) : 0
            return (t1.mixed(with: t2, t), b1.mixed(with: b2, t))
        }
        return (keys[0].1, keys[0].2)
    }

    /// 1 at night, 0 by day: fades out 5.5→6.3, back in 18.5→20.5.
    public static func night(atClockHour hour: Double) -> Double {
        let h = wrap(hour)
        switch h {
        case ..<5.5: return 1
        case ..<6.3: return 1 - (h - 5.5) / 0.8
        case ..<18.5: return 0
        case ..<20.5: return (h - 18.5) / 2
        default: return 1
        }
    }

    /// The sun's arc, 06:00 to 18:00, in unit coordinates.
    public static func sun(atClockHour hour: Double) -> CGPoint? {
        let h = wrap(hour)
        guard h >= 6, h <= 18 else { return nil }
        return arc((h - 6) / 12)
    }

    /// The moon's arc, 18:00 to 06:00.
    public static func moon(atClockHour hour: Double) -> CGPoint? {
        let h = wrap(hour)
        guard h >= 18 || h <= 6 else { return nil }
        return arc(wrap(h - 18) / 12)
    }

    private static func arc(_ a: Double) -> CGPoint {
        CGPoint(x: 0.067 + 0.866 * a, y: 0.636 - sin(.pi * a) * 0.508)
    }
}

public struct DaySkyView: View {
    let hour: Double

    public init(clockHour: Double) { hour = clockHour }

    private static let stars: [CGPoint] = [
        CGPoint(x: 0.13, y: 0.13), CGPoint(x: 0.3, y: 0.08), CGPoint(x: 0.47, y: 0.17), CGPoint(x: 0.67, y: 0.09),
        CGPoint(x: 0.87, y: 0.21), CGPoint(x: 0.77, y: 0.38), CGPoint(x: 0.2, y: 0.34), CGPoint(x: 0.57, y: 0.32),
        CGPoint(x: 0.93, y: 0.07),
    ]

    public var body: some View {
        let colors = DaySky.gradient(atClockHour: hour)
        let night = DaySky.night(atClockHour: hour)
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(stops: [.init(color: colors.top.color, location: 0), .init(color: colors.bottom.color, location: 0.8)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for star in Self.stars {
                let p = CGPoint(x: star.x * size.width, y: star.y * size.height)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)), with: .color(.white.opacity(0.9 * night)))
            }
            let r = min(size.width, size.height) * 0.085
            if let sun = DaySky.sun(atClockHour: hour) {
                let c = CGPoint(x: sun.x * size.width, y: sun.y * size.height)
                context.fill(
                    Path(ellipseIn: CGRect(x: c.x - r * 2, y: c.y - r * 2, width: r * 4, height: r * 4)),
                    with: .radialGradient(
                        Gradient(colors: [OdyPalette.sun.opacity(0.9 * (1 - night)), OdyPalette.sun.opacity(0)]),
                        center: c, startRadius: 0, endRadius: r * 2))
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(OdyPalette.sun.opacity(1 - night)))
            }
            if let moon = DaySky.moon(atClockHour: hour) {
                let c = CGPoint(x: moon.x * size.width, y: moon.y * size.height)
                var layer = context
                layer.opacity = night
                layer.drawLayer { l in
                    l.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y - r * 0.8, width: r * 1.6, height: r * 1.6)), with: .color(OdyPalette.hex(0xF4EFFF)))
                    l.blendMode = .destinationOut
                    l.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.4, y: c.y - r * 1.0, width: r * 1.6, height: r * 1.6)), with: .color(.black))
                }
            }
            let ground = RGB(hex: 0xF7E2A0).mixed(with: RGB(hex: 0x2B2660), night)
            context.fill(
                Path(ellipseIn: CGRect(x: -size.width * 0.2, y: size.height * 0.83, width: size.width * 1.4, height: size.height * 0.34)),
                with: .color(ground.color))
        }
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: Step 2's command. Expected: `Test run with 5 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OdyKit/DaySky.swift Tests/OdyKitTests/DaySkyTests.swift
git commit -m "feat(ody): the day sky — colours, stars, sun and moon by the clock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/OdyKit/DaySky.swift Tests/OdyKitTests/DaySkyTests.swift
```

---

### Task 6: Confetti

**Files:**
- Create: `Sources/OdyKit/Confetti.swift`
- Test: `Tests/OdyKitTests/ConfettiTests.swift`

**Interfaces:**
- Produces:
  - `public struct ConfettiSystem: Sendable { public private(set) var particles: [Particle]; static let gravity = 900.0; static func burst(count: Int, origin: CGPoint, seed: UInt64) -> ConfettiSystem; mutating func step(_ dt: Double, floor: Double); var isFinished: Bool }` with `struct Particle { x, y, vx, vy, angle, spin, scale: Double; kind: Kind; color: UInt32 }`, `enum Kind { bindle, star, square }`
  - `public struct ConfettiView: View { init(trigger: Int, origin: UnitPoint = UnitPoint(x: 0.5, y: 0.45)) }` — a full-size overlay; draws nothing under Reduce Motion; no hit testing.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/OdyKitTests/ConfettiTests.swift
import CoreGraphics
import Testing

@testable import OdyKit

struct ConfettiTests {
    @Test func burstThrowsUpward() {
        let s = ConfettiSystem.burst(count: 46, origin: CGPoint(x: 150, y: 300), seed: 1)
        #expect(s.particles.count == 46)
        #expect(s.particles.allSatisfy { $0.vy < 0 })
    }

    @Test func gravityBringsEverythingDown() {
        var s = ConfettiSystem.burst(count: 46, origin: CGPoint(x: 150, y: 300), seed: 1)
        for _ in 0..<240 { s.step(1.0 / 60, floor: 700) }
        #expect(s.isFinished)
    }

    @Test func sameSeedSameBurst() {
        let a = ConfettiSystem.burst(count: 10, origin: .zero, seed: 9)
        let b = ConfettiSystem.burst(count: 10, origin: .zero, seed: 9)
        #expect(a.particles.map(\.vx) == b.particles.map(\.vx))
    }

    @Test func allKindsAppear() {
        let s = ConfettiSystem.burst(count: 12, origin: .zero, seed: 2)
        #expect(Set(s.particles.map(\.kind)).count == 3)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test … -scheme OdyKit … -only-testing:OdyKitTests/ConfettiTests`
Expected: build failure — `ConfettiSystem` not found.

- [ ] **Step 3: Write it**

```swift
// Sources/OdyKit/Confetti.swift
import SwiftUI

/// A burst of little bindles, stars and squares thrown up and pulled down by gravity — the goal celebration.
public struct ConfettiSystem: Sendable {
    public enum Kind: Hashable, Sendable { case bindle, star, square }

    public struct Particle: Sendable {
        public var x, y, vx, vy, angle, spin, scale: Double
        public var kind: Kind
        public var color: UInt32
    }

    static let gravity = 900.0
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
        let drag = pow(0.6, dt)
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
}

/// Plays a burst each time `trigger` changes. Draws nothing under Reduce Motion.
public struct ConfettiView: View {
    let trigger: Int
    let origin: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var system: ConfettiSystem?
    @State private var last: Date?

    public init(trigger: Int, origin: UnitPoint = UnitPoint(x: 0.5, y: 0.45)) {
        self.trigger = trigger
        self.origin = origin
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: system == nil)) { timeline in
                Canvas { context, size in
                    guard let system else { return }
                    for p in system.particles { draw(p, in: &context) }
                    _ = size
                }
                .onChange(of: timeline.date) { _, now in
                    guard var s = system else { return }
                    let dt = min(1.0 / 30, now.timeIntervalSince(last ?? now))
                    last = now
                    s.step(dt, floor: proxy.size.height)
                    system = s.isFinished ? nil : s
                }
            }
            .onChange(of: trigger) {
                guard !reduceMotion else { return }
                last = nil
                system = .burst(
                    count: 46, origin: CGPoint(x: origin.x * proxy.size.width, y: origin.y * proxy.size.height),
                    seed: UInt64(trigger))
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
```

- [ ] **Step 4: Run to verify they pass**

Run: Step 2's command. Expected: `Test run with 4 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OdyKit/Confetti.swift Tests/OdyKitTests/ConfettiTests.swift
git commit -m "feat(ody): bindle-and-star confetti

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/OdyKit/Confetti.swift Tests/OdyKitTests/ConfettiTests.swift
```

---

### Task 7: The heartbeat wave

**Files:**
- Create: `Sources/OdyKit/HeartbeatWave.swift`, `Sources/OdyKit/HeartbeatWave.metal`
- Test: `Tests/OdyKitTests/ECGTests.swift`

**Interfaces:**
- Produces: `public enum ECG { static func value(phase: Double) -> Double }` (one beat over phase 0…1; R peak 1.0 at 0.3); `public struct HeartbeatWave: View { init(bpm: Double, color: Color) }` — glowing trace scrolling left at `bpm`, frozen under Reduce Motion; falls back to a `Path` trace when the shader bundle is missing.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/OdyKitTests/ECGTests.swift
import Testing

@testable import OdyKit

struct ECGTests {
    @Test func rPeakIsTheHighestPoint() {
        let samples = stride(from: 0.0, to: 1, by: 0.001).map { ($0, ECG.value(phase: $0)) }
        let peak = samples.max { $0.1 < $1.1 }!
        #expect(abs(peak.0 - 0.3) < 0.01)
        #expect(abs(peak.1 - 1) < 0.05)
    }

    @Test func flatBetweenBeats() {
        #expect(abs(ECG.value(phase: 0.85)) < 0.02)
    }

    @Test func periodic() {
        #expect(abs(ECG.value(phase: 0.3) - ECG.value(phase: 1.3)) < 1e-9)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test … -scheme OdyKit … -only-testing:OdyKitTests/ECGTests`
Expected: build failure — `ECG` not found.

- [ ] **Step 3: Write the waveform, shader and view**

```swift
// Sources/OdyKit/HeartbeatWave.swift
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
```

```metal
// Sources/OdyKit/HeartbeatWave.metal
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// HeartbeatWave.swift's ECG, sampled per pixel: a glowing trace, brightest at its leading edge, scrolling at bpm.

static float bump(float x, float c, float w, float h) {
    float d = (x - c) / w;
    return h * exp(-d * d);
}

static float ecg(float phase) {
    float x = phase - floor(phase);
    return bump(x, 0.18, 0.025, 0.12) + bump(x, 0.275, 0.008, -0.12) + bump(x, 0.3, 0.012, 1.0)
        + bump(x, 0.325, 0.01, -0.22) + bump(x, 0.5, 0.05, 0.25);
}

[[ stitchable ]] half4 heartbeatWave(float2 position, half4 color, float2 size, float time, float bpm) {
    const float beats = 2.5;
    float phase = position.x / size.x * beats + time * bpm / 60.0;
    float y = size.y * (0.6 - 0.45 * ecg(phase));
    float d = abs(position.y - y);
    float core = smoothstep(2.0, 0.0, d);
    float glow = exp(-d * d / 60.0) * 0.45;
    // Fade in from the left edge so the trace reads as moving toward the right.
    float edge = smoothstep(0.0, 0.25, position.x / size.x);
    float a = clamp(core + glow, 0.0, 1.0) * edge;
    return half4(color.rgb * a, a);
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `tuist generate --no-open` then Step 2's command. Expected: `Test run with 3 tests … passed`. Also `xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "generic/platform=iOS Simulator"` succeeds (the `.metal` compiles into `ExodusIos_OdyKit.bundle`).

- [ ] **Step 5: Commit**

```bash
git add Sources/OdyKit/HeartbeatWave.swift Sources/OdyKit/HeartbeatWave.metal Tests/OdyKitTests/ECGTests.swift
git commit -m "feat(ody): heartbeat wave shader with a Canvas fallback

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/OdyKit/HeartbeatWave.swift Sources/OdyKit/HeartbeatWave.metal Tests/OdyKitTests/ECGTests.swift
```

---

### Task 8: Ody gallery and visual check against the mockup

**Files:**
- Create: `Sources/App/OdyGallery.swift`
- Modify: `Sources/App/ExodusApp.swift:48-53` (one more `else if` branch)

**Interfaces:**
- Produces: DEBUG launch argument `-OdyGallery`.

- [ ] **Step 1: Write the gallery**

```swift
// Sources/App/OdyGallery.swift
#if DEBUG
import OdyKit
import SwiftUI

/// DEBUG-only visual check of OdyKit: `-OdyGallery` shows every scene, every expression, the sky through a day, the
/// heartbeat wave and a confetti button. Compare against `.superpowers/brainstorm/…/ody-states-v2.html`.
enum OdyGalleryLaunch {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-OdyGallery") }
}

struct OdyGalleryView: View {
    @State private var confetti = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(OdyScene.allCases, id: \.self) { scene in
                        VStack(spacing: 4) {
                            OdySceneView(scene, pokable: true).clipShape(.rect(cornerRadius: 18))
                            Text(verbatim: scene.rawValue).font(.caption2)
                        }
                    }
                }
                HStack(spacing: 6) {
                    ForEach(OdyExpression.allCases, id: \.self) { e in
                        OdyView(expression: e).frame(height: 44)
                    }
                }
                HStack(spacing: 4) {
                    ForEach([0.0, 5.5, 6.2, 8, 12, 18, 19.5, 22], id: \.self) { h in
                        DaySkyView(clockHour: h).frame(height: 60).clipShape(.rect(cornerRadius: 8))
                    }
                }
                HeartbeatWave(bpm: 61, color: OdyPalette.hex(0xFF7E95)).frame(height: 90)
                    .background(OdyPalette.hex(0x4A0F1C), in: .rect(cornerRadius: 16))
                Button {
                    confetti += 1
                } label: {
                    Text(verbatim: "Confetti")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .overlay { ConfettiView(trigger: confetti) }
    }
}
#endif
```

- [ ] **Step 2: Hook it up**

In `Sources/App/ExodusApp.swift`, after the `SettingsGalleryLaunch` branch (around line 52), add:

```swift
                } else if OdyGalleryLaunch.isEnabled {
                    OdyGalleryView()
```

and `import OdyKit` is **not** needed there (the gallery file imports it). The file has unrelated uncommitted edits: stage only this hunk.

- [ ] **Step 3: Build, launch, screenshot**

```bash
tuist generate --no-open
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath Derived
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted Derived/Build/Products/Debug-iphonesimulator/Exodus.app
xcrun simctl launch booted app.yancey.exodus.exodus-ios -OdyGallery
sleep 3; xcrun simctl io booted screenshot .superpowers/ody-gallery.png
```

Open `.superpowers/ody-gallery.png` and `.superpowers/ody-states-v2.png` side by side (Read both). Expected: each scene has the mockup's background, props in the same places, Ody in the same pose and expression. Fix any mismatched coordinate in `SceneArt.layers` / `OdyScene.placement`, rebuild, re-screenshot. Also screenshot with `xcrun simctl ui booted appearance dark` and confirm the scenes are unchanged.

- [ ] **Step 4: Run all OdyKit tests**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme OdyKit -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: `Test run with 32 tests … passed` (1 + 7 + 4 + 5 + 3 + 5 + 4 + 3).

- [ ] **Step 5: Commit**

```bash
git add Sources/App/OdyGallery.swift
git add -p Sources/App/ExodusApp.swift   # only the OdyGallery branch
git commit -m "feat(ody): DEBUG gallery for every scene, face, sky and effect

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
