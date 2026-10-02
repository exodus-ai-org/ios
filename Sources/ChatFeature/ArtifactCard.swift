import Models
import SwiftUI

/// `create_artifact`: the artifact itself, in the chat, the way the desktop shows it — the computer's own sandbox page,
/// live, as tall as it draws up to a limit, and a button that opens it full screen. When the phone cannot show it, a
/// line says to view it on the computer.
struct ArtifactCard: View {
    let artifact: ArtifactResult
    @State private var state = ArtifactInlineState()
    @State private var showsFullScreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                        .background(.tint.opacity(0.12), in: CardStyle.innerShape)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: ArtifactCardRules.title(artifact))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text("ios:chat.artifact.card.kind")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                if state.offersFullScreen {
                    Button {
                        showsFullScreen = true
                    } label: {
                        Label("ios:chat.artifact.card.fullScreen", systemImage: "arrow.up.left.and.arrow.down.right")
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .background(.fill.tertiary, in: .circle)
                    .transition(.opacity)
                }
            }
            .cardHeader()
            ArtifactInlineView(artifact: artifact, state: $state)
                .padding(.horizontal, CardStyle.inset)
                .padding(.bottom, CardStyle.inset)
        }
        .modifier(CardSurface())
        .fullScreenCover(isPresented: $showsFullScreen) {
            ArtifactPreviewScreen(artifact: artifact)
        }
    }
}

enum ArtifactCardRules {
    static func title(_ artifact: ArtifactResult) -> String {
        let title = artifact.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty
            ? String(localized: "ios:chat.artifact.card.kind", defaultValue: "Artifact", comment: "An artifact card's kind, under its title; also its title when it has none.")
            : title
    }

    /// The artifact's code: its row's, or the computer's when the row came without it (empty when neither has it).
    static func code(of artifact: ArtifactResult, from source: ArtifactSandboxSource?) async -> String {
        guard artifact.code.isEmpty, let source, let chatId = artifact.chatId else { return artifact.code }
        return (try? await source.code(chatId, artifact.artifactId)) ?? ""
    }
}

/// What the card has heard from its web view, apart from it so it can be tested: how the render went, and how tall
/// the artifact is. The height outlives the web view, so a card scrolled far away and back keeps its place.
struct ArtifactInlineState: Equatable {
    /// Before the artifact has said how tall it is: about a chart's height, so the list moves little when it does.
    static let placeholderHeight: CGFloat = 220
    /// The tallest the card shows; the rest fades out, and full screen has it all.
    static let maxHeight: CGFloat = 420
    static let minHeight: CGFloat = 44
    /// The fade at the bottom of an artifact taller than the card.
    static let fadeHeight: CGFloat = 56

    private(set) var phase: ArtifactPreviewPhase = .loading
    private(set) var reportedHeight: CGFloat?
    private(set) var hasRendered = false

    /// The card's height for the artifact: as reported once it has rendered, within the limits; the placeholder before.
    var height: CGFloat {
        guard let reportedHeight else { return Self.placeholderHeight }
        return min(max(reportedHeight.rounded(.up), Self.minHeight), Self.maxHeight)
    }

    /// Taller than the card: the bottom fades out.
    var overflows: Bool { (reportedHeight ?? 0) > Self.maxHeight }

    var isFallback: Bool {
        if case .fallback = phase { return true }
        return false
    }

    /// Full screen loads the artifact again, so it is offered unless the card already knows it would not show:
    /// after a fallback, only for an artifact that rendered here before (and failed on a tap).
    var offersFullScreen: Bool { !isFallback || hasRendered }

    mutating func apply(_ event: ArtifactPreviewEvent) {
        switch event {
        case .resized(let height):
            // The sandbox measures its "waiting" line too; only the artifact's own height sizes the card.
            guard phase == .rendered else { return }
            reportedHeight = height
        default:
            phase = ArtifactPreviewRules.next(phase, on: event)
            if phase == .rendered { hasRendered = true }
        }
    }

    /// A new web view for the card (it came back near the screen): loading again, at the height it had.
    mutating func reload() {
        if phase == .rendered { phase = .loading }
    }
}

/// When a card's web view may live: near the screen, and only a few at once. A card asks when it comes near and gives
/// its place up when it goes far or away; a card past the limit waits for one.
struct ArtifactLiveSlots: Equatable {
    static let limit = 4

