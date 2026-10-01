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
}
