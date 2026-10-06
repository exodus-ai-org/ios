// Tests/HealthFeatureTests/PeriodReportWireTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

/// The period report on the wire, held to the desktop's fixtures (`tests/unit/shared/types/health-period-fixtures.ts`
/// in the desktop repo: `PERIOD_REQUEST`, and `PERIOD_REPORT` with the period the route adds).
struct PeriodReportWireTests {
    static let cal = TestClock.calendar

    static func m(_ a: Double?, _ lo: Double?, _ hi: Double?, _ d: Int) -> MetricSummary {
        MetricSummary(average: a, min: lo, max: hi, days: d)
    }

    static let request = PeriodReportRequest(
        period: .init(kind: .month, start: "2026-09-01", end: "2026-09-30"),
        current: Aggregates(
            elapsedDays: 30, daysWithData: 28, sleepMin: m(432, 350, 510, 28), steps: m(7040, 2100, 13200, 28),
            exerciseMin: m(24, 0, 75, 28), hrvMs: m(44, 31, 58, 27), restingHr: m(59, 55, 64, 27),
            waterCups: m(nil, nil, nil, 0), stepGoalRate: 0.32, sleepTargetRate: 0.6),
        previous: Aggregates(
            elapsedDays: 31, daysWithData: 31, sleepMin: m(407, 330, 480, 31), steps: m(8000, 3100, 15000, 31),
            exerciseMin: m(24, 0, 60, 31), hrvMs: m(43, 30, 55, 31), restingHr: m(61, 57, 66, 31),
            waterCups: m(nil, nil, nil, 0), stepGoalRate: 0.45, sleepTargetRate: 0.42),
        notes: [
            .init(
                day: "2026-09-15", headline: "A little under-slept, so take it easy.",
                insights: [
                    .init(
                        category: "sleep",
                        title: "You slept 5 h 52 min last night, about half an hour less than usual.")
                ])
        ],
        habits: [], locale: "en")

