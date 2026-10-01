import SwiftUI
import WidgetKit
import WidgetUI

struct AskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.yancey.exodus.ask", provider: SnapshotProvider()) { entry in
            AskWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("ios:widget.ask.title"))
        .description(Text("ios:widget.ask.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct AskWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Group {
            switch family {
            case .systemMedium: AskMediumView(snapshot: entry.snapshot, date: entry.date)
            default: AskSmallView(snapshot: entry.snapshot, date: entry.date)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) {
            // Accented and clear Home Screens draw no sky: text and Ody's outline only.
            if mode == .fullColor { WidgetSky(date: entry.date, calendar: .current) }
        }
    }
}
