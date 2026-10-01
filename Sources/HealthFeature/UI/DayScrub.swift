// Sources/HealthFeature/UI/DayScrub.swift
import Foundation
import Models
import OdyKit

/// The hero's time scrub, in hours from today's midnight: from 18:00 yesterday (−6) to now. Dragging right goes back
/// in time; a hero's width is about ten hours. Past either end the hour resists (rubber band); a release carries on with
/// the finger's momentum (Apple's projection) and lands within the range, snapping to now when it lands near it.
struct DayScrub: Equatable {
    static let hoursPerWidth = 10.0
    static let snapToNow = 0.25
    let start: Double = -6
    let now: Double

    init(now: Date, calendar: Calendar) {
        let midnight = calendar.startOfDay(for: now)
        self.now = now.timeIntervalSince(midnight) / 3600
    }

    func hour(from startHour: Double, translation: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return startHour }
        var h = startHour - Double(translation / width) * Self.hoursPerWidth
        if h > now { h = now + Self.rubber(h - now, 4) }
        if h < start { h = start - Self.rubber(start - h, 4) }
        return h
    }

    func release(at hour: Double, velocity: CGFloat, width: CGFloat, reduceMotion: Bool) -> Double {
        let hoursPerSecond = width > 0 ? -Double(velocity / width) * Self.hoursPerWidth : 0
        let projected = reduceMotion ? hour : hour + Self.project(hoursPerSecond)
        let landed = min(max(projected, start), now)
        return now - landed < Self.snapToNow ? now : landed
    }

    func isScrubbing(_ hour: Double) -> Bool { abs(hour - now) > 0.05 }

    static func rubber(_ overshoot: Double, _ dimension: Double, constant: Double = 0.55) -> Double {
        (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }

    static func project(_ velocity: Double, deceleration d: Double = 0.998) -> Double {
        velocity / 1000 * d / (1 - d)
    }
}

/// What Ody is doing at an hour of the scrub.
struct HeroPose: Equatable {
    var expression: OdyExpression
    var tiredness: CGFloat
    var tilt: Double
    var sink: CGFloat
    var asleep: Bool
    var stage: SleepStage?

    static func stage(at hour: Double, night: SleepNight?, today: Date) -> SleepStage? {
        guard let night else { return nil }
        let date = today.addingTimeInterval(hour * 3600)
        return night.stages.first { $0.start <= date && date < $0.end }?.stage
    }

    static func at(hour: Double, scrub: DayScrub, mood: OdyMood, night: SleepNight?, today: Date) -> HeroPose {
        let stage = stage(at: hour, night: night, today: today)
        if let stage, stage.isAsleep, scrub.isScrubbing(hour) {
            let sink: CGFloat = stage == .deep ? 9 : stage == .core || stage == .unspecified ? 4 : 2
            return HeroPose(expression: .sleepy, tiredness: 0, tilt: -10, sink: sink, asleep: true, stage: stage)
        }
        guard !scrub.isScrubbing(hour) else {
            return HeroPose(expression: .happy, tiredness: 0, tilt: 0, sink: 0, asleep: false, stage: stage)
        }
        let expression: OdyExpression
        switch mood {
        case .tired, .happy, .permission: expression = .happy
        case .recovering: expression = .down
        case .active, .rested: expression = .grin
        case .calm: expression = .content
        case .noData: expression = .curious
        }
        return HeroPose(
            expression: expression, tiredness: mood == .tired ? 1 : 0, tilt: 0, sink: 0, asleep: false, stage: nil)
    }
}
