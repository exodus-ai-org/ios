// Sources/HealthFeature/Trends/PeriodReportCard.swift
import OdyKit
import SwiftUI

/// The shown period's report on the calendar (spec §3.2), between the three numbers and the days: its headline,
/// opening the report; while it is written, Ody writing; for a finished period that has numbers but still waits for
/// the computer, when it will be written, and Write now.
struct PeriodReportCard: View {
    let state: PeriodReports.State
    let period: Period
    /// The period has numbers: one with nothing recorded has nothing to wait for.
    let hasData: Bool
    let canWrite: Bool
    let onWrite: () -> Void

    static func shows(_ state: PeriodReports.State, hasData: Bool) -> Bool {
        switch state {
        case .ready, .writing: true
        case .pending: hasData
        case .missing: false
        }
    }

    var body: some View {
        if Self.shows(state, hasData: hasData) {
            switch state {
            case .ready(let report):
                NavigationLink(value: PeriodReportRoute(period: period)) { headline(report) }
                    .buttonStyle(.plain)
            case .writing:
                card { PeriodReportRow(scene: .writing, text: Text("ios:health.periodReport.writing")) }
            default:
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        PeriodReportRow(scene: .offline, text: Text("ios:health.periodReport.pending"))
                        if canWrite {
                            Button(action: onWrite) {
                                Text("ios:health.periodReport.writeNow").foregroundStyle(ReportInk.amber)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(OdyPalette.marigold)
                        }
                    }
                }
            }
        }
    }

    private func headline(_ report: PeriodReport) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(PeriodReportText.kind(report.period.kind))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(ReportInk.green)
                Text(verbatim: report.headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("ios:health.periodReport.openHint"))
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }
}

/// The home's line under This week when a report was written in the last two days (spec §3.1).
struct ReportReadyLine: View {
    let period: Period
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill").foregroundStyle(ReportInk.green).accessibilityHidden(true)
            Text(verbatim: PeriodReportText.ready(TrendText.title(period, calendar: calendar)))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("ios:health.periodReport.openHint"))
    }
}
