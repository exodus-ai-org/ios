import Foundation
import Models
import Testing

@testable import HealthFeature

struct DayRecordTests: Sendable {
    let cal = TestClock.calendar
    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: TestClock.today)! }

    /// A night of `minutes` core sleep that ends at 07:00 on the day `offset` from today.
    func night(_ offset: Int, minutes: Int, source: String = "watch") -> SleepSample {
        let wake = cal.date(byAdding: .hour, value: 7, to: day(offset))!
        return SleepSample(start: wake.addingTimeInterval(Double(-minutes * 60)), end: wake, stage: .core, source: source)
    }

    func builder(_ fake: FakeHealthSource) -> SnapshotBuilder { SnapshotBuilder(source: fake, calendar: cal) }

    /// Forty-one days of everything, a little different each day.
    func filled() async -> FakeHealthSource {
        let fake = FakeHealthSource()
        let nights = (0...40).map { night(-$0, minutes: 360 + $0 % 5 * 30) }
        let steps = (0...40).map { DayValue(day: day(-$0), value: Double(5000 + $0 * 400)) }
        let exercise = (0...40).map { DayValue(day: day(-$0), value: Double($0 % 4 * 10)) }
        let water = (0...40).map { DayValue(day: day(-$0), value: Double($0 % 3 * 500)) }
        let hrv = (0...40).reversed().map { DayValue(day: day(-$0), value: Double(44 - $0 % 6 * 2)) }
        let rhr = (0...40).reversed().map { DayValue(day: day(-$0), value: Double(58 + $0 % 3)) }
        let mood = [MoodSample(date: day(-2).addingTimeInterval(9 * 3600), label: .pleasant)]
        let workout = [WorkoutSample(start: day(-3).addingTimeInterval(7 * 3600), minutes: 30, kcal: 200, type: "running")]
        await fake.set {
            $0.sleep = nights
            $0.sums[.steps] = steps
            $0.sums[.exerciseMin] = exercise
            $0.sums[.waterMl] = water
            $0.averages[.hrv] = hrv
            $0.averages[.restingHr] = rhr
            $0.moodList = mood
            $0.workoutList = workout
        }
        return fake
    }

    @Test func aPastDayIsReadWhole() async throws {
        let d = try await builder(await filled()).snapshot(for: day(-1).addingTimeInterval(3600), now: TestClock.now, locale: "en")
        #expect(d.snapshot.date == "2026-09-30")
        #expect(d.snapshot.localTime == "23:59")
        #expect(d.snapshot.activity?.steps == 5400)
        #expect(d.snapshot.sleep?.asleepMin == 390)
    }

    @Test func aPastDaysBaselineIsTheThirtyNightsBeforeIt() async throws {
        let fake = FakeHealthSource()
        let nights = (2...10).map { night(-$0, minutes: 450) } + [night(-1, minutes: 400), night(0, minutes: 300)]
        await fake.set { $0.sleep = nights }
        let d = try await builder(fake).snapshot(for: day(-1), now: TestClock.now, locale: "en")
        #expect(d.snapshot.sleep?.asleepMin == 400)
        #expect(d.snapshot.sleep?.baselineMin == 450)
    }

    @Test func todayIsStillReadToNow() async throws {
        let built = try await builder(await filled()).build(now: TestClock.now, locale: "en")
        #expect(built.snapshot.date == "2026-10-01")
        #expect(built.snapshot.localTime == "15:00")
        #expect(built.snapshot.activity?.steps == 5000)
    }

    /// A run of days read at once and each day read alone agree, day by day — Ody's state included.
    @Test func recordsMatchEachDayBuiltAlone() async throws {
        let b = builder(await filled())
        let records = try await b.records(from: day(-9), through: day(0), now: TestClock.now)
        #expect(records.map(\.day) == (-9...0).map { day($0) })
        for record in records {
            let alone = try await b.snapshot(for: record.day, now: TestClock.now, locale: "en")
            #expect(record == DayRecord(day: record.day, snapshot: alone.snapshot, stepGoal: 8000))
        }
        #expect(records.contains { $0.mood != .noData })
    }

    @Test func recordsStopAtToday() async throws {
        let b = builder(await filled())
        let records = try await b.records(from: day(-2), through: day(5), now: TestClock.now)
        #expect(records.map(\.day) == [day(-2), day(-1), day(0)])
        #expect(try await b.records(from: day(1), through: day(5), now: TestClock.now).isEmpty)
    }

    /// The calendar's year view reads the store once per series, not once per day.
    @Test func aYearIsReadWithOneQueryPerSeries() async throws {
        let fake = await filled()
        let records = try await builder(fake).records(from: day(-364), through: day(0), now: TestClock.now)
        #expect(records.count == 365)
        #expect(await fake.sleepReads == 1)
        for metric in [SumMetric.steps, .activeKcal, .exerciseMin, .waterMl] {
            #expect(await fake.sumReads[metric] == 1)
        }
        for metric in [AverageMetric.hrv, .restingHr, .respRate, .weightKg] {
            #expect(await fake.averageReads[metric] == 1)
        }
        #expect(await fake.workoutReads == 1)
        #expect(await fake.moodReads == 1)
    }

    @Test func nightsForManyDaysMatchOneAtATime() {
        var samples = (0...6).map { night(-$0, minutes: 400) } + (0...6).map { night(-$0, minutes: 380, source: "phone") }
        // One long sample that reaches into two nights' windows.
        samples.append(
            SleepSample(
                start: day(-3).addingTimeInterval(11 * 3600), end: day(-3).addingTimeInterval(20 * 3600), stage: .core,
                source: "watch"))
        let days = (-8...0).map { day($0) }
        let many = SleepAnalyzer.nights(from: samples, days: days, calendar: cal)
        for d in days {
            #expect(many[d] == SleepAnalyzer.night(from: samples, endingOn: d, calendar: cal))
        }
    }

    // MARK: DayRecordStore

    @MainActor @Test func pastDaysAreReadOnce() async throws {
        let fake = await filled()
        let store = DayRecordStore(builder: builder(fake), calendar: cal, now: { TestClock.now })
        let first = try await store.records(from: day(-20), through: day(-1))
        #expect(first.count == 20)
        #expect(await fake.sleepReads == 1)
        let again = try await store.records(from: day(-10), through: day(-5))
        #expect(again.count == 6)
        #expect(again[day(-7)] == first[day(-7)])
        #expect(await fake.sleepReads == 1)
    }

    /// Today changes as it goes on: it is read again every time, and only today is.
    @MainActor @Test func todayIsReadAgainEachTime() async throws {
        let fake = await filled()
        let store = DayRecordStore(builder: builder(fake), calendar: cal, now: { TestClock.now })
        _ = try await store.records(from: day(-6), through: day(0))
        let more = DayValue(day: day(0), value: 1000)
        await fake.set { $0.sums[.steps]?.append(more) }
        let again = try await store.records(from: day(-6), through: day(0))
        #expect(again.count == 7)
        #expect(again[day(0)]?.steps == 6000)
        #expect(await fake.sleepReads == 2)
    }

    @MainActor @Test func daysToComeHaveNoRecord() async throws {
        let store = DayRecordStore(builder: builder(await filled()), calendar: cal, now: { TestClock.now })
        let r = try await store.records(from: day(-1), through: day(3))
        #expect(Set(r.keys) == [day(-1), day(0)])
    }
}
