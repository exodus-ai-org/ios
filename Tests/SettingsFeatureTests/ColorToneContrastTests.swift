import Models
import SwiftUI
import Testing
import UIKit

@testable import SettingsFeature

@Suite("Color tone: fills and inks, safe in every appearance")
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
        "every tone's ink reads as text on the page and on a cell, and as a control on a grouped background",
        arguments: ColorTone.allCases)
    func inksAreSafe(tone: ColorTone) {
        for (style, contrast) in Self.appearances {
            let t = Self.traits(style, contrast)
            let ink = Self.rgb(tone.inkUIColor, t)
            for background in [UIColor.systemBackground, .secondarySystemGroupedBackground] {
                #expect(ColorTone.contrast(ink, Self.rgb(background, t)) >= 4.5, "\(tone) \(style.rawValue)/\(contrast.rawValue)")
            }
            #expect(ColorTone.contrast(ink, Self.rgb(.systemGroupedBackground, t)) >= 3, "\(tone) \(style.rawValue)")
        }
    }

    @Test("a tone is painted in its own colours, in the phone's colour space: the fill, and the ink for text")
    func paintedInItsOwnColours() {
        for tone in ColorTone.allCases {
            for (style, contrast) in Self.appearances {
                let t = Self.traits(style, contrast)
                let scheme: ColorTone.Scheme = style == .dark ? .dark : .light
                let fill = tone.fill(scheme)
                let ink = tone.ink(scheme, increasedContrast: contrast == .high)
                #expect(tone.uiColor.resolvedColor(with: t) == ColorTone.uiColor(displaying: fill), "\(tone)")
                #expect(tone.inkUIColor.resolvedColor(with: t) == ColorTone.uiColor(displaying: ink), "\(tone)")
            }
        }
    }

    @Test("what tints text is the ink, never the fill")
    func tintIsTheInk() {
        let light = Self.traits(.light, .normal)
        #expect(Self.rgb(UIColor(ColorTone.yellow.tint), light) == Self.rgb(ColorTone.yellow.inkUIColor, light))
        #expect(Self.rgb(ColorTone.yellow.inkUIColor, light) != Self.rgb(ColorTone.yellow.uiColor, light))
    }

    @Test("no tone is one of the system's standard colours any more")
    func notASystemColour() {
        let light = Self.traits(.light, .normal)
        let system: [UIColor] = [.systemGreen, .systemBlue, .systemIndigo, .systemPink, .systemOrange, .systemYellow]
        for tone in ColorTone.allCases {
            for color in system {
                #expect(Self.rgb(tone.uiColor, light) != Self.rgb(color, light), "\(tone)")
                #expect(Self.rgb(tone.inkUIColor, light) != Self.rgb(color, light), "\(tone)")
            }
        }
    }

    @Test("neutral is black and white, as the desktop's default: its swatch, its tint and its glyph")
    func neutralIsBlackAndWhite() {
        let (light, dark) = (Self.traits(.light, .normal), Self.traits(.dark, .normal))
        #expect(Self.rgb(ColorTone.neutral.uiColor, light).hexString == "#171717")
        #expect(Self.rgb(ColorTone.neutral.uiColor, dark).hexString == "#E5E5E5")
        #expect(Self.rgb(UIColor(ColorTone.neutral.tint), light).hexString == "#171717")
        #expect(Self.rgb(UIColor(ColorTone.neutral.tint), dark).hexString == "#E5E5E5")
        #expect(Self.rgb(UIColor(ColorTone.neutral.glyphColor), light).hexString == "#FAFAFA")
        #expect(Self.rgb(UIColor(ColorTone.neutral.glyphColor), dark).hexString == "#171717")
        for (style, contrast) in Self.appearances {
            let t = Self.traits(style, contrast)
            #expect(Self.rgb(ColorTone.neutral.uiColor, t) != Self.rgb(.systemBlue, t))
            #expect(ColorTone.contrast(Self.rgb(ColorTone.neutral.inkUIColor, t), Self.rgb(.systemBackground, t)) >= 7)
        }
    }

    @Test("the send glyph stands out from the accent at 3:1 in every tone and appearance", arguments: ColorTone.allCases)
    func glyphStandsOut(tone: ColorTone) {
        for (style, contrast) in Self.appearances {
            let t = Self.traits(style, contrast)
            let accent = Self.rgb(tone.uiColor, t)
            let glyph = Self.rgb(UIColor(tone.glyphColor), t)
            #expect(ColorTone.contrast(glyph, accent) >= 3, "\(tone) \(style.rawValue)/\(contrast.rawValue)")
        }
    }
}
