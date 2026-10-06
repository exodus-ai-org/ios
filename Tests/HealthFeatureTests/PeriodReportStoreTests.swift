// Tests/HealthFeatureTests/PeriodReportStoreTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct PeriodReportStoreTests {
    let archive = HealthArchive(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    var store: PeriodReportStore { archive.reports }

    static func report(headline: String = "h") -> PeriodReport {
        let cal = TestClock.calendar
        let september = Period.containing(TestClock.date(2026, 9, 15), .month, calendar: cal)
        return PeriodReport(
            PeriodReportReply(headline: headline, insights: [.init(category: "sleep", title: "t")]),
            period: PeriodReport.Span(september, calendar: cal)!, generatedAt: TestClock.now,
            current: TrendMath.aggregate([], in: september, today: TestClock.now, calendar: cal), previous: nil)
    }

    @Test func aReportIsKeptUnderItsPeriodInTheArchive() throws {
        let report = Self.report()
        try store.write(report, id: "2026-09")
        let path = archive.directory.appending(path: "reports/2026-09.json").path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(store.read(id: "2026-09") == report)
        #expect(store.read(id: "2026-08") == nil)
    }

    @Test func writingAgainReplacesIt() throws {
        try store.write(Self.report(headline: "first"), id: "2026-09")
        try store.write(Self.report(headline: "second"), id: "2026-09")
        #expect(store.read(id: "2026-09")?.headline == "second")
    }

    @Test func aCorruptFileIsNoReport() throws {
        try store.write(Self.report(), id: "2026-09")
        try Data("{".utf8).write(to: #require(store.fileURL(id: "2026-09")))
        #expect(store.read(id: "2026-09") == nil)
    }

    @Test func onlyReportNamesHaveFiles() {
        for id in ["2026-W40", "2026-09", "2026-Q3", "2026"] { #expect(store.fileURL(id: id) != nil) }
        for id in ["../2026", "2026-Q5", "2026-9", "2026-W4", "x", ""] { #expect(store.fileURL(id: id) == nil) }
        #expect(throws: CocoaError.self) { try store.write(Self.report(), id: "../x") }
    }

    @Test func neitherTheFileNorItsFoldersAreBackedUp() throws {
        try store.write(Self.report(), id: "2026-09")
        let file = try #require(store.fileURL(id: "2026-09"))
        for url in [file, store.directory, archive.directory] {
            #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        }
    }

    @Test func clearingTheArchiveDeletesTheReports() throws {
        try store.write(Self.report(), id: "2026-09")
        try archive.clear()
        #expect(store.read(id: "2026-09") == nil)
    }
}
