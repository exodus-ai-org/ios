// Sources/HealthFeature/Trends/DaySheet.swift
import MarkdownKit
import Models
import OdyKit
import SwiftUI

/// A past day up close (spec §3.3): its note as it was written that day — the insight stories, or the Markdown note
/// of an older report — or, with no note, the day's numbers and "No note for this day". The ask box sends the whole
/// day's numbers with the question, so Chat shows them as its health card.
struct DaySheet: View {
    let day: Date
    let record: DayRecord?
    let archived: ArchivedDay?
    /// The workspace's title ("Health"), for the screenshot's name.
    let healthTitle: String
    let calendar: Calendar
    let loadSnapshot: () async -> HealthSnapshot?
    /// What the question carries until (or unless) Apple Health answers and the day has no note.
    let fallback: HealthSnapshot
    let onAsk: (String) -> Void

    @State private var snapshot: HealthSnapshot?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if let archived {
                        note(archived.summary)
                    } else {
                        Text("ios:health.day.noNote")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
                        if let record, record.hasData { DayNumbers(record: record) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(HealthSurface.page)
            .navigationTitle(Text(verbatim: dateText))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common:action.close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                AskComposer(
                    suggestions: [
                        LocalizedStringResource("ios:health.day.ask.compare", defaultValue: "How did this day compare to my usual?", comment: "Day sheet suggestion chip: compare the day to the user's usual."),
                        LocalizedStringResource("ios:health.day.ask.standout", defaultValue: "What stood out on this day?", comment: "Day sheet suggestion chip: what was notable about the day."),
                    ],
                    attachment: { Self.attachment(snapshot: snapshot, archived: archived?.snapshot, fallback: fallback) },
                    onSend: send)
            }
            .screenTitle(ScreenTitles.join(healthTitle, dateText))
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .task { snapshot = await loadSnapshot() }
    }

    private var tone: DayTone { record.map { DayTone($0.mood) } ?? .empty }

    /// "October 1, 2026".
    private var dateText: String {
        day.formatted(Date.FormatStyle(date: .long, time: .omitted, calendar: calendar, timeZone: calendar.timeZone))
    }

    /// "Thursday": the date is already the title, so the story's eyebrow only names the weekday.
    private var weekdayText: String {
        day.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            OdySceneView(OdyScene(hero: record?.mood ?? .noData))
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 16))
                .accessibilityHidden(true)
            Text(tone.name).font(.headline)
            if typeSize.isAccessibilitySize == false { Spacer(minLength: 0) }
            if record?.hasData == true {
                CornerRing(sleep: record?.sleepFraction, steps: record?.stepFraction, lineWidth: 4)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: dateText))
        .accessibilityValue(tone.name)
    }

    /// The note exactly as that day's home showed it, with the weekday where "Today" was.
    @ViewBuilder
    private func note(_ summary: HealthSummary) -> some View {
        if let story = ReportStory(summary, eyebrow: Text(verbatim: weekdayText)) {
            story
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: summary.headline).font(.headline)
                MarkdownView(text: summary.summary, isStreaming: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
        }
    }

    /// The whole day as Apple Health reads it; before (or without) that read, the note's own numbers; with neither,
    /// the fallback, so a question about a day never goes out without the day.
    static func attachment(snapshot: HealthSnapshot?, archived: HealthSnapshot?, fallback: HealthSnapshot) -> String? {
        guard let data = try? HealthWire.encoder().encode(snapshot ?? archived ?? fallback) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The day's date and the numbers the calendar already has that the wire holds as they are. Sleep and activity
    /// stay out: their wire shape wants stages, calories and hours stood the calendar never read, and a zero there
    /// would read as a measured zero. Chat's card shows what is left, or the date.
    static func minimalSnapshot(
        day: Date, record: DayRecord?, calendar: Calendar, locale: String, now: Date
    ) -> HealthSnapshot {
        let wire = WireDate(timeZone: calendar.timeZone)
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!
        let recovery = record.flatMap { r in
            r.hrvMs == nil && r.restingHr == nil
                ? nil
                : HealthSnapshot.Recovery(
                    level: nil, hrvMs: r.hrvMs, hrvBaselineMs: nil, restingHr: r.restingHr, restingHrBaseline: nil,
                    respRate: nil)
        }
        let body = record?.waterCups.map { HealthSnapshot.Body(waterCups: $0, weightKg: nil, weightTrend30d: nil, mood: nil) }
        return HealthSnapshot(
            date: wire.day(day), localTime: wire.clock(min(now, next.addingTimeInterval(-60))), locale: locale,
            sleep: nil, activity: nil, recovery: recovery, body: body, odyState: record?.mood ?? .noData)
    }

    /// The question goes to a new chat; the sheet steps out of the way first.
    private func send(_ text: String) {
        dismiss()
        onAsk(text)
    }
}

