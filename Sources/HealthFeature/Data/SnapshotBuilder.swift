// Sources/HealthFeature/Data/SnapshotBuilder.swift
import Foundation
import Models

/// The day as the home screen and the report see it: the wire snapshot, plus last night's stages for the hero.
public struct HealthDay: Sendable, Equatable {
    public var snapshot: HealthSnapshot
    public var night: SleepNight?
}

/// Everything the store holds for a run of days, read with one query per series: sleep from the evening before the
/// first baseline night, averages from 30 days before the first day (their baselines), sums, workouts and moods over
/// the days themselves. Hours stood and the rings' goals are one query per day, so only a single day reads them.
struct StoreSpan: Sendable {
    var sleep: [SleepSample] = []
    var sums: [SumMetric: [DayValue]] = [:]
    var averages: [AverageMetric: [DayValue]] = [:]
    var workouts: [WorkoutSample] = []
    var moods: [MoodSample] = []
    var stand = 0
    var goals: ActivityGoals?
}

/// Reads days from a `HealthDataSource` and turns them into `HealthDay`s and `DayRecord`s. A day runs from local
/// midnight to midnight (today: to `now`); each baseline is the median of the 30 days before that day, once there are
/// seven of them. A category with nothing in it is `nil`, so the report says nothing about it rather than "0". One
/// day or a year, the store is read once per series and every day is put together by the same rules, so a past day's
/// Ody is the one the home would have shown.
public struct SnapshotBuilder: Sendable {
    let source: any HealthDataSource
    let calendar: Calendar
    let stepGoal: Int
    private let format: WireDate

    public init(source: any HealthDataSource, calendar: Calendar = .current, stepGoal: Int = 8000) {
        self.source = source
        self.calendar = calendar
        self.stepGoal = stepGoal
        self.format = WireDate(timeZone: calendar.timeZone)
    }

    public func build(now: Date, locale: String) async throws -> HealthDay {
        try await snapshot(for: now, now: now, locale: locale)
    }

    /// The day holding `date`: today up to `now`, as the home shows it, or a past day whole ("23:59").
    public func snapshot(for date: Date, now: Date, locale: String) async throws -> HealthDay {
        let day = calendar.startOfDay(for: date)
        let authorized = await source.hasRequestedAuthorization()
        var span = try await read(from: day, through: day, now: now)
        span.stand = try await source.standHours(on: day)
        span.goals = try await source.activityGoals(on: day)
        let nights = SleepAnalyzer.nights(
            from: span.sleep, days: days(from: baselineStart(day), through: day), calendar: calendar)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        return assemble(
            day: day, span: span, nights: nights, authorized: authorized,
            localTime: clock(min(now, next.addingTimeInterval(-60))), locale: locale)
    }

    /// Each day from `first` through `last` that has begun, as the calendar reads it. Hours stood are not read per
    /// day here, so a day with nothing but stand hours reads as no activity.
    public func records(from first: Date, through last: Date, now: Date) async throws -> [DayRecord] {
        let first = calendar.startOfDay(for: first)
        let last = min(calendar.startOfDay(for: last), calendar.startOfDay(for: now))
        guard first <= last else { return [] }
        let authorized = await source.hasRequestedAuthorization()
        let span = try await read(from: first, through: last, now: now)
        let nights = SleepAnalyzer.nights(
            from: span.sleep, days: days(from: baselineStart(first), through: last), calendar: calendar)
        return days(from: first, through: last).map { day in
            let built = assemble(day: day, span: span, nights: nights, authorized: authorized, localTime: "", locale: "")
            return DayRecord(day: day, snapshot: built.snapshot, stepGoal: stepGoal)
        }
    }

    /// One query per series for the days `first` through `last`.
    func read(from first: Date, through last: Date, now: Date) async throws -> StoreSpan {
        let monthAgo = baselineStart(first)
        let end = calendar.date(byAdding: .day, value: 1, to: last)!
        var span = StoreSpan()
        let sleepFrom = SleepAnalyzer.window(endingOn: monthAgo, calendar: calendar).start
        let sleepTo = min(now, SleepAnalyzer.window(endingOn: last, calendar: calendar).end)
        span.sleep = try await source.sleepSamples(from: sleepFrom, to: sleepTo)
        for metric in [SumMetric.steps, .activeKcal, .exerciseMin] {
            span.sums[metric] = try await source.dailySums(metric, from: first, to: end)
        }
        for metric in [AverageMetric.hrv, .restingHr, .respRate, .weightKg] {
            span.averages[metric] = try await source.dailyAverages(metric, from: monthAgo, to: end)
        }
        span.sums[.waterMl] = try await source.dailySums(.waterMl, from: first, to: end)
        span.workouts = try await source.workouts(from: first, to: end)
        span.moods = try await source.moods(from: first, to: end)
        return span
    }

