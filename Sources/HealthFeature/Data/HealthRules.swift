// Sources/HealthFeature/Data/HealthRules.swift
import Foundation
import Models

public enum HealthCategory: String, CaseIterable, Sendable {
    case sleep, activity, recovery, body
}

/// The judgements the Health workspace makes on its own, so the illustration and the numbers never depend on the
/// model: baselines, recovery relative to the user's own normal (never a medical judgement), and which Ody to show.
enum HealthRules {
    static let minimumBaselineDays = 7
    /// Under 6.5 h is short sleep whatever the baseline.
    static let tiredFloorMin = 390

    /// The median of the trailing days, once there are at least a week of them.
    static func baseline(_ values: [Double]) -> Double? {
        guard values.count >= minimumBaselineDays else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Low when HRV is 12 % or more under its baseline or resting heart rate 7 % or more over; good when HRV is within
    /// 5 % under and resting heart rate within 3 % over; fair otherwise. Either pair alone decides; neither, no answer.
    static func recovery(hrv: Double?, hrvBaseline: Double?, restingHr: Double?, restingHrBaseline: Double?)
        -> RecoveryLevel?
    {
        func delta(_ value: Double?, _ base: Double?) -> Double? {
            guard let value, let base, base > 0 else { return nil }
            return (value - base) / base
        }
        let hrvDelta = delta(hrv, hrvBaseline)
        let rhrDelta = delta(restingHr, restingHrBaseline)
        guard hrvDelta != nil || rhrDelta != nil else { return nil }
        // Rounded to basis points so 88/100 is exactly −12 %.
        let h = hrvDelta.map { ($0 * 10_000).rounded() / 10_000 }
        let r = rhrDelta.map { ($0 * 10_000).rounded() / 10_000 }
        if (h ?? 0) <= -0.12 || (r ?? 0) >= 0.07 { return .low }
        if (h ?? 0) >= -0.05 && (r ?? 0) <= 0.03 { return .good }
        return .fair
    }

    static func isTired(_ sleep: HealthSnapshot.Sleep) -> Bool {
        if sleep.asleepMin < tiredFloorMin { return true }
        if let base = sleep.baselineMin, Double(sleep.asleepMin) < Double(base) * 0.85 { return true }
        return false
    }

    /// The hero's Ody: the first that applies.
    static func hero(_ s: HealthSnapshot, authorized: Bool) -> OdyMood {
        guard authorized else { return .permission }
        if s.sleep == nil && s.activity == nil && s.recovery == nil && s.body == nil { return .noData }
        if let sleep = s.sleep, isTired(sleep) { return .tired }
        if s.recovery?.level == .low { return .recovering }
        if s.activity?.reachedGoal == true { return .active }
        if let sleep = s.sleep, let base = sleep.baselineMin, sleep.asleepMin >= base, s.recovery?.level == .good {
            return .rested
        }
        if s.body?.mood?.isPleasant == true { return .calm }
        return .happy
    }

    /// A category card's own Ody.
    static func card(_ category: HealthCategory, in s: HealthSnapshot) -> OdyMood {
        switch category {
        case .sleep:
            guard let sleep = s.sleep else { return .noData }
            return isTired(sleep) ? .tired : .rested
        case .activity:
            guard let activity = s.activity else { return .noData }
            return activity.reachedGoal ? .active : .happy
        case .recovery:
            guard let recovery = s.recovery else { return .noData }
            switch recovery.level {
            case .low: return .recovering
            case .good: return .rested
            case .fair, nil: return .happy
            }
        case .body:
            guard let body = s.body else { return .noData }
            return body.mood?.isPleasant == true ? .calm : .happy
        }
    }
}
