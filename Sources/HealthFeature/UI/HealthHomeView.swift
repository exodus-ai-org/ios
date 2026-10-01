// Sources/HealthFeature/UI/HealthHomeView.swift
import Models
import OdyKit
import SwiftUI
import UIKit

/// The daily report: the hero, the note, four coloured cards, a memory suggestion, and a question box. Pull down to
/// stretch Ody and write the note again.
struct HealthHomeView: View {
    static let space = HealthCoordinateSpace.home
    /// How far a pull goes before letting go writes the note again.
    static let pullThreshold: CGFloat = 70

    @Bindable var model: HealthHomeModel
    let onAsk: (String) -> Void
    @Namespace private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pull: CGFloat = 0
    @State private var bindleAnchor: CGRect = .zero
    @State private var cardFrame: CGRect = .zero
    @State private var flight: (from: CGRect, to: CGRect)?
    /// The card fades while Remember is saving under Reduce Motion, in place of the flight.
    @State private var lifting = false
    @State private var bounce = 0
    @State private var confetti = 0
    @State private var refreshes = 0
    @State private var now = Date()

    init(model: HealthHomeModel, onAsk: @escaping (String) -> Void) {
        self.model = model
        self.onAsk = onAsk
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HealthHero(
                    day: model.day, mood: model.day?.snapshot.odyState ?? .noData, now: now, calendar: .current,
                    stretch: 1 + min(pull, 140) / 300, bindleBounce: bounce, bindleAnchor: $bindleAnchor
                )
                .padding(.horizontal, -16)
                if let summary = readySummary {
                    Text(verbatim: summary.headline).font(.headline).padding(.top, 2)
                }
                ReportCard(report: model.report) { Task { await model.grantConsent() } }
                if let snapshot = model.day?.snapshot {
                    if snapshot.odyState == .noData { noDataHelp }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(HealthCategory.allCases, id: \.self) { c in
                            NavigationLink(value: c) {
                                CategoryCard(category: c, snapshot: snapshot, line: line(c))
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: c, in: zoom)
                        }
                    }
                }
                if let suggestion = model.suggestion, flight == nil {
                    MemorySuggestionCard(
                        suggestion: suggestion,
                        onRemember: { remember() },
                        onDismiss: { withAnimation(.smooth) { model.dismissSuggestion() } }
                    )
                    .opacity(lifting ? 0 : 1)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { cardFrame = $0 }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(HealthSurface.page)
        .coordinateSpace(.named(Self.space))
        .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, v in
            pull = v
        }
        .refreshable {
            now = Date()
            await model.load(force: true)
            refreshes += 1
        }
        // Spec §5 haptics: crossing the pull threshold, a refresh done, the goal celebrated. Remember's is the
        // bindle's own, when it bounces.
        .sensoryFeedback(.impact(weight: .light), trigger: pull > Self.pullThreshold) { _, crossed in crossed }
        .sensoryFeedback(.success, trigger: refreshes)
        .sensoryFeedback(.success, trigger: confetti)
        .overlay {
            if let flight {
                MemoryFlight(from: flight.from, to: flight.to) {
                    bounce += 1
                    self.flight = nil
                }
            }
        }
        .overlay { ConfettiView(trigger: confetti).allowsHitTesting(false).accessibilityHidden(true) }
        .safeAreaInset(edge: .bottom) {
            AskComposer(
                suggestions: [
                    "ios:health.ask.suggestion.sleep", "ios:health.ask.suggestion.energy", "ios:health.ask.suggestion.week",
                ],
                attachment: { snapshotJSON }, onSend: onAsk)
        }
        .navigationDestination(for: HealthCategory.self) { c in
            HealthDetailView(category: c, model: model, onAsk: onAsk)
                .navigationTransition(.zoom(sourceID: c, in: zoom))
        }
        .onChange(of: model.celebrates, initial: true) { _, celebrate in
            guard celebrate else { return }
            confetti += 1
            model.didCelebrate()
        }
    }

    private var readySummary: HealthSummary? {
        if case .ready(let s) = model.report { s } else { nil }
    }

    private func line(_ c: HealthCategory) -> String? {
        guard let s = readySummary else { return nil }
        switch c {
        case .sleep: return s.categories.sleep
        case .activity: return s.categories.activity
        case .recovery: return s.categories.recovery
        case .body: return s.categories.body
        }
    }

    private var snapshotJSON: String? {
        guard let snapshot = model.day?.snapshot, let data = try? HealthWire.encoder().encode(snapshot) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private var noDataHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ios:health.noData.explain").font(.subheadline).foregroundStyle(.secondary)
            Button("ios:health.noData.openSettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }

    /// The card lifts off from where it last was; on a failed save it stays and nothing flies.
    private func remember() {
        let from = cardFrame
        let still = reduceMotion || bindleAnchor == .zero
        if reduceMotion { withAnimation(.easeOut(duration: 0.25)) { lifting = true } }
        Task {
            let saved = await model.remember()
            if reduceMotion { withAnimation(.easeOut(duration: 0.25)) { lifting = false } } else { lifting = false }
            guard saved else { return }
            if still {
                bounce += 1
            } else {
                flight = (from, bindleAnchor)
            }
        }
    }
}

/// The home's surfaces: the prototype's warm cream page with white cards; system grouped colours in Dark Mode.
enum HealthSurface {
    static let page = Color(
        UIColor { $0.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(OdyPalette.hex(0xFFF9E8)) })
    static let card = Color(
        UIColor { $0.userInterfaceStyle == .dark ? .secondarySystemGroupedBackground : .white })
}
