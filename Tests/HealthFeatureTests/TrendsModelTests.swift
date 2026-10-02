// Tests/HealthFeatureTests/TrendsModelTests.swift
import Foundation
import Models
import SwiftUI
import Testing

@testable import HealthFeature

@MainActor
struct TrendsModelTests {
    let cal = TestClock.calendar
    let source = FakeHealthSource()
    let archive = HealthArchive(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: TestClock.today)! }

    func model(_ scope: TrendScope = .month, anchor: Date = TestClock.now) -> TrendsModel {
        let store = DayRecordStore(
            builder: SnapshotBuilder(source: source, calendar: cal), calendar: cal, now: { TestClock.now })
        return TrendsModel(
            route: TrendsRoute(scope: scope, anchor: anchor), store: store, archive: archive, calendar: cal,
            locale: "en", now: { TestClock.now })
    }

    /// 1,000 steps every day for ten weeks.
    func steps() async {
        let values = (0..<70).map { DayValue(day: day(-$0), value: 1000) }
        await source.set { $0.sums[.steps] = values }
    }

    @Test func opensOnThePeriodHoldingTheAnchor() {
        let m = model(.month)
        #expect(m.period == Period.containing(TestClock.now, .month, calendar: cal))
        #expect(model(.week).title == "Week 40")
    }

    @Test func aRouteFromTheFutureOpensOnToday() {
        #expect(model(.week, anchor: day(30)).period == Period.containing(TestClock.now, .week, calendar: cal))
    }

    @Test func theCurrentPeriodIsTheLastOne() {
        let m = model(.week)
        #expect(!m.canGoForward)
        m.showNext()
        #expect(m.period == Period.containing(TestClock.now, .week, calendar: cal))
        m.showPrevious()
        #expect(m.canGoForward)
        #expect(m.period.start == day(-10))
    }

    @Test func loadingReadsThePeriodAndTheOneBefore() async {
        await steps()
        let m = model(.week)
        await m.load()
        #expect(m.phase == .ready)
        #expect(m.current?.steps.days == 4)
        #expect(m.previous?.steps.days == 7)
        #expect(m.current?.steps.average == 1000)
        #expect(m.cells.count == 7)
        #expect(m.cells.filter(\.isFuture).count == 3)
        #expect(m.cells.first { $0.isToday }?.day == TestClock.today)
    }

    @Test func aMonthGridOpensWithBlanksUpToItsFirstWeekday() {
        let m = model(.month)  // October 2026 starts on a Thursday
        #expect(m.cells.prefix(3).allSatisfy { $0.day == nil })
        #expect(m.cells[3].day == TestClock.today)
        #expect(m.cells.compactMap(\.day).count == 31)
        #expect(Set(m.cells.map(\.id)).count == m.cells.count)
    }

    @Test func switchingScopeStaysWhereTheUserIsLooking() {
        let m = model(.month)
        m.select(.week)
        #expect(m.period == Period.containing(TestClock.now, .week, calendar: cal))
        m.select(.month)
        m.showPrevious()
        m.select(.week)
        #expect(m.period.start == TestClock.date(2026, 8, 31))
    }

    @Test func aMonthOpensFromTheYear() {
        let m = model(.year)
        let bars = m.months
        #expect(bars.count == 12)
        #expect(bars.filter(\.isFuture).count == 2)
        m.open(month: bars[8].month)
        #expect(m.scope == .month)
        #expect(m.period.start == TestClock.date(2026, 9, 1))
    }

    /// Paging faster than Apple Health answers never lands an older period's numbers under a newer title.
    @Test func aSlowerOlderLoadNeverOverwritesANewerOne() async {
        await steps()
        let m = model(.week)
        await m.load()
        #expect(m.current?.steps.days == 4)
        await source.set { $0.gated = true }
        let first = Task { await m.load() }
        // The older load is provably in flight: its read is held in the fake.
        while await !source.holding { await Task.yield() }
        // A load in flight shows no numbers, so the last ones never sit under a new title.
        #expect(m.current == nil)
        await source.set { $0.gated = false }
        m.showPrevious()
        await m.load()
        #expect(m.current?.steps.days == 7)
        await source.release()
        await first.value
        #expect(m.period.start == day(-10))
        #expect(m.current?.steps.days == 7)
        #expect(m.phase == .ready)
    }

    @Test func aFailedReadSaysSo() async {
        await source.set { $0.failure = URLError(.unknown) }
        let m = model(.week)
        await m.load()
        #expect(m.phase == .failed)
    }

    @Test func aDaysNoteComesFromTheArchive() throws {
        try archive.write(HealthArchiveTests.entry("2026-09-30"))
        let m = model()
        #expect(m.archived(day(-1))?.summary.headline == "h")
        #expect(m.archived(day(-2)) == nil)
    }
}

struct TrendTextTests {
    @Test func deltasSayWhichWayAndHowMuch() {
        #expect(TrendText.delta(nil, metric: .sleep) == "—")
        #expect(TrendText.delta(TrendMath.change(100, from: 99), metric: .steps) == "→")
        #expect(
            TrendText.delta(TrendMath.change(8000, from: 10000), metric: .steps)
                == "↓ " + (0.2).formatted(.percent.precision(.fractionLength(0))))
        #expect(TrendText.delta(TrendMath.change(460, from: 408), metric: .sleep) == "↑ " + TrendText.duration(52))
    }

    @Test func spokenChangesUseWords() {
        let up = TrendText.spoken(metric: .sleep, value: 460, change: TrendMath.change(460, from: 408), scope: .week)
        #expect(up.contains("Up " + TrendText.duration(52)))
        #expect(up.contains("vs last week"))
        let none = TrendText.spoken(metric: .hrv, value: nil, change: nil, scope: .month)
        #expect(none.contains("Nothing earlier to compare"))
    }

    @Test func weekdaysStartOnMonday() {
        var c = TestClock.calendar
        c.firstWeekday = 1
        c.locale = .current
        #expect(TrendText.weekdayInitials(calendar: c).count == 7)
        #expect(TrendText.weekdayInitials(calendar: c).first == c.veryShortStandaloneWeekdaySymbols[1])
    }
}
