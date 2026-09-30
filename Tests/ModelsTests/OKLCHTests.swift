import Foundation
import Testing

@testable import Models

@Suite("OKLCH: the desktop's colours, converted")
struct OKLCHTests {
    private func near(_ a: ColorTone.RGB, _ b: ColorTone.RGB, _ tolerance: Double = 0.003) -> Bool {
        abs(a.red - b.red) <= tolerance && abs(a.green - b.green) <= tolerance && abs(a.blue - b.blue) <= tolerance
    }

    @Test("the sRGB primaries, white, black and a grey come out as themselves")
    func knownValues() {
        #expect(near(OKLCH(lightness: 1, chroma: 0, hue: 0).components(in: .sRGB), .white))
        #expect(near(OKLCH(lightness: 0, chroma: 0, hue: 0).components(in: .sRGB), .black))
        #expect(near(OKLCH(lightness: 0.62796, chroma: 0.25768, hue: 29.2339).components(in: .sRGB), .init(red: 1, green: 0, blue: 0)))
        #expect(near(OKLCH(lightness: 0.86644, chroma: 0.29483, hue: 142.495).components(in: .sRGB), .init(red: 0, green: 1, blue: 0)))
        #expect(near(OKLCH(lightness: 0.45201, chroma: 0.31321, hue: 264.052).components(in: .sRGB), .init(red: 0, green: 0, blue: 1)))
        let grey = OKLCH(lightness: 0.5, chroma: 0, hue: 0).components(in: .sRGB)
        #expect(near(grey, .init(red: 0x63 / 255, green: 0x63 / 255, blue: 0x63 / 255)))
    }

    @Test("a colour inside sRGB is the same colour in Display P3, in that space's own numbers")
    func insideBothGamuts() {
        let violet = OKLCH(lightness: 0.52, chroma: 0.17, hue: 285)
        #expect(near(violet.components(in: .sRGB), .init(red: 0x63 / 255, green: 0x53 / 255, blue: 0xC5 / 255)))
        #expect(near(violet.components(in: .displayP3), .init(red: 0x60 / 255, green: 0x54 / 255, blue: 0xBE / 255)))
    }

    @Test("a colour outside the gamut comes in by losing chroma: every channel in range, the hue kept")
    func outOfGamutLosesChroma() {
        let emerald = OKLCH(lightness: 0.52, chroma: 0.17, hue: 160)
        for gamut in [OKLCH.Gamut.sRGB, .displayP3] {
            let mapped = emerald.mapped(into: gamut)
            #expect(mapped.chroma < 0.17)
            #expect(mapped.hue == 160)
            #expect(mapped.lightness == 0.52)
            let rgb = emerald.components(in: gamut)
            for channel in [rgb.red, rgb.green, rgb.blue] {
                #expect(channel >= 0 && channel <= 1)
            }
        }
        // Display P3 holds more of it than sRGB does.
        #expect(emerald.mapped(into: .displayP3).chroma > emerald.mapped(into: .sRGB).chroma)
        #expect(near(emerald.components(in: .sRGB), .init(red: 0, green: 0x7D / 255, blue: 0x51 / 255)))
        #expect(near(emerald.components(in: .displayP3), .init(red: 0, green: 0x81 / 255, blue: 0x4C / 255)))
    }

    @Test("a colour inside the gamut is not touched")
    func insideIsKept() {
        let quiet = OKLCH(lightness: 0.94, chroma: 0.02, hue: 155)
        #expect(quiet.mapped(into: .sRGB) == quiet)
    }

    @Test("luminance is the colour's own, whichever space draws it")
    func luminance() {
        #expect(abs(OKLCH(lightness: 1, chroma: 0, hue: 0).luminance - 1) < 0.001)
        #expect(OKLCH(lightness: 0, chroma: 0, hue: 0).luminance == 0)
        let accent = OKLCH(lightness: 0.52, chroma: 0.17, hue: 285)
        #expect(abs(accent.luminance - ColorTone.luminance(accent.components(in: .sRGB))) < 0.002)
    }

    @Test("the hue angle of a colour as HSB has it")
    func hueAngle() {
        #expect(ColorTone.RGB(red: 1, green: 0, blue: 0).hueAngle == 0)
        #expect(ColorTone.RGB(red: 0, green: 1, blue: 0).hueAngle == 120)
        #expect(ColorTone.RGB(red: 0, green: 0, blue: 1).hueAngle == 240)
        #expect(ColorTone.RGB(red: 0.5, green: 0.5, blue: 0.5).hueAngle == 0)
        #expect(abs((ColorTone.emerald.accentHueAngle ?? 0) - 113) < 1.5)
        #expect(abs((ColorTone.orange.accentHueAngle ?? 0) - 25) < 1.5)
        #expect(ColorTone.neutral.accentHueAngle == nil)
    }

    @Test("an sRGB colour in OKLCH, and back")
    func fromRGB() {
        let red = OKLCH(ColorTone.RGB(red: 1, green: 0, blue: 0))
        #expect(abs(red.lightness - 0.62796) < 0.001)
        #expect(abs(red.chroma - 0.25768) < 0.001)
        #expect(abs(red.hue - 29.2339) < 0.05)
        let grey = OKLCH(ColorTone.RGB(red: 0.5, green: 0.5, blue: 0.5))
        #expect(grey.chroma < 0.0001)
        #expect(grey.hue == 0)
        for hex: UInt32 in [0x5480F0, 0x6CB362, 0xEDC859, 0xE17EAD, 0xDE8344, 0x8553E7, 0xB4B4B4] {
            let rgb = ColorTone.RGB(hex: hex)
            #expect(near(OKLCH(rgb).components(in: .sRGB), rgb, 0.001))
        }
        let blue = OKLCH(ColorTone.RGB(hex: 0x5480F0))
        #expect(abs(blue.lightness - 0.625) < 0.002)
        #expect(abs(blue.chroma - 0.175) < 0.002)
        #expect(abs(blue.hue - 265.5) < 0.3)
    }

    @Test("a colour as text: itself when it reads, else moved in lightness only as far as it takes")
    func readable() {
        let yellow = OKLCH(ColorTone.RGB(hex: 0xEDC859))
        let onWhite = yellow.readable(on: [1], minimum: 4.5, in: .sRGB)
        #expect(onWhite.contrast(onLuminance: 1) >= 4.5)
        #expect(onWhite.contrast(onLuminance: 1) < 4.6)
        #expect(onWhite.lightness < yellow.lightness)
        #expect(abs(onWhite.hue - yellow.hue) < 0.01)

        let onBlack = yellow.readable(on: [0], minimum: 4.5, in: .sRGB)
        #expect(onBlack == yellow.mapped(into: .sRGB))

        let violet = OKLCH(ColorTone.RGB(hex: 0x8553E7))
        let lifted = violet.readable(on: [0, 0.0185], minimum: 4.5, in: .sRGB)
        #expect(lifted.lightness > violet.lightness)
        #expect(lifted.contrast(onLuminance: 0.0185) >= 4.5)
    }
}

@Suite("The send button in light: a white arrow on the tone's ink")
struct SendButtonContrastTests {
    @Test("white on every tone's light ink reads at 4.5:1 or more", arguments: ColorTone.allCases)
    func whiteOnInk(tone: ColorTone) {
        // The chat's send button in light mode is the ink with a white arrow: a white arrow on the soft fill is
        // 1.6:1 in yellow, and a dark one on green read as a blot (owner, 2026-09-30).
        #expect(tone.ink(.light).contrast(onLuminance: 1) >= 4.5, "\(tone)")
    }
}
