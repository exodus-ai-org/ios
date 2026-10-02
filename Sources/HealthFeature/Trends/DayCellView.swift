// Sources/HealthFeature/Trends/DayCellView.swift
import Models
import OdyKit
import SwiftUI

/// One day of the calendar, style C: the day's state as the cell's colour, sleep and steps as the small ring in its
/// corner, today outlined in marigold. `compact` is a month's square, `large` a week's column with its numbers, `row`
/// a week's line at accessibility text sizes. The numerals are capped so seven cells still fit a row.
struct DayCellView: View {
    enum Style { case compact, large, row }

    let cell: CalendarCell
    let style: Style
    let calendar: Calendar

    var body: some View {
        switch style {
        case .compact: compact
        case .large: large
        case .row: row
        }
    }

    private var fill: Color { cell.isFuture ? DayTone.empty.fill.opacity(0.45) : cell.tone.fill }
    private var number: String { cell.day.map { calendar.component(.day, from: $0).formatted() } ?? "" }
    private var hasNumbers: Bool { cell.record?.hasData == true }
    private var dateStyle: Date.FormatStyle { Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone) }

    private var compact: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10).fill(fill)
            Text(verbatim: number)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(cell.isFuture ? .tertiary : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if hasNumbers {
                CornerRing(sleep: cell.record?.sleepFraction, steps: cell.record?.stepFraction, lineWidth: 1.6)
                    .frame(width: 12, height: 12)
                    .padding(3)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay { todayMark(cornerRadius: 10) }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var large: some View {
        VStack(spacing: 6) {
            Text(verbatim: cell.day.map { $0.formatted(dateStyle.weekday(.abbreviated)) } ?? "")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: number)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(cell.isFuture ? .tertiary : .primary)
            CornerRing(sleep: cell.record?.sleepFraction, steps: cell.record?.stepFraction, lineWidth: 3)
                .frame(width: 26, height: 26)
                .opacity(hasNumbers ? 1 : 0)
            VStack(spacing: 1) {
                Text(verbatim: cell.record?.sleepMin.map(TrendText.clock) ?? "—")
                Text(verbatim: cell.record?.steps.map(TrendText.compact) ?? "—")
            }
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .opacity(cell.isFuture ? 0 : 1)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(fill, in: .rect(cornerRadius: 14))
        .overlay { todayMark(cornerRadius: 14) }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var row: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(fill)
                .frame(width: 30, height: 30)
                .overlay { todayMark(cornerRadius: 8) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: cell.day.map { $0.formatted(dateStyle.weekday(.wide).month(.abbreviated).day()) } ?? "")
                    .font(.headline)
                Text(verbatim: values).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(HealthSurface.card, in: .rect(cornerRadius: 14))
        .opacity(cell.isFuture ? 0.5 : 1)
    }

    private var values: String {
        guard let r = cell.record, r.hasData else { return String(localized: DayTone.empty.name) }
        return [r.sleepMin.map { TrendText.duration(Double($0)) }, r.steps.map(CategoryValue.steps)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private func todayMark(cornerRadius: CGFloat) -> some View {
        if cell.isToday {
            RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(OdyPalette.marigold, lineWidth: 2)
        }
    }
}

/// A day that has begun opens its sheet; a day to come and a month's leading blank are only drawn.
struct DayCellButton: View {
    let cell: CalendarCell
    let style: DayCellView.Style
    let calendar: Calendar
    let onOpen: (Date) -> Void

    var body: some View {
        if let day = cell.day, !cell.isFuture {
            Button { onOpen(day) } label: { DayCellView(cell: cell, style: style, calendar: calendar) }
                .buttonStyle(PressScale())
                .accessibilityLabel(Text(verbatim: DayCellText.label(cell, calendar: calendar)))
        } else if cell.day != nil {
            DayCellView(cell: cell, style: style, calendar: calendar).accessibilityHidden(true)
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
        }
    }
}

/// A pressed cell gives a little, unless Reduce Motion is on.
struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

/// What VoiceOver reads for a day: "October 1, Today, Rested or active, Sleep 7h 40m, 9,120 steps". A list of
/// facts, each localized on its own.
enum DayCellText {
    static func label(_ cell: CalendarCell, calendar: Calendar) -> String {
        guard let day = cell.day else { return "" }
        var parts = [day.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).day())]
        if cell.isToday {
            parts.append(
                String(localized: "ios:health.calendar.today", defaultValue: "Today", comment: "VoiceOver for a calendar day: this day is today."))
        }
        parts.append(String(localized: cell.tone.name))
        if let m = cell.record?.sleepMin {
            let sleep = TrendText.duration(Double(m))
            parts.append(
                String(
                    localized: "ios:health.calendar.a11y.sleep", defaultValue: "Sleep \(sleep)",
                    comment: "VoiceOver for a calendar day: the night's sleep. %@ is a duration, e.g. 7h 40m."))
        }
        if let steps = cell.record?.steps { parts.append(CategoryValue.steps(steps)) }
        return parts.joined(separator: ", ")
    }
}
