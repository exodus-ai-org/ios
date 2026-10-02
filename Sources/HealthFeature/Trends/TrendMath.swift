// Sources/HealthFeature/Trends/TrendMath.swift
import Foundation

/// A stretch of whole days: an ISO week (Monday to Sunday, whatever the region's first weekday), a calendar month,
/// quarter or year, or the N days ending on a day. `start` is the first day's start and `end` the start of the day
/// after the last, in the calendar's time zone, so a daylight-saving week is still seven days.
public struct Period: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case week, month, quarter, year
        case days(Int)
    }

    public let kind: Kind
    public let start: Date
    public let end: Date

    /// The period of `kind` that holds `date`; for `.days(n)`, the n days ending on `date`'s day.
    public static func containing(_ date: Date, _ kind: Kind, calendar: Calendar) -> Period {
        let cal = TrendMath.calendar(calendar)
        let day = cal.startOfDay(for: date)
        let c = cal.dateComponents([.year, .month], from: day)
        func first(month: Int) -> Date {
            cal.startOfDay(for: cal.date(from: DateComponents(year: c.year, month: month, day: 1))!)
        }
        let start: Date
        switch kind {
        case .week:
            // Gregorian weekdays run Sunday 1 … Saturday 7; Monday is 0 days into an ISO week.
            let back = (cal.component(.weekday, from: day) + 5) % 7
            start = cal.startOfDay(for: cal.date(byAdding: .day, value: -back, to: day)!)
        case .month: start = first(month: c.month!)
        case .quarter: start = first(month: (c.month! - 1) / 3 * 3 + 1)
        case .year: start = first(month: 1)
        case .days(let n): start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(max(n, 1) - 1), to: day)!)
        }
        return Period(kind: kind, start: start, end: advance(start, kind, by: 1, cal))
    }

    public func previous(calendar: Calendar) -> Period { shifted(-1, calendar) }

    public func next(calendar: Calendar) -> Period { shifted(1, calendar) }

    /// Each day's start, first to last.
    public func days(calendar: Calendar) -> [Date] {
        var out: [Date] = []
        var d = start
        while d < end {
            out.append(d)
            d = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: d)!)
        }
        return out
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// The ISO week number of a week (1–53).
    public func isoWeek(calendar: Calendar) -> Int {
        TrendMath.calendar(calendar).component(.weekOfYear, from: start)
    }

    /// The name a later phase files this period's report under: "2026-W40", "2026-09", "2026-Q3", "2026"; an N-day
    /// window has none. Weeks use the ISO week-numbering year, so 1 January 2027 is in "2026-W53".
    public func reportID(calendar: Calendar) -> String? {
        let cal = TrendMath.calendar(calendar)
        let c = cal.dateComponents([.year, .month, .weekOfYear, .yearForWeekOfYear], from: start)
        switch kind {
        case .week: return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
        case .month: return String(format: "%04d-%02d", c.year!, c.month!)
        case .quarter: return String(format: "%04d-Q%d", c.year!, (c.month! - 1) / 3 + 1)
        case .year: return String(format: "%04d", c.year!)
        case .days: return nil
        }
    }

    private func shifted(_ n: Int, _ calendar: Calendar) -> Period {
        let cal = TrendMath.calendar(calendar)
        let s = Self.advance(start, kind, by: n, cal)
        return Period(kind: kind, start: s, end: Self.advance(s, kind, by: 1, cal))
    }

    /// Calendar arithmetic, never seconds: a month, quarter or year from its first day lands on a first day.
    private static func advance(_ start: Date, _ kind: Kind, by n: Int, _ cal: Calendar) -> Date {
        let moved: Date =
            switch kind {
            case .week: cal.date(byAdding: .day, value: 7 * n, to: start)!
            case .month: cal.date(byAdding: .month, value: n, to: start)!
            case .quarter: cal.date(byAdding: .month, value: 3 * n, to: start)!
            case .year: cal.date(byAdding: .year, value: n, to: start)!
            case .days(let d): cal.date(byAdding: .day, value: max(d, 1) * n, to: start)!
            }
        return cal.startOfDay(for: moved)
    }
}

/// One number over a period: its average, lowest and highest, and on how many days it was recorded.
public struct MetricSummary: Equatable, Sendable, Codable {
    public var average: Double?
    public var min: Double?
    public var max: Double?
    public var days: Int

    public init(average: Double?, min: Double?, max: Double?, days: Int) {
        self.average = average
        self.min = min
        self.max = max
        self.days = days
    }

