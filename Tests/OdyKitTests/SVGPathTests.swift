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
