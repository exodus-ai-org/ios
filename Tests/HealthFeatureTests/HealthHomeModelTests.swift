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

/// Each call takes the next delay and answers with its own number, so a test can tell which call landed.
actor SlowSummaries: HealthSummaryService {
    var delays: [Duration]
    var calls = 0
    init(_ delays: [Duration]) { self.delays = delays }
    func summary(for snapshot: HealthSnapshot) async throws -> HealthSummary {
        calls += 1
        let n = calls
        try? await Task.sleep(for: delays[n - 1])
        return HealthSummary(
            headline: "call \(n)", summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
            memorySuggestion: nil)
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

    @Test func authorizingDoesNotFinishOnboarding() async {
        let m = model()
        #expect(m.needsOnboarding)
        await m.authorize()
        #expect(m.needsOnboarding)
        #expect(!prefs.hasOnboarded)
    }

    @Test func finishingOnboardingPersists() {
        let m = model()
        m.finishOnboarding()
        #expect(!m.needsOnboarding)
        #expect(prefs.hasOnboarded)
        #expect(model().hasOnboarded)
    }

    @Test func aDeviceWithoutHealthSkipsOnboarding() {
        let m = HealthHomeModel(
            source: FakeHealthSource(isAvailable: false), summaries: summaries, memory: memory, cache: cache,
            preferences: prefs, calendar: TestClock.calendar, now: { TestClock.now }, locale: "en")
        #expect(!m.needsOnboarding)
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

    @Test func revokingConsentForgetsTheReport() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        #expect(m.suggestion != nil)
        #expect(FileManager.default.fileExists(atPath: cache.fileURL.path()))

        m.revokeConsent()
        #expect(!prefs.summaryConsent)
        #expect(!m.hasConsent)
        #expect(m.report == .needsConsent)
        #expect(m.suggestion == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.fileURL.path()))

        await m.load(force: true)
        #expect(m.report == .needsConsent)
        #expect(await summaries.calls == 1)
    }

    @Test func clearingAnEmptyCacheIsFine() throws {
        try cache.clear()
        #expect(cache.load(date: "2026-10-01") == nil)
    }

    @Test func errorsMapToStates() {
        #expect(HealthHomeModel.reportState(for: URLError(.cannotConnectToHost)) == .offline)
        // A timeout is usually a slow model, not a missing computer.
        #expect(HealthHomeModel.reportState(for: URLError(.timedOut)) == .failed)
        #expect(HealthHomeModel.reportState(for: HTTPError(statusCode: 400, code: "CONFIG_MISSING_PROVIDER", message: "")) == .needsModel)
        #expect(HealthHomeModel.reportState(for: HTTPError(statusCode: 404, code: "SETTING_NOT_FOUND", message: "")) == .needsModel)
        #expect(HealthHomeModel.reportState(for: HTTPError(statusCode: 0, code: "INVALID_BASE_URL", message: "")) == .offline)
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

    @Test func overlappingLoadsShareOneRun() async {
        await withData()
        prefs.summaryConsent = true
        let slow = SlowSummaries([.milliseconds(100)])
        let m = HealthHomeModel(
            source: source, summaries: slow, memory: memory, cache: cache, preferences: prefs,
            calendar: TestClock.calendar, now: { TestClock.now }, locale: "en")
        async let a: Void = m.load()
        async let b: Void = m.load()
        _ = await (a, b)
        #expect(await slow.calls == 1)
        #expect(!m.isLoading)
    }

    @Test func aForcedLoadReplacesASlowOne() async {
        await withData()
        prefs.summaryConsent = true
        let slow = SlowSummaries([.milliseconds(300), .milliseconds(0)])
        let m = HealthHomeModel(
            source: source, summaries: slow, memory: memory, cache: cache, preferences: prefs,
            calendar: TestClock.calendar, now: { TestClock.now }, locale: "en")
        let first = Task { await m.load() }
        while await slow.calls == 0 { await Task.yield() }
        await m.load(force: true)
        await first.value
        try? await Task.sleep(for: .milliseconds(400))
        #expect(m.report.readySummary?.headline == "call 2")
        #expect(cache.load(date: "2026-10-01")?.summary.headline == "call 2")
        #expect(!m.isLoading)
    }

    @Test func loggingWaterDuringALoadShowsTheCupWithoutRewritingTheReport() async {
        await withData()
        prefs.summaryConsent = true
        await source.set { $0.slowMs = 200 }
        let m = model()
        let first = Task { await m.load() }
        try? await Task.sleep(for: .milliseconds(50))
        await source.set { $0.slowMs = 0 }
        await m.logWater()
        await first.value
        try? await Task.sleep(for: .milliseconds(300))
        #expect(m.day?.snapshot.body?.waterCups == 1)
        #expect(await summaries.calls <= 1)
        #expect(!m.isLoading)
    }

    @Test func aWrittenNoteIsKeptForItsDay() async {
        await withData()
        prefs.summaryConsent = true
        await model().load()
        #expect(cache.archive.read(day: "2026-10-01")?.summary == Self.summary)
    }

    @Test func stoppingNotesKeepsThePastOnes() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        m.revokeConsent()
        #expect(cache.load(date: "2026-10-01") == nil)
        #expect(cache.archive.read(day: "2026-10-01") != nil)
    }

    @Test func clearingTheArchiveLeavesTodaysNote() async throws {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        try cache.archive.write(HealthArchiveTests.entry("2026-09-30"))
        #expect(m.clearArchive())
        #expect(cache.archive.read(day: "2026-09-30") == nil)
        #expect(cache.load(date: "2026-10-01") != nil)
        // Today's note stays filed; only the past is cleared.
        #expect(cache.archive.read(day: "2026-10-01")?.summary == Self.summary)
        #expect(m.report.readySummary != nil)
    }

    @Test func theWeekCardReadsThisWeekAndLast() async throws {
        let monday = TestClock.date(2026, 9, 28)
        let lastWeek = TestClock.date(2026, 9, 22)
        await source.set {
            $0.sums[.steps] = [
                DayValue(day: lastWeek, value: 6000), DayValue(day: monday, value: 7000),
                DayValue(day: TestClock.today, value: 1200),
            ]
        }
        let m = model()
        await m.load()
        let week = try #require(m.week)
        #expect(week.period == Period.containing(TestClock.now, .week, calendar: TestClock.calendar))
        #expect(week.cells.count == 7)
        // Today's 1,200 so far is on its cell but not in the average: the day isn't over.
        #expect(week.cells.first { $0.isToday }?.record?.steps == 1200)
        #expect(week.current.steps == MetricSummary(average: 7000, min: 7000, max: 7000, days: 1))
        #expect(week.previous.steps.average == 6000)
    }
}

extension HealthHomeModel.Report {
    var readySummary: HealthSummary? {
        if case .ready(let s) = self { return s }
        return nil
    }
}
