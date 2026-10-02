import Foundation
import Models

/// The composer's `+` strings that code puts together; the views use the other keys as literals.
enum ComposerText {
    static func level(_ level: ReasoningEffort) -> String {
        switch level {
        case .off:
            String(localized: "ios:chat.composer.level.off", defaultValue: "Off", comment: "Reasoning level: no reasoning.")
        case .low:
            String(localized: "ios:chat.composer.level.low", defaultValue: "Low", comment: "Reasoning level: low effort.")
        case .medium:
            String(
                localized: "ios:chat.composer.level.medium", defaultValue: "Medium",
                comment: "Reasoning level: medium effort.")
        case .high:
            String(localized: "ios:chat.composer.level.high", defaultValue: "High", comment: "Reasoning level: high effort.")
        case .xhigh:
            String(
                localized: "ios:chat.composer.level.xhigh", defaultValue: "Extra high",
                comment: "Reasoning level: above high.")
        case .max:
            String(
                localized: "ios:chat.composer.level.max", defaultValue: "Max",
                comment: "Reasoning level: the most the model allows.")
        }
    }

    static func reasoningPill(_ level: ReasoningEffort) -> String {
        let name = Self.level(level)
        return String(
            localized: "ios:chat.composer.reasoningPill", defaultValue: "Reasoning: \(name)",
            comment: "Pill over the message field while a reasoning level is on. %@ is the level, e.g. High.")
    }

    static func removePicture(_ position: Int, of count: Int) -> String {
        String(
            localized: "ios:chat.composer.removePicture", defaultValue: "Remove picture \(position) of \(count)",
            comment: "VoiceOver label of the ✕ on a picture waiting in the composer.")
    }

    static func unreadable(_ count: Int) -> String {
        if count == 1 {
            return String(
                localized: "ios:chat.composer.unreadableOne", defaultValue: "A picture couldn’t be read and was left out.",
                comment: "Banner over the composer: one picked picture could not be read.")
        }
        return String(
            localized: "ios:chat.composer.unreadableSome",
            defaultValue: "\(count) pictures couldn’t be read and were left out.",
            comment: "Banner over the composer: several picked pictures could not be read. %lld is how many.")
    }

    static func noDescription(_ name: String) -> String {
        String(
            localized: "ios:chat.composer.mcpSheet.noDescription", defaultValue: "No description for \(name).",
            comment: "MCP tools sheet: a tool its server gave no description. %@ is the tool's name.")
    }
}
