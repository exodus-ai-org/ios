// Tests/HealthFeatureTests/HealthKitNamesTests.swift
import HealthKit
import Models
import Testing

@testable import HealthFeature

struct HealthKitNamesTests {
    @Test func workoutNames() {
        #expect(HealthKitSource.name(.running) == "running")
        #expect(HealthKitSource.name(.traditionalStrengthTraining) == "strength training")
        #expect(HealthKitSource.name(.cardioDance) == "dance")
        #expect(HealthKitSource.name(.archery) == "other")
    }

    @Test func moodClasses() {
        #expect(HealthKitSource.label(.veryUnpleasant) == .veryUnpleasant)
        #expect(HealthKitSource.label(.neutral) == .neutral)
        #expect(HealthKitSource.label(.slightlyPleasant) == .slightlyPleasant)
        #expect(HealthKitSource.label(.veryPleasant) == .veryPleasant)
    }
}
