import MarkdownKit
import Models
import SwiftUI

/// A `deep_research` call, like the desktop's card: "researching" with where the job stands while it runs, and the
/// report once it is written — a few lines of it here, the whole report (with its sources, cited first) a tap away.
struct DeepResearchCard: View {
    let model: DeepResearchCardModel
    @Environment(\.deepResearchJobs) private var jobs

    var body: some View {
        switch model.phase {
        case .job(let id):
            if let jobs {
                DeepResearchJobCard(subject: model.subject, id: id, store: jobs)
            } else {
                DeepResearchFrame(subject: model.subject, status: .attention) {
                    DeepResearchNote(text: Text("ios:chat.card.research.unreachable"), systemImage: "wifi.slash")
                }
            }
        case .refused(let message):
            DeepResearchFrame(subject: model.subject, status: .failed) {
                DeepResearchError(text: message)
            }
        case .failed(let message):
            DeepResearchFrame(subject: model.subject, status: .failed) {
                DeepResearchError(text: message ?? ToolPresentation.failedText("deep_research"))
            }
        }
    }
}

/// The card for a job on the computer: its state comes from the store, which this card's task keeps reading while
/// the card is on screen and the app is in front.
struct DeepResearchJobCard: View {
    let subject: String
    let id: String
    let store: DeepResearchStore
    @State private var showsReport = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct PollKey: Equatable {
        let id: String
        let attempt: Int
        let isActive: Bool
    }

    var body: some View {
        let entry = store.entry(id)
        let state = entry.state
        DeepResearchFrame(subject: subject, status: DeepResearchStatus(state), detail: detail(state)) {
            content(state)
        }
        .task(id: PollKey(id: id, attempt: entry.attempt, isActive: scenePhase != .background)) {
            guard scenePhase != .background else { return }
            await store.follow(id)
        }
        .sheet(isPresented: $showsReport) {
            if case .done(let report) = state {
                DeepResearchReportView(report: report)
            }
        }
    }

    private func detail(_ state: DeepResearchJobState) -> String? {
        if case .done(let report) = state { DeepResearchText.completed(report) } else { nil }
    }

    @ViewBuilder
    private func content(_ state: DeepResearchJobState) -> some View {
        switch state {
        case .loading:
            DeepResearchNote(text: Text("ios:chat.card.research.loading"), systemImage: nil)
        case .running(let progress):
            DeepResearchProgressView(progress: progress, isLive: true)
        case .stalled(let progress):
            VStack(alignment: .leading, spacing: 12) {
                DeepResearchProgressView(progress: progress, isLive: false)
                DeepResearchNote(text: Text("ios:chat.card.research.stalled"), systemImage: "exclamationmark.triangle")
                retryButton(Text("ios:chat.card.research.checkAgain"))
            }
        case .done(let report):
            DeepResearchPreview(report: report) { showsReport = true }
        case .finishedWithoutReport:
            DeepResearchNote(text: Text("ios:chat.card.research.noReport"), systemImage: "doc")
        case .failed(let message):
            DeepResearchFailure(message: message)
        case .terminated:
            DeepResearchError(text: DeepResearchText.terminated)
        case .unknownStatus(let status):
            DeepResearchNote(text: Text(verbatim: DeepResearchText.unknownStatus(status)), systemImage: "questionmark.circle")
        case .unreadable:
            DeepResearchNote(text: Text("ios:chat.card.research.unreadable"), systemImage: "questionmark.circle")
        case .missing:
            DeepResearchNote(text: Text("ios:chat.card.research.missing"), systemImage: "trash")
        case .unreachable:
            VStack(alignment: .leading, spacing: 12) {
                DeepResearchNote(text: Text("ios:chat.card.research.unreachable"), systemImage: "wifi.slash")
                retryButton(Text("common:action.retry"))
            }
        }
    }

    private func retryButton(_ title: Text) -> some View {
        Button {
            store.retry(id)
        } label: {
            title
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
    }
}

/// The header and body frame every state shares.
struct DeepResearchFrame<Content: View>: View {
    let subject: String
    let status: DeepResearchStatus
    var detail: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeepResearchHeader(subject: subject, status: status, detail: detail)
            Divider()
            content
                .padding(CardStyle.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(CardSurface())
    }
}

enum DeepResearchStatus: Equatable {
    /// `starting`: the job is known, its first step is not. `working`: its steps are coming in.
    case starting, working, done, attention, failed

    /// One spinner at a time: once the steps show, the step in progress carries it.
    var spinsInHeader: Bool { self == .starting }

