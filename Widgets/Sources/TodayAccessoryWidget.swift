import SwiftUI
import WidgetKit
import WidgetUI

struct TodayAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.yancey.exodus.today", provider: SnapshotProvider()) { entry in
            TodayAccessoryView(entry: entry).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(Text("ios:widget.ask.title"))
        .description(Text("ios:widget.today.description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct TodayAccessoryView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular: TodayRectangularView(snapshot: entry.snapshot, date: entry.date)
        default: AskCircularView()
        }
    }
}
