// Sources/HealthFeature/Trends/DayToneStyle.swift
import SwiftUI

extension DayTone {
    /// What the colour means, for the legend and VoiceOver.
    var name: LocalizedStringResource {
        switch self {
        case .good: LocalizedStringResource("ios:health.calendar.tone.good", defaultValue: "Rested or active", comment: "Calendar day colour and legend: a good day (rested, active or calm).")
        case .tired: LocalizedStringResource("ios:health.calendar.tone.tired", defaultValue: "Short on sleep", comment: "Calendar day colour and legend: a day after too little sleep.")
        case .recovering: LocalizedStringResource("ios:health.calendar.tone.recovering", defaultValue: "Recovering", comment: "Calendar day colour and legend: a day with low recovery (HRV under the usual).")
        case .empty: LocalizedStringResource("ios:health.calendar.tone.empty", defaultValue: "No data", comment: "Calendar day colour and legend: Apple Health has nothing for the day.")
        }
    }
}
