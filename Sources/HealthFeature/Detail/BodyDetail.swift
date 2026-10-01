// Sources/HealthFeature/Detail/BodyDetail.swift
import Charts
import Models
import OdyKit
import SwiftUI

/// Today's water as a glass you tap to log a cup, a month of weight, and the week's moods.
struct BodyDetail: View {
    let data: HealthHistoryData
    let cups: Int
    let onLogWater: () -> Void
    @ScaledMetric(relativeTo: .body) private var weightHeight = 150
    @ScaledMetric(relativeTo: .body) private var moodHeight = 120
    @ScaledMetric(relativeTo: .body) private var glassHeight = 120

    private static let teal = OdyPalette.hex(0x2A9BA6)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            water
            if !data.weights.isEmpty {
                DetailSection("ios:health.body.weight") {
                    if let last = data.weights.last {
                        Text(verbatim: Measurement(value: last.value, unit: UnitMass.kilograms)
                            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))))
                            .font(.title2.weight(.heavy).monospacedDigit())
                    }
                    Chart(data.weights) { p in
                        LineMark(x: .value("day", p.day, unit: .day), y: .value("kg", p.value))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .foregroundStyle(Self.teal)
                        PointMark(x: .value("day", p.day, unit: .day), y: .value("kg", p.value))
                            .symbolSize(24)
                            .foregroundStyle(Self.teal)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .frame(height: weightHeight)
                }
            }
            if !data.moods.isEmpty {
                DetailSection("ios:health.body.mood") { moods }
            }
        }
    }

    /// The glass is white, so it sits on the card's own colour rather than the page.
    private var water: some View {
        let style = CategoryStyle.of(.body)
        return VStack(alignment: .leading, spacing: 10) {
            Text("ios:health.body.water").font(.headline).accessibilityAddTraits(.isHeader)
            HStack(alignment: .bottom, spacing: 18) {
                WaterGlassView(cups: cups, goal: 8, onLog: onLogWater).frame(height: glassHeight)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: CategoryValue.cups(cups))
                        .font(.title.weight(.heavy).monospacedDigit())
                        .contentTransition(.numericText(value: Double(cups)))
                        .animation(.snappy, value: cups)
                    Text("ios:health.body.tapToLog").font(.footnote).opacity(0.8)
                }
                .padding(.bottom, 4)
            }
        }
        .foregroundStyle(style.ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: style.gradient, startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 18))
    }

    /// Valence from -3 (very unpleasant) to 3 (very pleasant), with a sun and a cloud for the ends instead of words.
    private var moods: some View {
        Chart(data.moods, id: \.date) { m in
            PointMark(x: .value("day", m.date, unit: .day), y: .value("mood", Self.valence(m.label)))
                .symbolSize(90)
                .foregroundStyle(m.label.isPleasant ? OdyPalette.hex(0x4FAF5F) : m.label == .neutral ? .gray : OdyPalette.hex(0xF0567A))
        }
        .chartYScale(domain: -3.5...3.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [-3, 0, 3]) { value in
                AxisGridLine()
                AxisValueLabel {
                    switch value.as(Int.self) {
                    case 3: Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                    case -3: Image(systemName: "cloud.rain.fill").foregroundStyle(.secondary)
                    default: Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .frame(height: moodHeight)
    }

    static func valence(_ label: MoodLabel) -> Int {
        switch label {
        case .veryUnpleasant: -3
        case .unpleasant: -2
        case .slightlyUnpleasant: -1
        case .neutral: 0
        case .slightlyPleasant: 1
        case .pleasant: 2
        case .veryPleasant: 3
        }
    }
}
