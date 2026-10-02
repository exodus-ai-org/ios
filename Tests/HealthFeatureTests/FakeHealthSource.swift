// Tests/HealthFeatureTests/FakeHealthSource.swift
import Foundation
import Models

@testable import HealthFeature

/// A HealthKit stand-in: tests fill in what the store holds.
actor FakeHealthSource: HealthDataSource {
    nonisolated let isAvailable: Bool
    var requested = true
    var sleep: [SleepSample] = []
    var sums: [SumMetric: [DayValue]] = [:]
    var hourly: [SumMetric: [DayValue]] = [:]
    var averages: [AverageMetric: [DayValue]] = [:]
    var stand = 0
    var goals: ActivityGoals?
    var workoutList: [WorkoutSample] = []
    var moodList: [MoodSample] = []
    var loggedWater: [Double] = []
    var failure: Error?
    /// Delays the water read of a load (after it has read, so the answer is stale), so a test can act while it is in flight.
    var slowMs = 0
    /// How many times each series was read: one per load, however many days it covers.
    var sleepReads = 0
    var sumReads: [SumMetric: Int] = [:]
    var averageReads: [AverageMetric: Int] = [:]
    var workoutReads = 0
    var moodReads = 0

    init(isAvailable: Bool = true) { self.isAvailable = isAvailable }

    func set(_ change: @Sendable (isolated FakeHealthSource) -> Void) { change(self) }

    func hasRequestedAuthorization() async -> Bool { requested }
    func requestAuthorization() async throws { requested = true }

    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        sleepReads += 1
        if let failure { throw failure }
        return sleep.filter { $0.end > start && $0.start < end }
    }

    func dailySums(_ metric: SumMetric, from start: Date, to end: Date) async throws -> [DayValue] {
        sumReads[metric, default: 0] += 1
        let answer = (sums[metric] ?? []).filter { $0.day >= start && $0.day < end }
        if metric == .waterMl, slowMs > 0 { try? await Task.sleep(for: .milliseconds(slowMs)) }
        return answer
    }

    func hourlySums(_ metric: SumMetric, on day: Date) async throws -> [DayValue] { hourly[metric] ?? [] }

    func dailyAverages(_ metric: AverageMetric, from start: Date, to end: Date) async throws -> [DayValue] {
        averageReads[metric, default: 0] += 1
        return (averages[metric] ?? []).filter { $0.day >= start && $0.day < end }
    }

    func standHours(on day: Date) async throws -> Int { stand }
    func activityGoals(on day: Date) async throws -> ActivityGoals? { goals }

    func workouts(from start: Date, to end: Date) async throws -> [WorkoutSample] {
        workoutReads += 1
        return workoutList.filter { $0.start >= start && $0.start < end }
    }

    func moods(from start: Date, to end: Date) async throws -> [MoodSample] {
        moodReads += 1
        return moodList.filter { $0.date >= start && $0.date < end }
    }

    func logWater(milliliters: Double, at date: Date) async throws {
        loggedWater.append(milliliters)
        sums[.waterMl, default: []].append(DayValue(day: TestClock.today, value: milliliters))
    }
}

/// Fixed calendar and clock for every Health test: Taipei, 2026-10-01 15:00.
enum TestClock {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static let now = date(2026, 10, 1, 15, 0)
    static var today: Date { calendar.startOfDay(for: now) }
}
