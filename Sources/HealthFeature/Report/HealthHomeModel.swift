// Sources/HealthFeature/Report/HealthHomeModel.swift
import Foundation
import Models
import Observation

/// The home screen's state: the day read from the health store, and the report written about it. The day always
/// shows; the report needs consent and a reachable computer with a model, and says which one is missing.
@MainActor
@Observable
public final class HealthHomeModel {
    public enum Report: Equatable {
        case idle
        case needsConsent
        case writing
        case ready(HealthSummary)
        case offline
        case needsModel
        case failed
    }

    public private(set) var day: HealthDay?
    public private(set) var report: Report = .idle
    public private(set) var suggestion: HealthSummary.MemorySuggestion?
    public private(set) var isLoading = false
    public private(set) var celebrates = false
    public let preferences: HealthPreferences

    @ObservationIgnored private let source: any HealthDataSource
    @ObservationIgnored private let summaries: any HealthSummaryService
    @ObservationIgnored private let memory: any MemoryWriter
    @ObservationIgnored private let cache: ReportCache
    @ObservationIgnored private let builder: SnapshotBuilder
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let locale: String

    public init(
        source: any HealthDataSource, summaries: any HealthSummaryService, memory: any MemoryWriter,
        cache: ReportCache, preferences: HealthPreferences, calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }, locale: String
    ) {
        self.source = source
        self.summaries = summaries
        self.memory = memory
        self.cache = cache
        self.preferences = preferences
        self.builder = SnapshotBuilder(source: source, calendar: calendar)
        self.now = now
        self.locale = locale
    }

    public func load(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        let built: HealthDay
        do {
            built = try await builder.build(now: now(), locale: locale)
        } catch {
            report = .failed
            return
        }
        day = built
        let snapshot = built.snapshot
        celebrates = snapshot.activity?.reachedGoal == true && preferences.lastCelebrated != snapshot.date

        guard snapshot.odyState != .permission, snapshot.odyState != .noData else {
            report = .idle
            suggestion = nil
            return
        }
        guard preferences.summaryConsent else {
            report = .needsConsent
            return
        }
        let cached = cache.load(date: snapshot.date)
        if !ReportPolicy.needsRegeneration(cached: cached, current: snapshot, forced: force), let cached {
            show(cached.summary)
            return
        }
        report = .writing
        do {
            let summary = try await summaries.summary(for: snapshot)
            try? cache.save(CachedReport(snapshot: snapshot, summary: summary, generatedAt: now()))
            show(summary)
        } catch {
            // A report from earlier today beats an error.
            if let cached { show(cached.summary) } else { report = Self.reportState(for: error) }
        }
    }

    public func authorize() async {
        try? await source.requestAuthorization()
        preferences.hasOnboarded = true
        await load()
    }

    public func grantConsent() async {
        preferences.summaryConsent = true
        await load()
    }

    /// Saves the suggestion as a memory. False when it could not be saved; the card stays.
    public func remember() async -> Bool {
        guard let suggestion else { return false }
        do {
            try await memory.remember(suggestion)
            preferences.dismiss(suggestion.key)
            self.suggestion = nil
            return true
        } catch {
            return false
        }
    }

    public func dismissSuggestion() {
        guard let suggestion else { return }
        preferences.dismiss(suggestion.key)
        self.suggestion = nil
    }

    public func didCelebrate() {
        preferences.lastCelebrated = day?.snapshot.date
        celebrates = false
    }

    /// One cup (250 ml) into Apple Health, then the day again.
    public func logWater() async {
        try? await source.logWater(milliliters: 250, at: now())
        await load()
    }

    public static func reportState(for error: Error) -> Report {
        if error is URLError { return .offline }
        if let http = error as? HTTPError, http.code.hasPrefix("CONFIG_") || http.code == "SETTING_NOT_FOUND" {
            return .needsModel
        }
        return .failed
    }

    private func show(_ summary: HealthSummary) {
        report = .ready(summary)
        if let s = summary.memorySuggestion, !preferences.isDismissed(s.key) {
            suggestion = s
        } else {
            suggestion = nil
        }
    }
}
