// Sources/HealthFeature/Report/HealthHomeModel.swift
import Foundation
import Models
import Observation
import WidgetKitShared

/// The home screen's state: the day read from the health store, and the report written about it. The day always
/// shows; the report needs consent and a reachable computer with a model, and says which one is missing.
@MainActor
@Observable
public final class HealthHomeModel {
    public enum Report: Equatable, Sendable {
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
    /// Observed mirror of the stored flag, so finishing onboarding swaps the screen.
    public private(set) var hasOnboarded: Bool
    /// Observed mirror of the stored consent, for the menu's toggle.
    public private(set) var hasConsent: Bool
    /// This week for the home's card; nil until it has been read.
    private(set) var week: WeekGlance?
    /// The calendar's day records, kept across visits to it.
    @ObservationIgnored let dayRecords: DayRecordStore
    @ObservationIgnored let calendar: Calendar

    @ObservationIgnored private let source: any HealthDataSource
    @ObservationIgnored private let summaries: any HealthSummaryService
    @ObservationIgnored private let memory: any MemoryWriter
    @ObservationIgnored private let cache: ReportCache
    @ObservationIgnored private let builder: SnapshotBuilder
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let locale: String
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var remembering = false

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
        self.hasOnboarded = preferences.hasOnboarded
        self.hasConsent = preferences.summaryConsent
        let builder = SnapshotBuilder(source: source, calendar: calendar)
        self.builder = builder
        self.calendar = calendar
        self.dayRecords = DayRecordStore(builder: builder, calendar: calendar, now: now)
        self.now = now
        self.locale = locale
    }

    /// One load at a time: a plain call joins the one running, a forced one replaces it and rewrites the report. The
    /// week's card is read after it.
    public func load(force: Bool = false) async {
        await reload(replacing: force, regenerate: force)
        await loadWeek()
    }

    /// `replacing` starts a fresh read of the store even while one runs (its day may predate a change); `regenerate`
    /// skips the cache. A replaced run may still finish, so every result is checked against the generation.
    private func reload(replacing: Bool, regenerate: Bool) async {
        if !replacing, running != nil {
            // The run joined can be replaced while we wait; the caller wants the newest one done.
            while let joined = running {
                await joined.value
                if running == joined { break }
            }
            return
        }
        running?.cancel()
        generation += 1
        let mine = generation
        isLoading = true
        let task = Task { await run(force: regenerate, generation: mine) }
        running = task
        await task.value
        if generation == mine {
            running = nil
            isLoading = false
        }
    }

    /// The first read of a visit is still on its way: nothing real to show yet, and nothing to call "nothing".
    public var isReadingFirst: Bool { day == nil && isLoading }

