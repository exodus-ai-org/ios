// Sources/HealthFeature/Report/PeriodReports.swift
import Foundation
import Observation

/// The period reports (spec §5): which are kept, which are being written, and which wait for the computer. Each
/// Health open writes the last finished week, month, quarter and year that have no report, newest first and at most
/// two, only with the daily-note consent; the first failure ends the open and the rest wait for the next one. A kept
/// report is never written again by itself — only from its page.
@MainActor
@Observable
final class PeriodReports {
    enum State: Equatable {
        case missing, pending, writing
        case ready(PeriodReport)
    }

    /// Why the last try for a period failed, for its page.
    enum Failure: Equatable { case offline, needsModel, failed }

    /// How one write went: a report, nothing to write about (no data, so no call), or no report.
    enum Outcome: Equatable { case written, empty, failed }

    /// The home's line shows a report this long after it was written.
    static let freshFor: TimeInterval = 2 * 24 * 3600

    /// Reports written this session, by id; kept ones are read from disk through `report(id:)`.
    private(set) var written: [String: PeriodReport] = [:]
    /// Due on this open, with numbers to write about, and not written yet. In memory only: the next open works it out
    /// again.
    private(set) var pending: Set<String> = []
    private(set) var writing: Set<String> = []
    private(set) var failures: [String: Failure] = [:]
    @ObservationIgnored let calendar: Calendar

    /// What was read from disk, so a view can ask on every update. A miss is kept only when there is no file: one
    /// that can't be read yet (the phone locked) is read again next time.
    @ObservationIgnored private var read: [String: PeriodReport?] = [:]
    @ObservationIgnored private let store: PeriodReportStore
    @ObservationIgnored private let service: (any PeriodReportService)?
    @ObservationIgnored private let records: DayRecordStore
    @ObservationIgnored private let archive: HealthArchive
    @ObservationIgnored private let locale: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let hasConsent: @MainActor () -> Bool
    @ObservationIgnored private var running: Task<Void, Never>?
    /// Bumped by `stop()`: a write or an open that started before it sends nothing more and keeps nothing.
    @ObservationIgnored private var generation = 0

    init(
        store: PeriodReportStore, service: (any PeriodReportService)?, records: DayRecordStore, archive: HealthArchive,
        calendar: Calendar, locale: String, now: @escaping @Sendable () -> Date,
        hasConsent: @escaping @MainActor () -> Bool
    ) {
        self.store = store
        self.service = service
        self.records = records
        self.archive = archive
        self.calendar = calendar
        self.locale = locale
        self.now = now
        self.hasConsent = hasConsent
    }

    private var today: Date { calendar.startOfDay(for: now()) }

    /// The report kept for a period id, if any; a file that can't be read is none.
    func report(id: String) -> PeriodReport? {
        if let report = written[id] { return report }
        if let cached = read[id] { return cached }
        let report = store.read(id: id)
        if report != nil || !store.hasFile(id: id) { read[id] = .some(report) }
        return report
    }

    /// A report is kept for the id, even one that can't be read right now: never written again by itself.
    private func isKept(id: String) -> Bool { report(id: id) != nil || store.hasFile(id: id) }

    /// A kept report shows even while it is written again.
    func state(for period: Period) -> State {
        guard let id = period.reportID(calendar: calendar) else { return .missing }
        if let report = report(id: id) { return .ready(report) }
        if writing.contains(id) { return .writing }
        if pending.contains(id) { return .pending }
        return .missing
    }

    func failure(for period: Period) -> Failure? { period.reportID(calendar: calendar).flatMap { failures[$0] } }

    func isWriting(_ period: Period) -> Bool { period.reportID(calendar: calendar).map(writing.contains) ?? false }

    /// The newest report kept in the last two days among the last finished periods: the home's line (spec §3.1).
    func fresh() -> (period: Period, report: PeriodReport)? {
        let now = now()
        return PeriodReportSchedule.lastFinished(today: today, calendar: calendar)
            .compactMap { p in p.reportID(calendar: calendar).flatMap(report(id:)).map { (period: p, report: $0) } }
            .filter { $0.report.generatedAt <= now && now.timeIntervalSince($0.report.generatedAt) < Self.freshFor }
            .max { $0.report.generatedAt < $1.report.generatedAt }
    }