    let limit: Int
    private(set) var holders: [UUID] = []
    private(set) var waiting: [UUID] = []

    init(limit: Int = Self.limit) {
        self.limit = limit
    }

    func holds(_ id: UUID) -> Bool { holders.contains(id) }

    mutating func want(_ id: UUID) {
        guard !holders.contains(id), !waiting.contains(id) else { return }
        if holders.count < limit { holders.append(id) } else { waiting.append(id) }
    }

    mutating func drop(_ id: UUID) {
        holders.removeAll { $0 == id }
        waiting.removeAll { $0 == id }
        while holders.count < limit, !waiting.isEmpty { holders.append(waiting.removeFirst()) }
    }
}

/// Where a card stands from the screen: near loads its web view, far lets it go, and between keeps what it has, so a
/// card at the edge does not load and unload as the list moves.
enum ArtifactProximity: Equatable {
    case near, between, far

    /// `card` and `visible` (the scroll view's visible bounds) in the same space; no scroll view counts as near.
    static func of(card: CGRect, visible: CGRect?) -> ArtifactProximity {
        guard let visible, visible.height > 0 else { return .near }
        let distance: CGFloat
        if card.maxY < visible.minY {
            distance = visible.minY - card.maxY
        } else if card.minY > visible.maxY {
            distance = card.minY - visible.maxY
        } else {
            distance = 0
        }
        if distance <= visible.height * 0.5 { return .near }
        return distance > visible.height * 1.5 ? .far : .between
    }

    /// What a card does with its place on landing here.
    var slotChange: ArtifactSlotChange? {
        switch self {
        case .near: .want
        case .far: .drop
        case .between: nil
        }
    }

    /// A card that disappeared gave its place up, but one back on screen (scrolled just off the lazy list and back)
    /// may land where it was, and an unchanged proximity reports nothing: it asks again unless it was last far.
    static func slotChangeOnAppear(last: ArtifactProximity?) -> ArtifactSlotChange? {
        last == .far ? nil : .want
    }
}

enum ArtifactSlotChange: Equatable {
    case want, drop
}

@MainActor
@Observable
final class ArtifactLiveBudget {
    static let shared = ArtifactLiveBudget()
    private(set) var slots = ArtifactLiveSlots()

    func want(_ id: UUID) { slots.want(id) }
    func drop(_ id: UUID) { slots.drop(id) }
}

/// The artifact in the card: its web view while near the screen, otherwise the room it takes; the loading state until
/// it renders; a line instead when it cannot.
private struct ArtifactInlineView: View {
    let artifact: ArtifactResult
    @Binding var state: ArtifactInlineState
    @Environment(\.artifactSandbox) private var source
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var budget = ArtifactLiveBudget.shared
    @State private var slot = UUID()
    @State private var lastProximity: ArtifactProximity?
    @State private var code: String?

    private var isLive: Bool { budget.slots.holds(slot) }

    var body: some View {
        Group {
            if state.isFallback {
                fallback
            } else {
                artifactView
            }
        }
        .onGeometryChange(for: ArtifactProximity.self) { proxy in
            ArtifactProximity.of(card: proxy.frame(in: .local), visible: proxy.bounds(of: .scrollView))
        } action: { proximity in
            lastProximity = proximity
            apply(proximity.slotChange)
        }
        .onAppear { apply(ArtifactProximity.slotChangeOnAppear(last: lastProximity)) }
        .onDisappear { budget.drop(slot) }
        .onChange(of: isLive) { _, live in
            if live { state.reload() }
        }
        .task(id: isLive) { await watch() }
    }

