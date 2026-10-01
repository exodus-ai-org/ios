import Foundation
import Models
import Testing
import WidgetKitShared

@testable import HealthFeature

@MainActor
struct WidgetGlanceTests {
    let source = FakeHealthSource()
    let prefs = HealthPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let cache = ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))

    /// A consented day with a written report: 1251 steps of 8000, and a short night (352 min, tired) or none (happy).
    func readyModel(odyState: OdyMood) async throws -> HealthHomeModel {
        let cal = TestClock.calendar
        let wake = cal.date(byAdding: .hour, value: 7, to: TestClock.today)!
        let night = SleepSample(start: wake.addingTimeInterval(-352 * 60), end: wake, stage: .core, source: "watch")
        await source.set {
            $0.sums[.steps] = [DayValue(day: TestClock.today, value: 1251)]
            if odyState == .tired { $0.sleep = [night] }
        }
        prefs.summaryConsent = true
        let summary = HealthSummary(
            headline: "Take it easy", summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
            memorySuggestion: nil)
        let model = HealthHomeModel(
            source: source, summaries: StubSummaries(.success(summary)), memory: StubMemory(), cache: cache,
            preferences: prefs, calendar: TestClock.calendar, now: { TestClock.now }, locale: "en")
        await model.load()
        #expect(model.report == .ready(summary))
        #expect(model.day?.snapshot.odyState == odyState)
        return model
    }

    @Test("a ready report is a glance: the day, sleep, steps, headline, a question and a sleepy Ody")
    func glance() async throws {
        let model = try await readyModel(odyState: .tired)
        let glance = try #require(model.widgetGlance)
        #expect(glance.day == model.day?.snapshot.date)
        #expect(glance.sleepMinutes == 352 && glance.steps == 1251 && glance.stepGoal == 8000)
        #expect(glance.headline == "Take it easy")
        #expect(glance.suggestion == "Why do I feel tired today?")
        #expect(glance.mood == .sleepy)
    }

    @Test("consent taken back: no glance")
    func revoked() async throws {
        let model = try await readyModel(odyState: .happy)
        #expect(model.widgetGlance?.mood == .happy)
        #expect(model.widgetGlance?.suggestion == "How did I sleep last night?")
        model.revokeConsent()
        #expect(model.widgetGlance == nil)
    }
}
