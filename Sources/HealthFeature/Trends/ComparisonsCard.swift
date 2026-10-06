// Sources/HealthFeature/Trends/ComparisonsCard.swift
import SwiftUI

/// How each number moved against the period before, as the report put it: the metric's glyph and name, the arrow in
/// the colour of better or worse (down is better for the resting heart rate), the number now and what it was. One
/// under another at accessibility sizes; nothing at all when there is nothing to compare.
struct ComparisonsCard: View {
    let comparisons: [PeriodReport.Comparison]
    let scope: TrendScope
    @Environment(\.dynamicTypeSize) private var typeSize
    /// One column for every glyph, as the day sheet's rows.
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 26

    /// The comparisons this app can name, in the report's order.
    static func rows(_ comparisons: [PeriodReport.Comparison]) -> [(PeriodReport.Comparison, PeriodReportText.Metric)] {
        comparisons.compactMap { c in PeriodReportText.metric(c.metric).map { (c, $0) } }
    }

    var body: some View {
        let rows = Self.rows(comparisons)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(scope.versusLabel)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                    Divider()
                    row(item.0, item.1)
                }
            }
            .padding(.horizontal, 14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
        }
    }

    private func row(_ c: PeriodReport.Comparison, _ metric: PeriodReportText.Metric) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout =
            stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            Label {
                Text(metric.title)
            } icon: {
                Image(systemName: metric.symbol)
                    .font(.body.weight(.medium))
                    .imageScale(.small)
                    .foregroundStyle(CategoryStyle.of(metric.category).accent)
                    .frame(width: glyphWidth)
            }
            if !stacked { Spacer(minLength: 8) }
            VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: PeriodReportText.arrow(c.direction))
                        .font(.body.weight(.bold))
                        .foregroundStyle(PeriodReportText.color(metric: c.metric, direction: c.direction))
                    Text(verbatim: c.current).font(.body.weight(.semibold)).monospacedDigit()
                }
                if let previous = c.previous {
                    Text(verbatim: PeriodReportText.was(previous)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: PeriodReportText.spoken(c, title: metric.title)))
    }
}
