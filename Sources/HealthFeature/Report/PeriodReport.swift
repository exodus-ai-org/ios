// Sources/HealthFeature/Report/PeriodReport.swift
import Foundation
import Models

/// A finished week, month, quarter or year told like the daily note (spec §2.4): written by the computer from the
/// period's numbers and the notes kept in it, then kept on this phone (`archive/reports/2026-09.json`). It keeps the
/// numbers it was written from, as a kept note keeps its snapshot, so a question about it carries them.
public struct PeriodReport: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case week, month, quarter, year

        /// Nil for an N-day window, which has no report.
        init?(_ kind: Period.Kind) {
            switch kind {
            case .week: self = .week
            case .month: self = .month
            case .quarter: self = .quarter
            case .year: self = .year
            case .days: return nil
            }
        }
    }

    /// The period on the wire: its kind, first day and last day ("2026-09-01", "2026-09-30").
    public struct Span: Codable, Equatable, Sendable {
        public var kind: Kind
        public var start: String
        public var end: String

        public init(kind: Kind, start: String, end: String) {
            self.kind = kind
            self.start = start
            self.end = end
        }

        init?(_ period: Period, calendar: Calendar) {
            guard let kind = Kind(period.kind) else { return nil }
            let wire = WireDate(timeZone: calendar.timeZone)
            let last = calendar.date(byAdding: .day, value: -1, to: period.end)!
            self.init(kind: kind, start: wire.day(period.start), end: wire.day(last))
        }
    }

    /// One sentence about one category — the daily note's insight, with the sentence called `title`.
    public struct Insight: Codable, Equatable, Sendable {
        public var category: String
        public var title: String
        /// Exact substrings of `title`, coloured in the category's colour.
        public var highlights: [String]
        public var stat: HealthSummary.Stat?

        public init(category: String, title: String, highlights: [String] = [], stat: HealthSummary.Stat? = nil) {
            self.category = category
            self.title = title
            self.highlights = highlights
            self.stat = stat
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            category = try c.decode(String.self, forKey: .category)
            title = try c.decode(String.self, forKey: .title)
            highlights = try c.decodeIfPresent([String].self, forKey: .highlights) ?? []
            stat = try c.decodeIfPresent(HealthSummary.Stat.self, forKey: .stat)
        }
    }

    /// One number against the period before, as the model wrote it for the reader; the direction is the desktop's,
    /// worked out from the numbers sent.
    public struct Comparison: Codable, Equatable, Sendable {
        public enum Direction: String, Codable, Sendable {
            case up, down, flat
        }

        public var metric: String
        public var current: String
        public var previous: String?
        public var direction: Direction

        public init(metric: String, current: String, previous: String?, direction: Direction) {
            self.metric = metric
            self.current = current
            self.previous = previous
            self.direction = direction
        }

        /// A direction this app doesn't know reads as level, rather than costing the report.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            metric = try c.decode(String.self, forKey: .metric)
            current = try c.decode(String.self, forKey: .current)
            previous = try c.decodeIfPresent(String.self, forKey: .previous)
            direction = (try? c.decode(Direction.self, forKey: .direction)) ?? .flat
        }
    }

    public var period: Span
    public var headline: String
    /// The headline's key phrase, an exact substring of it, coloured as `headlineCategory`.
    public var headlineHighlight: String?
    public var headlineCategory: String?
    public var insights: [Insight]
    public var comparisons: [Comparison]
    public var nudge: String?
    /// When this phone kept it: the home's "report ready" line looks at the last two days.
    public var generatedAt: Date
    /// The numbers it was written from.
    public var current: Aggregates
    public var previous: Aggregates?

    public init(_ reply: PeriodReportReply, period: Span, generatedAt: Date, current: Aggregates, previous: Aggregates?) {
        self.period = period
        self.headline = reply.headline
        self.headlineHighlight = reply.headlineHighlight
        self.headlineCategory = reply.headlineCategory
        self.insights = reply.insights
        self.comparisons = reply.comparisons
        self.nudge = reply.nudge
        self.generatedAt = generatedAt
        self.current = current
        self.previous = previous
    }

    /// The report in the daily note's shape, so it is drawn with the same insight stories.
    var story: HealthSummary {
        HealthSummary(
            headline: headline, summary: headline,
            categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil), memorySuggestion: nil,
            headlineHighlight: headlineHighlight, headlineCategory: headlineCategory,
            insights: insights.map { .init(category: $0.category, text: $0.title, highlights: $0.highlights, stat: $0.stat) },
            nudge: nudge)
    }
}

/// What the computer answers (`POST /api/v1/health/period-report`): the report without what this phone adds. The
/// period it echoes is not read — the phone knows which period it asked about.
public struct PeriodReportReply: Decodable, Equatable, Sendable {
    public var headline: String
    public var headlineHighlight: String?
    public var headlineCategory: String?
    public var insights: [PeriodReport.Insight]
    public var comparisons: [PeriodReport.Comparison]
    public var nudge: String?

    public init(
        headline: String, headlineHighlight: String? = nil, headlineCategory: String? = nil,
        insights: [PeriodReport.Insight] = [], comparisons: [PeriodReport.Comparison] = [], nudge: String? = nil
    ) {
        self.headline = headline
        self.headlineHighlight = headlineHighlight
        self.headlineCategory = headlineCategory
        self.insights = insights
        self.comparisons = comparisons
        self.nudge = nudge
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headline = try c.decode(String.self, forKey: .headline)
        headlineHighlight = try c.decodeIfPresent(String.self, forKey: .headlineHighlight)
        headlineCategory = try c.decodeIfPresent(String.self, forKey: .headlineCategory)
        insights = try c.decodeIfPresent([PeriodReport.Insight].self, forKey: .insights) ?? []
        comparisons = try c.decodeIfPresent([PeriodReport.Comparison].self, forKey: .comparisons) ?? []
        nudge = try c.decodeIfPresent(String.self, forKey: .nudge)
    }

    private enum CodingKeys: String, CodingKey {
        case headline, headlineHighlight, headlineCategory, insights, comparisons, nudge
    }
}
