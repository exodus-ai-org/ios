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
    /// Cups tapped, cups written to the store, and how many were written when the shown data was read: the glass
    /// rises on the tap, not after the round trip, and never counts a cup twice.
    @State private var tapped = 0
    @State private var written = 0
    @State private var readWithWritten = 0
    @State private var generation = 0

    var body: some View {
        let style = CategoryStyle.of(category)
        let mood = model.day.map { HealthRules.card(category, in: $0.snapshot) } ?? .noData
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(style, mood: mood)
                if let data {
                    switch category {
                    case .sleep: SleepDetail(data: data, baseline: model.day?.snapshot.sleep?.baselineMin)
                    case .activity: ActivityDetail(data: data, goal: model.day?.snapshot.activity?.stepGoal ?? 8000)
                    case .recovery: RecoveryDetail(data: data, snapshot: model.day?.snapshot.recovery)
                    case .body: BodyDetail(data: data, cups: data.waterCups + tapped - readWithWritten, onLogWater: logWater)
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
        .safeAreaInset(edge: .bottom) {
            AskComposer(suggestions: Self.suggestions(category), attachment: { weekJSON }, onSend: onAsk)
        }
        .task { await reload() }
    }

    private func header(_ style: CategoryStyle, mood: OdyMood) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: style.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            if category == .recovery {
                HeartbeatWave(bpm: model.day?.snapshot.recovery?.restingHr ?? 60, color: .white)
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

    /// Only the newest read lands, so a slow earlier one can't take the glass back down.
    private func reload() async {
        generation += 1
        let mine = generation
        let writtenAtRead = written
        guard let loaded = try? await model.historyLoader().load(category, now: Date()), mine == generation else { return }
        data = loaded
        readWithWritten = writtenAtRead
    }

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
