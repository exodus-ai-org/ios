// Sources/HealthFeature/Trends/DayRecord.swift
import Foundation
import Models

/// One day's numbers as the calendar and the trends read them (and, later, the habits): computed on the phone from
/// Apple Health for any day, never sent anywhere by itself. A number the day doesn't have is `nil`, so an average
/// skips it instead of counting a zero.
public struct DayRecord: Equatable, Sendable {
    /// The day's start, in the calendar it was read with.
    public var day: Date
    public var sleepMin: Int?
    public var steps: Int?
    public var stepGoal: Int
    public var exerciseMin: Int?
    public var hrvMs: Double?
    public var restingHr: Double?
    public var waterCups: Int?
    /// When the night that ended on this day began, "HH:mm".
    public var bedtime: String?
    /// The day's Ody, by the same rules as the home's.
    public var mood: OdyMood

    public init(
        day: Date, sleepMin: Int? = nil, steps: Int? = nil, stepGoal: Int = 8000, exerciseMin: Int? = nil,
        hrvMs: Double? = nil, restingHr: Double? = nil, waterCups: Int? = nil, bedtime: String? = nil,
        mood: OdyMood = .noData
    ) {
        self.day = day
        self.sleepMin = sleepMin
        self.steps = steps
        self.stepGoal = stepGoal
        self.exerciseMin = exerciseMin
        self.hrvMs = hrvMs
        self.restingHr = restingHr
        self.waterCups = waterCups
        self.bedtime = bedtime
        self.mood = mood
    }

    /// The record of a built day. No cups is no water logged, not zero water.
    init(day: Date, snapshot s: HealthSnapshot, stepGoal: Int) {
        self.init(
            day: day, sleepMin: s.sleep?.asleepMin, steps: s.activity?.steps,
            stepGoal: s.activity?.stepGoal ?? stepGoal, exerciseMin: s.activity?.exerciseMin,
            hrvMs: s.recovery?.hrvMs, restingHr: s.recovery?.restingHr,
            waterCups: s.body.flatMap { $0.waterCups > 0 ? $0.waterCups : nil }, bedtime: s.sleep?.bedtime,
            mood: s.odyState)
    }

    public var hasData: Bool {
        sleepMin != nil || steps != nil || exerciseMin != nil || hrvMs != nil || restingHr != nil || waterCups != nil
    }

    /// The corner ring's outer arc: the night against the sleep target, full at or past it.
    public var sleepFraction: Double? {
        sleepMin.map { min(Double($0) / Double(TrendMath.sleepTargetMin), 1) }
    }

    /// The inner arc: steps against the day's goal.
    public var stepFraction: Double? {
        steps.map { stepGoal > 0 ? min(Double($0) / Double(stepGoal), 1) : 0 }
    }
}

/// A calendar cell's colour (style C): what kind of day it was, read from the day's Ody.
enum DayTone: CaseIterable, Equatable, Sendable {
    case good, tired, recovering, empty

    init(_ mood: OdyMood) {
        switch mood {
        case .active, .rested, .calm, .happy: self = .good
        case .tired: self = .tired
        case .recovering: self = .recovering
        case .noData, .permission: self = .empty
        }
    }
}
