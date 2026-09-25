import Foundation
import Models
import NetworkingKit
import Observation

/// Settings → Profile: the desktop's `profile.tsx` read-only — usage totals, streaks and token activity from
/// `/api/v1/usage`, the chat count from `/api/v1/history`, and installed/active skills. Nothing is written.
@MainActor
@Observable
public final class ProfileViewModel {
    public enum State: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    public enum ActivityMode: String, CaseIterable, Identifiable, Sendable {
        case daily, cumulative
        public var id: Self { self }
    }

    public private(set) var state: State = .idle
    public private(set) var usage: UsageSummary?
    public private(set) var chatCount: Int?
    public private(set) var skills: [InstalledSkill]?
    /// A reload that failed while earlier numbers stay on screen.
    public private(set) var refreshError: String?
    public var mode: ActivityMode = .daily

    private let apiClient: APIClient
    private let now: @Sendable () -> Date

    public init(apiClient: APIClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.apiClient = apiClient
        self.now = now
    }

    public func load() async {
        if usage == nil { state = .loading }
        async let usageRequest: UsageSummary = apiClient.get("/api/v1/usage")
        async let chatsRequest: [Counted] = apiClient.get("/api/v1/history")
        async let skillsRequest: [InstalledSkill] = apiClient.get("/api/v1/skills/installed")
        do {
            usage = try await usageRequest
            state = .loaded
            refreshError = nil
        } catch {
            if usage == nil {
                state = .failed(error.localizedDescription)
            } else {
                refreshError = error.localizedDescription
            }
        }
        if let chats = try? await chatsRequest { chatCount = chats.count }
        if let installed = try? await skillsRequest { skills = installed }
    }

    public var stats: UsageStats? {
        usage.map { UsageStats(usage: $0, today: now(), calendar: .current) }
    }

    public var activeSkillCount: Int? { skills?.filter(\.isActive).count }

    /// An element of a list whose length is all that is needed.
    private struct Counted: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

/// What the desktop's Profile derives from the usage summary: peak day, streaks, and the activity series, here the
/// last `windowDays` days ending today (the desktop draws 52 weeks).
public struct UsageStats: Equatable, Sendable {
    public struct Point: Equatable, Identifiable, Sendable {
        public let date: Date
        public let tokens: Double
        public var id: Date { date }
    }

    public static let windowDays = 30
    public static let topModelCount = 5

    public let peakDay: Double
    public let currentStreak: Int
    public let longestStreak: Int
    public let daily: [Point]
    /// Running total over the same window, starting from zero as the desktop's does over its window.
    public let cumulative: [Point]
    public let topModels: [UsageSummary.ModelUsage]
    /// Cost of the days in the window.
    public let windowCost: Double

    public init(usage: UsageSummary, today: Date, calendar: Calendar) {
        var byDay: [String: UsageSummary.Day] = [:]
        for day in usage.daily {
            byDay[day.date, default: UsageSummary.Day(date: day.date, tokens: 0)].tokens += day.tokens
            byDay[day.date]?.cost += day.cost
        }
        peakDay = byDay.values.map(\.tokens).max().map { max(0, $0) } ?? 0

        let active = byDay.values.filter { $0.tokens > 0 }.compactMap { Self.dayNumber($0.date) }
        let todayNumber = Self.dayNumber(Self.dayString(today, calendar: calendar))
        (currentStreak, longestStreak) = Self.streaks(activeDays: active, today: todayNumber)

        let start = calendar.startOfDay(for: today)
        var daily: [Point] = []
        var cumulative: [Point] = []
        var running = 0.0
        var cost = 0.0
        for offset in stride(from: Self.windowDays - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { continue }
            let day = byDay[Self.dayString(date, calendar: calendar)]
            let tokens = day?.tokens ?? 0
            running += tokens
            cost += day?.cost ?? 0
            daily.append(Point(date: date, tokens: tokens))
            cumulative.append(Point(date: date, tokens: running))
        }
        self.daily = daily
        self.cumulative = cumulative
        windowCost = cost
        topModels = Array(usage.models.prefix(Self.topModelCount))
    }

    /// The desktop's `computeStreaks`: the longest run of consecutive active days, and the latest run when it
    /// reaches today or yesterday.
    static func streaks(activeDays: [Int], today: Int?) -> (current: Int, longest: Int) {
        let sorted = Set(activeDays).sorted()
        guard let first = sorted.first else { return (0, 0) }
        var longest = 1
        var run = 1
        var previous = first
        for day in sorted.dropFirst() {
            run = day - previous == 1 ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }
        guard let today, previous == today || previous == today - 1 else { return (0, longest) }
        return (run, longest)
    }

    /// Days since 1970 of a `YYYY-MM-DD` calendar date; the same date gives the same number in every time zone.
    static func dayNumber(_ text: String) -> Int? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let date = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return nil
        }
        return Int((date.timeIntervalSince1970 / 86_400).rounded())
    }

    /// `YYYY-MM-DD` of `date` in `calendar`'s time zone (the desktop's `format(new Date(), 'yyyy-MM-dd')`).
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Locale-aware number formats for usage figures.
public enum UsageFormat {
    /// `1.2K`, `3.4M`: the desktop's `compact()`, localized.
    public static func tokens(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
    }

    /// The whole count, grouped for the locale: VoiceOver reads `12,345` as a number, where `12K` reads as letters.
    public static func spokenTokens(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }

    /// US dollars; a sub-dollar amount keeps two significant digits so a cheap month does not read as $0.00.
    public static func cost(_ value: Double, locale: Locale = .current) -> String {
        if value > 0 && value < 1 {
            return value.formatted(.currency(code: "USD").precision(.significantDigits(1...2)).locale(locale))
        }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(locale))
    }

    /// `3d`: the desktop's streak label, localized.
    public static func days(_ count: Int, locale: Locale = .current) -> String {
        Duration.seconds(count * 86_400).formatted(
            Duration.UnitsFormatStyle(allowedUnits: [.days], width: .narrow, zeroValueUnits: .show(length: 1))
                .locale(locale))
    }
}
