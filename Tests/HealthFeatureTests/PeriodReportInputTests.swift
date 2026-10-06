// Tests/HealthFeatureTests/PeriodReportInputTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct PeriodReportInputTests {
    let cal = TestClock.calendar
    let archive = HealthArchive(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    var september: Period { Period.containing(TestClock.date(2026, 9, 15), .month, calendar: cal) }
    var q3: Period { Period.containing(TestClock.date(2026, 9, 15), .quarter, calendar: cal) }

    func record(_ m: Int, _ d: Int) -> DayRecord { DayRecord(day: TestClock.date(2026, m, d), steps: 9000, mood: .active) }
    var august: [DayRecord] { (1...31).map { record(8, $0) } }
    var septemberDays: [DayRecord] { (1...30).map { record(9, $0) } }

    func keepNote(_ day: String, headline: String = "Short night.", text: String = "You slept 5 h 52 min.") throws {
        let snapshot = HealthSnapshot(
            date: day, localTime: "08:30", locale: "en", sleep: nil, activity: nil, recovery: nil, body: nil,
            odyState: .tired)
        let summary = HealthSummary(
            headline: headline, summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
            memorySuggestion: nil, insights: [.init(category: "sleep", text: text, highlights: [])])
        try archive.write(ArchivedDay(snapshot: snapshot, summary: summary, generatedAt: TestClock.now))
    }

    func request(_ period: Period, _ records: [DayRecord]) -> PeriodReportRequest? {
        PeriodReportInput.request(
            period: period, records: records, archive: archive, calendar: cal, locale: "en", today: TestClock.today)
    }

    @Test func aMonthCarriesItsNumbersTheMonthBeforeAndItsNotes() throws {
        try keepNote("2026-09-15")
        try keepNote("2026-08-20")  // the month before's note stays out
        let r = try #require(request(september, august + septemberDays))
        #expect(r.period == .init(kind: .month, start: "2026-09-01", end: "2026-09-30"))
        #expect(r.current.daysWithData == 30)
        #expect(r.current.steps.average == 9000)
        #expect(r.previous?.daysWithData == 31)
        #expect(r.notes == [.init(day: "2026-09-15", headline: "Short night.", insights: [.init(category: "sleep", title: "You slept 5 h 52 min.")])])
        #expect(r.habits.isEmpty)
        #expect(r.locale == "en")
    }

    @Test func aQuarterSendsHeadlinesOnly() throws {
        try keepNote("2026-09-15")
        let r = try #require(request(q3, septemberDays))
        #expect(r.notes.map(\.headline) == ["Short night."])
        #expect(r.notes[0].insights.isEmpty)
    }

    @Test func aPeriodWithNoDataIsNoRequest() {
        #expect(request(september, []) == nil)
        #expect(request(september, august) == nil)
    }

    @Test func withNothingBeforeThereIsNoPreviousPeriod() throws {
        #expect(try #require(request(september, septemberDays)).previous == nil)
    }

    @Test func longNotesAreCutToWhatTheComputerTakes() throws {
        try keepNote("2026-09-15", headline: String(repeating: "睡", count: 130), text: String(repeating: "😴", count: 105))
        let note = try #require(request(september, septemberDays)?.notes.first)
        #expect(note.headline.utf16.count == 120)
        #expect(note.insights[0].title.utf16.count == 200)
        #expect(note.insights[0].title.count == 100)
        #expect(PeriodReportInput.clip("  x  ", 5) == "x")
    }

    @Test func anEmptyHeadlineIsNoNote() throws {
        try keepNote("2026-09-15", headline: "   ")
        #expect(try #require(request(september, septemberDays)).notes.isEmpty)
    }
}
