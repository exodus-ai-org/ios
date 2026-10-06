// Tests/HealthFeatureTests/PeriodReportCardTests.swift
import Testing

@testable import HealthFeature

@MainActor
struct PeriodReportCardTests {
    @Test func theCalendarShowsAReportAWriteAndAWaitThatHasData() {
        #expect(PeriodReportCard.shows(.ready(PeriodReportPageTests.report()), hasData: false))
        #expect(PeriodReportCard.shows(.writing, hasData: true))
        #expect(PeriodReportCard.shows(.pending, hasData: true))
        #expect(!PeriodReportCard.shows(.pending, hasData: false))
        #expect(!PeriodReportCard.shows(.missing, hasData: true))
    }
}
