import MarkdownKit
import SwiftUI

struct ToolCardView: View {
    let card: ToolCard
    @Environment(\.renderDiagnostics) private var diagnostics

    var body: some View {
        switch ToolCardRegistry.resolve(card) {
        case .card(let view):
            view
        case .generic(let issue):
            GenericToolCard(card: card)
                .onAppear {
                    if let issue { diagnostics.report("chat.toolCard", issue.message, issue.attributes) }
                }
        }
    }
}

struct TerminalCard: View {
    let output: ToolPresentation.TerminalOutput
    @State private var showsAll = false
    private static let collapsedLines = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text(verbatim: output.command)
                    .lineLimit(showsAll ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let code = output.exitCode {
                    Label {
                        Text(verbatim: ToolPresentation.exitText(code))
                    } icon: {
                        Image(systemName: output.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")  // l10n:ignore: SF Symbol names
                    }
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(output.succeeded ? Color.green : Color.red)
                    .fixedSize()
                }
            }
            .cardHeader()
            Divider()
            outputBody
            if isLong {
                Divider()
                expandButton
            }
            if let cwd = output.cwd {
                Divider()
                Text(verbatim: cwd)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, CardStyle.inset)
                    .padding(.vertical, 6)
            }
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .modifier(CardSurface())
    }

    private var isLong: Bool { ToolPresentation.terminalOutputIsLong(output, collapsedLines: Self.collapsedLines) }

    // A button of its own: a tap on the card must stay free for selecting text.
    private var expandButton: some View {
        Button {
            showsAll.toggle()
        } label: {
            Group {
                if showsAll {
                    Label("ios:chat.message.terminal.showLess", systemImage: "chevron.up")
                } else {
                    Label("ios:chat.message.terminal.showAll", systemImage: "chevron.down")
                }
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var outputBody: some View {
        if output.stdout.isEmpty && output.stderr.isEmpty {
            Text("ios:chat.message.terminal.noOutput")
                .italic()
                .foregroundStyle(.secondary)
                .padding(.horizontal, CardStyle.inset)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !output.stdout.isEmpty {
                    Text(verbatim: output.stdout)
                        .lineLimit(showsAll ? nil : Self.collapsedLines)
                }
                if !output.stderr.isEmpty {
                    Text(verbatim: output.stderr)
                        .lineLimit(showsAll ? nil : Self.collapsedLines)
                        .foregroundStyle(output.succeeded ? Color.orange : Color.red)
                }
            }
            .padding(.horizontal, CardStyle.inset)
            .padding(.vertical, 8)
        }
    }
}

private struct GenericToolCard: View {
    let card: ToolCard
    @State private var openState: Bool?
    @Environment(\.timelineStartsExpanded) private var startsExpanded
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOpen: Bool { openState ?? startsExpanded }

    private static let maxLines = 200

    var body: some View {
        let hasPayload = ToolPresentation.hasPayload(card.payload)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { openState = !isOpen }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: ToolPresentation.systemImage(for: card.toolName))
                        .foregroundStyle(.secondary)
                    Text(verbatim: ToolPresentation.displayName(card.toolName))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if hasPayload {
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, CardStyle.inset)
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!hasPayload)
            .accessibilityValue(isOpen ? Text("ios:chat.message.timeline.expanded") : Text("ios:chat.message.timeline.collapsed"))
            if isOpen && hasPayload {
                Divider()
                Text(verbatim: ToolPresentation.prettyPayload(card.payload, maxLines: Self.maxLines))
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, CardStyle.inset)
                    .padding(.vertical, 8)
                    .transition(.opacity)
            }
        }
        .modifier(CardSurface())
    }
}