    static let desktopRequest = #"""
        {"period":{"kind":"month","start":"2026-09-01","end":"2026-09-30"},
         "current":{"elapsedDays":30,"daysWithData":28,"sleepMin":{"average":432,"min":350,"max":510,"days":28},
           "steps":{"average":7040,"min":2100,"max":13200,"days":28},"exerciseMin":{"average":24,"min":0,"max":75,"days":28},
           "hrvMs":{"average":44,"min":31,"max":58,"days":27},"restingHr":{"average":59,"min":55,"max":64,"days":27},
           "waterCups":{"days":0},"stepGoalRate":0.32,"sleepTargetRate":0.6},
         "previous":{"elapsedDays":31,"daysWithData":31,"sleepMin":{"average":407,"min":330,"max":480,"days":31},
           "steps":{"average":8000,"min":3100,"max":15000,"days":31},"exerciseMin":{"average":24,"min":0,"max":60,"days":31},
           "hrvMs":{"average":43,"min":30,"max":55,"days":31},"restingHr":{"average":61,"min":57,"max":66,"days":31},
           "waterCups":{"days":0},"stepGoalRate":0.45,"sleepTargetRate":0.42},
         "notes":[{"day":"2026-09-15","headline":"A little under-slept, so take it easy.",
           "insights":[{"category":"sleep","title":"You slept 5 h 52 min last night, about half an hour less than usual."}]}],
         "habits":[],"locale":"en"}
        """#

    static let desktopReply = #"""
        {"period":{"kind":"month","start":"2026-09-01","end":"2026-09-30"},
         "headline":"More sleep, fewer steps than in August.","headlineHighlight":"More sleep","headlineCategory":"sleep",
         "insights":[
           {"category":"sleep","title":"You slept 7 h 12 min a night on average, 25 minutes more than in August.",
            "highlights":["7 h 12 min","25 minutes more"],"stat":{"value":"7:12","unit":"hr","caption":"August 6:47"}},
           {"category":"activity","title":"Daily steps fell 12 % to 7,040; you reached your goal on 9 of 28 days.",
            "highlights":["fell 12 %","9 of 28 days"],"stat":{"value":"7,040","unit":"steps","caption":"August 8,000"}},
           {"category":"recovery","title":"Resting heart rate eased to 59 bpm from 61, and HRV held at 44 ms.",
            "highlights":["59 bpm"]}],
         "comparisons":[{"metric":"sleep","current":"7 h 12 min","previous":"6 h 47 min","direction":"up"},
           {"metric":"steps","current":"7,040","previous":"8,000","direction":"down"},
           {"metric":"hrv","current":"44 ms","previous":"43 ms","direction":"flat"},
           {"metric":"restingHr","current":"59 bpm","previous":"61 bpm","direction":"down"}],
         "nudge":"Take a short walk after lunch on workdays."}
        """#

    static func reply() throws -> PeriodReportReply {
        try JSONDecoder().decode(PeriodReportReply.self, from: Data(desktopReply.utf8))
    }

    @Test func aRequestEncodesAsTheDesktopReadsIt() throws {
        let mine = try JSONSerialization.jsonObject(with: HealthWire.encoder().encode(Self.request)) as? NSDictionary
        let theirs = try JSONSerialization.jsonObject(with: Data(Self.desktopRequest.utf8)) as? NSDictionary
        #expect(mine != nil)
        #expect(mine == theirs)
    }

    @Test func aReplyReadsAsTheDesktopWritesIt() throws {
        let reply = try Self.reply()
        #expect(reply.headline == "More sleep, fewer steps than in August.")
        #expect(reply.headlineHighlight == "More sleep")
        #expect(reply.headlineCategory == "sleep")
        #expect(reply.insights.count == 3)
        #expect(reply.insights[0].highlights == ["7 h 12 min", "25 minutes more"])
        #expect(reply.insights[2].stat == nil)
        #expect(reply.comparisons.map(\.direction) == [.up, .down, .flat, .down])
        #expect(reply.nudge == "Take a short walk after lunch on workdays.")
    }

    @Test func missingListsAreEmptyAndAnUnknownDirectionIsLevel() throws {
        let json = #"{"headline":"h","comparisons":[{"metric":"sleep","current":"7h","direction":"sideways"}]}"#
        let reply = try JSONDecoder().decode(PeriodReportReply.self, from: Data(json.utf8))
        #expect(reply.insights.isEmpty)
        #expect(reply.comparisons == [.init(metric: "sleep", current: "7h", previous: nil, direction: .flat)])
    }

    @Test func aSpanNamesThePeriodsFirstAndLastDay() {
        let cal = Self.cal
        let september = Period.containing(TestClock.date(2026, 9, 15), .month, calendar: cal)
        #expect(PeriodReport.Span(september, calendar: cal) == .init(kind: .month, start: "2026-09-01", end: "2026-09-30"))
        let week53 = Period.containing(TestClock.date(2027, 1, 1), .week, calendar: cal)
        #expect(PeriodReport.Span(week53, calendar: cal) == .init(kind: .week, start: "2026-12-28", end: "2027-01-03"))
        #expect(PeriodReport.Span(Period.containing(TestClock.now, .days(7), calendar: cal), calendar: cal) == nil)
    }

    @Test func aKeptReportRoundTrips() throws {
        let report = PeriodReport(
            try Self.reply(), period: Self.request.period, generatedAt: TestClock.now, current: Self.request.current,
            previous: Self.request.previous)
        let data = try HealthWire.encoder().encode(report)
        #expect(try JSONDecoder().decode(PeriodReport.self, from: data) == report)
    }

    @Test func theStoryIsTheDailyNotesShape() throws {
        let reply = try Self.reply()
        let story = PeriodReport(
            reply, period: Self.request.period, generatedAt: TestClock.now, current: Self.request.current,
            previous: nil
        ).story
        #expect(story.headline == reply.headline)
        #expect(story.headlineCategory == "sleep")
        #expect(story.insights?.map(\.text) == reply.insights.map(\.title))
        #expect(story.nudge == reply.nudge)
        #expect(ReportText.stories(story).count == 3)
    }
}
