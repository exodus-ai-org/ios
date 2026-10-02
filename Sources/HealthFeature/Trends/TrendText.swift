// Sources/HealthFeature/Trends/TrendText.swift
import Foundation
import SwiftUI

/// The calendar's four views.
public enum TrendScope: String, CaseIterable, Hashable, Sendable {
    case week, month, quarter, year

    var kind: Period.Kind {
        switch self {
        case .week: .week
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .week: LocalizedStringResource("ios:health.calendar.scope.week", defaultValue: "Week", comment: "Calendar page picker: show one week.")
        case .month: LocalizedStringResource("ios:health.calendar.scope.month", defaultValue: "Month", comment: "Calendar page picker: show one month.")
        case .quarter: LocalizedStringResource("ios:health.calendar.scope.quarter", defaultValue: "Quarter", comment: "Calendar page picker: show one quarter (three months).")
        case .year: LocalizedStringResource("ios:health.calendar.scope.year", defaultValue: "Year", comment: "Calendar page picker: show one year.")
        }
    }

    /// What a change is measured against.
    var versusLabel: LocalizedStringResource {
        switch self {
        case .week: LocalizedStringResource("ios:health.calendar.vs.week", defaultValue: "vs last week", comment: "Calendar header: the change shown is against last week.")
        case .month: LocalizedStringResource("ios:health.calendar.vs.month", defaultValue: "vs last month", comment: "Calendar header: the change shown is against last month.")
        case .quarter: LocalizedStringResource("ios:health.calendar.vs.quarter", defaultValue: "vs last quarter", comment: "Calendar header: the change shown is against the previous quarter.")
        case .year: LocalizedStringResource("ios:health.calendar.vs.year", defaultValue: "vs last year", comment: "Calendar header: the change shown is against last year.")
        }
    }
}

/// Where the calendar opens: a view, a day inside the period to show, and optionally a day whose sheet is up.
public struct TrendsRoute: Hashable, Sendable {
    public var scope: TrendScope
    public var anchor: Date
    public var presentedDay: Date?

    public init(scope: TrendScope, anchor: Date, presentedDay: Date? = nil) {
        self.scope = scope
        self.anchor = anchor
        self.presentedDay = presentedDay
    }
}

/// The three numbers the calendar's header (and the home card, sleep and steps) compares.
enum TrendMetric: CaseIterable, Hashable, Sendable {
    case sleep, steps, hrv

    func value(_ a: Aggregates) -> Double? {
        switch self {
        case .sleep: a.sleepMin.average
        case .steps: a.steps.average
        case .hrv: a.hrvMs.average
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .sleep: LocalizedStringResource("ios:health.calendar.stat.sleep", defaultValue: "Avg. sleep", comment: "Calendar header and home card: average sleep per night over the period.")
        case .steps: LocalizedStringResource("ios:health.calendar.stat.steps", defaultValue: "Daily steps", comment: "Calendar header and home card: average steps per day over the period.")
        case .hrv: LocalizedStringResource("ios:health.calendar.stat.hrv", defaultValue: "HRV", comment: "Calendar header: average heart rate variability (abbreviation) over the period.")
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .sleep: TrendText.duration(v)
        case .steps: TrendText.steps(v)
        case .hrv: TrendText.ms(v)
        }
    }
}

/// The calendar's words and numbers, in the user's language.
enum TrendText {
    /// "Week 40", "October 2026", "Q3 2026", "2026": the period row and the screenshot's name.
    static func title(_ p: Period, calendar: Calendar) -> String {
        let style = Date.FormatStyle(calendar: TrendMath.calendar(calendar), timeZone: calendar.timeZone)
        switch p.kind {
        case .week:
            let n = p.isoWeek(calendar: calendar)
            return String(
                localized: "ios:health.calendar.weekTitle", defaultValue: "Week \(n)",
                comment: "Calendar page: a week's title. %lld is the ISO week number (1-53).")
        case .month: return p.start.formatted(style.month(.wide).year())
        case .quarter: return p.start.formatted(style.quarter(.abbreviated).year())
        case .year: return p.start.formatted(style.year())
        case .days: return range(p, calendar: calendar)
        }
    }

