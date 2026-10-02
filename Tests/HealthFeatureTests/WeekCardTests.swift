import Foundation
import SwiftUI
import Testing

@testable import HealthFeature

@MainActor
struct WeekCardTests {
    let cal = TestClock.calendar

    private func glance() -> WeekGlance {
        let period = Period.containing(TestClock.today, .week, calendar: cal)
        let records = [TestClock.today: DayRecord(day: TestClock.today, sleepMin: 460, steps: 9120, mood: .rested)]
        let cells = CalendarGrid.cells(period, records: records, today: TestClock.today, calendar: cal)
        return WeekGlance(period: period, cells: cells, current: TrendMath.aggregate(Array(records.values), in: period, today: TestClock.today, calendar: cal),
            previous: TrendMath.aggregate([], in: period.previous(calendar: cal), today: TestClock.today, calendar: cal))
    }

    @Test func theCardHoldsSevenDaysAndRenders() {
        let week = glance()
        #expect(week.cells.count == 7)
        let image = ImageRenderer(content: WeekCard(week: week, calendar: cal).frame(width: 360))
        #expect(image.cgImage != nil)
    }
}
