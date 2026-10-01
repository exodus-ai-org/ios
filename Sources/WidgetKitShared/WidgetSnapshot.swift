import Foundation

/// The App Group the app and its widgets share.
public enum WidgetGroup {
    public static let identifier = "group.app.yancey.exodus"
}

/// Ody's face on a widget, decided by the app from the day.
public enum WidgetMood: String, Codable, Sendable {
    case sleepy, happy, neutral
}

public struct RecentChat: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var updatedAt: Date

    public init(id: String, title: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}

/// Today's health in a few numbers: what a widget may show of the day, never more.
public struct HealthGlance: Codable, Equatable, Sendable {
    /// The report's day, `yyyy-MM-dd`: a glance is shown only on that day.
    public var day: String
    public var sleepMinutes: Int?
    public var steps: Int?
    public var stepGoal: Int?
    public var headline: String?
    /// One question about the day, for the medium widget's chip.
    public var suggestion: String?
    public var mood: WidgetMood

    public init(
        day: String, sleepMinutes: Int?, steps: Int?, stepGoal: Int?, headline: String?, suggestion: String?,
        mood: WidgetMood
    ) {
        self.day = day
        self.sleepMinutes = sleepMinutes
        self.steps = steps
        self.stepGoal = stepGoal
        self.headline = headline
        self.suggestion = suggestion
        self.mood = mood
    }
}

/// What the widgets draw: written by the app, read by the extension. Titles and a few numbers, never a message.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    static let maxRecents = 3

    public var version: Int
    public var updatedAt: Date
    public var recentChats: [RecentChat]
    public var health: HealthGlance?

    public init(version: Int = currentVersion, updatedAt: Date, recentChats: [RecentChat], health: HealthGlance?) {
        self.version = version
        self.updatedAt = updatedAt
        self.recentChats = recentChats
        self.health = health
    }

    public static let empty = WidgetSnapshot(updatedAt: Date(timeIntervalSince1970: 0), recentChats: [], health: nil)

    /// Newest first, ties by id, one entry per chat: the same list always makes the same snapshot, so the app can
    /// tell an unchanged one and leave the widgets alone.
    public func updating(recents: [RecentChat], at date: Date) -> WidgetSnapshot {
        var copy = self
        var seen = Set<String>()
        copy.recentChats = Array(
            recents
                .map { RecentChat(id: $0.id, title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines), updatedAt: $0.updatedAt) }
                .filter { !$0.title.isEmpty }
                .sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id }
                .filter { seen.insert($0.id).inserted }
                .prefix(Self.maxRecents))
        copy.updatedAt = date
        return copy
    }

    public func updating(health: HealthGlance?, at date: Date) -> WidgetSnapshot {
        var copy = self
        copy.health = health
        copy.updatedAt = date
        return copy
    }

    /// Unpaired: nothing of the old computer stays on the Home Screen.
    public func cleared(at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(updatedAt: date, recentChats: [], health: nil)
    }
}

/// How the app's own types become a snapshot's, without the module knowing them.
public enum WidgetSnapshotRules {
    public static func recents(from chats: [(id: String, title: String, createdAt: String)]) -> [RecentChat] {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return chats.map { chat in
            let date = fractional.date(from: chat.createdAt) ?? plain.date(from: chat.createdAt) ?? .distantPast
            return RecentChat(id: chat.id, title: chat.title, updatedAt: date)
        }
    }
}