    init(_ state: DeepResearchJobState) {
        switch state {
        case .loading: self = .starting
        case .running: self = .working
        case .done: self = .done
        case .failed, .terminated: self = .failed
        case .stalled, .finishedWithoutReport, .unknownStatus, .unreadable, .missing, .unreachable: self = .attention
        }
    }
}

struct DeepResearchHeader: View {
    let subject: String
    let status: DeepResearchStatus
    let detail: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(.tint)
                    .frame(minWidth: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ios:chat.message.tool.deepResearch")
                        .font(.subheadline.weight(.medium))
                    if !subject.isEmpty {
                        Text(verbatim: subject)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                    if let detail {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            badge
        }
        .cardHeader()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .starting, .working:
            // The spinner alone: the title names the tool, and the words beside it took the room the question
            // needs. VoiceOver still hears them.
            if status.spinsInHeader {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("chat:deepResearchCard.researching"))
            }
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(Text("deepResearch:messages.complete.title"))
        case .attention:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
        }
    }
}

/// The running job: the current step, the latest searches, and the running counts.
struct DeepResearchProgressView: View {
    let progress: DeepResearchProgress
    let isLive: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                if isLive {
                    ProgressView().controlSize(.mini).frame(width: iconWidth).accessibilityHidden(true)
                }
                Text(verbatim: DeepResearchText.step(progress.step))
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !progress.recent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(progress.recent) { search in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .frame(width: iconWidth)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: search.query)
                                    .font(.subheadline)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                if !search.goal.isEmpty {
                                    Text(verbatim: search.goal)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { counts }
                VStack(alignment: .leading, spacing: 6) { counts }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var counts: some View {
        count(DeepResearchText.searches(progress.searches.count), systemImage: "magnifyingglass")
        count(DeepResearchText.sources(progress.sources), systemImage: "globe")
        count(DeepResearchText.learnings(progress.learnings), systemImage: "lightbulb")
    }

    private func count(_ text: String, systemImage: String) -> some View {
        Label {
            Text(verbatim: text).fixedSize()
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

/// A few blocks of the report, fading out, and the way into the whole of it.
struct DeepResearchPreview: View {
    let report: DeepResearchReport
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MarkdownDocumentView(parsed: report.preview, citations: report.citations)
                .frame(maxHeight: 220, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [.init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom)
                )
                .allowsHitTesting(false)
                // The whole preview opens the report; its links and chips are for the full view.
                .overlay {
                    Button(action: open) { Color.clear.contentShape(.rect) }
                        .buttonStyle(.plain)
                }
                .accessibilityHidden(true)
            Button(action: open) {
                Label {
                    Text("ios:chat.card.research.readFull")
                } icon: {
                    Image(systemName: "doc.richtext")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityHint(Text("ios:chat.card.research.openHint"))
        }
    }
}

struct DeepResearchNote: View {
    let text: Text
    let systemImage: String?

    var body: some View {
        Label {
            text.fixedSize(horizontal: false, vertical: true)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

struct DeepResearchError: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text).textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .font(.subheadline)
        .foregroundStyle(.red)
    }
}

/// A failed job, as the desktop's card shows it: "Research failed" and the stored error, when there is one.
struct DeepResearchFailure: View {
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("chat:deepResearchCard.failed")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.circle")
            }
            .foregroundStyle(.red)
            Text(verbatim: message ?? DeepResearchText.failed)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The whole report, its citation chips resolved to its own sources; a chip scrolls to its source and marks it. The
/// sources follow as the desktop lists them: cited first, then the rest.
struct DeepResearchReportView: View {
    let report: DeepResearchReport
    /// A source to open the report at, marked (as a tapped chip would).
    var startAt: Int?
    @State private var highlighted: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.screenTitle) private var enclosingTitle
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        MarkdownDocumentView(parsed: report.document, citations: report.citations) { rank in
                            highlighted = rank
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                proxy.scrollTo(Self.anchor(rank), anchor: .center)
                            }
                        }
                        if !report.cited.isEmpty {
                            section(Text("deepResearch:sources.citations"), report.cited)
                            if !report.more.isEmpty { section(Text("deepResearch:sources.more"), report.more) }
                        } else if !report.more.isEmpty {
                            section(Text("chat:messageAction.sources"), report.more)
                        }
                    }
                    .padding()
                }
                .task {
                    guard let startAt else { return }
                    highlighted = startAt
                    proxy.scrollTo(Self.anchor(startAt), anchor: .center)
                }
            }
            .navigationTitle("ios:chat.card.research.reportTitle")
            .navigationBarTitleDisplayMode(.inline)
            .screenTitle(
                ScreenTitles.join(
                    String(
                        localized: "ios:chat.card.research.reportTitle", defaultValue: "Research report",
                        comment: "Title of the full deep research report view."),
                    enclosingTitle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: report.markdown) {
                        Label {
                            Text("ios:chat.card.research.share")
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    static func anchor(_ rank: Int) -> String { "source-\(rank)" }

    private func section(_ title: Text, _ sources: [CitationSource]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                let entry = SourcesSheetModel.Entry(id: index, source: source, isHighlighted: source.rank == highlighted)
                SourceRow(entry: entry) { openURL($0) }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(
                        entry.isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear, in: .rect(cornerRadius: 8))
                    .id(Self.anchor(source.rank))
                if index < sources.count - 1 { Divider() }
            }
        }
    }
}
