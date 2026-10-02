// Sources/HealthFeature/Trends/CalendarGrid.swift
import Foundation

/// One square of the calendar: a day (past, today or still to come), or a blank before a month's first day.
struct CalendarCell: Identifiable, Equatable, Sendable {
    let id: Int
    let day: Date?
    let record: DayRecord?
    let isToday: Bool
    let isFuture: Bool

    var tone: DayTone { record.map { DayTone($0.mood) } ?? .empty }
}

/// A month as a bar in the quarter and year views.
struct MonthBar: Identifiable, Equatable, Sendable {
    let month: Period
    let aggregates: Aggregates
    let isFuture: Bool
    var id: Date { month.start }
}

/// The home's "This week" card: the week's days and its averages beside last week's.
struct WeekGlance: Equatable, Sendable {
    var period: Period
    var cells: [CalendarCell]
    var current: Aggregates
    var previous: Aggregates
}

enum CalendarGrid {
    /// The days of a week or a month, Monday first; a month opens with blanks up to its first weekday. Days to come
    /// carry no record.
    static func cells(_ period: Period, records: [Date: DayRecord], today: Date, calendar: Calendar) -> [CalendarCell] {
        let iso = TrendMath.calendar(calendar)
        let last = calendar.startOfDay(for: today)
        var cells: [CalendarCell] = []
        if period.kind == .month {
            let lead = (iso.component(.weekday, from: period.start) + 5) % 7
            cells += (0..<lead).map { CalendarCell(id: -1 - $0, day: nil, record: nil, isToday: false, isFuture: false) }
        }
        for (i, day) in period.days(calendar: calendar).enumerated() {
            cells.append(
                CalendarCell(
                    id: i, day: day, record: day <= last ? records[day] : nil, isToday: day == last,
                    isFuture: day > last))
        }
        return cells
    }

    /// The months of a quarter or a year, each with its own averages.
    static func months(_ period: Period, records: [DayRecord], today: Date, calendar: Calendar) -> [MonthBar] {
        let last = calendar.startOfDay(for: today)
        var bars: [MonthBar] = []
        var month = Period.containing(period.start, .month, calendar: calendar)
        while month.start < period.end {
            bars.append(
                MonthBar(
                    month: month, aggregates: TrendMath.aggregate(records, in: month, today: last, calendar: calendar),
                    isFuture: month.start > last))
            month = month.next(calendar: calendar)
        }
        return bars
    }
}
