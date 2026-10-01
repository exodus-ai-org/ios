// Tests/HealthFeatureTests/HealthHistoryTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct HealthHistoryTests: Sendable {
    let cal = TestClock.calendar
    func day(_ o: Int) -> Date { cal.date(byAdding: .day, value: o, to: TestClock.today)! }

    @Test func sleepHistoryHasNightsAndLastNight() async throws {
        let fake = FakeHealthSource()
        let nights = (0..<10).map { o -> SleepSample in
            let wake = cal.date(byAdding: .hour, value: 7, to: day(-o))!
            return SleepSample(start: wake.addingTimeInterval(-7 * 3600), end: wake, stage: .core, source: "w")
        }
        await fake.set { $0.sleep = nights }
        let data = try await HealthHistoryLoader(source: fake, calendar: cal).load(.sleep, now: TestClock.now)
        #expect(data.nights.count == 10)
        #expect(data.nights.allSatisfy { $0.value == 7 })
        #expect(data.lastNight?.asleepMin == 420)
        #expect(data.dailySteps.isEmpty)
    }

    @Test func activityHistory() async throws {
        let fake = FakeHealthSource()
        let days = (0..<7).map { DayValue(day: day(-$0), value: Double(1000 * ($0 + 1))) }
        let hour = DayValue(day: TestClock.today.addingTimeInterval(9 * 3600), value: 1200)
        await fake.set {
            $0.sums[.steps] = days
            $0.hourly[.steps] = [hour]
        }
        let data = try await HealthHistoryLoader(source: fake, calendar: cal).load(.activity, now: TestClock.now)
        #expect(data.dailySteps.count == 7)
        #expect(data.hourlySteps.first?.value == 1200)
    }

    @Test func lastWeekAttachmentIsSevenDaysOfThatCategory() async throws {
        var data = HealthHistoryData()
        data.dailySteps = (0..<10).map { DayPoint(day: day(-$0), value: 5000) }
        let h = HealthHistory.lastWeek(.activity, from: data, calendar: cal, now: TestClock.now)
        #expect(h.category == "activity")
        #expect(h.days.count == 7)
        #expect(h.days.last?.date == "2026-10-01")
        #expect(h.days.last?.values["steps"] == 5000)
        let text = try HealthContext.compose(h, question: "q")
        #expect(text.hasPrefix("```exodus-health\n{\"category\":\"activity\""))
    }

    func at(_ d: Date, _ minutes: Int) -> Date { d.addingTimeInterval(Double(minutes) * 60) }

    /// The week a sleep question carries has each night's stages and the time of waking.
    @Test func sleepWeekHasStagesAndWake() async throws {
        let fake = FakeHealthSource()
        let nights = (0..<3).flatMap { o -> [SleepSample] in
            let d = day(-o)
            return [
                SleepSample(start: at(d, -60), end: d, stage: .deep, source: "w"),
                SleepSample(start: d, end: at(d, 300), stage: .core, source: "w"),
                SleepSample(start: at(d, 300), end: at(d, 310), stage: .awake, source: "w"),
                SleepSample(start: at(d, 310), end: at(d, 360), stage: .rem, source: "w"),
            ]
        }
        await fake.set { $0.sleep = nights }
        let data = try await HealthHistoryLoader(source: fake, calendar: cal).load(.sleep, now: TestClock.now)
        let h = HealthHistory.lastWeek(.sleep, from: data, calendar: cal, now: TestClock.now)
        let last = try #require(h.days.last)
        #expect(last.values["asleepHours"] == 410.0 / 60)
        #expect(last.values["deepMin"] == 60)
        #expect(last.values["remMin"] == 50)
        #expect(last.values["awakeMin"] == 10)
        #expect(last.wake == "06:00")
        #expect(h.days.first?.wake == nil)
    }

    @Test func activityWeekHasExercise() async throws {
        let fake = FakeHealthSource()
        await fake.set {
            $0.sums[.steps] = [DayValue(day: TestClock.today, value: 4000)]
            $0.sums[.exerciseMin] = [DayValue(day: TestClock.today, value: 25)]
        }
        let data = try await HealthHistoryLoader(source: fake, calendar: cal).load(.activity, now: TestClock.now)
        let last = try #require(HealthHistory.lastWeek(.activity, from: data, calendar: cal, now: TestClock.now).days.last)
        #expect(last.values["steps"] == 4000)
        #expect(last.values["exerciseMin"] == 25)
    }

    @Test func recoveryWeekHasBreathing() async throws {
        let fake = FakeHealthSource()
        await fake.set { $0.averages[.respRate] = [DayValue(day: TestClock.today, value: 14.5)] }
        let data = try await HealthHistoryLoader(source: fake, calendar: cal).load(.recovery, now: TestClock.now)
        let last = try #require(HealthHistory.lastWeek(.recovery, from: data, calendar: cal, now: TestClock.now).days.last)
        #expect(last.values["respRate"] == 14.5)
    }

    /// Water per day, not just today's, and the day's last mood.
    @Test func bodyWeekHasWaterAndMood() async throws {
        let fake = FakeHealthSource()
        await fake.set {
            $0.sums[.waterMl] = [DayValue(day: self.day(-2), value: 1000), DayValue(day: TestClock.today, value: 500)]
            $0.moodList = [
                MoodSample(date: self.at(TestClock.today, 9 * 60), label: .unpleasant),
                MoodSample(date: self.at(TestClock.today, 13 * 60), label: .pleasant),
            ]
        }
        let data = try await HealthHistoryLoader(source: fake, calendar: cal).load(.body, now: TestClock.now)
        #expect(data.waterCups == 2)
        let h = HealthHistory.lastWeek(.body, from: data, calendar: cal, now: TestClock.now)
        #expect(h.days[4].values["waterCups"] == 4)
        #expect(h.days[4].mood == nil)
        #expect(h.days[6].values["waterCups"] == 2)
        #expect(h.days[6].mood == .pleasant)
        let json = String(decoding: try HealthWire.encoder().encode(h), as: UTF8.self)
        #expect(json.contains("\"mood\":\"pleasant\""))
    }
}
