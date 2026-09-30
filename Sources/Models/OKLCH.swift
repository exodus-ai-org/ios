import Foundation

/// A colour in OKLCH, the space the desktop's colour tokens are written in (`oklch(0.52 0.17 160)`): how light,
/// how colourful, and which hue in degrees. The phone paints the same colours by converting them.
public struct OKLCH: Equatable, Sendable {
    public var lightness: Double
    public var chroma: Double
    public var hue: Double

    public init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    /// An sRGB colour (gamma-encoded components) in OKLCH.
    public init(_ rgb: ColorTone.RGB) {
        let (red, green, blue) = (Self.decoded(rgb.red), Self.decoded(rgb.green), Self.decoded(rgb.blue))
        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let chroma = (a * a + b * b).squareRoot()
        let angle = atan2(b, a) * 180 / .pi
        self.init(
            lightness: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, chroma: chroma,
            // A grey has no hue; zero keeps it comparable.
            hue: chroma < 0.0001 ? 0 : (angle < 0 ? angle + 360 : angle))
    }

    /// The colour spaces a screen draws in. An iPhone's is Display P3, which holds more of a vivid colour than sRGB.
    public enum Gamut: Sendable {
        case sRGB, displayP3
    }

    /// Gamma-encoded components in `gamut`, each 0…1. A colour the gamut cannot hold is brought in first (`mapped`).
    public func components(in gamut: Gamut) -> ColorTone.RGB {
        let linear = mapped(into: gamut).linear(in: gamut)
        return ColorTone.RGB(red: Self.encoded(linear.0), green: Self.encoded(linear.1), blue: Self.encoded(linear.2))
    }

    /// The colour as `gamut` can show it: the same lightness and hue, with as much of its chroma as fits. Clamping
    /// the channels instead would shift the hue (an emerald turns to a plain green).
    public func mapped(into gamut: Gamut) -> OKLCH {
        guard !isInside(gamut) else { return self }
        var (low, high) = (0.0, chroma)
        for _ in 0..<32 {
            let middle = (low + high) / 2
            if OKLCH(lightness: lightness, chroma: middle, hue: hue).isInside(gamut) {
                low = middle
            } else {
                high = middle
            }
        }
        return OKLCH(lightness: lightness, chroma: low, hue: hue)
    }

    /// WCAG 2 relative luminance: the colour's own, whichever space draws it.
    public var luminance: Double {
        let (red, green, blue) = linearSRGB
        return min(max(0.2126 * red + 0.7152 * green + 0.0722 * blue, 0), 1)
    }

    /// WCAG 2 contrast with a background of that luminance, 1…21.
    public func contrast(onLuminance background: Double) -> Double {
        let own = luminance
        return (max(own, background) + 0.05) / (min(own, background) + 0.05)
    }

    /// This hue as text: the colour itself when it reads on every background at `minimum`:1, else moved in
    /// lightness — darker on a light page, lighter on a dark one — only as far as it takes, with as much of its
    /// chroma as `gamut` holds at that lightness. The backgrounds are given by their luminance.
    public func readable(on backgrounds: [Double], minimum: Double, in gamut: Gamut) -> OKLCH {
        func at(_ lightness: Double) -> OKLCH {
            OKLCH(lightness: lightness, chroma: chroma, hue: hue).mapped(into: gamut)
        }
        func reads(_ color: OKLCH) -> Bool {
            backgrounds.allSatisfy { color.contrast(onLuminance: $0) >= minimum }
        }
        let own = mapped(into: gamut)
        guard !reads(own), !backgrounds.isEmpty else { return own }
        let pageIsLight = backgrounds.reduce(0, +) / Double(backgrounds.count) > 0.18
        // `near` does not read, `far` does (black and white always do, where anything can).
        var (near, far) = (lightness, pageIsLight ? 0.0 : 1.0)
        for _ in 0..<32 {
            let middle = (near + far) / 2
            if reads(at(middle)) { far = middle } else { near = middle }
        }
        return at(far)
    }

    // MARK: Conversion

    private static let tolerance = 0.0001

    private func isInside(_ gamut: Gamut) -> Bool {
        let (red, green, blue) = linear(in: gamut)
        return [red, green, blue].allSatisfy { $0 >= -Self.tolerance && $0 <= 1 + Self.tolerance }
    }

    /// OKLCH → OKLab → LMS → linear sRGB (Björn Ottosson's matrices).
    private var linearSRGB: (Double, Double, Double) {
        let radians = hue * .pi / 180
        let (a, b) = (chroma * cos(radians), chroma * sin(radians))
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    private func linear(in gamut: Gamut) -> (Double, Double, Double) {
        let (red, green, blue) = linearSRGB
        switch gamut {
        case .sRGB:
            return (red, green, blue)
        case .displayP3:
            return (
                0.8224621 * red + 0.1775380 * green,
                0.0331941 * red + 0.9668058 * green,
                0.0170827 * red + 0.0723974 * green + 0.9105199 * blue
            )
        }
    }

    /// The sRGB transfer function, which Display P3 shares.
    private static func encoded(_ channel: Double) -> Double {
        let c = min(max(channel, 0), 1)
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func decoded(_ channel: Double) -> Double {
        let c = min(max(channel, 0), 1)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}

extension ColorTone.RGB {
    /// The hue as HSB has it, in degrees, 0…360; 0 for a grey.
    public var hueAngle: Double {
        let (high, low) = (max(red, green, blue), min(red, green, blue))
        let span = high - low
        guard span > 0 else { return 0 }
        let sixth: Double
        if high == red {
            sixth = ((green - blue) / span).truncatingRemainder(dividingBy: 6)
        } else if high == green {
            sixth = (blue - red) / span + 2
        } else {
            sixth = (red - green) / span + 4
        }
        let angle = sixth * 60
        return angle < 0 ? angle + 360 : angle
    }
}
