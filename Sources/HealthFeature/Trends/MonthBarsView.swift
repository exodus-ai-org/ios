// Sources/HealthFeature/Trends/MonthBarsView.swift
import SwiftUI

/// A quarter's or a year's months, a bar each: average sleep against the target, daily steps beside it. Tap a month
/// that has begun to open it.
struct MonthBarsView: View {
    let bars: [MonthBar]
    let calendar: Calendar
    let onOpen: (Period) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 6) {
            ForEach(bars) { bar in
                Button { onOpen(bar.month) } label: { row(bar) }
                    .buttonStyle(PressScale())
                    .disabled(bar.isFuture)
                    .accessibilityLabel(Text(verbatim: spoken(bar)))
            }
        }
    }

    private func row(_ bar: MonthBar) -> some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Text(verbatim: name(bar, width: .abbreviated))
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, alignment: .leading)
            sleepBar(bar.aggregates.sleepMin.average)
            Text(verbatim: values(bar)).font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HealthSurface.card, in: .rect(cornerRadius: 12))
        .opacity(bar.isFuture ? 0.45 : 1)
    }

    private func sleepBar(_ minutes: Double?) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(RingInk.sleep.opacity(0.18))
                Capsule()
                    .fill(RingInk.sleep)
                    .frame(width: g.size.width * min((minutes ?? 0) / Double(TrendMath.sleepTargetMin), 1))
            }
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
    }

    private func name(_ bar: MonthBar, width: Date.FormatStyle.Symbol.Month) -> String {
        bar.month.start.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(width))
    }

    /// "7h 12m · 8.1K", or "—" for a month with nothing in it.
    private func values(_ bar: MonthBar) -> String {
        let a = bar.aggregates
        let parts = [
            a.sleepMin.average.map(TrendText.duration), a.steps.average.map { TrendText.compact(Int($0.rounded())) },
        ].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func spoken(_ bar: MonthBar) -> String {
        let a = bar.aggregates
        var parts = [name(bar, width: .wide)]
        if let sleep = a.sleepMin.average {
            parts += [String(localized: TrendMetric.sleep.title), TrendText.duration(sleep)]
        }
        if let steps = a.steps.average {
            parts += [String(localized: TrendMetric.steps.title), TrendText.steps(steps)]
        }
        if parts.count == 1 { parts.append(String(localized: DayTone.empty.name)) }
        return parts.joined(separator: ", ")
    }
}
