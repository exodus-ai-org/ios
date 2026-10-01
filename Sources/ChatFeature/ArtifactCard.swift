import Models
import SwiftUI
import UIKit

/// `create_artifact`: the artifact's title, Preview — the computer's own sandbox page, rendering the code full
/// screen — and View Code. When the preview cannot show it, it says to open the chat on the computer and keeps the
/// code one tap away.
struct ArtifactCard: View {
    let artifact: ArtifactResult
    @State private var showsPreview = false
    @State private var showsCode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .cardHeader()
            HStack(spacing: 10) {
                Button {
                    showsPreview = true
                } label: {
                    Label("ios:chat.artifact.card.preview", systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button {
                    showsCode = true
                } label: {
                    Label("ios:chat.artifact.card.viewCode", systemImage: "chevron.left.forwardslash.chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(artifact.code.isEmpty)
            }
            .font(.subheadline.weight(.medium))
            .controlSize(.large)
            .padding(.horizontal, CardStyle.inset)
            .padding(.bottom, CardStyle.inset)
        }
        .modifier(CardSurface())
        .fullScreenCover(isPresented: $showsPreview) {
            ArtifactPreviewScreen(artifact: artifact)
        }
        .sheet(isPresented: $showsCode) {
            ArtifactCodeSheet(title: ArtifactCardRules.title(artifact), code: artifact.code)
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
}

/// The artifact, full screen, rendered by the computer's sandbox page — or, when that cannot happen, the calm state
/// that sends the reader to the computer, with the code.
struct ArtifactPreviewScreen: View {
    let artifact: ArtifactResult
    @Environment(\.artifactSandbox) private var source
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var phase: ArtifactPreviewPhase = .loading
    @State private var code: String?
    @State private var showsCode = false

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
                    ArtifactFallbackView(reason: reason, hasCode: !(code ?? "").isEmpty) { showsCode = true }
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: phase)
            .navigationTitle(Text(verbatim: ArtifactCardRules.title(artifact)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
                if let code, !code.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showsCode = true
                        } label: {
                            Label("ios:chat.artifact.card.viewCode", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                }
            }
            .sheet(isPresented: $showsCode) {
                ArtifactCodeSheet(title: ArtifactCardRules.title(artifact), code: code ?? "")
            }
        }
        .task { await start() }
    }

    private func handle(_ event: ArtifactPreviewEvent) {
        phase = ArtifactPreviewRules.next(phase, on: event)
    }

    private func start() async {
        var loaded = artifact.code
        if loaded.isEmpty, let source, let chatId = artifact.chatId {
            loaded = (try? await source.code(chatId, artifact.artifactId)) ?? ""
        }
        code = loaded
        guard source != nil, !loaded.isEmpty else {
            handle(.unavailable)
            return
        }
        try? await Task.sleep(for: ArtifactPreviewRules.timeout)
        if !Task.isCancelled { handle(.timedOut) }
    }
}

/// "See it on your computer": what the phone says when it cannot render an artifact, and the way to its code.
struct ArtifactFallbackView: View {
    let reason: ArtifactFallbackReason
    let hasCode: Bool
    let showCode: () -> Void

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
        } actions: {
            if hasCode {
                Button(action: showCode) {
                    Label("ios:chat.artifact.card.viewCode", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
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

/// The artifact's source: monospaced, selectable, to copy or share.
struct ArtifactCodeSheet: View {
    let title: String
    let code: String
    @Environment(\.dismiss) private var dismiss
    @State private var copies = 0
    @State private var showsCopied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                CodeLines(lines: LineDiff.lines(of: code).map { LineDiff.clip($0, to: 2_000) })
            }
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = code
                        copies += 1
                        showsCopied = true
                    } label: {
                        if showsCopied {
                            Label("common:state.copied", systemImage: "checkmark")
                        } else {
                            Label("common:action.copy", systemImage: "doc.on.doc")
                        }
                    }
                    ShareLink(item: code)
                }
            }
            .sensoryFeedback(.success, trigger: copies)
            .task(id: copies) {
                guard copies > 0 else { return }
                try? await Task.sleep(for: .seconds(1.5))
                showsCopied = false
            }
        }
    }
}
