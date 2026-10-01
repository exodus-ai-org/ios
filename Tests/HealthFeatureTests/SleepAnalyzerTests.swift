// Tests/HealthFeatureTests/SleepAnalyzerTests.swift
import Foundation
import Testing

@testable import HealthFeature

struct SleepAnalyzerTests {
    private let cal = TestClock.calendar
    private func t(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { TestClock.date(2026, d < 15 ? 10 : 9, d, h, m) }
    private func s(_ a: Date, _ b: Date, _ stage: SleepStage, _ source: String = "watch") -> SleepSample {
        SleepSample(start: a, end: b, stage: stage, source: source)
    }

    @Test func windowIsSixPmYesterdayToNoonToday() {
        let w = SleepAnalyzer.window(endingOn: TestClock.today, calendar: cal)
        #expect(w.start == t(30, 18))
        #expect(w.end == t(1, 12))
    }

    @Test func sumsStagesAndFindsBedtimeAndWake() throws {
        let samples = [
            s(t(30, 23, 48), t(1, 0, 30), .core),
            s(t(1, 0, 30), t(1, 1, 18), .deep),
            s(t(1, 1, 18), t(1, 1, 30), .awake),
            s(t(1, 1, 30), t(1, 2, 30), .rem),
            s(t(1, 2, 30), t(1, 6, 0), .core),
        ]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.deepMin == 48)
        #expect(night.remMin == 60)
        #expect(night.coreMin == 42 + 210)
        #expect(night.awakeMin == 12)
        #expect(night.asleepMin == 48 + 60 + 252)
        #expect(night.bedtime == t(30, 23, 48))
        #expect(night.wake == t(1, 6, 0))
        #expect(night.stages.count == 5)
    }

    @Test func overlappingSourcesAreCountedOnceFromTheStagedOne() throws {
        let samples = [
            s(t(30, 23, 0), t(1, 7, 0), .unspecified, "iphone"),  // 8 h, no stages
            s(t(30, 23, 30), t(1, 3, 0), .core, "watch"),
            s(t(1, 3, 0), t(1, 4, 0), .deep, "watch"),
            s(t(1, 4, 0), t(1, 6, 30), .rem, "watch"),
        ]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.asleepMin == 210 + 60 + 150)
        #expect(night.stages.allSatisfy { $0.source == "watch" })
    }

    @Test func withoutStagedDataTheLongestUnspecifiedSourceWins() throws {
        let samples = [
            s(t(30, 23, 0), t(1, 6, 0), .unspecified, "iphone"),
            s(t(1, 1, 0), t(1, 2, 0), .unspecified, "other"),
        ]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.asleepMin == 420)
    }

    @Test func samplesAreClippedToTheWindow() throws {
        let samples = [s(t(30, 17, 0), t(30, 19, 0), .core), s(t(1, 11, 0), t(1, 13, 0), .core)]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.asleepMin == 60 + 60)
    }

    @Test func noSleepIsNil() {
        #expect(SleepAnalyzer.night(from: [], endingOn: TestClock.today, calendar: cal) == nil)
        let awakeOnly = [s(t(1, 2, 0), t(1, 3, 0), .awake)]
        #expect(SleepAnalyzer.night(from: awakeOnly, endingOn: TestClock.today, calendar: cal) == nil)
    }

    @Test func windowFollowsTheWallClockAcrossDST() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        for (y, m, d, before) in [(2026, 3, 8, 7), (2026, 11, 1, 31)] {
            let day = ny.date(from: DateComponents(year: y, month: m, day: d))!
            let w = SleepAnalyzer.window(endingOn: day, calendar: ny)
            let from = ny.dateComponents([.day, .hour, .minute], from: w.start)
            let to = ny.dateComponents([.day, .hour, .minute], from: w.end)
            #expect(from.day == before && from.hour == 18 && from.minute == 0)
            #expect(to.day == d && to.hour == 12 && to.minute == 0)
        }
    }

    @Test func overlapsWithinOneSourceCountOnce() throws {
        let samples = [
            s(t(30, 23, 0), t(1, 7, 0), .unspecified, "watch"),
            s(t(1, 1, 0), t(1, 2, 0), .deep, "watch"),
            s(t(1, 3, 0), t(1, 4, 0), .rem, "watch"),
        ]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.asleepMin == 480)
        #expect(night.deepMin == 60)
        #expect(night.remMin == 60)
        #expect(night.coreMin == 360)
        #expect(night.stages.count == 5)
    }

    @Test func asleepBeatsAwakeWhereTheyOverlap() throws {
        let samples = [s(t(1, 0, 0), t(1, 4, 0), .core), s(t(1, 1, 0), t(1, 2, 0), .awake)]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.asleepMin == 240)
        #expect(night.awakeMin == 0)
    }

    @Test func aFullTieChoosesTheSourceByName() throws {
        let samples = [s(t(1, 0, 0), t(1, 2, 0), .core, "b"), s(t(1, 3, 0), t(1, 5, 0), .core, "a")]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.stages.allSatisfy { $0.source == "a" })
    }
}
