// Sources/HealthFeature/Detail/ActivityDetail.swift
import Charts
import OdyKit
import SwiftUI

/// Today's steps by the hour, the week against the goal, and the week's workouts.
struct ActivityDetail: View {
    let data: HealthHistoryData
    let goal: Int
    @ScaledMetric(relativeTo: .body) private var todayHeight = 150
    @ScaledMetric(relativeTo: .body) private var weekHeight = 170

    /// Dark enough to read on the light card, light enough on the dark one.
    private static let bar = OdyPalette.hex(0xFF9A1A)
    private static let short = OdyPalette.hex(0xFFC23D, 0.55)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !data.hourlySteps.isEmpty {
                DetailSection("ios:health.activity.today") {
                    Chart(data.hourlySteps) { p in
                        BarMark(x: .value("hour", p.day, unit: .hour), y: .value("steps", p.value))
                            .foregroundStyle(OdyPalette.marigold)
                            .clipShape(.rect(cornerRadius: 2))
                    }
                    .chartXScale(domain: Self.dayRange(of: data.hourlySteps))
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .frame(height: todayHeight)
                }
            }
            if !data.dailySteps.isEmpty {
                DetailSection("ios:health.activity.week") {
                    Chart {
                        ForEach(data.dailySteps) { p in
                            BarMark(x: .value("day", p.day, unit: .day), y: .value("steps", p.value))
                                .foregroundStyle(p.value >= Double(goal) ? Self.bar : Self.short)
                                .clipShape(.rect(cornerRadius: 3))
                        }
                        RuleMark(y: .value("goal", goal))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                                Text(verbatim: goal.formatted()).font(.caption2.weight(.semibold)).foregroundStyle(Color.secondary)
                                    .padding(.horizontal, 4)
                                    .background(HealthSurface.card, in: .capsule)
                            }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .frame(height: weekHeight)
                }
            }
            if !data.workouts.isEmpty {
                DetailSection("ios:health.activity.workouts") {
                    ForEach(data.workouts.sorted { $0.start > $1.start }, id: \.start) { w in
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) { workoutName(w); Spacer(); workoutNumbers(w) }
                            VStack(alignment: .leading, spacing: 2) { workoutName(w); workoutNumbers(w) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func workoutName(_ w: WorkoutSample) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: w.type.capitalized).font(.subheadline.weight(.semibold))
            Text(w.start, format: .dateTime.weekday(.wide).hour().minute()).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func workoutNumbers(_ w: WorkoutSample) -> some View {
        let minutes = Duration.seconds(w.minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        let kcal = w.kcal.map {
            Measurement(value: Double($0), unit: UnitEnergy.kilocalories)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        }
        return Text(verbatim: [minutes, kcal].compactMap { $0 }.joined(separator: " · "))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    /// The whole day on the axis, so a morning's steps don't stretch across the chart.
    private static func dayRange(of points: [DayPoint]) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: points.first?.day ?? Date())
        return start...calendar.date(byAdding: .day, value: 1, to: start)!
    }
}