    private var artifactView: some View {
        ZStack {
            if isLive, let source, let code, !code.isEmpty {
                ArtifactWebView(
                    source: source, code: code, artifactId: ArtifactCardRules.title(artifact),
                    colorScheme: colorScheme, layout: .card
                ) { event in
                    state.apply(event)
                }
                .opacity(state.phase == .rendered ? 1 : 0)
            }
            if state.phase != .rendered {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("ios:chat.artifact.preview.loading"))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: state.height)
        .mask {
            if state.overflows {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 1 - ArtifactInlineState.fadeHeight / state.height),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            } else {
                Color.black
            }
        }
        .clipShape(CardStyle.innerShape)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: state.height)
        .animation(.easeOut(duration: 0.2), value: state.phase)
    }

    private var fallback: some View {
        Label {
            Text(fallbackLine)
        } icon: {
            Image(systemName: "desktopcomputer")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .transition(.opacity)
    }

    private var fallbackLine: String {
        if case .fallback(.outdatedComputer) = state.phase {
            return String(
                localized: "ios:chat.artifact.inline.outdated",
                defaultValue: "Update Exodus on your computer to see this here.",
                comment: "Shown in an artifact's card in the chat, instead of the artifact, when the computer's Exodus is too old to serve it to the phone.")
        }
        return String(
            localized: "ios:chat.artifact.fallback.title", defaultValue: "View it on your computer",
            comment: "Title shown instead of an artifact preview that cannot be shown on the phone.")
    }

    private func apply(_ change: ArtifactSlotChange?) {
        switch change {
        case .want: budget.want(slot)
        case .drop: budget.drop(slot)
        case nil: break
        }
    }

    /// While live: the code (fetched when the row came without it), then the time the page has to render it.
    private func watch() async {
        guard isLive, !state.isFallback else { return }
        if code == nil { code = await ArtifactCardRules.code(of: artifact, from: source) }
        guard source != nil, let code, !code.isEmpty else {
            state.apply(.unavailable)
            return
        }
        try? await Task.sleep(for: ArtifactPreviewRules.timeout)
        if !Task.isCancelled { state.apply(.timedOut) }
    }
}

/// The artifact, full screen, rendered by the computer's sandbox page — or, when that cannot happen, the calm state
/// that sends the reader to the computer.
struct ArtifactPreviewScreen: View {
    let artifact: ArtifactResult
    @Environment(\.artifactSandbox) private var source
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var phase: ArtifactPreviewPhase = .loading
    @State private var code: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                if let source, let code, !code.isEmpty {
                    ArtifactWebView(
                        source: source, code: code, artifactId: ArtifactCardRules.title(artifact), colorScheme: colorScheme
                    ) { event in
                        handle(event)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .opacity(phase == .rendered ? 1 : 0)
                }
                switch phase {
                case .loading:
                    ProgressView {
                        Text("ios:chat.artifact.preview.loading")
                    }
                    .foregroundStyle(.secondary)
                case .rendered:
                    EmptyView()
                case .fallback(let reason):
                    ArtifactFallbackView(reason: reason)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: phase)
            .navigationTitle(Text(verbatim: ArtifactCardRules.title(artifact)))
            .navigationBarTitleDisplayMode(.inline)
            .screenTitle(ArtifactCardRules.title(artifact))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
            }
        }
        .task { await start() }
    }

    private func handle(_ event: ArtifactPreviewEvent) {
        phase = ArtifactPreviewRules.next(phase, on: event)
    }

    private func start() async {
        let loaded = await ArtifactCardRules.code(of: artifact, from: source)
        code = loaded
        guard source != nil, !loaded.isEmpty else {
            handle(.unavailable)
            return
        }
        try? await Task.sleep(for: ArtifactPreviewRules.timeout)
        if !Task.isCancelled { handle(.timedOut) }
    }
}

/// "See it on your computer": what the phone says, full screen, when it cannot render an artifact.
struct ArtifactFallbackView: View {
    let reason: ArtifactFallbackReason

    var body: some View {
        ContentUnavailableView {
            Label("ios:chat.artifact.fallback.title", systemImage: "desktopcomputer")
        } description: {
            VStack(spacing: 10) {
                Text(message)
                if case .renderFailed(let error) = reason, let line = ArtifactPreviewRules.displayMessage(error) {
                    Text(verbatim: line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var message: String {
        switch reason {
        case .outdatedComputer:
            String(
                localized: "ios:chat.artifact.fallback.outdated",
                defaultValue: "Update Exodus on your computer to preview artifacts on iPhone. Until then, open this chat there to see it.",
                comment: "Shown instead of an artifact preview when the computer's Exodus is too old to serve it.")
        case .unreachable:
            String(
                localized: "ios:chat.artifact.fallback.unreachable",
                defaultValue: "The preview couldn't load. Open this chat in Exodus on your computer to see it.",
                comment: "Shown instead of an artifact preview when the computer did not answer in time.")
        case .renderFailed:
            String(
                localized: "ios:chat.artifact.fallback.failed",
                defaultValue: "This artifact can't be shown on iPhone. Open this chat in Exodus on your computer to see it.",
                comment: "Shown instead of an artifact preview when its code did not render on the phone.")
        }
    }
}