    /// One day from what was read: the same rules whether the span held one day or a year.
    func assemble(
        day: Date, span: StoreSpan, nights: [Date: SleepNight], authorized: Bool, localTime: String, locale: String
    ) -> HealthDay {
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        let monthAgo = baselineStart(day)
        func on(_ values: [DayValue]?) -> [DayValue] { (values ?? []).filter { $0.day >= day && $0.day < next } }

        // Sleep: the night that ended this morning, against the 30 before it.
        let night = nights[day]
        let pastNights = (1...30).compactMap { offset -> Double? in
            let earlier = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: day)!)
            return nights[earlier].map { Double($0.asleepMin) }
        }
        let sleep = night.map { n in
            HealthSnapshot.Sleep(
                asleepMin: n.asleepMin, baselineMin: HealthRules.baseline(pastNights).map { Int($0.rounded()) },
                deepMin: n.deepMin, coreMin: n.coreMin, remMin: n.remMin, awakeMin: n.awakeMin,
                bedtime: clock(n.bedtime), wake: clock(n.wake))
        }

        // Activity: the day only.
        func sum(_ metric: SumMetric) -> Double { on(span.sums[metric]).reduce(0) { $0 + $1.value } }
        let steps = sum(.steps)
        let kcal = sum(.activeKcal)
        let exercise = sum(.exerciseMin)
        let workouts = span.workouts.filter { $0.start >= day && $0.start < next }
        let hasActivity = steps > 0 || kcal > 0 || exercise > 0 || span.stand > 0 || !workouts.isEmpty
        let activity =
            hasActivity
            ? HealthSnapshot.Activity(
                steps: Int(steps), stepGoal: stepGoal, activeKcal: Int(kcal), kcalGoal: span.goals?.moveKcal,
                exerciseMin: Int(exercise), standHours: span.stand,
                workouts: workouts.prefix(20).map { .init(type: $0.type, minutes: $0.minutes, kcal: $0.kcal) })
            : nil

        // Recovery: the day against the 30 before it.
        func dayAndBaseline(_ metric: AverageMetric) -> (Double?, Double?) {
            let values = span.averages[metric] ?? []
            let before = values.filter { $0.day >= monthAgo && $0.day < day }.map(\.value)
            return (on(values).last?.value, HealthRules.baseline(before))
        }
        let (hrv, hrvBase) = dayAndBaseline(.hrv)
        let (rhr, rhrBase) = dayAndBaseline(.restingHr)
        let (resp, _) = dayAndBaseline(.respRate)
        let recovery =
            (hrv ?? rhr ?? resp) == nil
            ? nil
            : HealthSnapshot.Recovery(
                level: HealthRules.recovery(hrv: hrv, hrvBaseline: hrvBase, restingHr: rhr, restingHrBaseline: rhrBase),
                hrvMs: hrv, hrvBaselineMs: hrvBase, restingHr: rhr, restingHrBaseline: rhrBase, respRate: resp)

        // Body & mood.
        let cups = Int(sum(.waterMl) / 250)
        let weights = (span.averages[.weightKg] ?? []).filter { $0.day >= monthAgo && $0.day < next }
        let trend = weights.count >= 2 ? weights.last!.value - weights.first!.value : nil
        let mood = span.moods.filter { $0.date >= day && $0.date < next }.max { $0.date < $1.date }?.label
        let body =
            cups == 0 && weights.isEmpty && mood == nil
            ? nil
            : HealthSnapshot.Body(waterCups: cups, weightKg: weights.last?.value, weightTrend30d: trend, mood: mood)

        var snapshot = HealthSnapshot(
            date: format.day(day), localTime: localTime, locale: locale,
            sleep: sleep, activity: activity, recovery: recovery, body: body, odyState: .happy)
        snapshot.odyState = HealthRules.hero(snapshot, authorized: authorized)
        return HealthDay(snapshot: snapshot, night: night)
    }

    /// Each day's start from `first` through `last`; a day whose midnight a clock change skipped starts at 01:00.
    func days(from first: Date, through last: Date) -> [Date] {
        var out: [Date] = []
        var d = calendar.startOfDay(for: first)
        while d <= last {
            out.append(d)
            d = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: d)!)
        }
        return out
    }

    private func baselineStart(_ day: Date) -> Date { calendar.date(byAdding: .day, value: -30, to: day)! }

    func clock(_ date: Date) -> String { format.clock(date) }
}
