import SwiftUI
import UIKit

/// Copy, Regenerate, Sources and the time, under a finished answer. Equatable on what it shows only: the closures
/// never change what a bar looks like, so a finished turn's bar is not evaluated again while a later reply streams.
struct TurnActionBarView: View, Equatable {
    nonisolated let bar: TurnActionBar
    let onRegenerate: () -> Void
    let onShowSources: () -> Void

    @State private var copyCount = 0
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (lhs: TurnActionBarView, rhs: TurnActionBarView) -> Bool { lhs.bar == rhs.bar }

    var body: some View {
        HStack(spacing: 0) {
            copyButton
            if bar.showsRegenerate {
                regenerateButton
            }
            if bar.showsSources {
                sourcesButton
            }
            Spacer(minLength: 8)
            if let time = TurnActions.timeText(bar.timestampMs) {
                Text(verbatim: time)
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
        }
        .foregroundStyle(.secondary)
        // Glyphs and a time, not prose: past this size the bar would no longer fit a line, and its targets are already large.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // Each target is its glyph plus `BarTarget.inset` all round (about 44 pt); the row is pulled up and left by that
        // padding, so the glyphs line up with the answer's text instead of sitting a full target below and beside it.
        .padding(.top, -10)
        .padding(.leading, -BarTarget.inset)
        .sensoryFeedback(.success, trigger: copyCount)
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            // A newer copy cancels this wait; its own task resets the glyph, not this one.
            guard (try? await Task.sleep(for: .seconds(1.5))) != nil else { return }
            copied = false
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = bar.copyText
            copied = true
            copyCount += 1
            AccessibilityNotification.Announcement(Self.copiedAnnouncement).post()
        } label: {
            Label {
                if copied {
                    Text("common:state.copied")
                } else {
                    Text("common:action.copy")
                }
            } icon: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")  // l10n:ignore: SF Symbol names
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .labelStyle(.iconOnly)
            .modifier(BarTarget())
        }
        .buttonStyle(.plain)
    }

    private var regenerateButton: some View {
        Button(action: onRegenerate) {
            Label("chat:messageAction.regenerate", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
                .modifier(BarTarget())
        }
        .buttonStyle(.plain)
    }

    private var sourcesButton: some View {
        Button(action: onShowSources) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text(bar.sourceCount, format: .number)
                    .font(.caption)
                    .monospacedDigit()
            }
            .modifier(BarTarget())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("chat:messageAction.sources"))
        .accessibilityValue(Text(bar.sourceCount, format: .number))
    }

    private static var copiedAnnouncement: String {
        String(localized: "common:state.copied", defaultValue: "Copied", comment: "Said aloud after the answer was copied.")
    }
}

/// A touch target of about 44 pt around a 15 pt glyph, growing with the glyph at larger text sizes.
private struct BarTarget: ViewModifier {
    static let inset: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .padding(Self.inset)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }
}
