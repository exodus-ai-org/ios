import Foundation
import Testing

@testable import WidgetKitShared

@Suite("WidgetPresentation: what an entry shows at its hour")
struct WidgetPresentationTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test("morning from 5, afternoon from 12, evening from 18 until 5", arguments: [
        (4, WidgetPresentation.Period.evening), (5, .morning), (11, .morning), (12, .afternoon), (17, .afternoon),
        (18, .evening), (23, .evening),
    ])
    func periods(hour: Int, period: WidgetPresentation.Period) {
        #expect(WidgetPresentation.period(at: date(1, hour), calendar: calendar) == period)
    }

    @Test("today's glance shows today, and after midnight it is gone")
    func staleHealth() {
        let glance = HealthGlance(
            day: "2026-10-01", sleepMinutes: 352, steps: 10, stepGoal: 8000, headline: nil, suggestion: nil,
            mood: .neutral)
        let snapshot = WidgetSnapshot.empty.updating(health: glance, at: date(1, 8))
        #expect(WidgetPresentation.health(of: snapshot, at: date(1, 23, 59), calendar: calendar) == glance)
        #expect(WidgetPresentation.health(of: snapshot, at: date(2, 0, 30), calendar: calendar) == nil)
    }

    @Test("twelve hourly entries, the first now, the rest on the hour")
    func entries() {
        let dates = WidgetPresentation.entryDates(from: date(1, 9, 41), calendar: calendar)
        #expect(dates.count == 12)
        #expect(dates.first == date(1, 9, 41))
        #expect(dates[1] == date(1, 10))
        #expect(dates.last == date(1, 20))
    }

    @Test("the clock hour carries the minutes, for the sky")
    func clockHour() {
        #expect(WidgetPresentation.clockHour(at: date(1, 18, 30), calendar: calendar) == 18.5)
    }
}
