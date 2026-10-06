// Sources/HealthFeature/Report/PeriodReportInput.swift
import Foundation
import Models

/// What the phone sends for a finished period (spec §4): its numbers and the period before's, the notes kept in it,
/// the habits (phase 3; none yet) and the language. The desktop's zod schema rejects anything else.
public struct PeriodReportRequest: Encodable, Equatable, Sendable {
    public struct Note: Encodable, Equatable, Sendable {
        public var day: String
        public var headline: String
        public var insights: [NoteInsight]
    }

    public struct NoteInsight: Encodable, Equatable, Sendable {
        public var category: String
        public var title: String
    }

    /// A 21-day habit's progress; phase 3 fills these in. A bedtime target is minutes after midnight.
    public struct Habit: Encodable, Equatable, Sendable {
        public var kind: String
        public var target: Double
        public var daysHit: Int
        public var streak: Int
        public var dayOfTwentyOne: Int
    }

    public var period: PeriodReport.Span
    public var current: Aggregates
    /// Left out (not null) when the period before has no data: the desktop takes either.
    public var previous: Aggregates?
    public var notes: [Note]
    public var habits: [Habit]
    public var locale: String
}

/// Builds a period's request from its day records and the archive. Pure, and fine off the main actor: a year reads
/// up to 366 small files.
enum PeriodReportInput {
    /// The desktop's limits, in UTF-16 units as JavaScript counts them.
    static let headlineLimit = 120
    static let titleLimit = 200
    static let categoryLimit = 20

    /// The request for a finished period, or nil when it has no data at all (nothing to write about, no call).
    /// `records` holds the period's days and the period before's. A week's or a month's notes carry their insight
    /// sentences; a quarter's or a year's only their headlines, so a year stays a small request.
    static func request(
        period: Period, records: [DayRecord], archive: HealthArchive, calendar: Calendar, locale: String, today: Date
    ) -> PeriodReportRequest? {
        guard let span = PeriodReport.Span(period, calendar: calendar) else { return nil }
        let current = TrendMath.aggregate(records, in: period, today: today, calendar: calendar)
        guard current.daysWithData > 0 else { return nil }
        let before = TrendMath.aggregate(
            records, in: period.previous(calendar: calendar), today: today, calendar: calendar)
        let detailed = span.kind == .week || span.kind == .month
        let wire = WireDate(timeZone: calendar.timeZone)
        let notes: [PeriodReportRequest.Note] = period.days(calendar: calendar).compactMap { day in
            let key = wire.day(day)
            guard let kept = archive.read(day: key) else { return nil }
            let headline = clip(kept.summary.headline, headlineLimit)
            guard !headline.isEmpty else { return nil }
            let insights: [PeriodReportRequest.NoteInsight] =
                detailed
                ? (kept.summary.insights ?? []).prefix(4).compactMap { i in
                    let title = clip(i.text, titleLimit)
                    let category = clip(i.category, categoryLimit)
                    return title.isEmpty || category.isEmpty ? nil : .init(category: category, title: title)
                }
                : []
            return .init(day: key, headline: headline, insights: insights)
        }
        return PeriodReportRequest(
            period: span, current: current, previous: before.daysWithData > 0 ? before : nil, notes: notes,
            habits: [], locale: locale)
    }

    /// Trimmed and cut to `limit` UTF-16 units on a character boundary, so an old long note or an emoji-heavy one can't
    /// make the computer refuse the whole request.
    static func clip(_ text: String, _ limit: Int) -> String {
        var out = ""
        var units = 0
        for ch in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            units += ch.utf16.count
            guard units <= limit else { break }
            out.append(ch)
        }
        return out
    }
}
