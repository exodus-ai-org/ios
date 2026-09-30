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
    static func scheme(_ traits: UITraitCollection) -> Scheme {
        traits.userInterfaceStyle == .dark ? .dark : .light
    }

    /// The tone as a surface or a shape (`fill`): the send button, a selected chip, a swatch. Drawn in Display P3,
    /// the phone's own space.
    public var uiColor: UIColor {
        UIColor { traits in Self.uiColor(displaying: self.fill(Self.scheme(traits))) }
    }

    /// The tone as text and glyphs on the page (`ink`): dark enough in light, light enough in dark, and more so
    /// under Increase Contrast. A fill is not an ink: yellow on white cannot be read.
    public var inkUIColor: UIColor {
        UIColor { traits in
            Self.uiColor(
                displaying: self.ink(Self.scheme(traits), increasedContrast: traits.accessibilityContrast == .high))
        }
    }

    static func uiColor(displaying color: OKLCH) -> UIColor {
        let p3 = color.components(in: .displayP3)
        return UIColor(displayP3Red: p3.red, green: p3.green, blue: p3.blue, alpha: 1)
    }

    public var color: Color { Color(uiColor: uiColor) }
    public var inkColor: Color { Color(uiColor: inkUIColor) }

    /// What `.tint` gets — the ink, since a tint colours links and button titles. Neutral's is black in light and
    /// near white in dark, as the desktop's default: nothing in a chat is the system's blue.
    public var tint: Color { inkColor }

    /// A glyph drawn on the fill, such as the send button's arrow.
    public var glyphColor: Color {
        Color(
            uiColor: UIColor { traits in
                let glyph = self.glyph(Self.scheme(traits))
                return UIColor(red: glyph.red, green: glyph.green, blue: glyph.blue, alpha: 1)
            })
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
