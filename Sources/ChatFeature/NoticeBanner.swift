import NetworkingKit
import SwiftUI

/// The banner over the composer for a stream notice. The message is the server's text: shown as it is, never
/// translated and never read as markdown.
struct NoticeBanner: View {
    let notice: StreamNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Self.symbol(for: notice.level))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Self.tint(for: notice.level))
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("chat:toast.headsUpTitle")
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: notice.message)
                    .font(.subheadline)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button(action: onDismiss) {
                Label("common:action.close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.trailing, -14)
            .padding(.vertical, -12)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(Self.tint(for: notice.level).opacity(0.14)), in: .rect(cornerRadius: 20))
    }

    /// What VoiceOver says when a notice arrives: the banner's title, then the server's message.
    nonisolated static func announcement(for notice: StreamNotice) -> String {
        let title = String(localized: "chat:toast.headsUpTitle", defaultValue: "Heads up", comment: "Title of a notice relayed from a tool.")
        return [title, notice.message].joined(separator: "\n")
    }

    static func symbol(for level: StreamNotice.Level) -> String {
        switch level {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    static func tint(for level: StreamNotice.Level) -> Color {
        switch level {
        case .info: .accentColor
        case .warning: .orange
        }
    }
}

/// Lays the banner over whatever sits at the bottom of the screen, and animates its coming and going.
struct NoticeStack<Content: View>: View {
    let notice: StreamNotice?
    let onDismiss: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if let notice {
                NoticeBanner(notice: notice, onDismiss: onDismiss)
                    .padding(.horizontal, 12)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            content
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.25), value: notice)
    }
}
