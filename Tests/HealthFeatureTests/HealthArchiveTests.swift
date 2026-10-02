import Foundation
import Models
import Testing

@testable import HealthFeature

struct HealthArchiveTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    var archive: HealthArchive { HealthArchive(directory: root.appending(path: "archive", directoryHint: .isDirectory)) }

    static func entry(_ day: String = "2026-10-01", headline: String = "h") -> ArchivedDay {
        ArchivedDay(
            snapshot: HealthSnapshot(
                date: day, localTime: "09:00", locale: "en", sleep: nil, activity: nil, recovery: nil, body: nil,
                odyState: .tired),
            summary: HealthSummary(
                headline: headline, summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
                memorySuggestion: nil),
            generatedAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func aNoteIsFiledByItsDay() throws {
        try archive.write(Self.entry())
        #expect(archive.read(day: "2026-10-01") == Self.entry())
        let path = archive.directory.appending(path: "2026/10/01.json").path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(archive.read(day: "2026-10-02") == nil)
    }

    @Test func writingTheSameDayAgainReplacesIt() throws {
        try archive.write(Self.entry(headline: "morning"))
        try archive.write(Self.entry("2026-09-30", headline: "yesterday"))
        try archive.write(Self.entry(headline: "evening"))
        #expect(archive.read(day: "2026-10-01")?.summary.headline == "evening")
        #expect(archive.read(day: "2026-09-30")?.summary.headline == "yesterday")
    }

    @Test func aCorruptFileIsNoNote() throws {
        try archive.write(Self.entry())
        try Data("{ not json".utf8).write(to: try #require(archive.fileURL(day: "2026-10-01")))
        #expect(archive.read(day: "2026-10-01") == nil)
    }

    /// A file that holds another day's note (copied by hand, or a clock gone wrong) is not that day's note.
    @Test func aFileHoldingAnotherDayIsNoNote() throws {
        try archive.write(Self.entry("2026-09-30"))
        let url = try #require(archive.fileURL(day: "2026-10-01"))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try #require(archive.fileURL(day: "2026-09-30")), to: url)
        #expect(archive.read(day: "2026-10-01") == nil)
    }

    @Test func onlyWireDaysHaveFiles() {
        #expect(archive.fileURL(day: "2026-10-01") != nil)
        for bad in ["", "2026-10", "2026-1-01", "../../x", "2026-10-01/../..", "2026-1O-01", "abcd-ef-gh"] {
            #expect(archive.fileURL(day: bad) == nil)
        }
        #expect(throws: (any Error).self) { try archive.write(Self.entry("../../etc")) }
    }

    @Test func clearingDeletesEveryNoteAndReport() throws {
        try archive.write(Self.entry())
        let reports = archive.directory.appending(path: "reports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: reports.appending(path: "2026-W40.json"))
        try archive.clear()
        #expect(archive.read(day: "2026-10-01") == nil)
        #expect(!FileManager.default.fileExists(atPath: archive.directory.path(percentEncoded: false)))
        try archive.clear()
    }

    @Test func theArchiveIsExcludedFromBackup() throws {
        try archive.write(Self.entry())
        let file = try #require(archive.fileURL(day: "2026-10-01"))
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try archive.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    // MARK: The report-save path

    /// Under a folder with a space in its name, as on a phone ("Application Support").
    var cache: ReportCache {
        ReportCache(directory: root.appending(path: "Application Support/Health", directoryHint: .isDirectory))
    }

    @Test func savingTodaysReportArchivesIt() throws {
        let report = ReportStoreTests.report()
        try cache.save(report)
        #expect(cache.archive.read(day: "2026-10-01") == ArchivedDay(report))
        #expect(cache.archive.directory == cache.directory.appending(path: "archive", directoryHint: .isDirectory))
    }

    /// Withdrawing consent forgets today's report from the disk — under "Application Support" too — and keeps the
    /// archive.
    @Test func clearingTheReportKeepsTheArchive() throws {
        try cache.save(ReportStoreTests.report())
        try cache.clear()
        #expect(cache.load(date: "2026-10-01") == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.fileURL.path(percentEncoded: false)))
        #expect(cache.archive.read(day: "2026-10-01") != nil)
    }
}
