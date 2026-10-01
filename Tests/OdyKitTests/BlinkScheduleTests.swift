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

    @Test func stretchAndTirednessAreClamped() {
        #expect(OdyView.clampedStretch(0.1) == 0.5)
        #expect(OdyView.clampedStretch(1.4) == 1.4)
        #expect(OdyView.clampedTiredness(-1) == 0)
        #expect(OdyView.clampedTiredness(3) == 1)
    }
}
