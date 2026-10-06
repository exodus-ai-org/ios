// Tests/HealthFeatureTests/PeriodReportTextTests.swift
import Foundation
import Testing

@testable import HealthFeature

/// The English the catalog's keys fall back to.
struct PeriodReportTextTests {
    @Test func theHomeLineNamesThePeriod() {
        #expect(PeriodReportText.ready("September 2026") == "September 2026 report ready")
    }

    @Test func sparseDataAndWhatItWas() {
        #expect(PeriodReportText.daysWithData(21, of: 30) == "21 of 30 days had data")
        #expect(PeriodReportText.was("6h 47m") == "was 6h 47m")
    }

    @Test func eachKindHasItsEyebrowAndScope() {
        #expect(PeriodReport.Kind.allCases.map { String(localized: PeriodReportText.kind($0)) } == ["Weekly report", "Monthly report", "Quarterly report", "Yearly report"])
        #expect(PeriodReport.Kind.allCases.map(PeriodReportText.scope) == [.week, .month, .quarter, .year])
    }

    @Test func downIsBetterOnlyForTheRestingHeartRate() {
        #expect(PeriodReportText.isBetter(metric: "restingHr", direction: .down) == true)
        #expect(PeriodReportText.isBetter(metric: "restingHr", direction: .up) == false)
        #expect(PeriodReportText.isBetter(metric: "sleep", direction: .up) == true)
        #expect(PeriodReportText.isBetter(metric: "steps", direction: .down) == false)
        #expect(PeriodReportText.isBetter(metric: "hrv", direction: .flat) == nil)
    }

    @Test func onlyKnownMetricsAreNamed() {
        #expect(PeriodReportText.metric("restingHr")?.symbol == "heart.fill")
        #expect(PeriodReportText.metric("water")?.category == .body)
        #expect(PeriodReportText.metric("sleep")?.category == .sleep)
        #expect(PeriodReportText.metric("weight") == nil)
    }

    @Test func voiceOverReadsAComparison() throws {
        let down = PeriodReport.Comparison(metric: "restingHr", current: "59 bpm", previous: "61 bpm", direction: .down)
        #expect(PeriodReportText.spoken(down, title: try #require(PeriodReportText.metric("restingHr")).title) == "Resting heart rate, 59 bpm, Down, was 61 bpm")
        let flat = PeriodReport.Comparison(metric: "hrv", current: "44 ms", previous: nil, direction: .flat)
        #expect(PeriodReportText.spoken(flat, title: try #require(PeriodReportText.metric("hrv")).title) == "Heart rate variability, 44 ms, About the same")
    }
}
