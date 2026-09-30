import Foundation

/// `settings.colorTone` (the desktop's `ColorToneSchema`): the accent the whole app is painted in. The column is
/// plain text on the desktop, so anything it does not know, or no value at all, reads as `neutral`, as there.
/// The phone stores the same values and paints each in a colour of its own choosing (`fill`, `ink`, `surface`):
/// softer and lighter than the system's standard colours, after the reference the owner picked. Neutral is the
/// desktop's own default, shadcn's black and white.
public enum ColorTone: String, CaseIterable, Sendable, Identifiable {
    case neutral, emerald, blue, violet, rose, orange, yellow

    public var id: String { rawValue }

    public init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .neutral
    }

    public enum Scheme: Sendable {
        case light, dark
    }

    /// The tone's colour as it was sampled from the reference (ChatGPT's accent colours, sRGB): softer and lighter
    /// than a system colour. `nil` for neutral, which has no colour: it is black and white (`Neutral`).
    public var reference: RGB? {
        switch self {
        case .neutral: nil
        case .emerald: RGB(hex: 0x6CB362)
        case .blue: RGB(hex: 0x5480F0)
        case .violet: RGB(hex: 0x8553E7)
        case .rose: RGB(hex: 0xE17EAD)
        case .orange: RGB(hex: 0xDE8344)
        case .yellow: RGB(hex: 0xEDC859)
        }
    }

    /// Neutral, as the desktop paints its default: the base tokens of its stylesheet (`:root` and `.dark` in
    /// `globals.css`, shadcn's neutral), converted. Black on white in light, the other way round in dark.
    public enum Neutral {
        /// `--primary`: what fills a button, and what text in the tone is written in.
        public static func primary(_ scheme: Scheme) -> OKLCH {
            OKLCH(lightness: scheme == .light ? 0.205 : 0.922, chroma: 0, hue: 0)
        }

        /// `--primary-foreground`: what is drawn on `primary`.
        public static func primaryForeground(_ scheme: Scheme) -> OKLCH {
            OKLCH(lightness: scheme == .light ? 0.985 : 0.205, chroma: 0, hue: 0)
        }

        /// `--secondary`: a quiet surface, the bubble of what the user wrote.
        public static func secondary(_ scheme: Scheme) -> OKLCH {
            OKLCH(lightness: scheme == .light ? 0.97 : 0.269, chroma: 0, hue: 0)
        }
    }

    /// The gamut the tones are drawn in: the phone's.
    public static let gamut = OKLCH.Gamut.displayP3

    /// What a dark page asks of a fill, chosen by eye: a touch lighter so it does not sink into black, a little
    /// less colourful so it does not glow.
    static let darkFillLift = 0.025
    static let darkFillChroma = 0.92

    /// The colour of a surface or a shape in the tone — the send button, a selected chip, a bar, a swatch. It is
    /// the reference in light. Not for text: yellow on white is 1.6:1 (see `ink`).
    public func fill(_ scheme: Scheme) -> OKLCH {
        guard let reference else { return Neutral.primary(scheme) }
        let color = OKLCH(reference)
        switch scheme {
        case .light:
            return color
        case .dark:
            return OKLCH(
                lightness: min(color.lightness + Self.darkFillLift, 1), chroma: color.chroma * Self.darkFillChroma,
                hue: color.hue
            ).mapped(into: Self.gamut)
        }
    }

    /// The least contrast an ink has with the page: WCAG's 4.5:1 for text and a little over, since a colour is
    /// rounded to eight bits on its way to the screen; 7:1 under Increase Contrast.
    public static func inkContrast(increased: Bool) -> Double { increased ? 7.1 : 4.6 }

    /// The luminances of what the chat's text stands on: the page, and a cell or card over it.
    public static func pageLuminances(_ scheme: Scheme) -> [Double] {
        switch scheme {
        case .light: [1]
        case .dark: [0, 0.0185]
        }
    }

    /// The colour of text and glyphs in the tone — a link, "+8 more", a card's icon: the fill's hue, as dark (on a
    /// light page) or as light (on a dark one) as it takes to read there. Neutral's fill is text already.
    public func ink(_ scheme: Scheme, increasedContrast: Bool = false) -> OKLCH {
        fill(scheme).readable(
            on: Self.pageLuminances(scheme), minimum: Self.inkContrast(increased: increasedContrast), in: Self.gamut)
    }

    /// What is drawn on the fill, such as the send button's arrow: white, as iOS draws it, unless white would not
    /// stand out from the fill, then black. Neutral's is the desktop's own (`--primary-foreground`). sRGB.
    public func glyph(_ scheme: Scheme) -> RGB {
        guard reference != nil else { return Neutral.primaryForeground(scheme).components(in: .sRGB) }
        return Self.glyphIsWhite(on: fill(scheme).components(in: .sRGB)) ? .white : .black
    }

    /// How much of the fill is in the bubble's surface, the rest being the page: chosen by eye.
    public static func surfaceShare(_ scheme: Scheme) -> Double {
        switch scheme {
        case .light: 0.14
        case .dark: 0.22
        }
    }

    /// A quiet surface with the tone in it, for what the user wrote: the fill mixed far toward the page (white, or
    /// black), as a thin wash of it would look. Neutral's is the desktop's grey (`--secondary`). sRGB.
    public func surface(_ scheme: Scheme) -> RGB {
        guard reference != nil else { return Neutral.secondary(scheme).components(in: .sRGB) }
        let page: RGB = scheme == .light ? .white : .black
        return page.mixed(with: fill(scheme).components(in: .sRGB), share: Self.surfaceShare(scheme))
    }

    /// The hue angle (HSB) of the fill, for telling other colours apart from it; none for neutral, which is a grey.
    public var accentHueAngle: Double? {
        reference?.hueAngle
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

        /// `0x5480F0`.
        public init(hex: UInt32) {
            self.init(
                red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255)
        }

        public static let white = RGB(red: 1, green: 1, blue: 1)
        public static let black = RGB(red: 0, green: 0, blue: 0)

        /// `share` of `other` in this colour, channel by channel as they are encoded: what drawing `other` over
        /// this one at that opacity gives.
        public func mixed(with other: RGB, share: Double) -> RGB {
            let s = min(max(share, 0), 1)
            return RGB(
                red: red + (other.red - red) * s, green: green + (other.green - green) * s,
                blue: blue + (other.blue - blue) * s)
        }

        /// `#5480F0`.
        public var hexString: String {
            let channels = [red, green, blue].map { Int((min(max($0, 0), 1) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
        }
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

    /// A colour as it is when that reads as text on every background given; otherwise its accessible variant.
    public static func safeVariant(standard: RGB, accessible: RGB, on backgrounds: [RGB]) -> RGB {
        backgrounds.allSatisfy { contrast(standard, $0) >= textContrast } ? standard : accessible
    }

    /// A glyph on the accent is white, as iOS draws it, unless white would not stand out from that accent.
    public static func glyphIsWhite(on accent: RGB) -> Bool {
        contrast(.white, accent) >= graphicContrast
    }
}
