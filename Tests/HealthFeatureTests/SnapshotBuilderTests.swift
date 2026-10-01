// Tests/HealthFeatureTests/SnapshotBuilderTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct SnapshotBuilderTests: Sendable {
    let cal = TestClock.calendar
    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: TestClock.today)! }

    /// A night of `minutes` core sleep that ends at 07:00 on the day `offset` from today.
    func night(_ offset: Int, minutes: Int, source: String = "watch") -> SleepSample {
        let wake = cal.date(byAdding: .hour, value: 7, to: day(offset))!
        return SleepSample(start: wake.addingTimeInterval(Double(-minutes * 60)), end: wake, stage: .core, source: source)
    }

    func build(_ fake: FakeHealthSource) async throws -> HealthDay {
        try await SnapshotBuilder(source: fake, calendar: cal).build(now: TestClock.now, locale: "en")
    }

    @Test func anEmptyStoreIsNoData() async throws {
        let d = try await build(FakeHealthSource())
        #expect(d.snapshot.sleep == nil && d.snapshot.activity == nil && d.snapshot.recovery == nil && d.snapshot.body == nil)
        #expect(d.snapshot.odyState == .noData)
        #expect(d.snapshot.date == "2026-10-01")
        #expect(d.snapshot.localTime == "15:00")
    }

    @Test func notYetAskedIsPermission() async throws {
        let fake = FakeHealthSource()
        await fake.set { $0.requested = false }
        #expect(try await build(fake).snapshot.odyState == .permission)
    }

    @Test func sleepWithBaselineFromThirtyPreviousNights() async throws {
        let fake = FakeHealthSource()
        let history = (1...10).map { night(-$0, minutes: 450) }
        await fake.set { $0.sleep = history + [night(0, minutes: 372)] }
        let d = try await build(fake)
        let sleep = try #require(d.snapshot.sleep)
        #expect(sleep.asleepMin == 372)
        #expect(sleep.baselineMin == 450)
        #expect(sleep.wake == "07:00")
        #expect(d.snapshot.odyState == .tired)
        #expect(d.night?.asleepMin == 372)
    }

    @Test func activityUsesTodayAndTheRingGoal() async throws {
        let fake = FakeHealthSource()
        await fake.set {
            $0.sums[.steps] = [DayValue(day: self.day(-1), value: 12000), DayValue(day: self.day(0), value: 5840)]
            $0.sums[.activeKcal] = [DayValue(day: self.day(0), value: 310.6)]
            $0.sums[.exerciseMin] = [DayValue(day: self.day(0), value: 12)]
            $0.stand = 6
            $0.goals = ActivityGoals(moveKcal: 500, exerciseMin: 30, standHours: 12)
            $0.workoutList = [WorkoutSample(start: self.day(0).addingTimeInterval(3600 * 7), minutes: 30, kcal: 200, type: "running")]
        }
        let a = try #require(try await build(fake).snapshot.activity)
        #expect(a.steps == 5840)
        #expect(a.stepGoal == 8000)
        #expect(a.activeKcal == 310)
        #expect(a.kcalGoal == 500)
        #expect(a.standHours == 6)
        #expect(a.workouts == [HealthSnapshot.Workout(type: "running", minutes: 30, kcal: 200)])
    }

    @Test func recoveryAgainstBaselines() async throws {
        let fake = FakeHealthSource()
        let past = (1...8).map { DayValue(day: self.day(-$0), value: 44) }
        let pastHr = (1...8).map { DayValue(day: self.day(-$0), value: 58) }
        await fake.set {
            $0.averages[.hrv] = past + [DayValue(day: self.day(0), value: 38)]
            $0.averages[.restingHr] = pastHr + [DayValue(day: self.day(0), value: 61)]
        }
        let r = try #require(try await build(fake).snapshot.recovery)
        #expect(r.hrvMs == 38 && r.hrvBaselineMs == 44)
        #expect(r.restingHr == 61 && r.restingHrBaseline == 58)
        #expect(r.level == .low)  // −13.6 % HRV
    }

    @Test func recoveryWithOnlyAFewDaysHasNoLevel() async throws {
        let fake = FakeHealthSource()
        await fake.set { $0.averages[.hrv] = [DayValue(day: self.day(-1), value: 40), DayValue(day: self.day(0), value: 30)] }
        let r = try #require(try await build(fake).snapshot.recovery)
        #expect(r.hrvBaselineMs == nil)
        #expect(r.level == nil)
    }

    @Test func bodyWaterWeightAndMood() async throws {
        let fake = FakeHealthSource()
        await fake.set {
            $0.sums[.waterMl] = [DayValue(day: self.day(0), value: 800)]
            $0.averages[.weightKg] = [DayValue(day: self.day(-20), value: 70.4), DayValue(day: self.day(-1), value: 69.9)]
            $0.moodList = [MoodSample(date: self.day(0).addingTimeInterval(3600 * 9), label: .pleasant)]
        }
        let b = try #require(try await build(fake).snapshot.body)
        #expect(b.waterCups == 3)
        #expect(b.weightKg == 69.9)
        #expect(abs((b.weightTrend30d ?? 0) - (-0.5)) < 0.001)
        #expect(b.mood == .pleasant)
    }
}
