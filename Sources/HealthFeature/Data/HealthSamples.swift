// Sources/HealthFeature/Data/HealthSamples.swift
import Foundation
import Models

/// HealthKit's sleep values, reduced to what the report uses. `inBed` samples are dropped at the source.
public enum SleepStage: String, Sendable {
    case awake, core, deep, rem, unspecified

    public var isAsleep: Bool { self != .awake }
}

public struct SleepSample: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage
    /// The recording device's bundle identifier (Watch and iPhone both write sleep).
    public var source: String

    public init(start: Date, end: Date, stage: SleepStage, source: String) {
        self.start = start
        self.end = end
        self.stage = stage
        self.source = source
    }
}

/// One calendar day's value; `day` is that day's start.
public struct DayValue: Sendable, Equatable {
    public var day: Date
    public var value: Double

    public init(day: Date, value: Double) {
        self.day = day
        self.value = value
    }
}

public struct WorkoutSample: Sendable, Equatable {
    public var start: Date
    public var minutes: Int
    public var kcal: Int?
    /// A short English name of the activity type ("running", "yoga"), as the model reads it.
    public var type: String

    public init(start: Date, minutes: Int, kcal: Int?, type: String) {
        self.start = start
        self.minutes = minutes
        self.kcal = kcal
        self.type = type
    }
}

public struct MoodSample: Sendable, Equatable {
    public var date: Date
    public var label: MoodLabel

    public init(date: Date, label: MoodLabel) {
        self.date = date
        self.label = label
    }
}

/// The Activity rings' goals for a day; HealthKit has no step goal.
public struct ActivityGoals: Sendable, Equatable {
    public var moveKcal: Int?
    public var exerciseMin: Int?
    public var standHours: Int?

    public init(moveKcal: Int?, exerciseMin: Int?, standHours: Int?) {
        self.moveKcal = moveKcal
        self.exerciseMin = exerciseMin
        self.standHours = standHours
    }
}

public enum SumMetric: Sendable { case steps, activeKcal, exerciseMin, waterMl }
public enum AverageMetric: Sendable { case restingHr, hrv, respRate, weightKg }

/// What the Health workspace reads and writes. The real one is `HealthKitSource`; tests give their own.
public protocol HealthDataSource: Sendable {
    var isAvailable: Bool { get }
    /// Whether the system sheet has been shown already. Read denial is invisible to apps, so this is all we can know.
    func hasRequestedAuthorization() async -> Bool
    func requestAuthorization() async throws
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample]
    /// Per-day sums over `[start, end)`, one entry per day that has data.
    func dailySums(_ metric: SumMetric, from start: Date, to end: Date) async throws -> [DayValue]
    /// Per-hour sums of one day (24 entries max, `day` holds the hour's start).
    func hourlySums(_ metric: SumMetric, on day: Date) async throws -> [DayValue]
    /// Per-day averages over `[start, end)`, one entry per day that has data.
    func dailyAverages(_ metric: AverageMetric, from start: Date, to end: Date) async throws -> [DayValue]
    func standHours(on day: Date) async throws -> Int
    func activityGoals(on day: Date) async throws -> ActivityGoals?
    func workouts(from start: Date, to end: Date) async throws -> [WorkoutSample]
    func moods(from start: Date, to end: Date) async throws -> [MoodSample]
    func logWater(milliliters: Double, at date: Date) async throws
}
