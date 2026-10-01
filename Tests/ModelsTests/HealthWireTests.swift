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

    @Test func pleasantMoods() {
        #expect(MoodLabel.slightlyPleasant.isPleasant)
        #expect(!MoodLabel.neutral.isPleasant)
    }
}
