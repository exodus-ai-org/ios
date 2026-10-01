// Sources/HealthFeature/Data/HealthKitSource.swift
import Foundation
import HealthKit
import Models

/// `HealthDataSource` over HealthKit. Reads happen in the foreground only (a locked device's store is encrypted).
public final class HealthKitSource: HealthDataSource, Sendable {
    private let store: HKHealthStore

    public init(store: HKHealthStore = HKHealthStore()) { self.store = store }

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let readTypes: Set<HKObjectType> = [
        HKCategoryType(.sleepAnalysis), HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleExerciseTime), HKCategoryType(.appleStandHour), HKObjectType.workoutType(),
        HKObjectType.activitySummaryType(), HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.respiratoryRate), HKQuantityType(.bodyMass),
        HKQuantityType(.dietaryWater), HKObjectType.stateOfMindType(),
    ]

    static var shareTypes: Set<HKSampleType> {
        #if DEBUG
        // The gallery's "write sample data" fills the simulator's store.
        return [
            HKQuantityType(.dietaryWater), HKCategoryType(.sleepAnalysis), HKQuantityType(.stepCount),
            HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN),
        ]
        #else
        return [HKQuantityType(.dietaryWater)]
        #endif
    }

    public func hasRequestedAuthorization() async -> Bool {
        let status = try? await store.statusForAuthorizationRequest(toShare: Self.shareTypes, read: Self.readTypes)
        return status == .unnecessary
    }

    public func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    public func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: Self.range(start, end))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).compactMap { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .awake: stage = .awake
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            case .asleepUnspecified: stage = .unspecified
            default: return nil  // inBed
            }
            return SleepSample(
                start: sample.startDate, end: sample.endDate, stage: stage,
                source: sample.sourceRevision.source.bundleIdentifier)
        }
    }

    public func dailySums(_ metric: SumMetric, from start: Date, to end: Date) async throws -> [DayValue] {
        try await collection(Self.type(metric), Self.unit(metric), .cumulativeSum, from: start, to: end, step: DateComponents(day: 1))
    }

    public func hourlySums(_ metric: SumMetric, on day: Date) async throws -> [DayValue] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return try await collection(Self.type(metric), Self.unit(metric), .cumulativeSum, from: start, to: end, step: DateComponents(hour: 1))
    }

    public func dailyAverages(_ metric: AverageMetric, from start: Date, to end: Date) async throws -> [DayValue] {
        try await collection(Self.type(metric), Self.unit(metric), .discreteAverage, from: start, to: end, step: DateComponents(day: 1))
    }

    public func standHours(on day: Date) async throws -> Int {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.appleStandHour), predicate: Self.range(start, end))],
            sortDescriptors: [])
        return try await descriptor.result(for: store)
            .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
    }

    public func activityGoals(on day: Date) async throws -> ActivityGoals? {
        var components = Calendar.current.dateComponents([.year, .month, .day, .era], from: day)
        components.calendar = Calendar.current
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: HKQuery.predicate(forActivitySummariesBetweenStart: components, end: components))
        guard let summary = try await descriptor.result(for: store).first else { return nil }
        return ActivityGoals(
            moveKcal: Self.goal(summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())),
            exerciseMin: summary.exerciseTimeGoal.flatMap { Self.goal($0.doubleValue(for: .minute())) },
            standHours: summary.standHoursGoal.flatMap { Self.goal($0.doubleValue(for: .count())) })
    }

    public func workouts(from start: Date, to end: Date) async throws -> [WorkoutSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(Self.range(start, end))], sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).map { w in
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            return WorkoutSample(
                start: w.startDate, minutes: Int(w.duration / 60), kcal: kcal.map { Int($0) },
                type: Self.name(w.workoutActivityType))
        }
    }

    public func moods(from start: Date, to end: Date) async throws -> [MoodSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.stateOfMind(Self.range(start, end))], sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).map { MoodSample(date: $0.startDate, label: Self.label($0.valenceClassification)) }
    }

    public func logWater(milliliters: Double, at date: Date) async throws {
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryWater), quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters),
            start: date, end: date)
        try await store.save(sample)
    }

    // MARK: - Helpers

    private func collection(
        _ type: HKQuantityType, _ unit: HKUnit, _ options: HKStatisticsOptions, from start: Date, to end: Date,
        step: DateComponents
    ) async throws -> [DayValue] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: Self.range(start, end)), options: options,
            anchorDate: Calendar.current.startOfDay(for: start), intervalComponents: step)
        let collection = try await descriptor.result(for: store)
        var out: [DayValue] = []
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            // The last bucket can start past `end`; the protocol is [start, end).
            guard stats.startDate < end else { return }
            let quantity = options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
            if let quantity { out.append(DayValue(day: stats.startDate, value: quantity.doubleValue(for: unit))) }
        }
        return out
    }

    private static func range(_ start: Date, _ end: Date) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    }

    private static func type(_ m: SumMetric) -> HKQuantityType {
        switch m {
        case .steps: HKQuantityType(.stepCount)
        case .activeKcal: HKQuantityType(.activeEnergyBurned)
        case .exerciseMin: HKQuantityType(.appleExerciseTime)
        case .waterMl: HKQuantityType(.dietaryWater)
        }
    }

    private static func unit(_ m: SumMetric) -> HKUnit {
        switch m {
        case .steps: .count()
        case .activeKcal: .kilocalorie()
        case .exerciseMin: .minute()
        case .waterMl: .literUnit(with: .milli)
        }
    }

    private static func type(_ m: AverageMetric) -> HKQuantityType {
        switch m {
        case .restingHr: HKQuantityType(.restingHeartRate)
        case .hrv: HKQuantityType(.heartRateVariabilitySDNN)
        case .respRate: HKQuantityType(.respiratoryRate)
        case .weightKg: HKQuantityType(.bodyMass)
        }
    }

    private static func unit(_ m: AverageMetric) -> HKUnit {
        switch m {
        case .restingHr, .respRate: .count().unitDivided(by: .minute())
        case .hrv: .secondUnit(with: .milli)
        case .weightKg: .gramUnit(with: .kilo)
        }
    }

    /// A zero goal means the user tracks move in time, not energy; report it as absent.
    private static func goal(_ value: Double) -> Int? { value > 0 ? Int(value) : nil }

    static func label(_ c: HKStateOfMind.ValenceClassification) -> MoodLabel {
        switch c {
        case .veryUnpleasant: .veryUnpleasant
        case .unpleasant: .unpleasant
        case .slightlyUnpleasant: .slightlyUnpleasant
        case .neutral: .neutral
        case .slightlyPleasant: .slightlyPleasant
        case .pleasant: .pleasant
        case .veryPleasant: .veryPleasant
        @unknown default: .neutral
        }
    }

    /// HKWorkoutActivityType is an unnamed NS_ENUM, so the short English names are spelled out.
    static func name(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: "running"
        case .walking: "walking"
        case .cycling: "cycling"
        case .swimming: "swimming"
        case .hiking: "hiking"
        case .yoga: "yoga"
        case .traditionalStrengthTraining: "strength training"
        case .functionalStrengthTraining: "functional strength training"
        case .highIntensityIntervalTraining: "hiit"
        case .elliptical: "elliptical"
        case .rowing: "rowing"
        case .socialDance, .cardioDance: "dance"
        case .coreTraining: "core training"
        case .pilates: "pilates"
        case .mindAndBody: "mind and body"
        case .cooldown: "cooldown"
        case .stairClimbing: "stairs"
        default: "other"
        }
    }
}

