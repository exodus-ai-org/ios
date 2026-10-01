import OdyKit
import SwiftUI
import WidgetKit
import WidgetKitShared

/// Home Screen, medium: on the left, today's numbers, two questions to start from and the Ask capsule; on the
/// right, the latest chats, each opening its own.
public struct AskMediumView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let calendar: Calendar

    public init(snapshot: WidgetSnapshot, date: Date, calendar: Calendar = .current) {
        self.snapshot = snapshot
        self.date = date
        self.calendar = calendar
    }

    public var body: some View {
        let health = WidgetPresentation.health(of: snapshot, at: date, calendar: calendar)
        let ink = WidgetInk.color(at: date, calendar: calendar)
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    if let health, let line = WidgetStrings.healthLine(health) {
                        Text(verbatim: line).font(.caption2.weight(.semibold)).foregroundStyle(ink.opacity(0.8))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .privacySensitive()
                    }
                    if let suggestion = health?.suggestion {
                        Link(destination: DeepLink.health(ask: suggestion).url) {
                            Chip(text: suggestion, ink: ink, fill: OdyPalette.marigold.opacity(0.22)).privacySensitive()
                        }
                    }
                    let planDay = String(
                        localized: "ios:widget.chip.planDay", defaultValue: "Plan my day", bundle: .main,
                        comment: "Medium widget chip; tapping it opens a new chat pre-filled with this text.")
                    Link(destination: DeepLink.newChat(prompt: planDay).url) {
                        Chip(text: planDay, ink: ink, fill: ink.opacity(0.12))
                    }
                    Spacer(minLength: 0)
                    Link(destination: DeepLink.newChat(prompt: nil).url) { AskCapsule(ink: ink) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RecentColumn(chats: snapshot.recentChats, ink: ink)
                    .frame(width: proxy.size.width * 0.44, alignment: .leading)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .widgetURL(DeepLink.newChat(prompt: nil).url)
    }
}

/// A question to start from, cut to one line.
private struct Chip: View {
    let text: String
    let ink: Color
    let fill: Color

    var body: some View {
        Text(verbatim: text).font(.caption).foregroundStyle(ink).lineLimit(1)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(fill, in: .rect(cornerRadius: 12))
    }
}

private struct RecentColumn: View {
    let chats: [RecentChat]
    let ink: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ios:widget.recent.title", bundle: .main).font(.caption2.weight(.semibold))
                .foregroundStyle(ink.opacity(0.6)).lineLimit(1)
                .padding(.bottom, 4)
            if chats.isEmpty {
                Text("ios:widget.recent.empty", bundle: .main).font(.caption).foregroundStyle(ink.opacity(0.6))
                    .lineLimit(2)
            } else {
                ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                    if index > 0 { Divider().overlay(ink.opacity(0.12)) }
                    Link(destination: DeepLink.chat(id: chat.id).url) {
                        // The time keeps its width; the title gives way.
                        HStack(spacing: 6) {
                            Text(verbatim: chat.title).font(.caption.weight(.semibold)).foregroundStyle(ink)
                                .lineLimit(1).privacySensitive()
                            Spacer(minLength: 0)
                            Text(chat.updatedAt, format: .relative(presentation: .named))
                                .font(.caption2).foregroundStyle(ink.opacity(0.55))
                                .lineLimit(1).fixedSize()
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }
}
