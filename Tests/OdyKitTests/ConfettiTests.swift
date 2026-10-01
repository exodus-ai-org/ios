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

    @Test func closedFormMatchesStepping() {
        let s = ConfettiSystem.burst(count: 20, origin: CGPoint(x: 150, y: 300), seed: 3)
        var stepped = s
        let dt = 1.0 / 600
        for _ in 0..<300 { stepped.step(dt, floor: 10_000) }
        for (a, b) in zip(s.particles, stepped.particles) {
            let p = a.at(0.5)
            #expect(abs(p.x - b.x) < 3)
            #expect(abs(p.y - b.y) < 3)
        }
    }

    @Test func flightTimeCoversTheLastParticle() {
        let s = ConfettiSystem.burst(count: 46, origin: CGPoint(x: 150, y: 300), seed: 1)
        let end = s.flightTime(floor: 700)
        #expect(end > 0)
        #expect(s.particles.allSatisfy { $0.at(end + 0.01).y > 740 })
    }
}
