import Models
import SwiftUI
import Testing
import UIKit

@testable import SettingsFeature

@Suite("Color tone: iOS colours, safe in every appearance")
struct ColorToneContrastTests {
    static let appearances: [(UIUserInterfaceStyle, UIAccessibilityContrast)] = [
        (.light, .normal), (.light, .high), (.dark, .normal), (.dark, .high),
    ]

    static func traits(_ style: UIUserInterfaceStyle, _ contrast: UIAccessibilityContrast) -> UITraitCollection {
        UITraitCollection {
            $0.userInterfaceStyle = style
            $0.accessibilityContrast = contrast
        }
    }

    static func rgb(_ color: UIColor, _ traits: UITraitCollection) -> ColorTone.RGB {
        ColorTone.rgb(color.resolvedColor(with: traits))
    }

    @Test(
        "every chromatic tone reads as text on the page and on a cell, and as a control on a grouped background",
        arguments: ColorTone.allCases.filter { $0 != .neutral })
    func chromaticTonesAreSafe(tone: ColorTone) {
        for (style, contrast) in Self.appearances {
            let t = Self.traits(style, contrast)
            let accent = Self.rgb(tone.uiColor, t)
            for background in [UIColor.systemBackground, .secondarySystemGroupedBackground] {
                #expect(ColorTone.contrast(accent, Self.rgb(background, t)) >= 4.5, "\(tone) \(style.rawValue)/\(contrast.rawValue)")
            }
            #expect(ColorTone.contrast(accent, Self.rgb(.systemGroupedBackground, t)) >= 3, "\(tone) \(style.rawValue)")
        }
    }

    @Test("a tone is its system colour as drawn whenever that is already safe; otherwise iOS's own accessible variant")
    func standardWhenSafe() {
        for tone in ColorTone.allCases {
            guard let system = tone.systemColor.map(ColorTone.uiColor(for:)) else { continue }
            for (style, contrast) in Self.appearances {
                let t = Self.traits(style, contrast)
                let painted = Self.rgb(tone.uiColor, t)
                let standard = Self.rgb(system, t)
                let accessible = Self.rgb(system, Self.traits(style, .high))
                #expect(painted == standard || painted == accessible)
                if ColorTone.contrast(standard, Self.rgb(.systemBackground, t)) >= 4.5,
                    ColorTone.contrast(standard, Self.rgb(.secondarySystemGroupedBackground, t)) >= 4.5
                {
                    #expect(painted == standard, "\(tone) needlessly darkened")
                }
            }
        }
    }

    @Test("light yellow is darkened for contrast; dark yellow is the system yellow")
    func yellowVariants() {
        let light = Self.traits(.light, .normal)
        let dark = Self.traits(.dark, .normal)
        #expect(Self.rgb(ColorTone.yellow.uiColor, light) != Self.rgb(.systemYellow, light))
        #expect(Self.rgb(ColorTone.yellow.uiColor, dark) == Self.rgb(.systemYellow, dark))
    }

    @Test("neutral is the system accent untouched: no tint, and the swatch is system blue")
    func neutralIsSystemDefault() {
        #expect(ColorTone.neutral.tint == nil)
        for (style, contrast) in Self.appearances {
            let t = Self.traits(style, contrast)
            #expect(Self.rgb(ColorTone.neutral.uiColor, t) == Self.rgb(.systemBlue, t))
            #expect(ColorTone.contrast(Self.rgb(ColorTone.neutral.uiColor, t), Self.rgb(.systemBackground, t)) >= 3)
        }
        #expect(ColorTone.violet.tint != nil)
    }

    @Test("the send glyph stands out from the accent at 3:1 in every tone and appearance", arguments: ColorTone.allCases)
    func glyphStandsOut(tone: ColorTone) {
        for (style, contrast) in Self.appearances {
            let t = Self.traits(style, contrast)
            let accent = Self.rgb(tone.uiColor, t)
            let glyph = ColorTone.glyphIsWhite(on: accent) ? ColorTone.RGB.white : .black
            #expect(ColorTone.contrast(glyph, accent) >= 3, "\(tone) \(style.rawValue)/\(contrast.rawValue)")
        }
    }
}
