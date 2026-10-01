import OdyKit
import SwiftUI
import WidgetKit
import WidgetKitShared

/// Home Screen, small: today's numbers, a greeting beside Ody, and the Ask capsule; a tap anywhere starts a chat.
public struct AskSmallView: View {
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
        VStack(alignment: .leading, spacing: 6) {
            if let health, let line = WidgetStrings.healthLine(health) {
                Text(verbatim: line).font(.caption2.weight(.semibold)).foregroundStyle(ink.opacity(0.8))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .privacySensitive()
            }
            // Side by side, so Ody never sits on the words; each line shrinks rather than wrap, so the greeting
            // reads as two lines.
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WidgetStrings.greeting(WidgetPresentation.period(at: date, calendar: calendar)))
                        .lineLimit(1)
                    Text("ios:widget.greeting.question", bundle: .main)
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ink)
                .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                WidgetOdy(expression: WidgetStrings.expression(health?.mood))
                    .frame(width: 48, height: 54)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            AskCapsule(ink: ink)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .widgetURL(DeepLink.newChat(prompt: nil).url)
    }
}

/// "Ask Exodus…" with the marigold send glyph.
struct AskCapsule: View {
    let ink: Color

    var body: some View {
        HStack {
            Text("ios:widget.ask.placeholder", bundle: .main).font(.footnote).foregroundStyle(ink.opacity(0.75))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Image(systemName: "arrow.up").font(.caption.weight(.bold)).foregroundStyle(.black.opacity(0.8))
                .frame(width: 22, height: 22).background(OdyPalette.marigold, in: .circle)
                .accessibilityHidden(true)
        }
        .padding(.leading, 10).padding(.trailing, 4).frame(height: 30)
        .background(ink.opacity(0.16), in: .capsule)
    }
}
