// Sources/HealthFeature/Data/SnapshotBuilder.swift
import Foundation
import Models

/// The day as the home screen and the report see it: the wire snapshot, plus last night's stages for the hero.
public struct HealthDay: Sendable, Equatable {
    public var snapshot: HealthSnapshot
    public var night: SleepNight?
}

/// Reads one day from a `HealthDataSource` and turns it into a `HealthDay`. Today is local midnight to `now`; each
/// baseline is the median of the 30 days before today, once there are seven of them. A category with nothing in it
/// is `nil`, so the report says nothing about it rather than "0".
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
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: today)!
        let authorized = await source.hasRequestedAuthorization()

        // Sleep: every night of the last 31, read once.
        let sleepFrom = SleepAnalyzer.window(endingOn: monthAgo, calendar: calendar).start
        let samples = try await source.sleepSamples(from: sleepFrom, to: now)
        let night = SleepAnalyzer.night(from: samples, endingOn: today, calendar: calendar)
        let pastNights = (1...30).compactMap { offset -> Double? in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return SleepAnalyzer.night(from: samples, endingOn: day, calendar: calendar).map { Double($0.asleepMin) }
        }
        let sleep = night.map { n in
            HealthSnapshot.Sleep(
                asleepMin: n.asleepMin, baselineMin: HealthRules.baseline(pastNights).map { Int($0.rounded()) },
                deepMin: n.deepMin, coreMin: n.coreMin, remMin: n.remMin, awakeMin: n.awakeMin,
                bedtime: clock(n.bedtime), wake: clock(n.wake))
        }

        // Activity: today only.
        func todaySum(_ metric: SumMetric) async throws -> Double {
            try await source.dailySums(metric, from: today, to: tomorrow).reduce(0) { $0 + $1.value }
        }
        let steps = try await todaySum(.steps)
        let kcal = try await todaySum(.activeKcal)
        let exercise = try await todaySum(.exerciseMin)
        let stand = try await source.standHours(on: today)
        let goals = try await source.activityGoals(on: today)
        let workouts = try await source.workouts(from: today, to: tomorrow)
        let hasActivity = steps > 0 || kcal > 0 || exercise > 0 || stand > 0 || !workouts.isEmpty
        let activity =
            hasActivity
            ? HealthSnapshot.Activity(
                steps: Int(steps), stepGoal: stepGoal, activeKcal: Int(kcal), kcalGoal: goals?.moveKcal,
                exerciseMin: Int(exercise), standHours: stand,
                workouts: workouts.prefix(20).map { .init(type: $0.type, minutes: $0.minutes, kcal: $0.kcal) })
            : nil

        // Recovery: today against the 30 days before.
        func todayAndBaseline(_ metric: AverageMetric) async throws -> (Double?, Double?) {
            let values = try await source.dailyAverages(metric, from: monthAgo, to: tomorrow)
            let todayValue = values.last { $0.day >= today }?.value
            return (todayValue, HealthRules.baseline(values.filter { $0.day < today }.map(\.value)))
        }
        let (hrv, hrvBase) = try await todayAndBaseline(.hrv)
        let (rhr, rhrBase) = try await todayAndBaseline(.restingHr)
        let (resp, _) = try await todayAndBaseline(.respRate)
        let recovery =
            (hrv ?? rhr ?? resp) == nil
            ? nil
            : HealthSnapshot.Recovery(
                level: HealthRules.recovery(hrv: hrv, hrvBaseline: hrvBase, restingHr: rhr, restingHrBaseline: rhrBase),
                hrvMs: hrv, hrvBaselineMs: hrvBase, restingHr: rhr, restingHrBaseline: rhrBase, respRate: resp)

        // Body & mood.
        let cups = Int(try await todaySum(.waterMl) / 250)
        let weights = try await source.dailyAverages(.weightKg, from: monthAgo, to: tomorrow)
        let trend = weights.count >= 2 ? weights.last!.value - weights.first!.value : nil
        let mood = try await source.moods(from: today, to: tomorrow).max { $0.date < $1.date }?.label
        let body =
            cups == 0 && weights.isEmpty && mood == nil
            ? nil
            : HealthSnapshot.Body(waterCups: cups, weightKg: weights.last?.value, weightTrend30d: trend, mood: mood)

        var snapshot = HealthSnapshot(
            date: day(now), localTime: clock(now), locale: locale,
            sleep: sleep, activity: activity, recovery: recovery, body: body, odyState: .happy)
        snapshot.odyState = HealthRules.hero(snapshot, authorized: authorized)
        return HealthDay(snapshot: snapshot, night: night)
    }

    func clock(_ date: Date) -> String { format.clock(date) }

    func day(_ date: Date) -> String { format.day(date) }
}
