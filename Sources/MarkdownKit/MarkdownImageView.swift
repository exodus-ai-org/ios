import SwiftUI
import UIKit

struct MarkdownImageView: View {
    let image: MarkdownImage
    var policy: MarkdownImagePolicy = .current
    var loader: MarkdownImageLoader = .shared

    private enum Phase {
        case idle
        case loading
        case loaded(MarkdownLoadedImage)
        case failed
    }

    private struct LoadKey: Equatable {
        let source: String
        let requested: Bool
        let attempt: Int
        let hasWidth: Bool
    }

    @State private var phase = Phase.idle
    @State private var requested = false
    @State private var attempt = 0
    @State private var width: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    private var decision: MarkdownImagePolicy.Decision { policy.decision(for: image.source) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: LoadKey(source: image.source, requested: requested, attempt: attempt, hasWidth: width > 0)) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch (decision, phase) {
        case (.unavailable, _):
            unavailable(retry: false)
        case (_, .loaded(let loaded)):
            Image(decorative: loaded.cgImage, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: CGFloat(loaded.sourcePixelWidth), alignment: .leading)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(accessibilityText)
        case (_, .failed):
            unavailable(retry: true)
        case (.askToLoad(_, let host), .idle) where !requested:
            askCard(host: host)
        default:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(height: 120)
                .overlay { ProgressView() }
        }
    }

    private func load() async {
        let url: URL
        switch decision {
        case .load(let loadable): url = loadable
        case .askToLoad(let remote, _) where requested: url = remote
        default: return
        }
        guard width > 0 else { return }
        if case .loaded = phase { return }
        phase = .loading
        do {
            phase = .loaded(try await loader.load(url, maxPixelWidth: Int((width * displayScale).rounded(.up))))
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = Task.isCancelled ? .idle : .failed
        }
    }

    private var accessibilityText: Text {
        if image.alt.isEmpty { Text("ios:chat.markdown.image") } else { Text(verbatim: image.alt) }
    }

    private var altLabel: some View {
        Group {
            if image.alt.isEmpty {
                Text("ios:chat.markdown.image")
            } else {
                Text(verbatim: image.alt)
            }
        }
        .lineLimit(2)
    }

    private func askCard(host: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                altLabel.font(.subheadline)
                Text(verbatim: host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("ios:chat.markdown.loadImage") { requested = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint(
                    Text(
                        String(
                            localized: "ios:chat.markdown.loadImageHint", defaultValue: "Downloads this image from \(host).",
                            comment: "VoiceOver hint of the Load image button. %@ is the website's host name.")))
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 10))
    }

    private func unavailable(retry: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "photo")
                if image.alt.isEmpty {
                    Text("ios:chat.markdown.imageUnavailable")
                } else {
                    Text(verbatim: image.alt)
                }
            }
            .accessibilityElement(children: .combine)
            if retry {
                Button("ios:chat.markdown.loadImageRetry") {
                    phase = .idle
                    attempt += 1
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 8))
    }
}
