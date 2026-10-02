// Sources/HealthFeature/Trends/DayToneStyle.swift
import OdyKit
import SwiftUI

extension DayTone {
    /// The cell's fill (style C): soft tints on the cream page, deeper ones in Dark Mode; the day's number in primary
    /// ink stays at 4.5:1 or more on each.
    var fill: Color {
        switch self {
        case .good: .adaptive(0xCFEFD8, dark: 0x2F6B54)
        case .tired: .adaptive(0xDDD6FF, dark: 0x4B3F9A)
        case .recovering: .adaptive(0xFFDDBF, dark: 0x8A5A2A)
        case .empty: .adaptive(0xF0EADB, dark: 0x24222C)
        }
    }

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

/// The ring's two colours: sleep's violet and activity's amber, deep enough to read on every tone's fill.
enum RingInk {
    static let sleep = Color.adaptive(0x6F5FD0, dark: 0xB9A3FF)
    static let steps = Color.adaptive(0xC96A00, dark: 0xF4B63F)
}

/// The corner ring: sleep against the target outside, steps against the goal inside. An arc with no number is only
/// its faint track.
struct CornerRing: View {
    let sleep: Double?
    let steps: Double?
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            arc(sleep, color: RingInk.sleep)
            arc(steps, color: RingInk.steps).padding(lineWidth * 1.6)
        }
        .accessibilityHidden(true)
    }

    private func arc(_ fraction: Double?, color: Color) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            if let fraction, fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
    }
}
