// Sources/HealthFeature/Report/PeriodReportSchedule.swift
import Foundation

/// Which period reports are due (spec §5): the last finished week, month, quarter and year that have no kept report.
/// Only the last of each — never a backlog.
enum PeriodReportSchedule {
    /// Model calls one Health open may make.
    static let perOpen = 2

    /// The last finished week, month, quarter and year, newest first: by when they ended, and of two that ended
    /// together the shorter first (on 1 October: September, then Q3).
    static func lastFinished(today: Date, calendar: Calendar) -> [Period] {
        let kinds: [Period.Kind] = [.week, .month, .quarter, .year]
        return kinds.enumerated()
            .map { (rank: $0.offset, period: Period.containing(today, $0.element, calendar: calendar).previous(calendar: calendar)) }
            .sorted { $0.period.end != $1.period.end ? $0.period.end > $1.period.end : $0.rank < $1.rank }
            .map(\.period)
    }

    /// Of those, the ones with no kept report: a kept one is never written again by itself.
    static func due(today: Date, calendar: Calendar, isKept: (String) -> Bool) -> [Period] {
        lastFinished(today: today, calendar: calendar).filter { period in
            period.reportID(calendar: calendar).map { !isKept($0) } ?? false
        }
    }
}
