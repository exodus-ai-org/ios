import Foundation
import Models
import Testing

@testable import HealthFeature

/// The first read of a visit: what the screen shows before Apple Health has answered.
@MainActor
struct HealthHomeFirstReadTests {
    let source = FakeHealthSource()
    let summaries = StubSummaries(.success(HealthHomeModelTests.summary))
    let memory = StubMemory()
    let prefs = HealthPreferences(defaults: UserDefaults(suiteName: "first-read-\(UUID())")!)
    let cache = ReportCache(
        directory: FileManager.default.temporaryDirectory.appending(path: "first-read-\(UUID())"))

    func model() -> HealthHomeModel {
        HealthHomeModel(
            source: source, summaries: summaries, memory: memory, cache: cache, preferences: prefs,
            calendar: TestClock.calendar, now: { TestClock.now }, locale: "en")
    }

    @Test("with nothing cached, the first read is a placeholder, never 'nothing recorded'")
    func firstReadIsAPlaceholder() async {
        await source.set {
            $0.sums[.steps] = [DayValue(day: TestClock.today, value: 9000)]
            $0.gated = true
        }
        let m = model()
        #expect(!m.isReadingFirst)
        let load = Task { await m.load() }
        while await !source.holding { await Task.yield() }
        #expect(m.isReadingFirst)
        #expect(m.day == nil)
        await source.release()
        await load.value
        #expect(!m.isReadingFirst)
        #expect(m.day?.snapshot.activity?.steps == 9000)
    }

    @Test("today's cached note fills the screen while Apple Health answers")
    func cachedNoteShowsFirst() async throws {
        await source.set {
            $0.sums[.steps] = [DayValue(day: TestClock.today, value: 9000)]
            $0.gated = true
        }
        prefs.summaryConsent = true
        let snapshot = HealthSnapshot(
            date: "2026-10-01", localTime: "08:00", locale: "en", sleep: nil,
            activity: .init(
                steps: 4000, stepGoal: 8000, activeKcal: 100, kcalGoal: nil, exerciseMin: 5, standHours: 3, workouts: []),
            recovery: nil, body: nil, odyState: .active)
        let summary = HealthSummary(
            headline: "cached", summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
            memorySuggestion: nil)
        try cache.save(CachedReport(snapshot: snapshot, summary: summary, generatedAt: TestClock.now))
        let m = model()
        let load = Task { await m.load() }
        while await !source.holding { await Task.yield() }
        #expect(!m.isReadingFirst)
        #expect(m.day?.snapshot.activity?.steps == 4000)
        #expect(m.report == .ready(summary))
        await source.release()
        await load.value
        #expect(m.day?.snapshot.activity?.steps == 9000)
    }
}
