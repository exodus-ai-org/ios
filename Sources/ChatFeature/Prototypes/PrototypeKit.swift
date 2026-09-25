#if DEBUG
import Foundation
import SwiftUI

// DEBUG-only building blocks of the card prototypes. Copy is `Text(verbatim:)`: this page never ships, and the real
// cards will take catalog keys when a design is picked.

struct ProtoCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground).opacity(0.5), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator), lineWidth: 0.5))
            .clipShape(.rect(cornerRadius: 12))
    }
}

extension View {
    func protoCard() -> some View { modifier(ProtoCardSurface()) }
}

enum ProtoStatus {
    case running, done, failed, warning
}

struct ProtoStatusIcon: View {
    let status: ProtoStatus

    var body: some View {
        switch status {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

/// The header band every file / computer card shares: an icon, a title that may truncate, and a trailing status.
struct ProtoCardHeader<Trailing: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var subtitleTruncation: Text.TruncationMode = .head
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the trailing status drops under the title instead of squeezing it to "…".
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .truncationMode(.middle)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .truncationMode(subtitleTruncation)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// The small caption above each rendering: which state of the card this is.
struct ProtoStateTag: View {
    let text: String

    var body: some View {
        Text(verbatim: text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: .capsule)
    }
}

/// One state of a card, placed as it would sit in an assistant reply: the reply's collapsed steps header above it, and
/// optionally a line of the answer below.
struct ProtoInReply<Card: View>: View {
    let state: String
    var header: String?
    var answer: String?
    @ViewBuilder var card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProtoStateTag(text: state)
            if let header {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").imageScale(.small)
                    Text(verbatim: header).fontWeight(.medium)
                    Image(systemName: "chevron.down").imageScale(.small)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            card
            if let answer {
                Text(verbatim: answer)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A full-width "Show all" / "Show less" row, the terminal card's pattern.
struct ProtoExpandRow: View {
    @Binding var isExpanded: Bool
    let collapsedTitle: String
    var expandedTitle = "Show less"

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            Label {
                if isExpanded { Text(verbatim: expandedTitle) } else { Text(verbatim: collapsedTitle) }
            } icon: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")  // l10n:ignore: SF Symbol names
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

enum ProtoFormat {
    static func bytes(_ count: Int) -> String {
        count.formatted(.byteCount(style: .file))
    }

    static func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func directory(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    static func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and))
    }
}

// MARK: - Drawn placeholders (no network, no bundled images)

/// A screenshot of a desktop window, drawn: a title bar, a sidebar and content rows. `step` shifts the content so a
/// sequence of shots reads as progress.
struct ProtoScreenshot: View {
    var step = 0
    var highlight: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Color(white: 0.96)
                VStack(spacing: 0) {
                    HStack(spacing: 5) {
                        Circle().fill(Color.red.opacity(0.8)).frame(width: 7, height: 7)
                        Circle().fill(Color.yellow.opacity(0.9)).frame(width: 7, height: 7)
                        Circle().fill(Color.green.opacity(0.8)).frame(width: 7, height: 7)
                        Spacer()
                        RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.8)).frame(width: size.width * 0.3, height: 7)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 18)
                    .background(Color(white: 0.9))
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(0..<6, id: \.self) { row in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(row == step % 6 ? Color.blue.opacity(0.55) : Color(white: 0.78))
                                    .frame(width: size.width * 0.18, height: 6)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .frame(width: size.width * 0.26)
                        .background(Color(white: 0.92))
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.55))
                                .frame(width: size.width * 0.4, height: 9)
                            ForEach(0..<(4 + step % 3), id: \.self) { row in
                                RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.8))
                                    .frame(width: size.width * (row.isMultiple(of: 2) ? 0.55 : 0.45), height: 5)
                            }
                            if step >= 2 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue.opacity(0.75))
                                    .frame(width: size.width * 0.18, height: 14)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let highlight {
                    Circle()
                        .strokeBorder(Color.red, lineWidth: 2)
                        .frame(width: 18, height: 18)
                        .position(x: size.width * highlight.x, y: size.height * highlight.y)
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.separator), lineWidth: 0.5))
        .environment(\.colorScheme, .light)
        .accessibilityLabel(Text(verbatim: "Screenshot of the target window, step \(step)"))
    }
}
#endif
