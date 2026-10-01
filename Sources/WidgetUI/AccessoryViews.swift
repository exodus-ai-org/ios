import OdyKit
import SwiftUI
import WidgetKit
import WidgetKitShared

/// Lock Screen, circular: Ody's outline; a tap starts a chat.
public struct AskCircularView: View {
    public init() {}

    public var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            OdyBodyShape().stroke(lineWidth: 2.5).frame(width: 24, height: 27).widgetAccentable()
        }
        .widgetURL(DeepLink.newChat(prompt: nil).url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ios:widget.ask.title", bundle: .main))
    }
}

/// Lock Screen, rectangular: the note's headline and today's numbers → Health; without today's note, "Ask Exodus".
public struct TodayRectangularView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let calendar: Calendar

    public init(snapshot: WidgetSnapshot, date: Date, calendar: Calendar = .current) {
        self.snapshot = snapshot
        self.date = date
        self.calendar = calendar
    }

    public var body: some View {
        if let health = WidgetPresentation.health(of: snapshot, at: date, calendar: calendar),
            let headline = health.headline
        {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: headline).font(.headline).lineLimit(1).widgetAccentable()
                if let line = WidgetStrings.healthLine(health, withGoal: true) {
                    Text(verbatim: line).font(.caption).lineLimit(2).privacySensitive()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.health(ask: nil).url)
        } else {
            Label {
                Text("ios:widget.ask.title", bundle: .main).lineLimit(1)
            } icon: {
                OdyBodyShape().stroke(lineWidth: 2).frame(width: 14, height: 16)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.newChat(prompt: nil).url)
        }
    }
}
