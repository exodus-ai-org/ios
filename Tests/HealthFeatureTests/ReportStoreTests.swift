import Foundation
import Models
import Testing

@testable import HealthFeature

struct ReportStoreTests {
    static func report(date: String = "2026-10-01", state: OdyMood = .tired) -> CachedReport {
        CachedReport(
            snapshot: HealthSnapshot(
                date: date, localTime: "15:00", locale: "en", sleep: nil, activity: nil, recovery: nil, body: nil,
                odyState: state),
            summary: HealthSummary(
                headline: "h", summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
                memorySuggestion: nil),
            generatedAt: Date(timeIntervalSince1970: 0))
    }

    func tempCache() -> ReportCache {
        ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func savesAndLoadsTodaysReport() throws {
        let cache = tempCache()
        try cache.save(Self.report())
        #expect(cache.load(date: "2026-10-01") == Self.report())
        #expect(cache.load(date: "2026-10-02") == nil)
    }

    @Test func theFileIsExcludedFromBackup() throws {
        let cache = tempCache()
        try cache.save(Self.report())
        let values = try cache.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    /// A report cached before the note had insights still loads, as the Markdown note it was.
    @Test func aReportCachedBeforeTheStoryStillLoads() throws {
        let cache = tempCache()
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        let old = """
            {"generatedAt":0,"snapshot":{"date":"2026-10-01","localTime":"15:00","locale":"en","odyState":"tired"},
             "summary":{"categories":{"activity":null,"body":null,"recovery":null,"sleep":null},"headline":"h","summary":"s"}}
            """
        try Data(old.utf8).write(to: cache.fileURL)
        let loaded = try #require(cache.load(date: "2026-10-01"))
        #expect(loaded.summary.summary == "s")
        #expect(loaded.summary.insights == nil)
    }

    @Test func aMissingOrCorruptFileIsNoReport() throws {
        let cache = tempCache()
        #expect(cache.load(date: "2026-10-01") == nil)
        try FileManager.default.createDirectory(at: cache.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cache.fileURL)
        #expect(cache.load(date: "2026-10-01") == nil)
    }

    @Test func regenerationPolicy() {
        let cached = Self.report()
        #expect(ReportPolicy.needsRegeneration(cached: nil, current: cached.snapshot, forced: false))
        #expect(!ReportPolicy.needsRegeneration(cached: cached, current: cached.snapshot, forced: false))
        #expect(ReportPolicy.needsRegeneration(cached: cached, current: cached.snapshot, forced: true))
        #expect(ReportPolicy.needsRegeneration(cached: cached, current: Self.report(date: "2026-10-02").snapshot, forced: false))
        #expect(ReportPolicy.needsRegeneration(cached: cached, current: Self.report(state: .active).snapshot, forced: false))
    }

    @Test func preferencesRememberConsentAndDismissals() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = HealthPreferences(defaults: defaults)
        #expect(!prefs.summaryConsent)
        prefs.summaryConsent = true
        prefs.dismiss("weekday-sleep")
        let again = HealthPreferences(defaults: defaults)
        #expect(again.summaryConsent)
        #expect(again.isDismissed("weekday-sleep"))
        #expect(!again.isDismissed("other"))
    }
}
