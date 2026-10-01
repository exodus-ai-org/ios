import Foundation
import Testing

@testable import Models

/// The same JSON as the desktop's tests/unit/shared/types/health.test.ts: both sides agree on the wire.
struct HealthWireTests {
    static let snapshotJSON = """
        {"date":"2026-10-01","localTime":"15:00","locale":"zh-Hant",
         "sleep":{"asleepMin":372,"baselineMin":425,"deepMin":52,"coreMin":209,"remMin":81,"awakeMin":30,"bedtime":"23:48","wake":"06:00"},
         "activity":{"steps":5840,"stepGoal":8000,"activeKcal":310,"kcalGoal":500,"exerciseMin":12,"standHours":6,"workouts":[]},
         "recovery":{"level":"low","hrvMs":38,"hrvBaselineMs":44,"restingHr":61,"restingHrBaseline":58,"respRate":14.2},
         "body":{"waterCups":3,"weightKg":null,"weightTrend30d":null,"mood":null},
         "odyState":"tired"}
        """
    static let summaryJSON = """
        {"headline":"有點沒睡飽","summary":"昨晚只睡了 **6 小時 12 分**。",
         "categories":{"sleep":"深睡偏少。","activity":"還差 2,160 步。","recovery":"HRV 偏低。","body":null},
         "memorySuggestion":{"section":"profile","key":"weekday-sleep","summary":"工作日平均只睡 6 小時左右"}}
        """

    /// The desktop's REPORT fixture as it leaves the route: the structured note, with `summary` filled in.
    static let storyJSON = """
        {"headline":"有點沒睡飽，記得多走走。","headlineHighlight":"有點沒睡飽","headlineCategory":"sleep",
         "insights":[
          {"category":"sleep","text":"昨晚只睡了 6 小時 12 分，比平時少了將近一小時。","highlights":["6 小時 12 分"],
           "stat":{"value":"6:12","unit":"小時","caption":"平時 7:05"}},
          {"category":"recovery","text":"HRV 38 ms，低於你的 44 基線，身體還在恢復。","highlights":["38 ms","身體還在恢復"]},
          {"category":"activity","text":"今天走了 5,840 步，離 8,000 的目標還差 2,160 步。","highlights":["5,840 步"],
           "stat":{"value":"5,840","unit":"步"}}],
         "nudge":"今晚早點上床，睡前少看螢幕。",
         "summary":"有點沒睡飽，記得多走走。\\n\\n昨晚只睡了 **6 小時 12 分**，比平時少了將近一小時。",
         "categories":{"sleep":"深睡偏少。","activity":"還差 2,160 步。","recovery":"HRV 偏低。","body":null},
         "memorySuggestion":null}
        """

    @Test func decodesTheSpecSnapshot() throws {
        let s = try JSONDecoder().decode(HealthSnapshot.self, from: Data(Self.snapshotJSON.utf8))
        #expect(s.sleep?.asleepMin == 372)
        #expect(s.recovery?.level == .low)
        #expect(s.body?.weightKg == nil)
        #expect(s.odyState == .tired)
    }

    @Test func roundTripsAndOmitsNothingItNeeds() throws {
        let s = try JSONDecoder().decode(HealthSnapshot.self, from: Data(Self.snapshotJSON.utf8))
        let data = try HealthWire.encoder().encode(s)
        let again = try JSONDecoder().decode(HealthSnapshot.self, from: data)
        #expect(again == s)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"odyState\":\"tired\""))
        #expect(!text.contains("weightKg"))  // nil is omitted, which the desktop's .nullish() accepts
    }

    @Test func decodesTheSpecSummary() throws {
        let r = try JSONDecoder().decode(HealthSummary.self, from: Data(Self.summaryJSON.utf8))
        #expect(r.categories.body == nil)
        #expect(r.memorySuggestion?.key == "weekday-sleep")
    }

    @Test func aSummaryWithoutSuggestionDecodes() throws {
        let json = Self.summaryJSON.replacingOccurrences(
            of: #""memorySuggestion":{"section":"profile","key":"weekday-sleep","summary":"工作日平均只睡 6 小時左右"}"#,
            with: #""memorySuggestion":null"#)
        let r = try JSONDecoder().decode(HealthSummary.self, from: Data(json.utf8))
        #expect(r.memorySuggestion == nil)
    }

    @Test func decodesTheStructuredNote() throws {
        let r = try JSONDecoder().decode(HealthSummary.self, from: Data(Self.storyJSON.utf8))
        #expect(r.headlineHighlight == "有點沒睡飽")
        #expect(r.headlineCategory == "sleep")
        #expect(r.insights?.count == 3)
        #expect(r.insights?.first?.highlights == ["6 小時 12 分"])
        #expect(r.insights?.first?.stat == .init(value: "6:12", unit: "小時", caption: "平時 7:05"))
        #expect(r.insights?[1].stat == nil)
        #expect(r.insights?[2].stat?.caption == nil)
        #expect(r.nudge == "今晚早點上床，睡前少看螢幕。")
    }

    @Test func anOldNoteDecodesWithoutTheStory() throws {
        let r = try JSONDecoder().decode(HealthSummary.self, from: Data(Self.summaryJSON.utf8))
        #expect(r.insights == nil)
        #expect(r.headlineHighlight == nil)
        #expect(r.nudge == nil)
        #expect(r.summary.contains("6 小時 12 分"))
    }

    @Test func theStoryRoundTrips() throws {
        let r = try JSONDecoder().decode(HealthSummary.self, from: Data(Self.storyJSON.utf8))
        let again = try JSONDecoder().decode(HealthSummary.self, from: HealthWire.encoder().encode(r))
        #expect(again == r)
    }

    @Test func anInsightWithoutHighlightsDecodes() throws {
        let json = #"{"category":"body","text":"Three cups so far."}"#
        let i = try JSONDecoder().decode(HealthSummary.Insight.self, from: Data(json.utf8))
        #expect(i.highlights.isEmpty)
    }

    @Test func pleasantMoods() {
        #expect(MoodLabel.slightlyPleasant.isPleasant)
        #expect(!MoodLabel.neutral.isPleasant)
    }
}
