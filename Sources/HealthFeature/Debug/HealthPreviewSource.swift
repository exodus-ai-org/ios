// Sources/HealthFeature/Debug/HealthPreviewSource.swift
#if DEBUG
import Foundation
import Models

/// A believable year in memory, for the gallery and previews: sleep with stages each night, steps, heart, water.
public actor HealthPreviewSource: HealthDataSource {
    public nonisolated let isAvailable = true
    let now: Date
    let cal = Calendar.current
    var water = 750.0

    public init(now: Date = Date()) { self.now = now }

    public func hasRequestedAuthorization() async -> Bool { true }
    public func requestAuthorization() async throws {}

    public func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        let today = cal.startOfDay(for: now)
        return (0..<400).flatMap { offset -> [SleepSample] in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            var t = day.addingTimeInterval(-12 * 60 - Double(offset % 5) * 540)
            let plan: [(SleepStage, Double)] = [
                (.core, 42), (.deep, 48 - Double(offset % 3) * 6), (.rem, 60), (.awake, 8), (.core, offset == 0 ? 132 : 150 + Double(offset % 4) * 15),
                (.deep, 30), (.rem, 40),
            ]
            return plan.map { stage, minutes in
                defer { t = t.addingTimeInterval(minutes * 60) }
                return SleepSample(start: t, end: t.addingTimeInterval(minutes * 60), stage: stage, source: "preview")
            }
        }.filter { $0.end > start && $0.start < end }
    }

    public func dailySums(_ metric: SumMetric, from start: Date, to end: Date) async throws -> [DayValue] {
        days(from: start, to: end).map { day in
            let o = cal.dateComponents([.day], from: day, to: cal.startOfDay(for: now)).day ?? 0
            let v: Double = switch metric {
            case .steps: o == 0 ? 5840 : Double(6000 + (o * 731) % 5000)
            case .activeKcal: o == 0 ? 310 : 420
            case .exerciseMin: o == 0 ? 12 : 28
            case .waterMl: o == 0 ? water : 1500
            }
            return DayValue(day: day, value: v)
        }
    }

    public func hourlySums(_ metric: SumMetric, on day: Date) async throws -> [DayValue] {
        (7..<15).map { h in DayValue(day: cal.startOfDay(for: day).addingTimeInterval(Double(h) * 3600), value: Double(300 + (h * 977) % 900)) }
    }

    public func dailyAverages(_ metric: AverageMetric, from start: Date, to end: Date) async throws -> [DayValue] {
        days(from: start, to: end).compactMap { day in
            let o = cal.dateComponents([.day], from: day, to: cal.startOfDay(for: now)).day ?? 0
            let v: Double? = switch metric {
            // Every ninth day well under the usual, so the calendar has recovering days.
            case .hrv: o == 0 ? 38 : (o % 9 == 4 ? 34 : Double(42 + o % 5))
            case .restingHr: o == 0 ? 61 : Double(57 + o % 3)
            case .respRate: 14.2
            case .weightKg: o % 3 == 0 ? 70.4 - Double(30 - o) * 0.02 : nil
            }
            return v.map { DayValue(day: day, value: $0) }
        }
    }

    public func standHours(on day: Date) async throws -> Int { 6 }
    public func activityGoals(on day: Date) async throws -> ActivityGoals? { ActivityGoals(moveKcal: 500, exerciseMin: 30, standHours: 12) }
    public func workouts(from start: Date, to end: Date) async throws -> [WorkoutSample] {
        [WorkoutSample(start: cal.startOfDay(for: now).addingTimeInterval(-86400 + 7 * 3600), minutes: 32, kcal: 260, type: "running")]
            .filter { $0.start >= start && $0.start < end }
    }
    public func moods(from start: Date, to end: Date) async throws -> [MoodSample] { [] }
    public func logWater(milliliters: Double, at date: Date) async throws { water += milliliters }

    private func days(from start: Date, to end: Date) -> [Date] {
        var out: [Date] = []
        var d = cal.startOfDay(for: start)
        while d < end, d <= now {
            out.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }
}

public struct PreviewSummaryService: HealthSummaryService {
    let report: HealthHomeModel.Report
    let delay: Duration

    public init(report: HealthHomeModel.Report, delay: Duration = .zero) {
        self.report = report
        self.delay = delay
    }

    /// Says what `HealthPreviewSource` holds: last night 5 h 52 min asleep (deep as usual), 5,840 steps, HRV 38 against
    /// a normal of 44, three cups.
    public static let sample = HealthSummary(
        headline: "A little under-slept, so take it easy.",
        summary: "A little under-slept, so take it easy.\n\nYou slept **5 h 52 min** last night, about half an hour less than usual.\n\nHRV is **38 ms**, under your normal of 44 — your body is still recovering.\n\n**5,840 steps** so far, 2,160 to go to 8,000.",
        categories: .init(sleep: "A short night, but the deep sleep held up.", activity: "2,160 steps to go.", recovery: "HRV 14 % under your normal.", body: "Three cups so far."),
        memorySuggestion: .init(section: "profile", key: "weekday-sleep", summary: "On weekdays you usually sleep about six hours."),
        headlineHighlight: "under-slept", headlineCategory: "sleep",
        insights: [
            .init(
                category: "sleep", text: "You slept 5 h 52 min last night, about half an hour less than usual.",
                highlights: ["5 h 52 min"], stat: .init(value: "5:52", unit: "hr", caption: "usual 6:28")),
            .init(
                category: "recovery", text: "HRV is 38 ms, under your normal of 44 — your body is still recovering.",
                highlights: ["38 ms", "still recovering"], stat: .init(value: "38", unit: "ms HRV", caption: "normal 44")),
            .init(
                category: "activity", text: "5,840 steps so far, 2,160 to go to 8,000.",
                highlights: ["5,840 steps"], stat: .init(value: "5,840", unit: "steps", caption: "goal 8,000")),
        ],
        nudge: "Skip the hard workout today — a 20-minute walk after lunch is plenty.")