    /// "Sep 28 – Oct 4".
    static func range(_ p: Period, calendar: Calendar) -> String {
        let last = calendar.date(byAdding: .day, value: -1, to: p.end)!
        let style = Date.IntervalFormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        return (p.start..<last).formatted(style)
    }

    /// Monday first, in the user's language ("M T W T F S S").
    static func weekdayInitials(calendar: Calendar) -> [String] {
        var c = calendar
        c.locale = .current
        let symbols = c.veryShortStandaloneWeekdaySymbols
        return Array(symbols[1...] + symbols[..<1])
    }

    /// "7h 40m".
    static func duration(_ minutes: Double) -> String {
        Duration.seconds(Int(minutes.rounded()) * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// "7:40", for a week cell's narrow column.
    static func clock(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.time(pattern: .hourMinute))
    }

    static func steps(_ n: Double) -> String { Int(n.rounded()).formatted() }

    /// "9.1K".
    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }

    /// "38 ms".
    static func ms(_ v: Double) -> String {
        Measurement(value: v.rounded(), unit: UnitDuration.milliseconds)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// "↑ 52m", "↓ 12%", "→", or "—" with nothing to compare. Steps change by share, the others by amount.
    static func delta(_ change: TrendChange?, metric: TrendMetric) -> String {
        guard let change else { return "—" }
        switch change.direction {
        case .flat: return "→"
        case .up: return "↑ " + amount(change, metric: metric)
        case .down: return "↓ " + amount(change, metric: metric)
        }
    }

    static func amount(_ change: TrendChange, metric: TrendMetric) -> String {
        switch metric {
        case .sleep: duration(abs(change.absolute))
        case .steps:
            change.relative.map { abs($0).formatted(.percent.precision(.fractionLength(0))) }
                ?? steps(abs(change.absolute))
        case .hrv: ms(abs(change.absolute))
        }
    }

    /// What VoiceOver reads for a number: its name, its value, which way it went, against what.
    static func spoken(metric: TrendMetric, value: Double?, change: TrendChange?, scope: TrendScope) -> String {
        let shown = value.map(metric.format) ?? String(localized: DayTone.empty.name)
        let moved: String
        if let change {
            switch change.direction {
            case .up:
                let by = amount(change, metric: metric)
                moved = String(
                    localized: "ios:health.calendar.change.up", defaultValue: "Up \(by)",
                    comment: "VoiceOver: a number went up against the previous period. %@ is the amount, e.g. 52m or 12%.")
            case .down:
                let by = amount(change, metric: metric)
                moved = String(
                    localized: "ios:health.calendar.change.down", defaultValue: "Down \(by)",
                    comment: "VoiceOver: a number went down against the previous period. %@ is the amount, e.g. 52m or 12%.")
            case .flat:
                moved = String(
                    localized: "ios:health.calendar.change.flat", defaultValue: "About the same",
                    comment: "VoiceOver: a number changed less than 3% against the previous period.")
            }
        } else {
            moved = String(
                localized: "ios:health.calendar.change.none", defaultValue: "Nothing earlier to compare",
                comment: "VoiceOver: the previous period has no data for this number.")
        }
        return [String(localized: metric.title), shown, moved, String(localized: scope.versusLabel)]
            .joined(separator: ", ")
    }

    /// Up in the note's green, down in a warm orange (4.5:1 on the card in both modes), level in secondary ink.
    static func color(_ change: TrendChange?) -> AnyShapeStyle {
        switch change?.direction {
        case .up: AnyShapeStyle(ReportInk.green)
        case .down: AnyShapeStyle(Color.adaptive(0xB4470C, dark: 0xFFA27A))
        case .flat, nil: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }
}
