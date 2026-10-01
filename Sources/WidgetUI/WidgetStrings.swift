import Foundation
import OdyKit
import WidgetKitShared

enum WidgetStrings {
    static func greeting(_ period: WidgetPresentation.Period) -> LocalizedStringResource {
        switch period {
        case .morning: LocalizedStringResource("ios:widget.greeting.morning", bundle: .main)
        case .afternoon: LocalizedStringResource("ios:widget.greeting.afternoon", bundle: .main)
        case .evening: LocalizedStringResource("ios:widget.greeting.evening", bundle: .main)
        }
    }

    /// "☾ 5:52 · 1,251 steps"; nil when there is neither number.
    static func healthLine(_ health: HealthGlance) -> String? {
        let sleep = health.sleepMinutes.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }
        let steps = health.steps.map { $0.formatted(.number) }
        switch (sleep, steps) {
        case let (sleep?, steps?):
            return "☾ " + String(
                localized: "ios:widget.health.line", defaultValue: "\(sleep) · \(steps) steps",
                bundle: .main, comment: "Widget health line: sleep duration (h:mm), then today's step count.")
        case let (sleep?, nil): return "☾ " + sleep
        case let (nil, steps?): return steps
        default: return nil
        }
    }

    static func expression(_ mood: WidgetMood?) -> OdyExpression {
        switch mood {
        case .sleepy: .sleepy
        case .happy: .happy
        default: .content
        }
    }
}
