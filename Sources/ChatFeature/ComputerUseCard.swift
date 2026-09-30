import Models
import SwiftUI
import UIKit

/// A `computer_use` call, like the desktop's card: the step and the latest screenshot while the session runs, its
/// question when it waits for the user (answered from here, or on the computer), Stop, and the outcome with its
/// summary. A finished run shows the frames this phone kept while it streamed; one reopened from history, the final
/// screenshot. Any screenshot opens full screen.
struct ComputerUseCard: View {
    let model: ComputerUseCardModel
    @State private var viewerStart: ImageViewerPage?
    @State private var finalImage: UIImage?
    @Environment(\.toolCardsAreLive) private var isLive
    @Environment(\.computerUseFrames) private var frames
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var store: ComputerUseFrameStore { frames ?? .shared }

    var body: some View {
        let shots = store.filmstrip(for: model.callId)?.shots ?? []
        let status = ComputerUseRules.status(model, isLive: isLive)
        let final = finalImage ?? store.cachedFinal(for: model.callId)
        let layout = ComputerUseRules.shots(model, isLive: isLive, recorded: shots.count, hasFinal: final != nil)
        let items = Self.items(shots: shots, final: layout == .live ? nil : final)
        VStack(alignment: .leading, spacing: 0) {
            ComputerUseHeader(target: model.target, status: status)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if !model.task.isEmpty {
                    Text(verbatim: model.task)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                }
                if case .running(let frame) = model.phase {
                    Label {
                        Text(verbatim: ComputerUseRules.stepLine(frame.step, action: frame.action))
                    } icon: {
                        Image(systemName: "cursorarrow.click")
                    }
                    .font(.subheadline.weight(.medium))
                }
                shotsView(layout, items: items)
                if ComputerUseRules.isRunning(model, isLive: isLive) {
                    ComputerUseControls(model: model)
                }
                outcome
            }
            .padding(CardStyle.inset)
        }
        .modifier(CardSurface())
        .task(id: model.finalScreenshot) { await loadFinal() }
        .fullScreenCover(item: $viewerStart) { page in
            ImageViewer(
                pages: items.enumerated().map { index, item in
                    ImageViewerPage.Content(id: index, image: item.image, caption: item.caption)
                },
                start: page.id)
        }
    }

    struct Item: Equatable {
        let step: Int?
        let action: String?
        let image: UIImage

        var label: String { step.map(ComputerUseRules.shotLabel(step:)) ?? ComputerUseRules.finalShotLabel }
        var caption: String {
            step.map { ComputerUseRules.stepLine($0, action: action) } ?? ComputerUseRules.finalShotLabel
        }
    }

    static func items(shots: [ComputerUseShot], final: UIImage?) -> [Item] {
        shots.map { Item(step: $0.step, action: $0.action, image: $0.image) } + (final.map { [Item(step: nil, action: nil, image: $0)] } ?? [])
    }

    @ViewBuilder
    private func shotsView(_ layout: ComputerUseRules.Shots, items: [Item]) -> some View {
        switch layout {
        case .none:
            EmptyView()
        case .live, .single:
            if let item = items.last {
                ComputerUseShotButton(item: item, width: nil) { viewerStart = ImageViewerPage(id: items.count - 1) }
            }
        case .filmstrip:
            ComputerUseFilmstripView(items: items) { viewerStart = ImageViewerPage(id: $0) }
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch model.phase {
        case .finished(let outcome):
            if let summary = model.summary {
                Text(verbatim: summary)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
            if let sessionId = outcome.sessionId {
                sessionLine(sessionId)
            }
        case .refused(let code):
            errorText(ComputerUseRules.errorText(code, target: model.target))
        case .failed(let message):
            errorText(message ?? ToolPresentation.failedText("computer_use"))
        case .starting, .running:
            EmptyView()
        }
    }

    private func errorText(_ text: String) -> some View {
        Label {
            Text(verbatim: text).textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .font(.subheadline)
        .foregroundStyle(.red)
    }

    @ViewBuilder
    private func sessionLine(_ id: String) -> some View {
        let text = Text(verbatim: ComputerUseRules.sessionText(id))
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
        // At accessibility sizes the whole id wraps; an ellipsis would hide part of what the user may need to quote.
        if dynamicTypeSize.isAccessibilitySize {
            text.fixedSize(horizontal: false, vertical: true)
        } else {
            text.lineLimit(1).truncationMode(.middle)
        }
    }

    private func loadFinal() async {
        guard finalImage == nil, let dataURL = model.finalScreenshot else { return }
        finalImage = await store.finalScreenshot(for: model.callId, dataURL: dataURL)
    }
}

/// The header band: the tool, the app it drives, and where the session stands.
struct ComputerUseHeader: View {
    let target: String
    let status: ComputerUseRules.Status
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.tint)
                    .frame(minWidth: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("chat:computerUseCard.title")
                        .font(.subheadline.weight(.medium))
                    if !target.isEmpty {
                        Text(verbatim: target)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            badge
        }
        .cardHeader()
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        HStack(spacing: 5) {
            switch status {
            case .starting, .step:
                ProgressView().controlSize(.mini).accessibilityHidden(true)
            case .needsYou:
                Image(systemName: "hand.raised.fill").accessibilityHidden(true)
            default:
                EmptyView()
            }
            Text(verbatim: ComputerUseRules.statusText(status))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .fixedSize()
    }

    private var tint: Color {
        switch status {
        case .needsYou: .orange
        case .error: .red
        case .outcome("success"): .green
        case .outcome("failed"): .red
        case .outcome("stuck"): .orange
        default: .secondary
        }
    }
}

/// One screenshot: fitted in a thin frame, opening the viewer; VoiceOver hears its step and action.
struct ComputerUseShotButton: View {
    let item: ComputerUseCard.Item
    /// A fixed width in the filmstrip; nil fills the card.
    let width: CGFloat?
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            Image(uiImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: width ?? .infinity, maxHeight: width == nil ? 280 : nil)
                .frame(width: width)
                .background(Color(.tertiarySystemFill))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator), lineWidth: 0.5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .id(item.step ?? -1)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: item.step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.label))
        .accessibilityValue(Text(verbatim: item.action.map(ComputerUseRules.actionName) ?? ""))
        .accessibilityAddTraits(.isImage)
        .accessibilityHint(Text("ios:chat.card.image.openHint"))
    }
}

