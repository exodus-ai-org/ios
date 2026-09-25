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

    @Test("each tone is painted in its iOS system colour; neutral keeps the system accent")
    func tonesMapToSystemColors() {
        #expect(ColorTone.allCases.map(\.systemColor) == [nil, .green, .blue, .indigo, .pink, .orange, .yellow])
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
