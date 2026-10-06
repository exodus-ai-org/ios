// Sources/HealthFeature/Trends/WeekCard.swift
import SwiftUI

/// This week on the home (spec §3.1): seven style-C days, Monday first, and average sleep and daily steps against
/// last week. It opens the calendar on this week; the home draws the card around it, with a fresh report's line under
/// it when there is one.
struct WeekCard: View {
    let week: WeekGlance
    let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ios:health.week.title").font(.headline)
                Spacer()
                HStack(spacing: 2) {
                    Text("ios:health.calendar.title")
                    Image(systemName: "chevron.right")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                ForEach(week.cells) { cell in DayCellView(cell: cell, style: .compact, calendar: calendar) }
            }
            .accessibilityHidden(true)
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
            layout {
                stat(.sleep)
                stat(.steps)
            }
        }
        .padding(14)
        .contentShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("ios:health.calendar.title"))
    }

    private func stat(_ metric: TrendMetric) -> some View {
        let value = metric.value(week.current)
        let change = TrendMath.change(value, from: metric.value(week.previous))
        return VStack(alignment: .leading, spacing: 2) {
            Text(metric.title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: value.map(metric.format) ?? "—").font(.title3.weight(.heavy)).monospacedDigit()
                Text(verbatim: TrendText.delta(change, metric: metric))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrendText.color(change))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TrendText.spoken(metric: metric, value: value, change: change, scope: .week)))
    }
}