    /// Writes what is due. One run at a time: an open while one runs waits for it instead of asking again.
    func writeDue() async {
        if let running { return await running.value }
        let task = Task { await runDue() }
        running = task
        await task.value
        if running == task { running = nil }
    }

    private func runDue() async {
        guard service != nil, hasConsent() else { return }
        let mine = generation
        let today = self.today
        let due = PeriodReportSchedule.due(today: today, calendar: calendar) { isKept(id: $0) }
        guard let first = due.map(\.start).min(), let end = due.map(\.end).max(),
            let known = try? await records.records(
                from: first, through: calendar.date(byAdding: .day, value: -1, to: end)!)
        else { return }
        guard generation == mine, !Task.isCancelled else { return }
        // A period with no numbers has nothing to write about: it neither waits nor costs a call.
        let days = Array(known.values)
        let withData = due.filter {
            TrendMath.aggregate(days, in: $0, today: today, calendar: calendar).daysWithData > 0
        }
        pending.formUnion(withData.compactMap { $0.reportID(calendar: calendar) })
        var calls = 0
        for period in withData where calls < PeriodReportSchedule.perOpen {
            // Consent taken back or the archive cleared meanwhile: this open is over, a new one counts its own.
            guard generation == mine, !Task.isCancelled else { return }
            switch await write(period) {
            case .written: calls += 1
            case .empty: continue
            case .failed: return
            }
        }
    }

    /// Writes one period's report now: an open's due period, the page's Write again, the card's Write now. An
    /// earlier report stays on screen and on disk until the new one is in.
    @discardableResult
    func write(_ period: Period) async -> Outcome {
        guard let service, hasConsent(), let id = period.reportID(calendar: calendar),
            let span = PeriodReport.Span(period, calendar: calendar), !writing.contains(id)
        else { return .failed }
        let mine = generation
        writing.insert(id)
        // The last try's failure no longer stands while this one writes.
        failures[id] = nil
        // After `stop()` the id may be a newer write's.
        defer { if generation == mine { writing.remove(id) } }
        var hasData = false
        do {
            let before = period.previous(calendar: calendar)
            let lastDay = calendar.date(byAdding: .day, value: -1, to: period.end)!
            let days = Array(try await records.records(from: before.start, through: lastDay).values)
            let (archive, calendar, locale, today) = (archive, calendar, locale, today)
            let request = await Task.detached(priority: .utility) {
                PeriodReportInput.request(
                    period: period, records: days, archive: archive, calendar: calendar, locale: locale, today: today)
            }.value
            // Consent taken back (or the archive cleared) while the days were read: nothing is sent.
            guard generation == mine, hasConsent() else { return .failed }
            guard let request else {
                pending.remove(id)
                return .empty
            }
            hasData = true
            let reply = try await service.report(for: request)
            // Consent taken back (or the archive cleared) while it was written: it is not kept.
            guard generation == mine, hasConsent() else { return .failed }
            let report = PeriodReport(
                reply, period: span, generatedAt: now(), current: request.current, previous: request.previous)
            try store.write(report, id: id)
            written[id] = report
            pending.remove(id)
            failures[id] = nil
            return .written
        } catch {
            guard generation == mine else { return .failed }
            failures[id] = Self.failure(for: error)
            // A kept report stays as it is; a due one never written, with numbers, waits for the next open.
            if hasData, !isKept(id: id),
                PeriodReportSchedule.lastFinished(today: today, calendar: calendar).contains(period)
            {
                pending.insert(id)
            }
            return .failed
        }
    }

    /// Consent taken back: nothing is written or waits any more. Kept reports stay readable, like kept notes.
    func stop() {
        generation += 1
        running?.cancel()
        running = nil
        pending = []
        writing = []
        failures = [:]
    }

    /// The archive was cleared, reports with it.
    func forget() {
        stop()
        written = [:]
        read = [:]
    }

    static func failure(for error: Error) -> Failure {
        switch HealthHomeModel.reportState(for: error) {
        case .offline: .offline
        case .needsModel: .needsModel
        default: .failed
        }
    }
}
