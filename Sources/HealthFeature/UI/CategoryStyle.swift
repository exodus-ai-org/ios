import Models
import OdyKit
import SwiftUI
import UIKit

/// How each category looks: the coloured scene cards of the approved home (layout A with C's colours), and the ink
/// the daily note writes it in.
struct CategoryStyle {
    let gradient: [Color]
    let ink: Color
    let title: LocalizedStringResource
    let systemImage: String
    /// The note's colour for this category, on a card: deepened in Light Mode and lightened in Dark Mode so a
    /// highlighted phrase stays readable on either surface.
    let accent: Color
    /// For the big things in the note (the headline's phrase, an insight's number).
    let accentGradient: [Color]
    /// The note's icon for this category.
    let symbol: String

    static func of(_ c: HealthCategory) -> CategoryStyle {
        switch c {
        case .sleep:
            CategoryStyle(
                gradient: [OdyPalette.hex(0x3D3480), OdyPalette.hex(0x6F5FD0)], ink: .white,
                title: LocalizedStringResource("ios:health.category.sleep", comment: "Sleep category title."),
                systemImage: "moon.zzz.fill",
                accent: .adaptive(0x6F5FD0, dark: 0xB9A3FF),
                accentGradient: [.adaptive(0x6F5FD0, dark: 0xA88BFF), .adaptive(0xA88BFF, dark: 0xD2C4FF)],
                symbol: "moon.zzz.fill")
        case .activity:
            CategoryStyle(
                gradient: [OdyPalette.hex(0xFFC23D), OdyPalette.hex(0xFF9A1A)], ink: OdyPalette.hex(0x3A2A00),
                title: LocalizedStringResource("ios:health.category.activity", comment: "Activity category title."),
                systemImage: "figure.walk",
                accent: .adaptive(0xE07B00, dark: 0xFFB340),
                accentGradient: [.adaptive(0xFF9A1A, dark: 0xFFB340), .adaptive(0xFFC23D, dark: 0xFFD98A)],
                symbol: "figure.walk")
        case .recovery:
            CategoryStyle(
                gradient: [OdyPalette.hex(0xFFB3C1), OdyPalette.hex(0xFF7E95)], ink: OdyPalette.hex(0x4A0F1C),
                title: LocalizedStringResource("ios:health.category.recovery", comment: "Heart & recovery category title."),
                systemImage: "heart.fill",
                accent: .adaptive(0xE8456B, dark: 0xFF8FA8),
                accentGradient: [.adaptive(0xFF5C8A, dark: 0xFF8FA8), .adaptive(0xFF9EB3, dark: 0xFFC2CF)],
                symbol: "heart.text.square.fill")
        case .body:
            CategoryStyle(
                gradient: [OdyPalette.hex(0xA8E6E0), OdyPalette.hex(0x4FC1C9)], ink: OdyPalette.hex(0x063A3E),
                title: LocalizedStringResource("ios:health.category.body", comment: "Body & mood category title."),
                systemImage: "drop.fill",
                accent: .adaptive(0x2A9BA6, dark: 0x6FD6DE),
                accentGradient: [.adaptive(0x2A9BA6, dark: 0x6FD6DE), .adaptive(0x4FC1C9, dark: 0xA8EEF2)],
                symbol: "drop.fill")
        }
    }
}

extension Color {
    /// One colour per appearance.
    static func adaptive(_ light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(OdyPalette.hex(dark)) : UIColor(OdyPalette.hex(light)) })
    }
}

extension OdyScene {
    init(hero mood: OdyMood) {
        switch mood {
        case .permission: self = .permission
        case .noData: self = .noData
        case .tired: self = .tired
        case .recovering: self = .recovering
        case .active: self = .active
        case .rested, .happy: self = .rested
        case .calm: self = .calm
        }
    }

    init(card category: HealthCategory, mood: OdyMood) {
        if mood == .noData {
            self = .noData
            return
        }
        switch category {
        case .sleep: self = mood == .tired ? .tired : .rested
        case .activity: self = .active
        case .recovery: self = mood == .recovering ? .recovering : .calm
        case .body: self = mood == .calm ? .calm : .hydrating
        }
    }
}

enum CategoryValue {
    static func text(_ c: HealthCategory, in s: HealthSnapshot) -> String? {
        switch c {
        case .sleep:
            guard let m = s.sleep?.asleepMin else { return nil }
            return Duration.seconds(m * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        case .activity:
            guard let steps = s.activity?.steps else { return nil }
            return String(
                localized: "ios:health.value.steps", defaultValue: "\(steps) steps",
                comment: "Card value: today's step count.")
        case .recovery:
            guard let r = s.recovery else { return nil }
            switch r.level {
            case .good:
                return String(
                    localized: "ios:health.value.recoveryGood", defaultValue: "Good",
                    comment: "Card value: recovery is good.")
            case .fair:
                return String(
                    localized: "ios:health.value.recoveryFair", defaultValue: "Fair",
                    comment: "Card value: recovery is fair.")
            case .low:
                return String(
                    localized: "ios:health.value.recoveryLow", defaultValue: "Low",
                    comment: "Card value: recovery is low.")
            case nil:
                guard let hr = r.restingHr, hr.isFinite else { return nil }
                let n = Int(hr)
                return String(
                    localized: "ios:health.value.bpm", defaultValue: "\(n) bpm",
                    comment: "Card value: resting heart rate.")
            }
        case .body:
            guard let cups = s.body?.waterCups else { return nil }
            return Self.cups(cups)
        }
    }

    static func cups(_ n: Int) -> String {
        String(
            localized: "ios:health.value.cups", defaultValue: "\(n) cups",
            comment: "Cups of water today (250 ml each).")
    }
}
