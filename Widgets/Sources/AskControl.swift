import SwiftUI
import WidgetKit
import WidgetKitShared

struct AskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.yancey.exodus.ask-control") {
            ControlWidgetButton(action: AskExodusIntent()) {
                Label("ios:widget.ask.title", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .displayName("ios:widget.ask.title")
    }
}
