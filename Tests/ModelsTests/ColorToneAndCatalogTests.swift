import Foundation
import Testing

@testable import Models

@Suite("Color tone and model catalog")
struct ColorToneAndCatalogTests {
    private func decode(_ json: String) throws -> SettingsSnapshot {
        try JSONDecoder().decode(SettingsSnapshot.self, from: Data(json.utf8))
    }

    @Test("colorTone decodes leniently: a known name, an unknown one, null, absent, another type")
    func colorToneDecodes() throws {
        #expect(ColorTone(stored: try decode(#"{"id":"g","colorTone":"rose"}"#).colorTone) == .rose)
        #expect(ColorTone(stored: try decode(#"{"id":"g","colorTone":"teal"}"#).colorTone) == .neutral)
        #expect(ColorTone(stored: try decode(#"{"id":"g","colorTone":null}"#).colorTone) == .neutral)
        #expect(ColorTone(stored: try decode(#"{"id":"g"}"#).colorTone) == .neutral)
        let numeric = try decode(#"{"id":"g","colorTone":3}"#)
        #expect(numeric.colorTone == nil)
        #expect(numeric.unreadableColumns.isEmpty)
    }

    @Test("the tones are the desktop's ColorToneSchema, in its order")
    func tonesMatchDesktop() {
        #expect(ColorTone.allCases.map(\.rawValue) == ["neutral", "emerald", "blue", "violet", "rose", "orange", "yellow"])
    }

    @Test("the fills are the reference's colours in light")
    func fillsAreTheReference() {
        let expected: [ColorTone: String] = [
            .emerald: "#6CB362", .blue: "#5480F0", .violet: "#8553E7", .rose: "#E17EAD", .orange: "#DE8344",
            .yellow: "#EDC859",
        ]
        for (tone, hex) in expected {
            #expect(tone.fill(.light).components(in: .sRGB).hexString == hex, "\(tone)")
        }
        #expect(ColorTone.neutral.reference == nil)
    }

    @Test("neutral is the desktop's default, shadcn's black and white: its base tokens, converted")
    func neutralIsTheDesktopsBase() {
        let neutral = ColorTone.neutral
        // --primary: oklch(0.205 0 0) and oklch(0.922 0 0).
        #expect(neutral.fill(.light) == OKLCH(lightness: 0.205, chroma: 0, hue: 0))
        #expect(neutral.fill(.dark) == OKLCH(lightness: 0.922, chroma: 0, hue: 0))
        #expect(neutral.fill(.light).components(in: .sRGB).hexString == "#171717")
        #expect(neutral.fill(.dark).components(in: .sRGB).hexString == "#E5E5E5")
        // --primary-foreground: oklch(0.985 0 0) and oklch(0.205 0 0).
        #expect(neutral.glyph(.light).hexString == "#FAFAFA")
        #expect(neutral.glyph(.dark).hexString == "#171717")
        // --secondary: oklch(0.97 0 0) and oklch(0.269 0 0).
        #expect(neutral.surface(.light).hexString == "#F5F5F5")
        #expect(neutral.surface(.dark).hexString == "#262626")
        // Black on white and the other way round are text already: the ink is the fill.
        for scheme in [ColorTone.Scheme.light, .dark] {
            for increased in [false, true] {
                #expect(neutral.ink(scheme, increasedContrast: increased) == neutral.fill(scheme), "\(scheme)")
            }
        }
        // It is a grey: it has no hue to keep other colours away from.
        #expect(neutral.accentHueAngle == nil)
        #expect(ColorTone.blue.accentHueAngle != nil)
    }

    @Test("on a dark page a fill keeps its hue, a touch lighter and a little less colourful")
    func darkFills() {
        for tone in ColorTone.allCases where tone != .neutral {
            let light = tone.fill(.light)
            let dark = tone.fill(.dark)
            #expect(abs(dark.hue - light.hue) < 0.5, "\(tone)")
            #expect(dark.lightness > light.lightness, "\(tone)")
            #expect(dark.lightness - light.lightness < 0.06, "\(tone)")
            #expect(dark.chroma < light.chroma, "\(tone)")
            #expect(dark.chroma > light.chroma * 0.8, "\(tone)")
        }
    }

    @Test(
        "an ink reads as text on the page at 4.5:1, light and dark, and at 7:1 under Increase Contrast",
        arguments: ColorTone.allCases)
    func inksRead(tone: ColorTone) {
        for scheme in [ColorTone.Scheme.light, .dark] {
            let fill = tone.fill(scheme)
            for (increased, minimum) in [(false, 4.5), (true, 7.0)] {
                let ink = tone.ink(scheme, increasedContrast: increased)
                for background in ColorTone.pageLuminances(scheme) {
                    #expect(ink.contrast(onLuminance: background) >= minimum, "\(tone) \(scheme) \(increased)")
                }
                // The same hue, moved away from the page and no further than the contrast asks.
                #expect(abs(ink.hue - fill.hue) < 0.5, "\(tone)")
                #expect(scheme == .light ? ink.lightness <= fill.lightness : ink.lightness >= fill.lightness)
                #expect(ink.contrast(onLuminance: scheme == .light ? 1 : 0.0185) < minimum + 1.2 || ink == fill.mapped(into: ColorTone.gamut))
            }
        }
    }

    @Test("a fill that reads already is its own ink; one that does not is never used as text")
    func inkIsTheFillWhenItReads() {
        // Violet on white is 4.8:1 as it is.
        #expect(ColorTone.violet.ink(.light) == ColorTone.violet.fill(.light))
        // Yellow on white is 1.6:1.
        let yellow = ColorTone.yellow.fill(.light)
        #expect(yellow.contrast(onLuminance: 1) < 2)
        let ink = ColorTone.yellow.ink(.light)
        #expect(ink.lightness < yellow.lightness - 0.2)
    }

    @Test("the glyph on a fill is decided by contrast, tone by tone: white on blue and violet, black on the rest")
    func glyphOnFills() {
        for scheme in [ColorTone.Scheme.light, .dark] {
            for tone in ColorTone.allCases where tone != .neutral {
                let fill = tone.fill(scheme).components(in: .sRGB)
                let white = ColorTone.glyphIsWhite(on: fill)
                let glyph: ColorTone.RGB = white ? .white : .black
                #expect(tone.glyph(scheme) == glyph, "\(tone) \(scheme)")
                #expect(ColorTone.contrast(glyph, fill) >= 3, "\(tone) \(scheme)")
                if scheme == .light {
                    #expect(white == [ColorTone.blue, .violet].contains(tone), "\(tone)")
                }
            }
        }
    }

    @Test("a glyph stands out from its fill at 3:1 in every tone, neutral's included")
    func glyphsStandOut() {
        for scheme in [ColorTone.Scheme.light, .dark] {
            for tone in ColorTone.allCases {
                let fill = tone.fill(scheme).components(in: .sRGB)
                #expect(ColorTone.contrast(tone.glyph(scheme), fill) >= 3, "\(tone) \(scheme)")
            }
        }
    }

    @Test("the bubble's surface is the fill washed far into the page: mostly page, the tone still in it")
    func surfaces() {
        let wash = ColorTone.RGB.white.mixed(with: .init(hex: 0x5480F0), share: ColorTone.surfaceShare(.light))
        #expect(near(ColorTone.blue.surface(.light), wash))
        #expect(ColorTone.blue.surface(.light).hexString == "#E7EDFD")
        let dark = ColorTone.blue.surface(.dark)
        #expect(dark.blue > dark.red)
        #expect(dark.blue < 0.3)
        // Neutral's is a grey: the desktop's `--secondary`.
        let neutral = ColorTone.neutral.surface(.light)
        #expect(near(neutral, .init(red: neutral.green, green: neutral.green, blue: neutral.green)))
        #expect(neutral.hexString == "#F5F5F5")
    }

    private func near(_ a: ColorTone.RGB, _ b: ColorTone.RGB, _ tolerance: Double = 0.001) -> Bool {
        abs(a.red - b.red) <= tolerance && abs(a.green - b.green) <= tolerance && abs(a.blue - b.blue) <= tolerance
    }

    @Test("text reads on the bubble at 4.5:1 and better, in every tone")
    func textReadsOnTheSurface() {
        for tone in ColorTone.allCases {
            #expect(ColorTone.contrast(.black, tone.surface(.light)) >= 4.5, "\(tone)")
            #expect(ColorTone.contrast(.white, tone.surface(.dark)) >= 4.5, "\(tone)")
        }
    }

    @Test("mixing: none of the other is the colour itself, all of it is the other")
    func mixing() {
        let blue = ColorTone.RGB(hex: 0x5480F0)
        #expect(ColorTone.RGB.white.mixed(with: blue, share: 0) == .white)
        #expect(near(ColorTone.RGB.white.mixed(with: blue, share: 1), blue))
        #expect(ColorTone.RGB.white.mixed(with: blue, share: 0.5).hexString == "#AAC0F8")
        #expect(ColorTone.RGB(hex: 0x5480F0).hexString == "#5480F0")
    }

    @Test("WCAG contrast: the known extremes and a mid grey")
    func contrastMath() {
        #expect(abs(ColorTone.contrast(.white, .black) - 21) < 0.001)
        #expect(ColorTone.contrast(.black, .black) == 1)
        let grey = ColorTone.RGB(red: 0x76 / 255, green: 0x76 / 255, blue: 0x76 / 255)
        #expect(abs(ColorTone.contrast(grey, .white) - 4.54) < 0.01)
    }

    @Test("the standard colour is kept when it reads as text on every background, else the accessible one")
    func safeVariantChoosesByContrast() {
        let yellow = ColorTone.RGB(red: 1, green: 0.8, blue: 0)
        let darkYellow = ColorTone.RGB(red: 0.631, green: 0.416, blue: 0)
        let indigo = ColorTone.RGB(red: 0.380, green: 0.333, blue: 0.961)
        #expect(ColorTone.safeVariant(standard: yellow, accessible: darkYellow, on: [.white]) == darkYellow)
        #expect(ColorTone.safeVariant(standard: indigo, accessible: darkYellow, on: [.white]) == indigo)
        #expect(ColorTone.safeVariant(standard: yellow, accessible: darkYellow, on: [.black]) == yellow)
        #expect(ColorTone.safeVariant(standard: indigo, accessible: darkYellow, on: [.white, .black]) == darkYellow)
    }

    @Test("a glyph on the accent is white unless white falls under 3:1 there")
    func glyphColor() {
        #expect(ColorTone.glyphIsWhite(on: .init(red: 0, green: 0.533, blue: 1)))
        #expect(!ColorTone.glyphIsWhite(on: .init(red: 1, green: 0.839, blue: 0)))
        #expect(!ColorTone.glyphIsWhite(on: .init(red: 0.188, green: 0.820, blue: 0.345)))
    }

    @Test("the colorTone column writes the tone's name next to id and lastBackupAt")
    func colorToneWriteBody() throws {
        let body = SettingsWriteBody(
            id: "global", lastBackupAt: nil, columns: [SettingsColumn.colorTone.assigning(ColorTone.violet.rawValue)]
                .map { ($0.name, $0.value) })
        let object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        #expect(Set(object.keys) == ["id", "lastBackupAt", "colorTone"])
        #expect(object["colorTone"] as? String == "violet")
        #expect(SettingsColumn.colorTone.name == "colorTone")
    }

    private static let catalogRow = #"""
        {"id":"g","modelCatalog":{
          "Anthropic Claude":[{"id":"claude-opus-5","displayName":"Claude Opus 5","snapshot":{"contextWindow":1000000,"reasoningLevels":["high"]}},
                              {"id":"bare"},{"displayName":"no id"}],
          "OpenAI GPT":[{"id":"gpt-5.6","displayName":"GPT-5.6","snapshot":{},"tier":"pro"}]}}
        """#

    @Test("a stored list reads leniently: only an entry without an id is skipped")
    func catalogReadsLeniently() throws {
        let catalog = try #require(try decode(Self.catalogRow).modelCatalog)
        let models = try #require(catalog.models(for: .anthropicClaude))
        #expect(models.map(\.id) == ["claude-opus-5", "bare"])
        #expect(models[0].snapshot.contextWindow == 1_000_000)
        #expect(models[1].displayName == "bare")
        #expect(catalog.models(for: .googleGemini) == nil)
    }

    @Test("replacing one provider's list leaves every other list exactly as stored")
    func settingOneListKeepsOthers() throws {
        let catalog = try #require(try decode(Self.catalogRow).modelCatalog)
        let updated = catalog.setting(
            [CachedModelEntry(id: "claude-haiku-5", displayName: "Claude Haiku 5", snapshot: ModelSnapshot())],
            for: .anthropicClaude)
        #expect(updated.models(for: .anthropicClaude)?.map(\.id) == ["claude-haiku-5"])
        #expect(updated.lists["OpenAI GPT"] == catalog.lists["OpenAI GPT"])
        let json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(updated)) as? [String: Any])
        let openAI = try #require(json["OpenAI GPT"] as? [[String: Any]])
        #expect(openAI.first?["tier"] as? String == "pro")
    }

    @Test("a modelCatalog that is not an object is an unreadable column, never written over")
    func catalogOfAnotherShapeIsUnreadable() throws {
        let snapshot = try decode(#"{"id":"g","modelCatalog":["x"]}"#)
        #expect(snapshot.modelCatalog == nil)
        #expect(snapshot.unreadableColumns == ["modelCatalog"])
    }
}
