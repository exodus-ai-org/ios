import Foundation
import Models

public struct CachedReport: Codable, Equatable, Sendable {
    public var snapshot: HealthSnapshot
    public var summary: HealthSummary
    public var generatedAt: Date

    public init(snapshot: HealthSnapshot, summary: HealthSummary, generatedAt: Date) {
        self.snapshot = snapshot
        self.summary = summary
        self.generatedAt = generatedAt
    }
}

/// Today's report on disk, so reopening Health does not ask the computer again. Kept in Application Support and
/// excluded from backups: App Review does not allow health data in iCloud.
public struct ReportCache: Sendable {
    let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static func standard() -> ReportCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ReportCache(directory: base.appending(path: "Health", directoryHint: .isDirectory))
    }

    public var fileURL: URL { directory.appending(path: "report.json") }

    public func load(date: String) -> CachedReport? {
        guard let data = try? Data(contentsOf: fileURL),
            let report = try? JSONDecoder().decode(CachedReport.self, from: data), report.snapshot.date == date
        else { return nil }
        return report
    }

    public func save(_ report: CachedReport) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try HealthWire.encoder().encode(report).write(to: fileURL, options: [.atomic, .completeFileProtection])
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

/// When the report is written again: on request, on a new day, or when the day has changed enough to change Ody.
enum ReportPolicy {
    static func needsRegeneration(cached: CachedReport?, current: HealthSnapshot, forced: Bool) -> Bool {
        guard !forced, let cached else { return true }
        return cached.snapshot.date != current.date || cached.snapshot.odyState != current.odyState
    }
}

/// The small things Health remembers on this phone.
public final class HealthPreferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The user agreed to send the day's summary to their AI provider.
    public var summaryConsent: Bool {
        get { defaults.bool(forKey: "health.summaryConsent") }
        set { defaults.set(newValue, forKey: "health.summaryConsent") }
    }

    public var hasOnboarded: Bool {
        get { defaults.bool(forKey: "health.hasOnboarded") }
        set { defaults.set(newValue, forKey: "health.hasOnboarded") }
    }

    /// The day ("yyyy-MM-dd") the goal confetti last played, so it plays once a day.
    public var lastCelebrated: String? {
        get { defaults.string(forKey: "health.lastCelebrated") }
        set { defaults.set(newValue, forKey: "health.lastCelebrated") }
    }

    public func isDismissed(_ key: String) -> Bool { dismissed.contains(key) }

    public func dismiss(_ key: String) { defaults.set(Array(dismissed.union([key])), forKey: "health.dismissedSuggestions") }

    private var dismissed: Set<String> { Set(defaults.stringArray(forKey: "health.dismissedSuggestions") ?? []) }
}