/// The day's numbers when it has no note: a row each, only the ones the day has.
struct DayNumbers: View {
    struct Row {
        let title: LocalizedStringResource
        let symbol: String
        let value: String
        /// Whose colour the glyph takes, as on the home's cards.
        var category: HealthCategory = .sleep
    }

    let record: DayRecord
    @Environment(\.dynamicTypeSize) private var typeSize
    /// One column for every glyph: SF Symbols are not one width (a bed is twice a walker), and labels that start
    /// where their glyph ends do not line up.
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 26

    var body: some View {
        let rows = Self.rows(record)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
                layout {
                    Label {
                        Text(row.title)
                    } icon: {
                        Image(systemName: row.symbol)
                            .font(.body.weight(.medium))
                            .imageScale(.small)
                            .foregroundStyle(CategoryStyle.of(row.category).accent)
                            .frame(width: glyphWidth)
                    }
                    if typeSize.isAccessibilitySize == false { Spacer(minLength: 8) }
                    Text(verbatim: row.value).monospacedDigit().foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 14)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }

    static func rows(_ r: DayRecord) -> [Row] {
        var rows: [Row] = []
        if let m = r.sleepMin {
            rows.append(Row(title: CategoryStyle.of(.sleep).title, symbol: "moon.zzz.fill", value: TrendText.duration(Double(m))))
        }
        if let bedtime = r.bedtime {
            rows.append(Row(title: LocalizedStringResource("ios:health.day.bedtime", defaultValue: "Bedtime", comment: "Day sheet row: when the night began."), symbol: "bed.double.fill", value: bedtime))
        }
        if let steps = r.steps {
            rows.append(Row(title: LocalizedStringResource("ios:health.day.steps", defaultValue: "Steps", comment: "Day sheet row: the day's step count."), symbol: "figure.walk", value: steps.formatted(), category: .activity))
        }
        if let m = r.exerciseMin {
            rows.append(
                Row(
                    title: LocalizedStringResource("ios:health.day.exercise", defaultValue: "Exercise", comment: "Day sheet row: minutes of exercise."), symbol: "flame.fill",
                    value: Duration.seconds(m * 60).formatted(.units(allowed: [.minutes], width: .abbreviated)), category: .activity))
        }
        if let hrv = r.hrvMs {
            rows.append(Row(title: LocalizedStringResource("ios:health.recovery.hrv", defaultValue: "Heart rate variability", comment: "Day sheet row: HRV."), symbol: "waveform.path.ecg", value: TrendText.ms(hrv), category: .recovery))
        }
        if let hr = r.restingHr, hr.isFinite {
            rows.append(
                Row(
                    title: LocalizedStringResource("ios:health.recovery.restingHr", defaultValue: "Resting heart rate", comment: "Day sheet row: resting heart rate."), symbol: "heart.fill",
                    value: CategoryValue.bpm(hr), category: .recovery))
        }
        if let cups = r.waterCups {
            rows.append(Row(title: LocalizedStringResource("ios:health.body.water", defaultValue: "Water", comment: "Day sheet row: cups of water."), symbol: "drop.fill", value: CategoryValue.cups(cups), category: .body))
        }
        return rows
    }
}
