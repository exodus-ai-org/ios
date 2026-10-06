// Sources/HealthFeature/Trends/TrendsView.swift
import Models
import OdyKit
import SwiftUI

/// A day the calendar opened a sheet for.
struct PresentedDay: Identifiable, Equatable {
    let day: Date
    var id: Date { day }
}

/// The calendar (spec §3.2): Week · Month · Quarter · Year, paged with ‹ ›; average sleep, daily steps and HRV
/// against the period before; the days as style-C cells, or for a quarter or a year a bar per month. A day opens its
/// sheet, a month bar opens that month. Each page turn slides in from its side (a cross-fade under Reduce Motion) with
/// a selection tick. Under the numbers, the period's report (or when it will be written).
struct TrendsView: View {
    @State private var trends: TrendsModel
    @State private var presented: PresentedDay?
    /// Which way the last page turned, so the new one comes in from that side.
    @State private var forward = true
    /// Bumped when Write now brought a report: the success tap.
    @State private var reportsWritten = 0
    private let home: HealthHomeModel
    let onAsk: (String) -> Void
    /// The workspace's ("Health"): a screenshot of this page is "Health · October 2026".
    @Environment(\.screenTitle) private var enclosingTitle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(route: TrendsRoute, home: HealthHomeModel, onAsk: @escaping (String) -> Void) {
        _trends = State(initialValue: home.trends(route))
        self.home = home
        _presented = State(initialValue: route.presentedDay.map { PresentedDay(day: home.calendar.startOfDay(for: $0)) })
        self.onAsk = onAsk
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker(selection: scope) {
                    ForEach(TrendScope.allCases, id: \.self) { s in Text(s.label).tag(s) }
                } label: {
                    Text("ios:health.calendar.scope")
                }
                .pickerStyle(.segmented)
                periodRow
                TrendStatsHeader(scope: trends.scope, current: trends.current, previous: trends.previous)
                    .redacted(reason: trends.current == nil ? .placeholder : [])
                PeriodReportCard(
                    state: home.reports.state(for: trends.period), period: trends.period,
                    hasData: (trends.current?.daysWithData ?? 0) > 0, canWrite: home.hasConsent, onWrite: writeReport)
                // One slot for the old page and the new, so they cross rather than stack.
                ZStack(alignment: .top) {
                    Group {
                        if trends.phase == .failed, trends.records.isEmpty {
                            failedNote
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                if trends.phase == .ready, trends.current?.daysWithData == 0 {
                                    note(Text("ios:health.calendar.empty"))
                                }
                                periodBody
                            }
                        }
                    }
                    .id(trends.period)
                    .transition(pageTransition)
                }
                legend
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(HealthSurface.page)
        .navigationTitle(Text("ios:health.calendar.title"))
        .navigationBarTitleDisplayMode(.inline)
        .screenTitle(ScreenTitles.join(enclosingTitle, trends.title))
        .sensoryFeedback(.selection, trigger: trends.period)
        .sensoryFeedback(.success, trigger: reportsWritten)
        .task(id: trends.period) { await trends.load() }
        .sheet(item: $presented) { p in
            DaySheet(
                day: p.day, record: trends.records[p.day], archived: trends.archived(p.day), healthTitle: enclosingTitle,
                calendar: trends.calendar,
                loadSnapshot: { await trends.snapshot(for: p.day) }, fallback: trends.minimalSnapshot(for: p.day),
                onAsk: onAsk)
        }
    }

    // MARK: Paging

    private var motion: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35) }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity), removal: .opacity)
    }

    private var scope: Binding<TrendScope> {
        Binding(
            get: { trends.scope },
            set: { s in
                forward = true
                withAnimation(motion) { trends.select(s) }
            })
    }

    private func turn(forward: Bool) {
        self.forward = forward
        withAnimation(motion) {
            if forward { trends.showNext() } else { trends.showPrevious() }
        }
    }

    private var periodRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: trends.title).font(.title3.weight(.bold))
                if trends.scope == .week {
                    Text(verbatim: TrendText.range(trends.period, calendar: trends.calendar))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { turn(forward: false) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("ios:health.calendar.previous"))
            Button { turn(forward: true) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("ios:health.calendar.next"))
            .disabled(!trends.canGoForward)
        }
        .tint(.primary)
    }

    // MARK: The period

    @ViewBuilder
    private var periodBody: some View {
        switch trends.scope {
        case .week: weekDays
        case .month: monthGrid
        case .quarter, .year:
            MonthBarsView(bars: trends.months, calendar: trends.calendar) { month in
                forward = true
                withAnimation(motion) { trends.open(month: month) }
            }
        }
    }

    @ViewBuilder
    private var weekDays: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                ForEach(trends.cells) { cell in
                    DayCellButton(cell: cell, style: .row, calendar: trends.calendar, onOpen: open)
                }
            }
        } else {
            HStack(spacing: 6) {
                ForEach(trends.cells) { cell in
                    DayCellButton(cell: cell, style: .large, calendar: trends.calendar, onOpen: open)
                }
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(Array(TrendText.weekdayInitials(calendar: trends.calendar).enumerated()), id: \.offset) { _, s in
                Text(verbatim: s)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .accessibilityHidden(true)
            }
            ForEach(trends.cells) { cell in
                DayCellButton(cell: cell, style: .compact, calendar: trends.calendar, onOpen: open)
            }
        }
    }

    private func open(_ day: Date) { presented = PresentedDay(day: day) }

    /// The card's Write now, for the period on screen when it was tapped.
    private func writeReport() {
        let period = trends.period
        Task { if await home.reports.write(period) == .written { reportsWritten += 1 } }
    }

    // MARK: Around it

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { legendItems }
            VStack(alignment: .leading, spacing: 6) { legendItems }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var legendItems: some View {
        ForEach([DayTone.good, .tired, .recovering], id: \.self) { tone in
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(tone.fill).frame(width: 10, height: 10)
                Text(tone.name)
            }
        }
        HStack(spacing: 4) {
            CornerRing(sleep: 0.75, steps: 0.5, lineWidth: 1.6).frame(width: 12, height: 12)
            Text("ios:health.calendar.legend.ring")
        }
    }

    private func note(_ text: Text) -> some View {
        text.font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }

    private var failedNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(HealthDetailView.failedText).font(.subheadline).foregroundStyle(.secondary)
            Button { Task { await trends.load() } } label: {
                Text(HealthDetailView.retryText).foregroundStyle(ReportInk.amber)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(OdyPalette.marigold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }
}
