// Tests/HealthFeatureTests/HealthHomeReportsTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

/// The period reports as Health's opens drive them through the home model.
@MainActor
struct HealthHomeReportsTests {
    let cal = TestClock.calendar
    let source = FakeHealthSource()
    let summaries = StubSummaries(.success(HealthHomeModelTests.summary))
    let service = StubPeriodReports()
    let prefs = HealthPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let cache = ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    var september: Period { Period.containing(TestClock.date(2026, 9, 15), .month, calendar: cal) }

    func model(consent: Bool = true) async -> HealthHomeModel {
        prefs.summaryConsent = consent
        prefs.hasOnboarded = true
        let values = (0..<500).map { DayValue(day: cal.date(byAdding: .day, value: -$0, to: TestClock.today)!, value: 9000) }
        await source.set { $0.sums[.steps] = values }
        return HealthHomeModel(
            source: source, summaries: summaries, memory: StubMemory(), cache: cache, preferences: prefs,
            periodReports: service, calendar: cal, now: { TestClock.now }, locale: "en")
    }

    @Test func anOpenWritesTheDueReportsAfterTheNote() async {
        let m = await model()
        await m.load()
        await m.writeDueReports()
        #expect(await summaries.calls == 1)
        #expect(await service.starts == ["2026-09-01", "2026-07-01"])
        #expect(m.reports.state(for: september) != .missing)
    }

    @Test func withoutHealthAccessNoReportIsWritten() async {
        let m = await model()
        await source.set { $0.requested = false }
        await m.load()
        await m.writeDueReports()
        #expect(await service.asked.isEmpty)
    }

    @Test func grantingConsentWritesTheDueReports() async {
        let m = await model(consent: false)
        await m.grantConsent()
        #expect(await service.asked.count == 2)
    }

    @Test func clearingTheArchiveForgetsTheReports() async {
        let m = await model()
        await m.load()
        await m.writeDueReports()
        guard case .ready = m.reports.state(for: september) else { Issue.record("no report"); return }
        #expect(m.clearArchive())
        #expect(m.reports.state(for: september) == .missing)
        #expect(cache.archive.reports.read(id: "2026-09") == nil)
    }

    @Test func revokingConsentDropsTheReportBeingWritten() async {
        let m = await model()
        await m.load()
        await service.hold()
        let open = Task { await m.writeDueReports() }
        while await service.asked.isEmpty { await Task.yield() }
        m.revokeConsent()
        await service.release()
        await open.value
        #expect(cache.archive.reports.read(id: "2026-09") == nil)
        #expect(m.reports.state(for: september) == .missing)
        #expect(await service.asked.count == 1)
    }
}
