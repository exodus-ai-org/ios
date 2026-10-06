// Sources/HealthFeature/Trends/PeriodReportView.swift
import Models
import OdyKit
import SwiftUI

/// Where a period report opens.
public struct PeriodReportRoute: Hashable, Sendable {
    public let period: Period

    public init(period: Period) { self.period = period }
}

/// A period's report (spec §3.4), told like the daily note: the kind of report as the eyebrow over the coloured
/// headline, the insight cards, how each number moved against the period before, then the small idea. Write again
/// rewrites it (the earlier one stays until the new one is in); the ask box sends the period's numbers with the
/// question.
struct PeriodReportView: View {
    let period: Period
    let home: HealthHomeModel
    let onAsk: (String) -> Void
    /// Bumped when Write again (or Write now) brought a report: the success tap.
    @State private var rewritten = 0
    /// The workspace's ("Health"): a screenshot of this page is "Health · September 2026".
    @Environment(\.screenTitle) private var enclosingTitle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reports: PeriodReports { home.reports }
    private var title: String { TrendText.title(period, calendar: home.calendar) }

    var body: some View {
        let state = reports.state(for: period)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch state {
                case .ready(let report):
                    page(report)
                case .writing:
                    card { PeriodReportRow(scene: .writing, text: Text("ios:health.periodReport.writing")) }
                case .pending:
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            PeriodReportRow(scene: .offline, text: Text("ios:health.periodReport.pending"))
                            writeNow
                        }
                    }
                case .missing:
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ios:health.periodReport.none").font(.subheadline).foregroundStyle(.secondary)
                            writeNow
                        }
                    }
                }
                if let failure = reports.failure(for: period) {
                    Text(PeriodReportText.failure(failure))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(reduceMotion ? nil : .smooth, value: state)
        }
        .background(HealthSurface.page)
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .screenTitle(ScreenTitles.join(enclosingTitle, title))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if reports.isWriting(period) {
                    ProgressView()
                } else if case .ready = state, home.hasConsent {
                    Button(action: write) {
                        Label {
                            Text("ios:health.periodReport.writeAgain")
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if case .ready(let report) = state {
                AskComposer(
                    suggestions: [
                        LocalizedStringResource("ios:health.periodReport.ask.changed", defaultValue: "What changed most in this period?", comment: "Report page suggestion chip: ask what changed most in the period."),
                        LocalizedStringResource("ios:health.periodReport.ask.next", defaultValue: "What should I focus on next?", comment: "Report page suggestion chip: ask what to focus on next."),
                    ],
                    attachment: { Self.attachment(report) },
                    placeholder: LocalizedStringResource(
                        "ios:health.periodReport.ask.placeholder", defaultValue: "Ask about this report…",
                        comment: "Report page ask box placeholder."),
                    onSend: onAsk)
            }
        }
        .sensoryFeedback(.success, trigger: rewritten)
    }

    /// The stories, the comparisons, the idea, then when it was written (and how many days it had).
    @ViewBuilder
    private func page(_ report: PeriodReport) -> some View {
        let eyebrow = Text(PeriodReportText.kind(report.period.kind))
        if let story = ReportStory(Self.story(report), eyebrow: eyebrow) {
            story
        } else {
            // Its insights all fell away: the report is its headline.
            VStack(alignment: .leading, spacing: 6) {
                eyebrow.font(.footnote.weight(.bold)).foregroundStyle(ReportInk.green)
                Text(verbatim: report.headline)
                    .font(.title2.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        ComparisonsCard(comparisons: report.comparisons, scope: PeriodReportText.scope(report.period.kind))
        if let nudge = report.nudge, !nudge.isEmpty { NudgeCard(text: nudge) }
        VStack(alignment: .leading, spacing: 4) {
            if report.current.daysWithData < report.current.elapsedDays {
                Text(verbatim: PeriodReportText.daysWithData(report.current.daysWithData, of: report.current.elapsedDays))
            }
            Text(verbatim: PeriodReportText.written(report.generatedAt, calendar: home.calendar))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var writeNow: some View {
        if home.hasConsent {
            Button(action: write) { Text("ios:health.periodReport.writeNow").foregroundStyle(ReportInk.amber) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(OdyPalette.marigold)
        }
    }

    private func write() {
        Task { if await reports.write(period) == .written { rewritten += 1 } }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }

    /// The report as the daily note's stories, without its idea: here that comes after the comparisons.
    static func story(_ report: PeriodReport) -> HealthSummary {
        var story = report.story
        story.nudge = nil
        return story
    }

    /// What a question about the report carries: the period, its numbers and the period before's, and what the report
    /// said. Chat's card shows it as "Health" (it is not a day).
    static func attachment(_ report: PeriodReport) -> String? {
        let ask = Ask(
            period: report.period, current: report.current, previous: report.previous, headline: report.headline,
            insights: report.insights.map(\.title))
        guard let data = try? HealthWire.encoder().encode(ask) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private struct Ask: Encodable {
        let period: PeriodReport.Span
        let current: Aggregates
        let previous: Aggregates?
        let headline: String
        let insights: [String]
    }
}

/// Ody beside a line: a report being written, or waiting for the computer.
struct PeriodReportRow: View {
    let scene: OdyScene
    let text: Text
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            OdySceneView(scene)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 14))
                .accessibilityHidden(true)
            text.font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
