// Tests/HealthFeatureTests/HypnogramTests.swift
import Foundation
import Testing

@testable import HealthFeature

struct HypnogramTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000_000)

    func sample(_ from: Double, _ to: Double, _ stage: SleepStage) -> SleepSample {
        SleepSample(start: t0.addingTimeInterval(from * 60), end: t0.addingTimeInterval(to * 60), stage: stage, source: "w")
    }

    @Test func slivers_go_and_the_same_stage_joins_up() {
        let segments = Hypnogram.segments([
            sample(0, 10, .core), sample(10, 10.5, .awake), sample(11, 20, .core), sample(20, 30, .unspecified),
        ])
        #expect(segments == [.init(start: t0, end: t0.addingTimeInterval(30 * 60), stage: .core)])
    }

    @Test func a_short_break_between_stages_closes_and_a_long_one_stays() {
        let segments = Hypnogram.segments([sample(0, 10, .core), sample(11, 20, .rem), sample(30, 40, .deep)])
        #expect(segments.map(\.stage) == [.core, .rem, .deep])
        #expect(segments[0].end == segments[1].start)
        #expect(segments[1].end == t0.addingTimeInterval(20 * 60))
        #expect(segments[2].start == t0.addingTimeInterval(30 * 60))
    }

    @Test func ticks_every_two_hours_or_three_for_a_long_night() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let bed = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 20, minute: 5))!
        let hours = { (ticks: [Date]) in ticks.map { calendar.component(.hour, from: $0) } }
        let long = Hypnogram.ticks(from: bed, to: bed.addingTimeInterval(11.9 * 3600), calendar: calendar)
        #expect(hours(long) == [21, 0, 3, 6])
        let short = Hypnogram.ticks(from: bed.addingTimeInterval(3 * 3600), to: bed.addingTimeInterval(11.9 * 3600), calendar: calendar)
        #expect(hours(short) == [0, 2, 4, 6])
    }
}
