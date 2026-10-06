// Tests/HealthFeatureTests/PeriodReportScheduleTests.swift
import Foundation
import Testing

@testable import HealthFeature

struct PeriodReportScheduleTests {
    let cal = TestClock.calendar

    func ids(_ periods: [Period]) -> [String] { periods.compactMap { $0.reportID(calendar: cal) } }

    @Test func onTheFirstOfAMonthTheMonthComesFirst() {
        // Thursday 1 October 2026: September and Q3 ended this morning, week 39 on Monday.
        #expect(ids(PeriodReportSchedule.lastFinished(today: TestClock.now, calendar: cal)) == ["2026-09", "2026-Q3", "2026-W39", "2025"])
    }

    @Test func onAMondayLastWeekComesFirst() {
        #expect(ids(PeriodReportSchedule.lastFinished(today: TestClock.date(2026, 10, 5, 9), calendar: cal)) == ["2026-W40", "2026-09", "2026-Q3", "2025"])
    }

    @Test func newYearsDay() {
        // Friday 1 January 2027 is in 2026-W53; December, Q4 and 2026 all ended this morning, the shorter first.
        #expect(ids(PeriodReportSchedule.lastFinished(today: TestClock.date(2027, 1, 1, 9), calendar: cal)) == ["2026-12", "2026-Q4", "2026", "2026-W52"])
    }

    @Test func aKeptReportIsNotDue() {
        let due = PeriodReportSchedule.due(today: TestClock.now, calendar: cal) { $0 == "2026-09" || $0 == "2025" }
        #expect(ids(due) == ["2026-Q3", "2026-W39"])
    }
}
