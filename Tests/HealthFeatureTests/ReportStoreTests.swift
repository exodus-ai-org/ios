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
