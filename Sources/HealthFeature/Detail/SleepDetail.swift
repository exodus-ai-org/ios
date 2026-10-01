// Sources/HealthFeature/Detail/SleepDetail.swift
import Charts
import OdyKit
import SwiftUI

/// Last night as a band of stages under the stars — slide a finger along it to light a stage — and thirty nights
/// against the usual.
struct SleepDetail: View {
    let data: HealthHistoryData
    let baseline: Int?
    @State private var selected: Date?
    @ScaledMetric(relativeTo: .body) private var bandHeight = 170
    @ScaledMetric(relativeTo: .body) private var monthHeight = 170

    private static let stages: [SleepStage] = [.awake, .rem, .core, .deep]

    private var selectedStage: SleepSample? {
        guard let selected else { return nil }
        return data.lastNight?.stages.first { $0.start <= selected && selected < $0.end }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let night = data.lastNight, !night.stages.isEmpty {
                DetailSection("ios:health.sleep.lastNight") { hypnogram(night) }
            }
            if !data.nights.isEmpty {
                DetailSection("ios:health.sleep.month") { month }
            }
        }
    }

    private func hypnogram(_ night: SleepNight) -> some View {
        let lit = selectedStage
        return VStack(alignment: .leading, spacing: 10) {
            Chart(night.stages, id: \.start) { s in
                RectangleMark(
                    xStart: .value("start", s.start), xEnd: .value("end", s.end),
                    y: .value("stage", Self.label(s.stage)), height: .ratio(0.7))
                .foregroundStyle(Self.color(s.stage).opacity(lit == nil || lit == s ? 1 : 0.3))
                .clipShape(.rect(cornerRadius: 3))
                if let selected {
                    RuleMark(x: .value("now", selected))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .chartXSelection(value: $selected)
            .chartXScale(domain: night.bedtime...night.wake)
            .chartYScale(domain: Self.stages.map(Self.label))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { _ in
                    AxisValueLabel(format: .dateTime.hour()).foregroundStyle(.white.opacity(0.75))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().foregroundStyle(.white.opacity(0.85))
                }
            }
            .chartPlotStyle { $0.background(alignment: .center) { StarField().opacity(0.8) } }
            .frame(height: bandHeight)
            .sensoryFeedback(.selection, trigger: lit?.start) { old, new in old != nil && new != nil }
            Group {
                if let s = lit {
                    Text(verbatim: "\(Self.label(s.stage)) · \(Self.span(s.start, s.end))")
                } else {
                    Text(verbatim: Self.span(night.bedtime, night.wake))
                }
            }
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.18), value: lit?.start)
        }
        .padding(12)
        .background(
            LinearGradient(colors: [OdyPalette.hex(0x1E1A4D), OdyPalette.hex(0x3D3480)], startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 14)
        )
        .environment(\.colorScheme, .dark)
    }

    private var month: some View {
        Chart {
            ForEach(data.nights) { p in
                BarMark(x: .value("day", p.day, unit: .day), y: .value("hours", p.value))
                    .foregroundStyle(OdyPalette.hex(0x8C7BD6))
                    .clipShape(.rect(cornerRadius: 2))
            }
            if let baseline {
                RuleMark(y: .value("usual", Double(baseline) / 60))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text(verbatim: Duration.seconds(baseline * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 4)
                            .background(HealthSurface.card, in: .capsule)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel { if let h = value.as(Double.self) { Text(verbatim: "\(Int(h)) h") } }
            }
        }
        .frame(height: monthHeight)
    }

    private static func span(_ a: Date, _ b: Date) -> String {
        "\(a.formatted(date: .omitted, time: .shortened))–\(b.formatted(date: .omitted, time: .shortened))"
    }

    static func label(_ s: SleepStage) -> String {
        switch s {
        case .deep: String(localized: "ios:health.stage.deep")
        case .core, .unspecified: String(localized: "ios:health.stage.core")
        case .rem: String(localized: "ios:health.stage.rem")
        case .awake: String(localized: "ios:health.stage.awake")
        }
    }

    static func color(_ s: SleepStage) -> Color {
        switch s {
        case .deep: OdyPalette.hex(0x7B6CF0)
        case .core, .unspecified: OdyPalette.hex(0xB9AEF0)
        case .rem: OdyPalette.hex(0x5EC8F2)
        case .awake: OdyPalette.hex(0xFFB3C1)
        }
    }
}

/// A few fixed stars behind the hypnogram, the same every time.
private struct StarField: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x5EED
            func next() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }
            for _ in 0..<36 {
                let r = 0.6 + next() * 1.1
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.25 + next() * 0.45)))
            }
        }
        .accessibilityHidden(true)
    }
}
