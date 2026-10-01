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
