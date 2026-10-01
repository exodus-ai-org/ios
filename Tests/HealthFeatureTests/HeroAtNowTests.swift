// Tests/HealthFeatureTests/HeroAtNowTests.swift
import Foundation
import Testing

@testable import HealthFeature

@MainActor
struct HeroAtNowTests {
    let scrub = DayScrub(now: TestClock.now, calendar: TestClock.calendar)  // now = 15.0

    @Test func aNudgePastNowIsStillNow() {
        let past = scrub.hour(from: 15, translation: 20, width: 300)  // rightward: rubber-bands into the future
        #expect(past > 15.05)
        #expect(HealthHero.isAtNow(hour: past, scrub: scrub))
        #expect(HealthHero.isAtNow(hour: 18, scrub: scrub))
    }

    @Test func goingBackIsAScrub() {
        #expect(HealthHero.isAtNow(hour: 14.99, scrub: scrub))
        #expect(!HealthHero.isAtNow(hour: 14.9, scrub: scrub))
        #expect(!HealthHero.isAtNow(hour: 3, scrub: scrub))
    }
}
