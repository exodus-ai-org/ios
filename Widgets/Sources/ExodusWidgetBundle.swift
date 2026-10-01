import SwiftUI
import WidgetKit

@main
struct ExodusWidgetBundle: WidgetBundle {
    var body: some Widget {
        AskWidget()
        TodayAccessoryWidget()
        AskControl()
    }
}
