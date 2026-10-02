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

    /// No note and no Apple Health answer (yet, or at all): the question still carries the day, with what the calendar
    /// already knows of it, and Chat's card still has something to show.
    @Test func aQuestionAlwaysCarriesTheDay() throws {
        let day = TestClock.date(2026, 9, 28)
        let record = DayRecord(day: day, sleepMin: 400, steps: 6000, hrvMs: 44, restingHr: 58, waterCups: 4, mood: .calm)
        let full = DaySheet.minimalSnapshot(day: day, record: record, calendar: TestClock.calendar, locale: "en", now: TestClock.now)
        #expect(full.date == "2026-09-28")
        #expect(full.localTime == "23:59")
        #expect(full.locale == "en")
        #expect(full.odyState == .calm)
        #expect(full.recovery?.hrvMs == 44 && full.recovery?.restingHr == 58)
        #expect(full.body?.waterCups == 4)
        // Their wire shape wants stages, calories and hours stood the calendar never read; a zero would read as measured.
        #expect(full.sleep == nil && full.activity == nil)

        let bare = DaySheet.minimalSnapshot(day: day, record: nil, calendar: TestClock.calendar, locale: "en", now: TestClock.now)
        #expect(bare.date == "2026-09-28" && bare.recovery == nil && bare.body == nil && bare.odyState == .noData)
        let today = DaySheet.minimalSnapshot(
            day: TestClock.today, record: nil, calendar: TestClock.calendar, locale: "en", now: TestClock.now)
        #expect(today.localTime == "15:00")

        let json = try #require(DaySheet.attachment(snapshot: nil, archived: nil, fallback: bare))
        let sent = try JSONDecoder().decode(HealthSnapshot.self, from: Data(json.utf8))
        #expect(sent.date == "2026-09-28")
        let read = HealthRulesTests.snapshot(recovery: HealthRulesTests.recovery(nil))
        let fromRead = try #require(DaySheet.attachment(snapshot: read, archived: bare, fallback: bare))
        #expect(try JSONDecoder().decode(HealthSnapshot.self, from: Data(fromRead.utf8)) == read)
        let fromNote = try #require(DaySheet.attachment(snapshot: nil, archived: full, fallback: bare))
        #expect(try JSONDecoder().decode(HealthSnapshot.self, from: Data(fromNote.utf8)) == full)
    }
}
