// Tests/HealthFeatureTests/DayScrubTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct DayScrubTests: Sendable {
    let scrub = DayScrub(now: TestClock.now, calendar: TestClock.calendar)  // now = 15.0

    @Test func rangeIsSixPmYesterdayToNow() {
        #expect(scrub.start == -6)
        #expect(scrub.now == 15)
    }

    /// The knob runs earliest-left to now-right, and follows the finger.
    @Test func dragLeftGoesBackInTimeAndRightComesForward() {
        #expect(scrub.hour(from: 15, translation: -300, width: 300) == 5)
        #expect(scrub.hour(from: 5, translation: 150, width: 300) == 10)
    }

    @Test func pastTheEndsItResists() {
        let past = scrub.hour(from: 15, translation: 300, width: 300)  // 10 h into the future
        #expect(past > 15 && past < 18)  // rubber(10, 4) ≈ 2.3 h
        let before = scrub.hour(from: -6, translation: -300, width: 300)
        #expect(before < -6 && before > -9)
    }

    @Test func throwSpeedHasTheDragsSign() {
        #expect(DayScrub.hoursPerSecond(velocity: 300, width: 300) == 10)
        #expect(DayScrub.hoursPerSecond(velocity: -150, width: 300) == -5)
        #expect(DayScrub.hoursPerSecond(velocity: 300, width: 0) == 0)
    }

    @Test func releaseProjectsAndClamps() {
        let flung = scrub.release(at: 10, velocity: -3000, width: 300, reduceMotion: false)  // fast, leftward
        #expect(flung < 10)
        #expect(flung >= -6)
        let forward = scrub.release(at: 10, velocity: 3000, width: 300, reduceMotion: false)  // fast, rightward
        #expect(forward > 10 && forward <= 15)
        #expect(scrub.release(at: 16, velocity: 0, width: 300, reduceMotion: false) == 15)
    }

    @Test func nearNowSnapsToNow() {
        #expect(scrub.release(at: 14.8, velocity: 0, width: 300, reduceMotion: false) == 15)
        #expect(!scrub.isScrubbing(15.01))
        #expect(scrub.isScrubbing(14))
    }

    @Test func reduceMotionHasNoMomentum() {
        #expect(scrub.release(at: 10, velocity: -3000, width: 300, reduceMotion: true) == 10)
    }

    @Test func earlyMorningRangeIsValid() {
        let s = DayScrub(now: TestClock.date(2026, 10, 1, 0, 30), calendar: TestClock.calendar)
        #expect(s.now == 0.5)
        #expect(s.start < s.now)
    }

    // Pose
    func night() -> SleepNight {
        let t = { (h: Double) in TestClock.today.addingTimeInterval(h * 3600) }
        let stages = [
            SleepSample(start: t(-0.2), end: t(0.5), stage: .core, source: "w"),
            SleepSample(start: t(0.5), end: t(1.3), stage: .deep, source: "w"),
            SleepSample(start: t(1.3), end: t(6), stage: .rem, source: "w"),
        ]
        return SleepNight(asleepMin: 372, deepMin: 48, coreMin: 42, remMin: 282, awakeMin: 0, bedtime: t(-0.2), wake: t(6), stages: stages)
    }

    @Test func asleepDuringTheNightAndDeeperInDeepSleep() {
        let deep = HeroPose.at(hour: 1, scrub: scrub, mood: .tired, night: night(), today: TestClock.today)
        let rem = HeroPose.at(hour: 3, scrub: scrub, mood: .tired, night: night(), today: TestClock.today)
        #expect(deep.asleep && deep.expression == .sleepy && deep.stage == .deep)
        #expect(deep.sink > rem.sink)
        #expect(deep.tilt == -10)
    }

    @Test func nowShowsTheHeroMood() {
        let tired = HeroPose.at(hour: 15, scrub: scrub, mood: .tired, night: night(), today: TestClock.today)
        #expect(!tired.asleep && tired.tiredness == 1 && tired.expression == .happy)
        #expect(HeroPose.at(hour: 15, scrub: scrub, mood: .active, night: nil, today: TestClock.today).expression == .grin)
        #expect(HeroPose.at(hour: 15, scrub: scrub, mood: .noData, night: nil, today: TestClock.today).expression == .curious)
    }

    @Test func awakeBeforeBedWhileScrubbing() {
        let p = HeroPose.at(hour: -3, scrub: scrub, mood: .tired, night: night(), today: TestClock.today)
        #expect(!p.asleep && p.tiredness == 0)
    }
}
