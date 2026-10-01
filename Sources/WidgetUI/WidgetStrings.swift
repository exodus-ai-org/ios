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

    /// "☾ 5:52 · 1,251 steps", or with the goal "☾ 5:52 · 1,251 / 8,000 steps"; nil when there is neither number.
    static func healthLine(_ health: HealthGlance, withGoal: Bool = false) -> String? {
        let sleep = health.sleepMinutes.map { "☾ " + String(format: "%d:%02d", $0 / 60, $0 % 60) }
        let steps = health.steps.map { $0.formatted(.number) }
        let goal = withGoal ? health.stepGoal.map { $0.formatted(.number) } : nil
        switch (sleep, steps, goal) {
        case let (sleep?, steps?, goal?):
            return String(
                localized: "ios:widget.health.lineGoal", defaultValue: "\(sleep) · \(steps) / \(goal) steps",
                bundle: .main,
                comment: "Lock Screen health line: sleep duration (h:mm), today's step count, then the daily step goal.")
        case let (sleep?, steps?, nil):
            return String(
                localized: "ios:widget.health.line", defaultValue: "\(sleep) · \(steps) steps",
                bundle: .main, comment: "Widget health line: sleep duration (h:mm), then today's step count.")
        case let (nil, steps?, _):
            return String(
                localized: "ios:widget.health.steps", defaultValue: "\(steps) steps",
                bundle: .main, comment: "Widget health line when only today's step count is known.")
        case let (sleep?, nil, _): return sleep
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
