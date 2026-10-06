// Sources/HealthFeature/Trends/PeriodReportText.swift
import Foundation
import SwiftUI

/// The period reports' words, in the user's language, and how a comparison reads and is coloured.
enum PeriodReportText {
    /// A comparison's metric as the day sheet names it, with its glyph and whose colour the glyph takes.
    struct Metric {
        let title: LocalizedStringResource
        let symbol: String
        let category: HealthCategory
    }

    /// The report's eyebrow: "Monthly report".
    static func kind(_ kind: PeriodReport.Kind) -> LocalizedStringResource {
        switch kind {
        case .week: LocalizedStringResource("ios:health.periodReport.kind.week", defaultValue: "Weekly report", comment: "Eyebrow over a weekly health report's headline, and on its card in the calendar.")
        case .month: LocalizedStringResource("ios:health.periodReport.kind.month", defaultValue: "Monthly report", comment: "Eyebrow over a monthly health report's headline, and on its card in the calendar.")
        case .quarter: LocalizedStringResource("ios:health.periodReport.kind.quarter", defaultValue: "Quarterly report", comment: "Eyebrow over a quarterly (three-month) health report's headline, and on its card in the calendar.")
        case .year: LocalizedStringResource("ios:health.periodReport.kind.year", defaultValue: "Yearly report", comment: "Eyebrow over a yearly health report's headline, and on its card in the calendar.")
        }
    }

    /// The calendar view a kind of report belongs to (for "vs last month").
    static func scope(_ kind: PeriodReport.Kind) -> TrendScope {
        switch kind {
        case .week: .week
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
    }

    /// "September 2026 report ready".
    static func ready(_ title: String) -> String {
        String(
            localized: "ios:health.periodReport.ready", defaultValue: "\(title) report ready",
            comment: "Health home, under This week: a period report was just written. %@ is the period, e.g. September 2026 or Week 39.")
    }

    /// "Written Oct 1".
    static func written(_ date: Date, calendar: Calendar) -> String {
        let when = date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())
        return String(
            localized: "ios:health.periodReport.written", defaultValue: "Written \(when)",
            comment: "Report page footer: when the report was written. %@ is a short date, e.g. Oct 1.")
    }

    /// "21 of 30 days had data".
    static func daysWithData(_ n: Int, of total: Int) -> String {
        String(
            localized: "ios:health.periodReport.daysWithData", defaultValue: "\(n) of \(total) days had data",
            comment: "Report page footer when some days had no health data. The first %lld is the days with data, the second the days in the period.")
    }

    /// "was 6 h 47 min".
    static func was(_ value: String) -> String {
        String(
            localized: "ios:health.periodReport.was", defaultValue: "was \(value)",
            comment: "Report page comparison: the value in the period before. %@ is that value, e.g. 6 h 47 min.")
    }

    /// The metrics the desktop compares; another name is left out.
    static func metric(_ wire: String) -> Metric? {
        switch wire {
        case "sleep":
            Metric(title: LocalizedStringResource("ios:health.category.sleep", defaultValue: "Sleep", comment: "Sleep category title."), symbol: "moon.zzz.fill", category: .sleep)
        case "steps":
            Metric(title: LocalizedStringResource("ios:health.day.steps", defaultValue: "Steps", comment: "Day sheet row: the day's step count."), symbol: "figure.walk", category: .activity)
        case "exercise":
            Metric(title: LocalizedStringResource("ios:health.day.exercise", defaultValue: "Exercise", comment: "Day sheet row: minutes of exercise."), symbol: "flame.fill", category: .activity)
        case "hrv":
            Metric(title: LocalizedStringResource("ios:health.recovery.hrv", defaultValue: "Heart rate variability", comment: "Day sheet row: HRV."), symbol: "waveform.path.ecg", category: .recovery)
        case "restingHr":
            Metric(title: LocalizedStringResource("ios:health.recovery.restingHr", defaultValue: "Resting heart rate", comment: "Day sheet row: resting heart rate."), symbol: "heart.fill", category: .recovery)
        case "water":
            Metric(title: LocalizedStringResource("ios:health.body.water", defaultValue: "Water", comment: "Day sheet row: cups of water."), symbol: "drop.fill", category: .body)
        default: nil
        }
    }

    /// Whether a move is for the better: up for most numbers, down for the resting heart rate; level is neither.
    static func isBetter(metric: String, direction: PeriodReport.Comparison.Direction) -> Bool? {
        switch direction {
        case .flat: nil
        case .up: metric != "restingHr"
        case .down: metric == "restingHr"
        }
    }

    static func arrow(_ direction: PeriodReport.Comparison.Direction) -> String {
        switch direction {
        case .up: "↑"  // l10n:ignore: arrow
        case .down: "↓"  // l10n:ignore: arrow
        case .flat: "→"  // l10n:ignore: arrow
        }
    }

    /// Better in the note's green, worse in the calendar's warm orange, level in secondary ink.
    static func color(metric: String, direction: PeriodReport.Comparison.Direction) -> AnyShapeStyle {
        switch isBetter(metric: metric, direction: direction) {
        case true?: AnyShapeStyle(ReportInk.green)
        case false?: AnyShapeStyle(Color.adaptive(0xB4470C, dark: 0xFFA27A))
        case nil: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    /// What VoiceOver reads for a comparison: "Resting heart rate, 59 bpm, Down, was 61 bpm".
    static func spoken(_ c: PeriodReport.Comparison, title: LocalizedStringResource) -> String {
        let moved: String =
            switch c.direction {
            case .up: String(localized: "ios:health.periodReport.up", defaultValue: "Up", comment: "VoiceOver, report page comparison: the number went up against the period before.")
            case .down: String(localized: "ios:health.periodReport.down", defaultValue: "Down", comment: "VoiceOver, report page comparison: the number went down against the period before.")
            case .flat: String(localized: "ios:health.calendar.change.flat", defaultValue: "About the same", comment: "VoiceOver: a number changed less than 3% against the previous period.")
            }
        return ([String(localized: title), c.current, moved] + [c.previous.map(was)].compactMap { $0 })
            .joined(separator: ", ")
    }

    static func failure(_ failure: PeriodReports.Failure) -> LocalizedStringResource {
        switch failure {
        case .offline:
            LocalizedStringResource("ios:health.periodReport.offline", defaultValue: "Your computer isn't reachable, so the report couldn't be written. Try again when it is.", comment: "Report page: writing the report failed because the computer could not be reached.")
        case .needsModel:
            LocalizedStringResource("ios:health.report.needsModel", defaultValue: "Set up an AI provider on your computer and Ody will write your notes.", comment: "Health: no AI provider is set up on the computer.")
        case .failed:
            LocalizedStringResource("ios:health.periodReport.failed", defaultValue: "The report couldn't be written. Try again later.", comment: "Report page: writing the report failed for another reason.")
        }
    }
}
