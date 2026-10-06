// Tests/HealthFeatureTests/PeriodReportPageTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

@MainActor
struct PeriodReportPageTests {
    static func report() -> PeriodReport {
        PeriodReport(
            PeriodReportReply(
                headline: "More sleep.", headlineHighlight: "More sleep", headlineCategory: "sleep",
                insights: [
                    .init(category: "sleep", title: "You slept 7 h 12 min.", highlights: ["7 h 12 min"]),
                    .init(category: "mood", title: "Calm month."),
                ],
                comparisons: [
                    .init(metric: "sleep", current: "7 h 12 min", previous: "6 h 47 min", direction: .up),
                    .init(metric: "weight", current: "70 kg", previous: "71 kg", direction: .down),
                ],
                nudge: "Walk after lunch."),
            period: PeriodReportWireTests.request.period, generatedAt: TestClock.now,
            current: PeriodReportWireTests.request.current, previous: PeriodReportWireTests.request.previous)
    }

    @Test func theStoryKeepsTheIdeaForAfterTheComparisons() {
        let story = PeriodReportView.story(Self.report())
        #expect(story.nudge == nil)
        #expect(story.headlineHighlight == "More sleep")
        #expect(ReportText.stories(story).map { $0.1.text } == ["You slept 7 h 12 min."])
    }

    @Test func comparisonsThisAppCannotNameAreLeftOut() {
        #expect(ComparisonsCard.rows(Self.report().comparisons).map { $0.0.metric } == ["sleep"])
    }

    @Test func aQuestionCarriesThePeriodItsNumbersAndWhatTheReportSaid() throws {
        let json = try #require(PeriodReportView.attachment(Self.report()))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect((object["period"] as? [String: Any])?["kind"] as? String == "month")
        #expect((object["current"] as? [String: Any])?["daysWithData"] as? Int == 28)
        #expect((object["previous"] as? [String: Any])?["daysWithData"] as? Int == 31)
        #expect(object["headline"] as? String == "More sleep.")
        #expect(object["insights"] as? [String] == ["You slept 7 h 12 min.", "Calm month."])
        // Chat's card reads a block with a category as a week block; this one is not.
        #expect(object["category"] == nil)
    }
}
