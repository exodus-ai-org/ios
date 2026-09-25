import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

@MainActor
@Suite("Profile")
struct ProfileViewModelTests {
    private static let usage = #"""
        {"totalCost":12.5,"totalTokens":1500000,"totalRequests":321,
         "daily":[{"date":"2026-09-20","cost":1,"tokens":1000},{"date":"2026-09-23","cost":2,"tokens":5000}],
         "models":[{"model":"a","provider":"anthropic","cost":9,"inputTokens":800,"outputTokens":200,"cacheReadTokens":5,"requests":10},
                   {"model":"b","provider":"openai","cost":3.5,"inputTokens":100,"outputTokens":50,"cacheReadTokens":0,"requests":2}]}
        """#
    private static let skills = #"""
        [{"slug":"pdf","displayName":"PDF","version":"1.0.0","isActive":true,"installPath":"/x","installedAt":1756000000000,"source":"skills.sh"},
         {"slug":"old","displayName":"Old","version":"0.1","isActive":false,"installPath":"/y","installedAt":1745000000000}]
        """#
    private static let failure = #"{"type":"error","error":{"code":"INTERNAL","message":"usage down"}}"#

    private func server(usage: [(Int, String)] = [(200, usage)]) -> SettingsPageTestServer {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/usage", usage)
        server.route("GET", "/api/v1/history", [(200, #"[{"id":"1","title":"x"},{"id":"2"},{"id":"3","title":null}]"#)])
        server.route("GET", "/api/v1/skills/installed", [(200, Self.skills)])
        return server
    }

    @Test("load() reads usage, the chat count and the skills, and writes nothing")
    func loadReadsEverything() async {
        let server = server()
        let vm = ProfileViewModel(apiClient: server.makeClient().0)
        await vm.load()
        #expect(vm.state == .loaded)
        #expect(vm.usage?.totalTokens == 1_500_000)
        #expect(vm.usage?.totalRequests == 321)
        #expect(vm.usage?.models.map(\.model) == ["a", "b"])
        #expect(vm.chatCount == 3)
        #expect(vm.skills?.count == 2)
        #expect(vm.activeSkillCount == 1)
        #expect(
            Set(server.requests(under: "/api/v1"))
                == ["GET /api/v1/usage", "GET /api/v1/history", "GET /api/v1/skills/installed"])
    }

    @Test("a failed usage read is an error state with the server's message; Retry recovers")
    func usageFailureThenRetry() async {
        let server = server(usage: [(500, Self.failure), (200, Self.usage)])
        let vm = ProfileViewModel(apiClient: server.makeClient().0)
        await vm.load()
        #expect(vm.state == .failed("usage down"))
        #expect(vm.stats == nil)
        await vm.load()
        #expect(vm.state == .loaded)
        #expect(vm.stats != nil)
    }

    @Test("a failed reload keeps the numbers on screen and reports the failure")
    func refreshFailureKeepsUsage() async {
        let server = server(usage: [(200, Self.usage), (500, Self.failure)])
        let vm = ProfileViewModel(apiClient: server.makeClient().0)
        await vm.load()
        await vm.load()
        #expect(vm.state == .loaded)
        #expect(vm.usage?.totalCost == 12.5)
        #expect(vm.refreshError == "usage down")
    }

    @Test("chats or skills that cannot be read leave their figures unknown, not zero")
    func sideFiguresFailSoftly() async {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/usage", [(200, Self.usage)])
        server.route("GET", "/api/v1/history", [(500, Self.failure)])
        server.route("GET", "/api/v1/skills/installed", [(500, Self.failure)])
        let vm = ProfileViewModel(apiClient: server.makeClient().0)
        await vm.load()
        #expect(vm.state == .loaded)
        #expect(vm.chatCount == nil)
        #expect(vm.skills == nil)
        #expect(vm.activeSkillCount == nil)
    }

    @Test("an account with no usage reads as empty")
    func emptyUsage() async {
        let server = server(usage: [(200, #"{"totalCost":0,"totalTokens":0,"totalRequests":0,"daily":[],"models":[]}"#)])
        let vm = ProfileViewModel(apiClient: server.makeClient().0)
        await vm.load()
        #expect(vm.usage?.isEmpty == true)
        #expect(vm.stats?.peakDay == 0)
        #expect(vm.stats?.currentStreak == 0)
    }
}

@Suite("Usage stats")
struct UsageStatsTests {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ text: String) -> Date {
        try! Date.ISO8601FormatStyle().parse(text + "T12:00:00Z")
    }

    @Test("peak, streaks, the 30-day window, its cost and the top five follow the desktop's Profile")
    func derivesDesktopFigures() {
        let usage = UsageSummary(
            daily: [
                .init(date: "2026-08-01", cost: 9, tokens: 900),
                .init(date: "2026-09-20", cost: 1, tokens: 100),
                .init(date: "2026-09-21", cost: 1, tokens: 300),
                .init(date: "2026-09-23", cost: 0.5, tokens: 50),
                .init(date: "2026-09-24", cost: 0.25, tokens: 25),
                .init(date: "2026-09-22", cost: 0, tokens: 0),
            ],
            models: (1...7).map { .init(model: "m\($0)") })
        let stats = UsageStats(usage: usage, today: Self.date("2026-09-24"), calendar: Self.utc)
        #expect(stats.peakDay == 900)
        #expect(stats.currentStreak == 2)
        #expect(stats.longestStreak == 2)
        #expect(stats.daily.count == 30)
        #expect(stats.daily.first?.date == Self.utc.startOfDay(for: Self.date("2026-08-26")))
        #expect(stats.daily.last?.tokens == 25)
        #expect(stats.daily.map(\.tokens).reduce(0, +) == 475)
        #expect(stats.cumulative.last?.tokens == 475)
        #expect(stats.cumulative.map(\.tokens) == stats.cumulative.map(\.tokens).sorted())
        #expect(stats.windowCost == 2.75)
        #expect(stats.topModels.map(\.model) == ["m1", "m2", "m3", "m4", "m5"])
    }

    @Test(
        "streaks: the longest run, and the latest one only while it reaches today or yesterday",
        arguments: [
            ([], 0, 0),
            ([10], 1, 1),
            ([9, 10], 2, 2),
            ([8, 9], 2, 2),
            ([7, 8], 0, 2),
            ([1, 2, 3, 4, 9, 10], 2, 4),
            ([10, 10, 9], 2, 2),
        ] as [([Int], Int, Int)])
    func streaks(days: [Int], current: Int, longest: Int) {
        let result = UsageStats.streaks(activeDays: days, today: 10)
        #expect(result.current == current)
        #expect(result.longest == longest)
    }

    @Test("a calendar date is the same day number in every time zone")
    func dayNumbers() {
        #expect(UsageStats.dayNumber("1970-01-02") == 1)
        #expect(UsageStats.dayNumber("2026-09-24")! - UsageStats.dayNumber("2026-09-23")! == 1)
        #expect(UsageStats.dayNumber("2026-03-01")! - UsageStats.dayNumber("2026-02-28")! == 1)
        #expect(UsageStats.dayNumber("nonsense") == nil)
    }

    @Test("tokens, cost and streaks are formatted for the locale")
    func formats() {
        let en = Locale(identifier: "en_US")
        let de = Locale(identifier: "de_DE")
        #expect(UsageFormat.tokens(950, locale: en) == "950")
        #expect(UsageFormat.tokens(1234, locale: en) == "1.2K")
        #expect(UsageFormat.tokens(48_250_000, locale: en) == "48.2M")
        #expect(UsageFormat.cost(0, locale: en) == "$0.00")
        #expect(UsageFormat.cost(0.0034, locale: en) == "$0.0034")
        #expect(UsageFormat.cost(1234.5, locale: en) == "$1,234.50")
        #expect(UsageFormat.cost(1234.5, locale: de).hasPrefix("1.234,50"))
        #expect(UsageFormat.days(3, locale: en) == "3d")
        #expect(UsageFormat.days(0, locale: en) == "0d")
    }

    @Test("the chart's spoken value is the whole count, grouped for the locale")
    func spokenTokens() {
        #expect(UsageFormat.spokenTokens(48_250_000, locale: Locale(identifier: "en_US")) == "48,250,000")
        #expect(UsageFormat.spokenTokens(1234.4, locale: Locale(identifier: "de_DE")) == "1.234")
    }
}
