// Sources/HealthFeature/Detail/HealthDetailView.swift
import Models
import OdyKit
import SwiftUI

/// A category up close: its big scene as the header (zoomed out of the home card), its charts, and a question box
/// that sends the category's last seven days.
struct HealthDetailView: View {
    let category: HealthCategory
    let model: HealthHomeModel
    let onAsk: (String) -> Void
    @State private var data: HealthHistoryData?
    @State private var failed = false
    /// Cups tapped, cups written to the store, and how many were written when the shown data was read: the glass
    /// rises on the tap, not after the round trip, and never counts a cup twice.
    @State private var tapped = 0
    @State private var written = 0
    @State private var readWithWritten = 0
    @State private var generation = 0
    /// The workspace's ("Health"): a screenshot of this page is "Health · Sleep".
    @Environment(\.screenTitle) private var enclosingTitle

    var body: some View {
        let style = CategoryStyle.of(category)
        let mood = model.day.map { HealthRules.card(category, in: $0.snapshot) } ?? .noData
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(style, mood: mood)
                if let data {
                    if Self.isEmpty(category, data) {
                        note(Text(Self.emptyText))
                    } else {
                        switch category {
                        case .sleep: SleepDetail(data: data, baseline: model.day?.snapshot.sleep?.baselineMin)
                        case .activity: ActivityDetail(data: data, goal: model.day?.snapshot.activity?.stepGoal ?? 8000)
                        case .recovery: RecoveryDetail(data: data, snapshot: model.day?.snapshot.recovery)
                        case .body: BodyDetail(data: data, cups: data.waterCups + tapped - readWithWritten, onLogWater: logWater)
                        }
                    }
                } else if failed {
                    note(Text(Self.failedText)) {
                        Button { Task { await reload() } } label: { Text(Self.retryText) }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(OdyPalette.marigold)
                    }
                    if category == .body {
                        // The glass still works from the day the home read; each cup it logs reloads that day.
                        let cups = (model.day?.snapshot.body?.waterCups ?? 0) + tapped - written
                        BodyDetail(data: HealthHistoryData(waterCups: cups), cups: cups, onLogWater: logWater)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(HealthSurface.page)
        .navigationTitle(Text(style.title))
        .navigationBarTitleDisplayMode(.inline)
        .screenTitle(ScreenTitles.join(enclosingTitle, String(localized: style.title)))
        .safeAreaInset(edge: .bottom) {
            AskComposer(
                suggestions: Self.suggestions(category), canAttach: data != nil,
                attachedLabel: Self.attachedWeekText(style.title), attachByDefault: model.hasConsent,
                attachment: { weekJSON }, onSend: onAsk)
        }
        .task { await reload() }
    }

    private func header(_ style: CategoryStyle, mood: OdyMood) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: style.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            // No resting heart rate, no beat: the wave never animates a made-up pulse.
            if category == .recovery, let bpm = model.day?.snapshot.recovery?.restingHr, bpm.isFinite, bpm > 0 {
                HeartbeatWave(bpm: bpm, color: .white)
                    .frame(height: 90)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .opacity(0.85)
                    .accessibilityHidden(true)
            }
            OdySceneView(OdyScene(card: category, mood: mood), showsBackground: false, pokable: true)
                .frame(width: 140, height: 140)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(8)
            VStack(alignment: .leading, spacing: 2) {
                Text(style.title)
                    .font(.largeTitle.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let snapshot = model.day?.snapshot {
                    Text(verbatim: CategoryValue.text(category, in: snapshot) ?? "—")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(style.ink)
            .padding(20)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .frame(height: 240)
        .clipShape(.rect(cornerRadius: 28))
    }

    private func logWater() {
        tapped += 1
        Task {
            await model.logWater()
            written += 1
            await reload()
        }
    }

    /// Only the newest read lands, so a slow earlier one can't take the glass back down. A failed read keeps what is
    /// on screen; with nothing on screen it says so and offers a retry.
    private func reload() async {
        generation += 1
        let mine = generation
        let writtenAtRead = written
        let loaded = try? await model.historyLoader().load(category, now: Date())
        guard mine == generation else { return }
        guard let loaded else {
            failed = true
            return
        }
        failed = false
        data = loaded
        readWithWritten = writtenAtRead
    }

    /// A one-line card for when there is nothing to chart, with an optional action under it.
    private func note(_ text: Text, @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            text.font(.subheadline).foregroundStyle(.secondary)
            action()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }

    /// Body always has its glass, so it is never empty.
    static func isEmpty(_ c: HealthCategory, _ d: HealthHistoryData) -> Bool {
        switch c {
        case .sleep: (d.lastNight?.stages.isEmpty ?? true) && d.nights.isEmpty
        case .activity: d.hourlySteps.isEmpty && d.dailySteps.isEmpty && d.workouts.isEmpty
        case .recovery: d.hrv.isEmpty && d.restingHr.isEmpty && d.respRate.isEmpty
        case .body: false
        }
    }

    static func attachedWeekText(_ category: LocalizedStringResource) -> LocalizedStringResource {
        LocalizedStringResource(
            "ios:health.ask.attachedWeek", defaultValue: "This week's \(String(localized: category)) attached",
            comment: "Detail page ask box: the category's last seven days go with the question. %@ is the category name.")
    }

    static let emptyText = LocalizedStringResource(
        "ios:health.detail.empty", defaultValue: "Nothing recorded here yet.",
        comment: "Detail page: the category has no data in Apple Health.")
    static let failedText = LocalizedStringResource(
        "ios:health.detail.loadFailed", defaultValue: "Couldn't read your health data. Try again.",
        comment: "Detail page: reading the history from Apple Health failed.")
    static let retryText = LocalizedStringResource(
        "ios:health.detail.retry", defaultValue: "Try again", comment: "Detail page: retry reading the history.")

    private var weekJSON: String? {
        guard let data,
            let encoded = try? HealthWire.encoder().encode(
                HealthHistory.lastWeek(category, from: data, calendar: .current, now: Date()))
        else { return nil }
        return String(decoding: encoded, as: UTF8.self)
    }

    static func suggestions(_ c: HealthCategory) -> [LocalizedStringResource] {
        switch c {
        case .sleep: ["ios:health.ask.sleep.wakeEarly", "ios:health.ask.sleep.deep"]
        case .activity: ["ios:health.ask.activity.goal", "ios:health.ask.activity.week"]
        case .recovery: ["ios:health.ask.recovery.hrv", "ios:health.ask.recovery.train"]
        case .body: ["ios:health.ask.body.water", "ios:health.ask.body.weight"]
        }
    }
}

/// A titled section of a detail page: the home's card surface, so the two read as one place.
struct DetailSection<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }
}
