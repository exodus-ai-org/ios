// Sources/HealthFeature/Detail/SleepDetail.swift
import Charts
import OdyKit
import SwiftUI

/// Last night as a hypnogram under the stars — slide a finger along it to light a stage — and thirty nights
/// against the usual.
struct SleepDetail: View {
    let data: HealthHistoryData
    let baseline: Int?
    @State private var selected: Date?
    @ScaledMetric(relativeTo: .body) private var bandHeight = 170
    @ScaledMetric(relativeTo: .body) private var monthHeight = 170

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
        let segments = Hypnogram.segments(night.stages)
        let lit = selected.flatMap { t in segments.first { $0.start <= t && t < $0.end } }
        return VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(Array(zip(segments, segments.dropFirst())), id: \.1.start) { a, b in
                    // Joins a stage to the next where one hands over to the other, so the night reads as one line.
                    if a.end == b.start {
                        RuleMark(x: .value("time", b.start), yStart: .value("from", Hypnogram.row(a.stage)), yEnd: .value("to", Hypnogram.row(b.stage)))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.white.opacity(lit == nil ? 0.35 : 0.15))
                            .accessibilityHidden(true)
                    }
                }
                ForEach(segments, id: \.start) { s in
                    let row = Double(Hypnogram.row(s.stage))
                    RectangleMark(
                        xStart: .value("start", s.start), xEnd: .value("end", s.end),
                        yStart: .value("stage", row - 0.26), yEnd: .value("stage", row + 0.26))
                    .foregroundStyle(Self.color(s.stage).opacity(lit == nil || lit == s ? 1 : 0.3))
                    .clipShape(.rect(cornerRadius: 3))
                    .accessibilityLabel(Text(verbatim: Self.label(s.stage)))
                    .accessibilityValue(Text(verbatim: Self.span(s.start, s.end)))
                }
                if let selected {
                    RuleMark(x: .value("now", selected))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .chartXSelection(value: $selected)
            .chartXScale(domain: night.bedtime...night.wake)
            .chartYScale(domain: -0.5...3.5)
            .chartXAxis {
                AxisMarks(values: Hypnogram.ticks(from: night.bedtime, to: night.wake)) { value in
                    AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(.white.opacity(0.4))
                    AxisValueLabel(collisionResolution: .greedy) {
                        if let t = value.as(Date.self) {
                            Text(t, format: .dateTime.hour())
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
            }
            // Stage names sit in their own column left of the plot, centred on their rows, never over a bar.
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 1, 2, 3]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(.white.opacity(0.18))
                    AxisValueLabel(horizontalSpacing: 8) {
                        if let row = value.as(Int.self), let stage = Hypnogram.stage(atRow: row) {
                            Text(verbatim: Self.label(stage))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Self.color(stage))
                        }
                    }
                }
            }
            .chartPlotStyle { $0.background(alignment: .center) { StarField().opacity(0.8) } }
            // Past this, stage names crowd the night out of the plot; the line below and VoiceOver carry the rest.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
                AxisValueLabel { if let h = value.as(Double.self) { Text(verbatim: Duration.seconds(h * 3600).formatted(.units(allowed: [.hours], width: .narrow))) } }
            }
        }
        .frame(height: monthHeight)
    }

    private static func span(_ a: Date, _ b: Date) -> String {
        "\(a.formatted(date: .omitted, time: .shortened))–\(b.formatted(date: .omitted, time: .shortened))"
    }

    static func label(_ s: SleepStage) -> String {
        switch s {
        case .deep: String(localized: "ios:health.stage.deep", defaultValue: "Deep sleep")
        case .core, .unspecified: String(localized: "ios:health.stage.core", defaultValue: "Core sleep")
        case .rem: String(localized: "ios:health.stage.rem", defaultValue: "REM")
        case .awake: String(localized: "ios:health.stage.awake", defaultValue: "Awake")
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

/// Last night as the hypnogram draws it. Watch data comes in many slivers; drawn as they are the night is confetti.
/// For display only (the night's minutes are the analyzer's): slivers under a minute go, the same stage either side
/// of a short break joins up, and a short break between two stages closes so they meet at a connector.
enum Hypnogram {
    struct Segment: Equatable {
        var start: Date
        var end: Date
        var stage: SleepStage
    }

    /// Shorter than this is not drawn.
    static let shortest: TimeInterval = 60
    /// A break shorter than this is no break.
    static let join: TimeInterval = 120

    static func segments(_ samples: [SleepSample]) -> [Segment] {
        var out: [Segment] = []
        for s in samples.sorted(by: { $0.start < $1.start }) where s.end.timeIntervalSince(s.start) >= shortest {
            let stage: SleepStage = s.stage == .unspecified ? .core : s.stage
            guard var last = out.last, s.start.timeIntervalSince(last.end) < join else {
                out.append(Segment(start: s.start, end: s.end, stage: stage))
                continue
            }
            if last.stage == stage {
                last.end = max(last.end, s.end)
                out[out.count - 1] = last
            } else if s.end > last.end {
                // Meets the one before: a gap closes, an overlap goes to the later stage.
                let start = max(s.start, last.start)
                last.end = start
                out[out.count - 1] = last
                if last.end <= last.start { out.removeLast() }
                out.append(Segment(start: start, end: s.end, stage: stage))
            }
        }
        return out
    }

    /// Top to bottom: awake, REM, core, deep (Health's order).
    static func row(_ stage: SleepStage) -> Int {
        switch stage {
        case .awake: 3
        case .rem: 2
        case .core, .unspecified: 1
        case .deep: 0
        }
    }

    static func stage(atRow row: Int) -> SleepStage? { rows.indices.contains(row) ? rows[row] : nil }

    private static let rows: [SleepStage] = [.deep, .core, .rem, .awake]

    /// Whole hours every two hours (three for a night over ten), on hours that divide by the step, so a phone's width
    /// holds every label.
    static func ticks(from start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        let step = end.timeIntervalSince(start) > 10 * 3600 ? 3 : 2
        guard var t = calendar.nextDate(after: start, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)
        else { return [] }
        if calendar.component(.minute, from: start) == 0, calendar.component(.second, from: start) == 0 { t = start }
        var out: [Date] = []
        while t <= end {
            if calendar.component(.hour, from: t) % step == 0 { out.append(t) }
            t = t.addingTimeInterval(3600)
        }
        return out
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
