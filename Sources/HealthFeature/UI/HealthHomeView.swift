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
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var pull: CGFloat = 0
    @State private var scroll = ScrollPosition()
    /// The visible part of the scroll view, in its own coordinate space.
    @State private var viewport: CGRect = .zero
    @State private var bindleAnchor: CGRect = .zero
    @State private var cardFrame: CGRect = .zero
    @State private var flight: (from: CGRect, to: CGRect)?
    /// The suggestion being remembered: it stays on screen until it flies (or fades), though the model has let go.
    @State private var leaving: HealthSummary.MemorySuggestion?
    /// The card fades out when there is no flight (Reduce Motion, or the bindle out of sight).
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
                .id(Self.heroID)
                if let summary = readySummary {
                    Text(verbatim: summary.headline).font(.headline).padding(.top, 2)
                }
                ReportCard(report: model.report) { Task { await model.grantConsent() } }
                if let snapshot = model.day?.snapshot {
                    if snapshot.odyState == .noData { noDataHelp }
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(HealthCategory.allCases, id: \.self) { c in
                            NavigationLink(value: c) {
                                CategoryCard(category: c, snapshot: snapshot, line: line(c))
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: c, in: zoom)
                        }
                    }
                }
                if let suggestion = model.suggestion ?? leaving, flight == nil {
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
        .scrollPosition($scroll)
        .background(HealthSurface.page)
        .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, v in
            pull = v
        }
        .onScrollGeometryChange(for: CGRect.self) { g in
            CGRect(origin: .zero, size: g.containerSize)
                .inset(by: UIEdgeInsets(top: g.contentInsets.top, left: 0, bottom: g.contentInsets.bottom, right: 0))
        } action: { _, v in viewport = v }
        .refreshable {
            now = Date()
            await model.load(force: true)
            // Done means a note: a refresh that ended offline or failed gets no success tap.
            if case .ready = model.report { refreshes += 1 }
        }
        // Spec §5 haptics: crossing the pull threshold, a refresh done, the goal celebrated. Remember's is the
        // bindle's own, when it bounces.
        .sensoryFeedback(.impact(weight: .light), trigger: pull > Self.pullThreshold) { _, crossed in crossed }
        .sensoryFeedback(.success, trigger: refreshes)
        .sensoryFeedback(.success, trigger: confetti)
        // Before `coordinateSpace`, so the overlay is inside the space the frames were read in; it reads its own origin
        // there and draws from it, wherever the safe area put it.
        .overlay {
            if let flight {
                GeometryReader { proxy in
                    let origin = proxy.frame(in: .named(Self.space)).origin
                    MemoryFlight(
                        from: flight.from.offsetBy(dx: -origin.x, dy: -origin.y),
                        to: flight.to.offsetBy(dx: -origin.x, dy: -origin.y)
                    ) {
                        bounce += 1
                        self.flight = nil
                    }
                }
                .ignoresSafeArea()
            }
        }
        .coordinateSpace(.named(Self.space))
        .overlay { ConfettiView(trigger: confetti).allowsHitTesting(false).accessibilityHidden(true) }
        .safeAreaInset(edge: .bottom) {
            AskComposer(
                suggestions: [
                    "ios:health.ask.suggestion.sleep", "ios:health.ask.suggestion.energy", "ios:health.ask.suggestion.week",
                ],
                canAttach: model.day != nil, attachment: { snapshotJSON }, onSend: onAsk)
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

    private static let heroID = "hero"

    /// One column at accessibility sizes, so the numbers keep their size.
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150), spacing: 10)]
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

    /// Saves the suggestion and flies the card into the bindle. The hero is scrolled into view first, so the flight
    /// lands where it can be seen; with no bindle in sight (Ody asleep in a scrubbed night) or under Reduce Motion the
    /// card fades instead. Either way the bindle bounces, which is the success tap. On a failed save the card stays.
    private func remember() {
        guard let suggestion = model.suggestion, leaving == nil else { return }
        leaving = suggestion
        let fade = Animation.easeOut(duration: 0.25)
        if reduceMotion { withAnimation(fade) { lifting = true } }
        Task {
            async let saved = model.remember()
            if !reduceMotion, !bindleInView {
                withAnimation(.smooth(duration: 0.35)) { scroll.scrollTo(id: Self.heroID, anchor: .top) }
                try? await Task.sleep(for: .milliseconds(380))
            }
            guard await saved else {
                withAnimation(fade) { lifting = false }
                leaving = nil
                return
            }
            if !reduceMotion, bindleInView, cardFrame != .zero {
                flight = (cardFrame, bindleAnchor)
                leaving = nil
            } else {
                if !lifting {
                    withAnimation(fade) { lifting = true }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                leaving = nil
                lifting = false
                bounce += 1
            }
        }
    }

    /// The bindle is drawn (`bindleAnchor` is `.zero` while Ody sleeps) and wholly inside the visible scroll area.
    private var bindleInView: Bool {
        bindleAnchor != .zero && viewport.contains(bindleAnchor)
    }
}

/// The home's surfaces: the prototype's warm cream page with white cards; system grouped colours in Dark Mode.
enum HealthSurface {
    static let page = Color(
        UIColor { $0.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(OdyPalette.hex(0xFFF9E8)) })
    static let card = Color(
        UIColor { $0.userInterfaceStyle == .dark ? .secondarySystemGroupedBackground : .white })
}
