import Foundation
import Models
import NetworkingKit
import Observation
import SwiftUI
import UIKit

/// The app-wide accent: the computer's `settings.colorTone`, read at launch, on every return to the foreground and on
/// every Settings load, and changed live by the Color tone page. The last tone is remembered on the phone (it is not
/// a secret) so the app opens in it instead of flashing the default first.
@MainActor
@Observable
public final class ColorToneModel {
    public private(set) var tone: ColorTone

    private let defaults: UserDefaults
    private static let defaultsKey = "exodus.colorTone"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tone = ColorTone(stored: defaults.string(forKey: Self.defaultsKey))
        #if DEBUG
        if let override = Self.launchOverride { tone = override }
        #endif
    }

    public func apply(_ tone: ColorTone) {
        guard tone != self.tone else { return }
        self.tone = tone
        defaults.set(tone.rawValue, forKey: Self.defaultsKey)
    }

    /// Reads the tone from the computer; a failure (locked, unreachable, unpaired) keeps the current one.
    public func refresh(apiClient: APIClient) async {
        #if DEBUG
        if Self.launchOverride != nil { return }
        #endif
        guard let snapshot: SettingsSnapshot = try? await apiClient.get("/api/v1/settings") else { return }
        apply(ColorTone(stored: snapshot.colorTone))
    }

    #if DEBUG
    /// `-ColorTone violet`: screenshots of any gallery in a given tone.
    private static var launchOverride: ColorTone? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ColorTone"), index + 1 < arguments.count else { return nil }
        return ColorTone(rawValue: arguments[index + 1])
    }
    #endif
}

extension ColorTone {
    /// The tone as painted: neutral is the system accent as it is; every other tone is its system colour, in the
    /// variant that reads as text on this appearance's backgrounds (see `safeVariant`).
    public var uiColor: UIColor {
        guard let system = systemColor.map(Self.uiColor(for:)) else { return .systemBlue }
        return UIColor { traits in
            let standard = system.resolvedColor(with: traits)
            let accessible = system.resolvedColor(
                with: traits.modifyingTraits { $0.accessibilityContrast = .high })
            let backgrounds = [UIColor.systemBackground, .secondarySystemGroupedBackground]
                .map { Self.rgb($0.resolvedColor(with: traits)) }
            let safe = Self.safeVariant(standard: Self.rgb(standard), accessible: Self.rgb(accessible), on: backgrounds)
            return safe == Self.rgb(accessible) ? accessible : standard
        }
    }

    public var color: Color { Color(uiColor: uiColor) }

    /// What `.tint` gets: nothing for neutral, so every control keeps its system look (switches stay green).
    public var tint: Color? { self == .neutral ? nil : color }

    /// A glyph drawn on the accent, such as the send button's arrow.
    public var glyphColor: Color {
        let accent = uiColor
        return Color(
            uiColor: UIColor { traits in
                Self.glyphIsWhite(on: Self.rgb(accent.resolvedColor(with: traits))) ? .white : .black
            })
    }

    static func uiColor(for system: SystemColor) -> UIColor {
        switch system {
        case .blue: .systemBlue
        case .green: .systemGreen
        case .indigo: .systemIndigo
        case .pink: .systemPink
        case .orange: .systemOrange
        case .yellow: .systemYellow
        }
    }

    static func rgb(_ color: UIColor) -> RGB {
        var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGB(red: Double(red), green: Double(green), blue: Double(blue))
    }

    var title: LocalizedStringResource {
        switch self {
        case .neutral: LocalizedStringResource("settings:general.colorTone.tones.neutral")
        case .emerald: LocalizedStringResource("settings:general.colorTone.tones.emerald")
        case .blue: LocalizedStringResource("settings:general.colorTone.tones.blue")
        case .violet: LocalizedStringResource("settings:general.colorTone.tones.violet")
        case .rose: LocalizedStringResource("settings:general.colorTone.tones.rose")
        case .orange: LocalizedStringResource("settings:general.colorTone.tones.orange")
        case .yellow: LocalizedStringResource("settings:general.colorTone.tones.yellow")
        }
    }
}

extension View {
    /// Paints everything below in `tone`: tinted controls, links, selection and switches.
    public func colorTone(_ tone: ColorTone) -> some View {
        tint(tone.tint)
    }
}
