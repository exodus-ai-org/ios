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
