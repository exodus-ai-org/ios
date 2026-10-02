import Foundation
import Models
import Testing

@testable import HealthFeature

struct DayCellTextTests {
    let cal = TestClock.calendar

    @Test func aCellReadsItsDayStateAndNumbers() {
        let record = DayRecord(day: TestClock.today, sleepMin: 460, steps: 9120, mood: .rested)
        let cell = CalendarCell(id: 0, day: TestClock.today, record: record, isToday: true, isFuture: false)
        let label = DayCellText.label(cell, calendar: cal)
        let date = TestClock.today.formatted(Date.FormatStyle(calendar: cal, timeZone: cal.timeZone).month(.wide).day())
        #expect(label.hasPrefix(date))
        #expect(label.contains("Today"))
        #expect(label.contains("Rested or active"))
        #expect(label.contains("Sleep " + TrendText.duration(460)))
        #expect(label.contains(CategoryValue.steps(9120)))
    }

    @Test func aDayWithNothingSaysSo() {
        let cell = CalendarCell(id: 0, day: TestClock.today, record: nil, isToday: false, isFuture: false)
        #expect(DayCellText.label(cell, calendar: cal).hasSuffix("No data"))
        #expect(!DayCellText.label(cell, calendar: cal).contains("Today"))
    }
}
