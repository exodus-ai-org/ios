// Tests/HealthFeatureTests/HealthRulesTests.swift
import Models
import Testing

@testable import HealthFeature

struct HealthRulesTests {
    static func snapshot(
        sleep: HealthSnapshot.Sleep? = nil, activity: HealthSnapshot.Activity? = nil,
        recovery: HealthSnapshot.Recovery? = nil, body: HealthSnapshot.Body? = nil
    ) -> HealthSnapshot {
        HealthSnapshot(
            date: "2026-10-01", localTime: "15:00", locale: "en", sleep: sleep, activity: activity,
            recovery: recovery, body: body, odyState: .happy)
    }
    static func sleep(_ min: Int, base: Int? = nil) -> HealthSnapshot.Sleep {
        .init(asleepMin: min, baselineMin: base, deepMin: 0, coreMin: min, remMin: 0, awakeMin: 0, bedtime: "23:00", wake: "07:00")
    }
    static func steps(_ n: Int) -> HealthSnapshot.Activity {
        .init(steps: n, stepGoal: 8000, activeKcal: 0, kcalGoal: nil, exerciseMin: 0, standHours: 0, workouts: [])
    }
    static func recovery(_ level: RecoveryLevel?) -> HealthSnapshot.Recovery {
        .init(level: level, hrvMs: 40, hrvBaselineMs: 40, restingHr: 60, restingHrBaseline: 60, respRate: nil)
    }

    // Baselines
    @Test func baselineNeedsSevenDays() {
        #expect(HealthRules.baseline([1, 2, 3, 4, 5, 6]) == nil)
        #expect(HealthRules.baseline([]) == nil)
        #expect(HealthRules.baseline([5, 1, 3, 2, 4, 7, 6]) == 4)
        #expect(HealthRules.baseline([1, 2, 3, 4, 5, 6, 7, 8]) == 4.5)
    }

    // Recovery thresholds, at their edges
    @Test func recoveryLowAtTwelvePercentHrvDrop() {
        #expect(HealthRules.recovery(hrv: 88, hrvBaseline: 100, restingHr: 60, restingHrBaseline: 60) == .low)
        #expect(HealthRules.recovery(hrv: 89, hrvBaseline: 100, restingHr: 60, restingHrBaseline: 60) == .fair)
    }

    @Test func recoveryLowAtSevenPercentRestingRise() {
        #expect(HealthRules.recovery(hrv: 100, hrvBaseline: 100, restingHr: 107, restingHrBaseline: 100) == .low)
    }

    @Test func recoveryGoodNeedsBothWithinBounds() {
        #expect(HealthRules.recovery(hrv: 95, hrvBaseline: 100, restingHr: 103, restingHrBaseline: 100) == .good)
        #expect(HealthRules.recovery(hrv: 94, hrvBaseline: 100, restingHr: 100, restingHrBaseline: 100) == .fair)
        #expect(HealthRules.recovery(hrv: 100, hrvBaseline: 100, restingHr: 104, restingHrBaseline: 100) == .fair)
    }

    @Test func recoveryFromRestingHeartRateAlone() {
        #expect(HealthRules.recovery(hrv: nil, hrvBaseline: nil, restingHr: 108, restingHrBaseline: 100) == .low)
        #expect(HealthRules.recovery(hrv: nil, hrvBaseline: nil, restingHr: 102, restingHrBaseline: 100) == .good)
    }

    @Test func noBaselinesNoRecovery() {
        #expect(HealthRules.recovery(hrv: 40, hrvBaseline: nil, restingHr: 60, restingHrBaseline: nil) == nil)
    }

    // Hero priority
    @Test func heroPriorityOrder() {
        typealias S = HealthRulesTests
        #expect(HealthRules.hero(S.snapshot(sleep: S.sleep(480)), authorized: false) == .permission)
        #expect(HealthRules.hero(S.snapshot(), authorized: true) == .noData)
        #expect(HealthRules.hero(S.snapshot(sleep: S.sleep(389), recovery: S.recovery(.low)), authorized: true) == .tired)
        #expect(HealthRules.hero(S.snapshot(sleep: S.sleep(420, base: 500)), authorized: true) == .tired)  // < 85 %
        #expect(HealthRules.hero(S.snapshot(sleep: S.sleep(480), recovery: S.recovery(.low)), authorized: true) == .recovering)
        #expect(HealthRules.hero(S.snapshot(sleep: S.sleep(480), activity: S.steps(8000)), authorized: true) == .active)
        #expect(
            HealthRules.hero(S.snapshot(sleep: S.sleep(480, base: 450), recovery: S.recovery(.good)), authorized: true)
                == .rested)
        #expect(
            HealthRules.hero(
                S.snapshot(body: .init(waterCups: 0, weightKg: nil, weightTrend30d: nil, mood: .pleasant)),
                authorized: true) == .calm)
        #expect(HealthRules.hero(S.snapshot(activity: S.steps(100)), authorized: true) == .happy)
    }

    @Test func restedNeedsABaseline() {
        let s = Self.snapshot(sleep: Self.sleep(480, base: nil), recovery: Self.recovery(.good))
        #expect(HealthRules.hero(s, authorized: true) == .happy)
    }

    // Cards
    @Test func cardsDecideOnTheirOwnData() {
        let s = Self.snapshot(sleep: Self.sleep(300), activity: Self.steps(9000), recovery: Self.recovery(nil))
        #expect(HealthRules.card(.sleep, in: s) == .tired)
        #expect(HealthRules.card(.activity, in: s) == .active)
        #expect(HealthRules.card(.recovery, in: s) == .happy)
        #expect(HealthRules.card(.body, in: s) == .noData)
        #expect(HealthRules.card(.recovery, in: Self.snapshot(recovery: Self.recovery(.low))) == .recovering)
    }
}