    private func run(force: Bool, generation mine: Int) async {
        func current() -> Bool { generation == mine && !Task.isCancelled }
        // Today's note, as it was cached, fills the screen while Apple Health answers: a returning reader sees the
        // page they left, not a blank one that says nothing was recorded.
        if day == nil, let cached = cache.load(date: WireDate(timeZone: calendar.timeZone).day(now())) {
            day = HealthDay(snapshot: cached.snapshot, night: nil)
            show(cached.summary)
        }
        let built: HealthDay
        do {
            built = try await builder.build(now: now(), locale: locale)
        } catch {
            // Whatever is already on screen beats an error.
            if current(), !Self.isCancellation(error), day == nil { report = .failed }
            return
        }
        guard current() else { return }
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
            guard current() else { return }
            try? cache.save(CachedReport(snapshot: snapshot, summary: summary, generatedAt: now()))
            show(summary)
        } catch {
            guard current(), !Self.isCancellation(error) else { return }
            // A report from earlier today beats an error.
            if let cached { show(cached.summary) } else { report = Self.reportState(for: error) }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    public func authorize() async {
        try? await source.requestAuthorization()
        await load()
    }

    public func grantConsent() async {
        preferences.summaryConsent = true
        hasConsent = true
        await load()
    }

    /// Stops the daily note: forgets today's report on disk and on screen, and drops a note still being written, so
    /// nothing more about the day goes to the computer until consent is given again.
    public func revokeConsent() {
        preferences.summaryConsent = false
        hasConsent = false
        running?.cancel()
        running = nil
        generation += 1
        isLoading = false
        try? cache.clear()
        suggestion = nil
        report = .needsConsent
    }

    /// Onboarding shows until the user has been through both asks; a device without Health has nothing to ask for.
    public var needsOnboarding: Bool { !hasOnboarded && source.isAvailable }

    public func finishOnboarding() {
        preferences.hasOnboarded = true
        hasOnboarded = true
    }

    /// Saves the suggestion as a memory. False when it could not be saved; the card stays.
    public func remember() async -> Bool {
        guard let suggestion, !remembering else { return false }
        remembering = true
        defer { remembering = false }
        do {
            try await memory.remember(suggestion)
            preferences.dismiss(suggestion.key)
            if self.suggestion?.key == suggestion.key { self.suggestion = nil }
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
        // A read that started before the cup was written would miss it, but the report is not rewritten per cup.
        await reload(replacing: true, regenerate: false)
    }

    /// A detail page reads its month from the same store the day came from.
    func historyLoader(calendar: Calendar = .current) -> HealthHistoryLoader { HealthHistoryLoader(source: source, calendar: calendar) }

    /// Every daily note kept on this phone.
    var archive: HealthArchive { cache.archive }

    /// This week and last, for the home's card. A failed read keeps what is shown.
    func loadWeek() async {
        let today = calendar.startOfDay(for: now())
        let period = Period.containing(today, .week, calendar: calendar)
        let before = period.previous(calendar: calendar)
        guard let records = try? await dayRecords.records(from: before.start, through: today) else { return }
        let all = Array(records.values)
        week = WeekGlance(
            period: period, cells: CalendarGrid.cells(period, records: records, today: today, calendar: calendar),
            current: TrendMath.aggregate(all, in: period, today: today, calendar: calendar),
            previous: TrendMath.aggregate(all, in: before, today: today, calendar: calendar))
    }

    /// The calendar page's model, on the same store and day records as the home.
    func trends(_ route: TrendsRoute) -> TrendsModel {
        TrendsModel(route: route, store: dayRecords, archive: archive, calendar: calendar, locale: locale, now: now)
    }

    /// Deletes every kept note on this phone (the menu's Clear archive), then files today's again: today's note stays
    /// on screen, so it stays in the calendar too. Apple Health is untouched.
    @discardableResult
    public func clearArchive() -> Bool {
        guard (try? archive.clear()) != nil else { return false }
        if let today = cache.load(date: WireDate(timeZone: calendar.timeZone).day(now())) {
            try? archive.write(ArchivedDay(today))
        }
        return true
    }

    public static func reportState(for error: Error) -> Report {
        if let url = error as? URLError {
            // A timeout is usually the model taking too long, not a missing computer.
            return url.code == .timedOut ? .failed : .offline
        }
        // Status 0 is no usable address: no computer is paired or configured.
        if let http = error as? HTTPError, http.statusCode == 0 { return .offline }
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

extension HealthHomeModel {
    /// What the widgets may show of today: only with a ready report (so only with consent).
    public var widgetGlance: HealthGlance? {
        guard case .ready(let summary) = report, let snapshot = day?.snapshot else { return nil }
        let mood: WidgetMood =
            switch snapshot.odyState {
            case .tired, .recovering: .sleepy
            case .happy, .active, .rested: .happy
            default: .neutral
            }
        let suggestion =
            mood == .sleepy
            ? String(localized: "ios:health.ask.suggestion.energy", defaultValue: "Why do I feel tired today?")
            : String(localized: "ios:health.ask.suggestion.sleep", defaultValue: "How did I sleep last night?")
        return HealthGlance(
            day: snapshot.date, sleepMinutes: snapshot.sleep?.asleepMin, steps: snapshot.activity?.steps,
            stepGoal: snapshot.activity?.stepGoal, headline: summary.headline, suggestion: suggestion, mood: mood)
    }
}
