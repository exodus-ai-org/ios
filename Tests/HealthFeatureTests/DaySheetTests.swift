import Foundation
import Models
import SwiftUI
import Testing

@testable import HealthFeature

@MainActor
struct DaySheetTests {
    @Test func aDayWithoutANoteShowsTheNumbersItHas() {
        let r = DayRecord(
            day: TestClock.today, sleepMin: 460, steps: 9120, stepGoal: 8000, hrvMs: 48, waterCups: 3,
            bedtime: "23:40", mood: .rested)
        let rows = DayNumbers.rows(r)
        #expect(rows.map(\.symbol) == ["moon.zzz.fill", "bed.double.fill", "figure.walk", "waveform.path.ecg", "drop.fill"])
        #expect(rows[0].value == TrendText.duration(460))
        #expect(rows[1].value == "23:40")
        #expect(rows[2].value == 9120.formatted())
        #expect(rows[3].value == TrendText.ms(48))
        #expect(rows[4].value == CategoryValue.cups(3))
    }

    @Test func anEmptyDayHasNoRows() {
        #expect(DayNumbers.rows(DayRecord(day: TestClock.today)).isEmpty)
    }

    @Test func restingHeartRateReadsAsTheCardDoes() {
        let rows = DayNumbers.rows(DayRecord(day: TestClock.today, restingHr: 61.7))
        #expect(rows.map(\.symbol) == ["heart.fill"])
        #expect(rows[0].value == CategoryValue.bpm(61.7))
        #expect(rows[0].value.contains("61"))
        let noLevel = HealthRulesTests.snapshot(recovery: HealthRulesTests.recovery(nil))
        #expect(CategoryValue.text(.recovery, in: noLevel) == CategoryValue.bpm(60))
    }

    @Test func aNonFiniteHeartRateIsNotShown() {
        #expect(DayNumbers.rows(DayRecord(day: TestClock.today, restingHr: .nan)).isEmpty)
    }

    @Test func stepsReadAsTheCardDoes() {
        let s = HealthRulesTests.snapshot(activity: HealthRulesTests.steps(9120))
        #expect(CategoryValue.text(.activity, in: s) == CategoryValue.steps(9120))
        #expect(CategoryValue.steps(9120).contains("9"))
    }
}
