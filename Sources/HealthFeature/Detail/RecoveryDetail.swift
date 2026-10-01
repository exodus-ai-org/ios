// Sources/HealthFeature/Detail/RecoveryDetail.swift
import Charts
import Models
import OdyKit
import SwiftUI

/// HRV and resting heart rate over a month, each against a band around the user's own normal, and the breathing rate.
struct RecoveryDetail: View {
    let data: HealthHistoryData
    let snapshot: HealthSnapshot.Recovery?
    @ScaledMetric(relativeTo: .body) private var chartHeight = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !data.hrv.isEmpty {
                chart("ios:health.recovery.hrv", data.hrv, value: Self.ms, baseline: snapshot?.hrvBaselineMs, color: OdyPalette.hex(0xF0567A))
            }
            if !data.restingHr.isEmpty {
                chart(
                    "ios:health.recovery.restingHr", data.restingHr, value: Self.bpm, baseline: snapshot?.restingHrBaseline,
                    color: OdyPalette.hex(0xE5392E))
            }
            if let resp = snapshot?.respRate ?? data.respRate.last?.value {
                DetailSection("ios:health.recovery.respRate") {
                    HStack(alignment: .center, spacing: 12) {
                        Text(verbatim: Self.perMinute(resp))
                            .font(.title2.weight(.heavy).monospacedDigit())
                        if data.respRate.count > 1 {
                            Chart(data.respRate) { p in
                                LineMark(x: .value("day", p.day, unit: .day), y: .value("breaths", p.value))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(OdyPalette.hex(0x4FA3C9))
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 36)
                            .accessibilityHidden(true)
                        }
                    }
                }
            }
            Text("ios:health.recovery.disclaimer")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func chart(_ title: LocalizedStringResource, _ points: [DayPoint], value: (Double) -> String, baseline: Double?, color: Color)
        -> some View
    {
        DetailSection(title) {
            if let last = points.last {
                Text(verbatim: value(last.value))
                    .font(.title2.weight(.heavy).monospacedDigit())
            }
            Chart {
                if let baseline, let first = points.first?.day, let last = points.last?.day {
                    RectangleMark(
                        xStart: .value("from", first), xEnd: .value("to", last),
                        yStart: .value("low", baseline * 0.95), yEnd: .value("high", baseline * 1.05))
                    .foregroundStyle(color.opacity(0.14))
                    RuleMark(y: .value("usual", baseline))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(color.opacity(0.5))
                }
                ForEach(points) { p in
                    LineMark(x: .value("day", p.day), y: .value("value", p.value))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(color)
                }
                if let last = points.last {
                    PointMark(x: .value("day", last.day), y: .value("value", last.value))
                        .symbolSize(60)
                        .foregroundStyle(color)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .frame(height: chartHeight)
        }
    }

    static func ms(_ v: Double) -> String {
        Measurement(value: v.rounded(), unit: UnitDuration.milliseconds)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func bpm(_ v: Double) -> String {
        let n = Int(v.rounded())
        return String(localized: "ios:health.value.bpm", defaultValue: "\(n) bpm", comment: "Card value: resting heart rate.")
    }

    static func perMinute(_ v: Double) -> String {
        let n = v.formatted(.number.precision(.fractionLength(1)))
        return String(
            localized: "ios:health.unit.breathsPerMin", defaultValue: "\(n) /min", comment: "Breaths per minute; the number is pre-formatted.")
    }
}