#if DEBUG
extension HealthKitSource {
    /// Fills the simulator's store with a believable month: nightly sleep with stages, steps, resting HR, HRV, water.
    public func writeSampleData(now: Date) async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var samples: [HKSample] = []
        for offset in 0..<30 {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let bed = cal.date(byAdding: .minute, value: -(12 + offset % 5 * 9), to: day)!  // ~23:48
            let stages: [(HKCategoryValueSleepAnalysis, Int)] = [
                (.asleepCore, 42), (.asleepDeep, 48 - offset % 3 * 6), (.asleepREM, 60), (.awake, 8),
                (.asleepCore, 150 + offset % 4 * 15), (.asleepDeep, 30), (.asleepREM, 40),
            ]
            var t = bed
            for (value, minutes) in stages {
                let end = t.addingTimeInterval(Double(minutes * 60))
                samples.append(HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: value.rawValue, start: t, end: end))
                t = end
            }
            let noon = cal.date(byAdding: .hour, value: 12, to: day)!
            func q(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ v: Double) -> HKQuantitySample {
                HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: v), start: noon, end: noon)
            }
            if offset > 0 || now > noon {
                samples.append(q(.stepCount, .count(), Double(6000 + (offset * 731) % 5000)))
            }
            samples.append(q(.restingHeartRate, .count().unitDivided(by: .minute()), Double(57 + offset % 4)))
            samples.append(q(.heartRateVariabilitySDNN, .secondUnit(with: .milli), Double(40 + offset % 7)))
        }
        try await store.save(samples)
    }
}
#endif
