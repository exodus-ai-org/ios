import CoreGraphics
import Testing

@testable import HealthFeature

struct WaterSurfaceTests {
    @Test func stillWaterIsFlatAtItsLevel() {
        let p = WaterSurface.points(width: 100, height: 200, level: 0.5, tilt: 0, amplitude: 0, phase: 0)
        #expect(p.allSatisfy { abs($0.y - 100) < 0.001 })
        #expect(p.first?.x == 0 && p.last?.x == 100)
    }

    @Test func tiltSlopesTheSurface() {
        let p = WaterSurface.points(width: 100, height: 200, level: 0.5, tilt: 1, amplitude: 0, phase: 0)
        #expect(p.last!.y > p.first!.y)
        let mid = p.first { abs($0.x - 50) < 0.01 }!
        #expect(abs(mid.y - 100) < 0.001)  // pivots about the middle: volume stays put
    }

    @Test func emptyAndFull() {
        #expect(WaterSurface.points(width: 10, height: 50, level: 0, tilt: 0, amplitude: 0, phase: 0).allSatisfy { $0.y == 50 })
        #expect(WaterSurface.points(width: 10, height: 50, level: 1, tilt: 0, amplitude: 0, phase: 0).allSatisfy { $0.y == 0 })
    }
}
