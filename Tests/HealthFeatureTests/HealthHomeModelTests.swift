// Tests/HealthFeatureTests/HealthHomeModelTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

actor StubSummaries: HealthSummaryService {
    var result: Result<HealthSummary, Error>
    var calls = 0
    init(_ result: Result<HealthSummary, Error>) { self.result = result }
    func set(_ r: Result<HealthSummary, Error>) { result = r }
    func summary(for snapshot: HealthSnapshot) async throws -> HealthSummary {
        calls += 1
        return try result.get()
    }
}

actor StubMemory: MemoryWriter {
    var saved: [HealthSummary.MemorySuggestion] = []
    var fails = false
    func setFails() { fails = true }
    func remember(_ s: HealthSummary.MemorySuggestion) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        saved.append(s)
    }
}

@MainActor
struct HealthHomeModelTests {
    static let suggestion = HealthSummary.MemorySuggestion(section: "profile", key: "weekday-sleep", summary: "s")
    static let summary = HealthSummary(
        headline: "h", summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
        memorySuggestion: suggestion)

    let source = FakeHealthSource()
    let summaries = StubSummaries(.success(summary))
    let memory = StubMemory()
    let prefs = HealthPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let cache = ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))

    func model() -> HealthHomeModel {
        HealthHomeModel(
            source: source, summaries: summaries, memory: memory, cache: cache, preferences: prefs,
            calendar: TestClock.calendar, now: { TestClock.now }, locale: "en")
    }

    func withData() async {
        await source.set { $0.sums[.steps] = [DayValue(day: TestClock.today, value: 9000)] }
    }

    @Test func withoutConsentThereIsDataButNoReport() async {
        await withData()
        let m = model()
        await m.load()
        #expect(m.day?.snapshot.activity?.steps == 9000)
        #expect(m.report == .needsConsent)
        #expect(await summaries.calls == 0)
    }

    @Test func withConsentTheReportIsWrittenAndCached() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        #expect(m.report == .ready(Self.summary))
        #expect(m.suggestion == Self.suggestion)
        #expect(cache.load(date: "2026-10-01")?.summary == Self.summary)

        let again = model()
        await again.load()
        #expect(again.report == .ready(Self.summary))
        #expect(await summaries.calls == 1)  // the cache answered
    }

    @Test func forceRewrites() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        await m.load(force: true)
        #expect(await summaries.calls == 2)
    }

    @Test func errorsMapToStates() {
        #expect(HealthHomeModel.reportState(for: URLError(.cannotConnectToHost)) == .offline)
        #expect(HealthHomeModel.reportState(for: HTTPError(statusCode: 400, code: "CONFIG_MISSING_PROVIDER", message: "")) == .needsModel)
        #expect(HealthHomeModel.reportState(for: HTTPError(statusCode: 404, code: "SETTING_NOT_FOUND", message: "")) == .needsModel)
        #expect(HealthHomeModel.reportState(for: HTTPError(statusCode: 500, code: "AI_GENERATION_FAILED", message: "")) == .failed)
    }

    @Test func anOfflineComputerStillShowsTheDay() async {
        await withData()
        prefs.summaryConsent = true
        await summaries.set(.failure(URLError(.cannotConnectToHost)))
        let m = model()
        await m.load()
        #expect(m.report == .offline)
        #expect(m.day != nil)
        #expect(!m.isLoading)
    }

    @Test func rememberSavesAndClearsTheSuggestion() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        #expect(await m.remember())
        #expect(await memory.saved == [Self.suggestion])
        #expect(m.suggestion == nil)
    }

    @Test func aFailedRememberKeepsTheSuggestion() async {
        await withData()
        prefs.summaryConsent = true
        await memory.setFails()
        let m = model()
        await m.load()
        #expect(await !m.remember())
        #expect(m.suggestion == Self.suggestion)
    }

    @Test func aDismissedSuggestionStaysDismissed() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        m.dismissSuggestion()
        #expect(m.suggestion == nil)
        await m.load(force: true)
        #expect(m.suggestion == nil)
    }

    @Test func celebrationPlaysOncePerDay() async {
        await withData()  // 9000 ≥ 8000
        let m = model()
        await m.load()
        #expect(m.celebrates)
        m.didCelebrate()
        await m.load()
        #expect(!m.celebrates)
    }

    @Test func loggingWaterWritesAndReloads() async {
        await withData()
        let m = model()
        await m.load()
        await m.logWater()
        #expect(await source.loggedWater == [250])
    }
}