    public func summary(for snapshot: HealthSnapshot) async throws -> HealthSummary {
        try await Task.sleep(for: delay)
        switch report {
        case .ready(let s): return s
        case .offline: throw URLError(.cannotConnectToHost)
        case .needsModel: throw HTTPError(statusCode: 400, code: "CONFIG_MISSING_PROVIDER", message: "")
        case .writing:
            try await Task.sleep(for: .seconds(3600))
            return Self.sample
        default: throw HTTPError(statusCode: 500, code: "AI_GENERATION_FAILED", message: "")
        }
    }
}

public struct PreviewMemoryWriter: MemoryWriter {
    public init() {}
    public func remember(_ suggestion: HealthSummary.MemorySuggestion) async throws {}
}

extension HealthArchive {
    /// The gallery's kept note: the sample note, filed under `day`.
    public func writePreview(day: Date, calendar: Calendar = .current) throws {
        let snapshot = HealthSnapshot(
            date: WireDate(timeZone: calendar.timeZone).day(day), localTime: "08:30", locale: "en", sleep: nil,
            activity: nil, recovery: nil, body: nil, odyState: .tired)
        try write(ArchivedDay(snapshot: snapshot, summary: PreviewSummaryService.sample, generatedAt: day))
    }
}
/// The computer for period reports in the gallery: a month a little better slept and a little less walked than the
/// one before (the numbers `writePreview` keeps), or unreachable.
public struct PreviewPeriodReportService: PeriodReportService {
    let offline: Bool

    public init(offline: Bool = false) { self.offline = offline }

    public static let sample = PeriodReportReply(
        headline: "More sleep, fewer steps than the month before.", headlineHighlight: "More sleep",
        headlineCategory: "sleep",
        insights: [
            .init(
                category: "sleep", title: "You slept 7 h 12 min a night on average, 25 minutes more than the month before.",
                highlights: ["7 h 12 min", "25 minutes more"], stat: .init(value: "7:12", unit: "hr", caption: "before 6:47")),
            .init(
                category: "activity", title: "Daily steps fell 12 % to 7,040; you reached your goal on 9 of 21 days.",
                highlights: ["fell 12 %", "9 of 21 days"], stat: .init(value: "7,040", unit: "steps", caption: "before 8,000")),
            .init(
                category: "recovery", title: "Resting heart rate eased to 59 bpm from 61, and HRV held at 44 ms.",
                highlights: ["59 bpm"]),
        ],
        comparisons: [
            .init(metric: "sleep", current: "7 h 12 min", previous: "6 h 47 min", direction: .up),
            .init(metric: "steps", current: "7,040", previous: "8,000", direction: .down),
            .init(metric: "hrv", current: "44 ms", previous: "43 ms", direction: .flat),
            .init(metric: "restingHr", current: "59 bpm", previous: "61 bpm", direction: .down),
        ],
        nudge: "Take a short walk after lunch on workdays.")

    public func report(for request: PeriodReportRequest) async throws -> PeriodReportReply {
        if offline { throw URLError(.cannotConnectToHost) }
        return Self.sample
    }
}

extension PeriodReportStore {
    /// The gallery's kept report for `period`: the sample, written from 21 days with data.
    public func writePreview(period: Period, generatedAt: Date, calendar: Calendar = .current) throws {
        guard let span = PeriodReport.Span(period, calendar: calendar), let id = period.reportID(calendar: calendar)
        else { return }
        func m(_ a: Double, _ lo: Double, _ hi: Double, _ d: Int) -> MetricSummary {
            MetricSummary(average: a, min: lo, max: hi, days: d)
        }
        let none = MetricSummary(average: nil, min: nil, max: nil, days: 0)
        let current = Aggregates(
            elapsedDays: period.days(calendar: calendar).count, daysWithData: 21, sleepMin: m(432, 350, 510, 21),
            steps: m(7040, 2100, 13200, 21), exerciseMin: m(24, 0, 75, 21), hrvMs: m(44, 31, 58, 21),
            restingHr: m(59, 55, 64, 21), waterCups: none, stepGoalRate: 0.43, sleepTargetRate: 0.6)
        let previous = Aggregates(
            elapsedDays: 31, daysWithData: 31, sleepMin: m(407, 330, 480, 31), steps: m(8000, 3100, 15000, 31),
            exerciseMin: m(24, 0, 60, 31), hrvMs: m(43, 30, 55, 31), restingHr: m(61, 57, 66, 31), waterCups: none,
            stepGoalRate: 0.45, sleepTargetRate: 0.42)
        try write(
            PeriodReport(
                PreviewPeriodReportService.sample, period: span, generatedAt: generatedAt, current: current,
                previous: previous),
            id: id)
    }
}
#endif
