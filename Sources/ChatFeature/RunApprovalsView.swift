import Models
import SwiftUI

/// The foot of a run whose tool call touched a secret outside Exodus (an SSH key, cloud credentials, a `.env`
/// elsewhere): what it wants, with Allow once / Deny, then one quiet line saying how it ended. Reads only its own run's
/// list from the store, so a streaming frame of this or another run does not redraw it.
struct RunApprovalsView: View {
    let runId: String
    /// Whether the run still streams: a call still pending once it does not was cut off by Stop.
    let runIsActive: Bool
    @Environment(\.runApprovals) private var store

    var body: some View {
        if let store {
            let list = store.list(for: runId)
            ForEach(list.entries) { entry in
                ApprovalCard(entry: entry, runIsActive: runIsActive, store: store)
            }
        }
    }
}

private struct ApprovalCard: View {
    let entry: ApprovalEntry
    let runIsActive: Bool
    let store: RunApprovalStore

    var body: some View {
        switch ApprovalDisplay.of(entry.state, runIsActive: runIsActive) {
        case .asking(let sending):
            ApprovalAsk(entry: entry, sending: sending, store: store)
        case let display:
            ApprovalSettledLine(summary: entry.request.summary, display: display)
        }
    }
}

/// Allow once stays disabled this long after the card appears (the desktop's `ALLOW_ENABLE_DELAY_MS`), so a tap already
/// on its way cannot land on it the moment it shows.
let approvalAllowDelay = Duration.milliseconds(600)

private struct ApprovalAsk: View {
    let entry: ApprovalEntry
    let sending: Bool
    let store: RunApprovalStore
    @ScaledMetric(relativeTo: .footnote) private var summaryMaxHeight: CGFloat = 220

    private var request: ApprovalRequest { entry.request }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("chat:approval.title").font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "key")
            }
            .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                if request.toolName == "terminal" {
                    Text("ios:chat.approval.commandHint")
                } else {
                    Text("ios:chat.approval.fileHint")
                }
                // All of it, wrapped, in a region that scrolls once it is long: nothing is cut or hidden.
                ScrollView {
                    ApprovalSummaryText(summary: request.summary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: summaryMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .scrollBounceBehavior(.basedOnSize)
                .background(.fill.tertiary, in: .rect(cornerRadius: 8))
                if request.truncated, let hidden = request.hiddenChars, hidden > 0 {
                    Text(verbatim: ApprovalSummary.truncatedNote(hiddenChars: hidden))
                        .font(.footnote.weight(.medium))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { meta }
                VStack(alignment: .leading, spacing: 4) { meta }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
            if entry.sendFailed {
                Text("chat:approval.decideFailed")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quinary, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.separator) }
        .accessibilityElement(children: .contain)
        .task(id: ObjectIdentifier(entry)) {
            await store.arm(entry)
        }
    }

    @ViewBuilder
    private var meta: some View {
        Label {
            Text(verbatim: ToolPresentation.displayName(request.toolName))
        } icon: {
            Image(systemName: ToolPresentation.systemImage(for: request.toolName))
        }
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(verbatim: ApprovalText.countdown(until: request.expiresAt, now: context.date))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            Task { await store.decide(entry, .allow) }
        } label: {
            Text("chat:approval.allow").frame(minWidth: 88)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!entry.allowArmed || sending)
        Button {
            Task { await store.decide(entry, .deny) }
        } label: {
            Text("chat:approval.deny").frame(minWidth: 88)
        }
        .buttonStyle(.bordered)
        .disabled(sending)
        if sending {
            ProgressView().controlSize(.small)
        }
    }
}

struct ApprovalSettledLine: View {
    let summary: String
    let display: ApprovalDisplay
    @ScaledMetric(relativeTo: .caption) private var summaryMaxHeight: CGFloat = 120

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: ApprovalText.settledSymbol(display))
                .imageScale(.small)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ApprovalText.settledTitle(display))
                ScrollView {
                    ApprovalSummaryText(summary: summary, font: .caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: summaryMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// The summary as the card draws it: sanitized (`ApprovalSummary`), monospaced, never truncated; VoiceOver reads the
/// same sanitized text.
struct ApprovalSummaryText: View {
    let summary: String
    var font: Font = .footnote.monospaced()

    var body: some View {
        let shown = ApprovalSummary.sanitized(summary)
        Text(verbatim: shown)
            .font(font)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityLabel(Text(verbatim: shown))
    }
}