    static func of(_ values: [Double]) -> MetricSummary {
        guard !values.isEmpty else { return MetricSummary(average: nil, min: nil, max: nil, days: 0) }
        return MetricSummary(
            average: values.reduce(0, +) / Double(values.count), min: values.min(), max: values.max(),
            days: values.count)
    }
}

/// A period in numbers: what the home card, the calendar's header and (later) the period reports and habits read.
public struct Aggregates: Equatable, Sendable, Codable {
    /// Days of the period that have begun: all of a past period, up to and including today in the current one.
    public var elapsedDays: Int
    /// Days with any number at all, today included. A summary's own `days` says how many days it averaged.
    public var daysWithData: Int
    public var sleepMin: MetricSummary
    public var steps: MetricSummary
    public var exerciseMin: MetricSummary
    public var hrvMs: MetricSummary
    public var restingHr: MetricSummary
    public var waterCups: MetricSummary
    /// Of the finished days with steps, the share at or over that day's goal.
    public var stepGoalRate: Double?
    /// Of the nights recorded, the share at or over the sleep target.
    public var sleepTargetRate: Double?
}

/// A number against the same number in the period before.
public struct TrendChange: Equatable, Sendable {
    public enum Direction: Equatable, Sendable { case up, down, flat }

    public var absolute: Double
    /// Against the previous value; nil when that was zero.
    public var relative: Double?
    public var direction: Direction
}

/// The trends' arithmetic, in one place for the home card, the calendar and the later phases.
public enum TrendMath {
    /// Under 3 % either way is no change.
    public static let flatThreshold = 0.03
    /// A night at or over 7 hours hit the target.
    public static let sleepTargetMin = 420

    /// The calendar periods are counted in: Gregorian in the given calendar's time zone, weeks from Monday, week 1
    /// the one holding the year's first Thursday (ISO 8601) — the same whatever the region's own first weekday.
    public static func calendar(_ base: Calendar) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = base.timeZone
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    /// The records inside `period` up to `today` (later or outside ones are ignored), summed up. Steps, exercise and
    /// water still add up through today, so their summaries and the step-goal rate stop at yesterday: a Monday
    /// morning's 1,200 steps is not a day of steps. Last night's sleep, HRV and resting heart rate are done and count.
    public static func aggregate(
        _ records: [DayRecord], in period: Period, today: Date, calendar: Calendar,
        sleepTarget: Int = TrendMath.sleepTargetMin
    ) -> Aggregates {
        let last = calendar.startOfDay(for: today)
        let days = records.filter { period.contains($0.day) && $0.day <= last }
        let finished = days.filter { $0.day < last }
        func values(_ pick: (DayRecord) -> Double?) -> [Double] { days.compactMap(pick) }
        func totals(_ pick: (DayRecord) -> Int?) -> [Double] { finished.compactMap { pick($0).map(Double.init) } }
        let withSteps = finished.compactMap { r in r.steps.map { (steps: $0, goal: r.stepGoal) } }
        let nights = days.compactMap(\.sleepMin)
        return Aggregates(
            elapsedDays: period.days(calendar: calendar).filter { $0 <= last }.count,
            daysWithData: days.filter(\.hasData).count,
            sleepMin: .of(values { $0.sleepMin.map { Double($0) } }),
            steps: .of(totals(\.steps)),
            exerciseMin: .of(totals(\.exerciseMin)),
            hrvMs: .of(values { $0.hrvMs }),
            restingHr: .of(values { $0.restingHr }),
            waterCups: .of(totals(\.waterCups)),
            stepGoalRate: withSteps.isEmpty
                ? nil : Double(withSteps.filter { $0.steps >= $0.goal }.count) / Double(withSteps.count),
            sleepTargetRate: nights.isEmpty
                ? nil : Double(nights.filter { $0 >= sleepTarget }.count) / Double(nights.count))
    }

    /// The change from `previous` to `current`; nil unless both are known.
    public static func change(_ current: Double?, from previous: Double?) -> TrendChange? {
        guard let current, let previous else { return nil }
        let absolute = current - previous
        let relative: Double? = previous == 0 ? nil : absolute / abs(previous)
        let direction: TrendChange.Direction
        if let relative {
            if abs(relative) < flatThreshold {
                direction = .flat
            } else {
                direction = relative > 0 ? .up : .down
            }
        } else if absolute == 0 {
            direction = .flat
        } else {
            direction = absolute > 0 ? .up : .down
        }
        return TrendChange(absolute: absolute, relative: relative, direction: direction)
    }
}
