// Tests/HealthFeatureTests/PeriodReportsTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

@MainActor
struct PeriodReportsTests {
    let cal = TestClock.calendar
    let source = FakeHealthSource()
    let service = StubPeriodReports()
    let archive = HealthArchive(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))

    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: TestClock.today)! }
    var september: Period { Period.containing(TestClock.date(2026, 9, 15), .month, calendar: cal) }
    var q3: Period { Period.containing(TestClock.date(2026, 9, 15), .quarter, calendar: cal) }
    var week39: Period { Period.containing(TestClock.date(2026, 9, 23), .week, calendar: cal) }
    var year2025: Period { Period.containing(TestClock.date(2025, 6, 1), .year, calendar: cal) }

    func reports(consent: Bool = true, now: @escaping @Sendable () -> Date = { TestClock.now }) -> PeriodReports {
        reports(consent: Consent(consent), now: now)
    }

    func reports(consent: Consent, now: @escaping @Sendable () -> Date = { TestClock.now }) -> PeriodReports {
        let records = DayRecordStore(builder: SnapshotBuilder(source: source, calendar: cal), calendar: cal, now: now)
        return PeriodReports(
            store: archive.reports, service: service, records: records, archive: archive, calendar: cal, locale: "en",
            now: now, hasConsent: { consent.given })
    }

    /// Consent a test can take back halfway.
    @MainActor final class Consent {
        var given: Bool
        init(_ given: Bool) { self.given = given }
    }

    /// 9,000 steps a day, going back `days` days from today.
    func steps(days: Int = 500) async {
        let values = (0..<days).map { DayValue(day: day(-$0), value: 9000) }
        await source.set { $0.sums[.steps] = values }
    }

    func keep(_ period: Period, headline: String = "kept", at date: Date) throws {
        let report = PeriodReport(
            PeriodReportReply(headline: headline), period: PeriodReport.Span(period, calendar: cal)!, generatedAt: date,
            current: TrendMath.aggregate([], in: period, today: TestClock.now, calendar: cal), previous: nil)
        try archive.reports.write(report, id: period.reportID(calendar: cal)!)
    }

    @Test func dueReportsAreWrittenNewestFirstTwoAnOpen() async {
        await steps()
        let r = reports()
        await r.writeDue()
        #expect(await service.starts == ["2026-09-01", "2026-07-01"])
        #expect(r.state(for: week39) == .pending)
        await r.writeDue()
        #expect(await service.starts == ["2026-09-01", "2026-07-01", "2026-09-21", "2025-01-01"])
        await r.writeDue()
        #expect(await service.asked.count == 4)
        #expect(archive.reports.read(id: "2026-W39")?.headline == "Report 2026-09-21")
        guard case .ready(let report) = r.state(for: september) else { Issue.record("no September report"); return }
        #expect(report.generatedAt == TestClock.now)
        #expect(report.current.daysWithData == 30)
    }

    @Test func aFailureEndsTheOpenAndTheRestWait() async {
        await steps()
        await service.fail(URLError(.cannotConnectToHost))
        let r = reports()
        await r.writeDue()
        #expect(await service.asked.count == 1)
        #expect(r.state(for: september) == .pending)
        #expect(r.state(for: q3) == .pending)
        #expect(r.failure(for: september) == .offline)
        await service.fail(nil)
        await r.writeDue()
        #expect(await service.starts == ["2026-09-01", "2026-09-01", "2026-07-01"])
        #expect(r.failure(for: september) == nil)
    }

    @Test func withoutConsentNothingIsAskedOrWaits() async {
        await steps()
        let r = reports(consent: false)
        await r.writeDue()
        #expect(await service.asked.isEmpty)
        #expect(r.state(for: september) == .missing)
        #expect(await r.write(september) == .failed)
    }

    @Test func aKeptReportIsNeverWrittenAgainByItself() async throws {
        await steps()
        try keep(september, at: day(-1))
        let r = reports()
        await r.writeDue()
        #expect(await service.starts == ["2026-07-01", "2026-09-21"])
        #expect(archive.reports.read(id: "2026-09")?.headline == "kept")
    }

    @Test func aPeriodWithNoDataCostsNoCall() async {
        await steps(days: 70)
        let r = reports()
        await r.writeDue()
        await r.writeDue()
        await r.writeDue()
        #expect(await service.starts == ["2026-09-01", "2026-07-01", "2026-09-21"])
        #expect(r.state(for: year2025) == .missing)
    }

    @Test func aPeriodWithNoDataNeverWaits() async {
        await steps(days: 70)
        let r = reports()
        await r.writeDue()
        #expect(r.state(for: week39) == .pending)
        #expect(r.state(for: year2025) == .missing)
    }

    @Test func revokingConsentWhileTheDaysAreReadSendsNothing() async {
        await steps()
        let consent = Consent(true)
        let r = reports(consent: consent)
        await source.set { $0.gated = true }
        let write = Task { await r.write(september) }
        while !(await source.holding) { await Task.yield() }
        consent.given = false
        r.stop()
        await source.release()
        #expect(await write.value == .failed)
        #expect(await service.asked.isEmpty)
        #expect(archive.reports.read(id: "2026-09") == nil)
        #expect(r.state(for: september) == .missing)
    }

    @Test func clearingTheArchiveWhileTheDaysAreReadSendsNothing() async {
        await steps()
        let r = reports()
        await source.set { $0.gated = true }
        let write = Task { await r.write(september) }
        while !(await source.holding) { await Task.yield() }
        r.forget()
        await source.release()
        #expect(await write.value == .failed)
        #expect(await service.asked.isEmpty)
        #expect(archive.reports.read(id: "2026-09") == nil)
    }

    @Test func clearingTheArchiveMidWriteEndsThatOpen() async {
        await steps()
        let r = reports()
        await service.hold()
        let first = Task { await r.writeDue() }
        while await service.asked.isEmpty { await Task.yield() }
        r.forget()
        let second = Task { await r.writeDue() }
        // Bounded, so a new open that never asks fails the test instead of hanging it.
        var tries = 0
        while await service.asked.count < 2, tries < 10_000 {
            tries += 1
            await Task.yield()
        }
        await service.release()
        await first.value
        await second.value
        // The old open stops at its first answer; the new one writes its own two.
        #expect(await service.starts == ["2026-09-01", "2026-09-01", "2026-07-01"])
        #expect(r.state(for: week39) == .pending)
        guard case .ready = r.state(for: september) else { Issue.record("no September report"); return }
    }

    @Test func writingAgainReplacesTheKeptReport() async throws {
        await steps()
        try keep(september, at: day(-3))
        let r = reports()
        #expect(await r.write(september) == .written)
        #expect(archive.reports.read(id: "2026-09")?.headline == "Report 2026-09-01")
        guard case .ready(let report) = r.state(for: september) else { Issue.record("no report"); return }
        #expect(report.headline == "Report 2026-09-01")
    }

    @Test func aFailedRewriteKeepsTheReport() async throws {
        await steps()
        try keep(september, at: day(-3))
        await service.fail(URLError(.timedOut))
        let r = reports()
        #expect(await r.write(september) == .failed)
        guard case .ready(let report) = r.state(for: september) else { Issue.record("report lost"); return }
        #expect(report.headline == "kept")
        #expect(r.failure(for: september) == .failed)
    }

    @Test func twoOpensAtOnceStillAskTwice() async {
        await steps()
        let r = reports()
        async let a: Void = r.writeDue()
        async let b: Void = r.writeDue()
        _ = await (a, b)
        #expect(await service.asked.count == 2)
    }

    @Test func theReadyLineShowsTheNewestReportForTwoDays() async throws {
        try keep(september, at: TestClock.now.addingTimeInterval(-3600))
        try keep(week39, at: TestClock.now.addingTimeInterval(-60))
        #expect(reports().fresh()?.period == week39)
        let later = TestClock.now.addingTimeInterval(49 * 3600)
        #expect(reports(now: { later }).fresh() == nil)
        #expect(reports(now: { TestClock.now.addingTimeInterval(47 * 3600) }).fresh()?.period == week39)
    }
}