/// Every kept frame side by side, oldest first, scrolled to the end.
struct ComputerUseFilmstripView: View {
    let items: [ComputerUseCard.Item]
    let open: (Int) -> Void
    @ScaledMetric(relativeTo: .caption2) private var width: CGFloat = 150
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let frameWidth = min(width, 260)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            ComputerUseShotButton(item: item, width: frameWidth) { open(index) }
                            Text(verbatim: item.caption)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                                .frame(width: frameWidth, alignment: .leading)
                                .accessibilityHidden(true)
                        }
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .onAppear { proxy.scrollTo(items.count - 1, anchor: .trailing) }
            // The final screen is decoded after the frames are drawn; keep the newest in view when it lands.
            .onChange(of: items.count) { _, count in proxy.scrollTo(count - 1, anchor: .trailing) }
        }
    }
}

/// The question the session is waiting on, and the controls the desktop's card has: a reply that lets it continue, and
/// Stop. Both go to the computer through the paired session.
struct ComputerUseControls: View {
    let model: ComputerUseCardModel
    @State private var controls = ComputerUseControlState()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.toolCardsAreLive) private var isLive
    @Environment(\.computerUseRemote) private var remote
    @Environment(\.accentGlyph) private var accentGlyph

    var body: some View {
        let question = ComputerUseRules.question(model, isLive: isLive)
        VStack(alignment: .leading, spacing: 10) {
            if let question { ask(question) }
            if ComputerUseRules.isRunning(model, isLive: isLive), remote != nil {
                Button(role: .destructive) {
                    stop()
                } label: {
                    Label("chat:computerUseCard.stop", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .disabled(controls.busy)
            }
            if let failure = controls.failure {
                Text(verbatim: failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: question) { _, new in
            if let new { AccessibilityNotification.Announcement(new).post() }
        }
    }

    private var step: Int? { if case .running(let frame) = model.phase { frame.step } else { nil } }

    private func ask(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: question)
                .font(.subheadline)
                .textSelection(.enabled)
            if let remote, let sessionId = model.sessionId, controls.answeredStep != step {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { field; continueButton(remote, sessionId) }
                    VStack(alignment: .leading, spacing: 8) { field; continueButton(remote, sessionId) }
                }
            } else if remote != nil {
                Text("chat:computerUseCard.waitingForReply")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.tint.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.tint.opacity(0.3), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }

    private var field: some View {
        // A placeholder stays on one line, so at accessibility sizes its words move above the field, where they wrap.
        let isLarge = dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 4) {
            if isLarge {
                Text("chat:computerUseCard.replyPlaceholder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            TextField(
                // An empty prompt, not nil: without one the field shows its label, which would ellipsize again.
                text: $controls.reply, prompt: isLarge ? Text(verbatim: "") : Text("chat:computerUseCard.replyPlaceholder"),
                axis: .vertical
            ) {
                Text("chat:computerUseCard.replyPlaceholder")
            }
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.send)
        }
        .frame(minWidth: 160)
    }

    private func continueButton(_ remote: ComputerUseRemote, _ sessionId: String) -> some View {
        Button {
            controls.answer(remote, sessionId: sessionId, step: step)
        } label: {
            Text("chat:computerUseCard.doneContinue").foregroundStyle(accentGlyph)
        }
        .buttonStyle(.borderedProminent)
        .toneFill()
        .disabled(controls.busy)
    }

    private func stop() {
        guard let remote else { return }
        controls.stop(remote)
    }
}

/// The controls' state. One request at a time: a second tap that lands before `.disabled` has redrawn the button is
/// refused here, so the computer gets one answer and one abort.
@Observable
@MainActor
final class ComputerUseControlState {
    var reply = ""
    private(set) var answeredStep: Int?
    private(set) var busy = false
    private(set) var failure: String?

    /// The request's task, or nil when one is already in flight.
    @discardableResult
    func answer(_ remote: ComputerUseRemote, sessionId: String, step: Int?) -> Task<Void, Never>? {
        guard !busy else { return nil }
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        failure = nil
        return Task {
            do {
                try await remote.answer(sessionId, text.isEmpty ? "(done)" : text)
                reply = ""
                answeredStep = step
            } catch {
                failure = String(
                    localized: "chat:computerUseCard.answerFailedTitle", defaultValue: "Could not send your answer",
                    comment: "Computer Use card: sending the reply to the computer failed.")
            }
            busy = false
        }
    }

    @discardableResult
    func stop(_ remote: ComputerUseRemote) -> Task<Void, Never>? {
        guard !busy else { return nil }
        busy = true
        failure = nil
        return Task {
            do {
                try await remote.stop()
            } catch {
                failure = String(
                    localized: "chat:computerUseCard.stopFailedTitle", defaultValue: "Could not stop the session",
                    comment: "Computer Use card: the stop request failed.")
            }
            busy = false
        }
    }
}
