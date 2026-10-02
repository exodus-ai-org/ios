// Sources/HealthFeature/Trends/TrendsModel.swift
import Foundation
import Models
import Observation

/// The calendar page's state: which view and period is shown, its days' records and the previous period's (for the
/// change), and the day sheet's note and numbers. Moving changes the period at once; the view then calls `load()`,
/// and only the newest load lands.
@MainActor
@Observable
final class TrendsModel {
    enum Phase: Equatable { case loading, ready, failed }

    private(set) var scope: TrendScope
    private(set) var period: Period
    private(set) var phase: Phase = .loading
    /// The shown period's days and the previous period's, by day.
    private(set) var records: [Date: DayRecord] = [:]
    private(set) var current: Aggregates?
    private(set) var previous: Aggregates?
    let calendar: Calendar
    let locale: String

    @ObservationIgnored private let store: DayRecordStore
    @ObservationIgnored private let archive: HealthArchive
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var generation = 0

    init(
        route: TrendsRoute, store: DayRecordStore, archive: HealthArchive, calendar: Calendar, locale: String,
        now: @escaping @Sendable () -> Date
    ) {
        self.scope = route.scope
        self.period = Period.containing(min(route.anchor, now()), route.scope.kind, calendar: calendar)
        self.store = store
        self.archive = archive
        self.calendar = calendar
        self.locale = locale
        self.now = now
    }

    var today: Date { calendar.startOfDay(for: now()) }

    /// The next period has begun; the calendar never pages into days with nothing in them yet.
    var canGoForward: Bool { period.end <= today }

    var title: String { TrendText.title(period, calendar: calendar) }

    var cells: [CalendarCell] { CalendarGrid.cells(period, records: records, today: today, calendar: calendar) }

    var months: [MonthBar] {
        CalendarGrid.months(period, records: Array(records.values), today: today, calendar: calendar)
    }

    /// Stays where the user is looking: today if it is on screen, else the shown period's first day.
    func select(_ scope: TrendScope) {
        guard scope != self.scope else { return }
        let anchor = period.contains(today) ? today : period.start
        self.scope = scope
        period = Period.containing(anchor, scope.kind, calendar: calendar)
    }

    func showPrevious() { period = period.previous(calendar: calendar) }

    func showNext() {
        guard canGoForward else { return }
        period = period.next(calendar: calendar)
    }

    func open(month: Period) {
        scope = .month
        period = month
    }

    /// Reads the shown period and the one before it. A load that a newer one overtook is dropped, so paging faster
    /// than Apple Health answers never shows an older period's numbers under a newer title.
    func load() async {
        generation += 1
        let mine = generation
        let shown = period
        let before = shown.previous(calendar: calendar)
        phase = .loading
        // The old period's numbers never show under the new title.
        current = nil
        previous = nil
        do {
            let lastDay = calendar.date(byAdding: .day, value: -1, to: shown.end)!
            let read = try await store.records(from: before.start, through: lastDay)
            guard mine == generation else { return }
            let all = Array(read.values)
            records = read
            current = TrendMath.aggregate(all, in: shown, today: today, calendar: calendar)
            previous = TrendMath.aggregate(all, in: before, today: today, calendar: calendar)
            phase = .ready
        } catch {
            guard mine == generation else { return }
            records = [:]
            phase = .failed
        }
    }

    /// The note kept for a day, if any.
    func archived(_ day: Date) -> ArchivedDay? {
        archive.read(day: WireDate(timeZone: calendar.timeZone).day(day))
    }

    /// The whole day as the home builds today, for the day sheet's question; nil when it can't be read.
    func snapshot(for day: Date) async -> HealthSnapshot? {
        try? await store.snapshot(for: day, locale: locale).snapshot
    }
}
