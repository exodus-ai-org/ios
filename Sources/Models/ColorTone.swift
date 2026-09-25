import Foundation

/// `settings.colorTone` (the desktop's `ColorToneSchema`): the accent the whole app is painted in. The column is
/// plain text on the desktop, so anything it does not know, or no value at all, reads as `neutral`, as there.
/// The phone stores the same values but paints each in an iOS system colour, not the desktop's exact shade.
public enum ColorTone: String, CaseIterable, Sendable, Identifiable {
    case neutral, emerald, blue, violet, rose, orange, yellow

    public var id: String { rawValue }

    public init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .neutral
    }

    /// The iOS system colours a tone can be painted in.
    public enum SystemColor: Sendable {
        case blue, green, indigo, pink, orange, yellow
    }

    /// `nil` for neutral: the system's own default accent, untouched.
    public var systemColor: SystemColor? {
        switch self {
        case .neutral: nil
        case .emerald: .green
        case .blue: .blue
        case .violet: .indigo
        case .rose: .pink
        case .orange: .orange
        case .yellow: .yellow
        }
    }

    /// sRGB components, gamma-encoded, each 0…1.
    public struct RGB: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public static let white = RGB(red: 1, green: 1, blue: 1)
        public static let black = RGB(red: 0, green: 0, blue: 0)
    }

    /// WCAG 2's minimum for text; a tint colours links and button titles, so it is held to this.
    public static let textContrast = 4.5
    /// WCAG 2's minimum for a graphical object, such as the send button's glyph.
    public static let graphicContrast = 3.0

    /// WCAG 2 relative luminance.
    public static func luminance(_ color: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            let c = min(max(channel, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// WCAG 2 contrast ratio, 1…21.
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The system colour as the system draws it when that reads as text on every background given; otherwise the
    /// variant iOS itself draws under Increase Contrast.
    public static func safeVariant(standard: RGB, accessible: RGB, on backgrounds: [RGB]) -> RGB {
        backgrounds.allSatisfy { contrast(standard, $0) >= textContrast } ? standard : accessible
    }

    /// A glyph on the accent is white, as iOS draws it, unless white would not stand out from that accent.
    public static func glyphIsWhite(on accent: RGB) -> Bool {
        contrast(.white, accent) >= graphicContrast
    }
}
