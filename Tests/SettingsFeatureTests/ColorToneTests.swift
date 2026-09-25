import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

@MainActor
@Suite("Color tone: the page and the app-wide accent")
struct ColorToneTests {
    private static func row(tone: String?) -> String {
        let value = tone.map { #""\#($0)""# } ?? "null"
        return #"{"id":"global","lastBackupAt":"2026-09-24T08:00:00.000Z","colorTone":\#(value),"memory":{"autoCapture":false}}"#
    }

    private func defaults(_ suite: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "tone-\(suite)")!
        defaults.removePersistentDomain(forName: "tone-\(suite)")
        return defaults
    }

    @Test("the page shows the stored tone; an unknown or missing one reads as neutral", arguments: [
        (String?("violet"), ColorTone.violet), (String?("teal"), .neutral), (String?.none, .neutral),
    ])
    func loadReadsStoredTone(stored: String?, expected: ColorTone) async {
        let server = SettingsPageTestServer(rows: [Self.row(tone: stored)])
        let vm = ColorToneViewModel(store: server.makeStore())
        await vm.load()
        #expect(vm.hasLoaded)
        #expect(vm.selected == expected)
    }

    @Test("picking a tone writes only colorTone, echoing id and lastBackupAt")
    func pickWritesColumn() async throws {
        let server = SettingsPageTestServer(rows: [Self.row(tone: "neutral")])
        let vm = ColorToneViewModel(store: server.makeStore())
        await vm.load()
        await vm.select(.emerald)
        #expect(server.methods == ["GET", "GET", "POST"])
        let body = try server.onlyPostBody()
        #expect(Set(body.keys) == ["id", "lastBackupAt", "colorTone"])
        #expect(body["colorTone"] as? String == "emerald")
        #expect(body["lastBackupAt"] as? String == "2026-09-24T08:00:00.000Z")
        #expect(vm.selected == .emerald)
        #expect(vm.errorMessage == nil)
    }

    @Test("a failed write goes back to the stored tone and says so")
    func failedWriteReverts() async {
        let server = SettingsPageTestServer(rows: [Self.row(tone: "blue")], postStatus: 500)
        let vm = ColorToneViewModel(store: server.makeStore())
        await vm.load()
        await vm.select(.rose)
        #expect(vm.selected == .blue)
        #expect(vm.errorMessage != nil)
    }

    @Test("nothing is written before the tone was read")
    func noWriteBeforeLoad() async {
        let server = SettingsPageTestServer(rows: [Self.row(tone: "blue")])
        let vm = ColorToneViewModel(store: server.makeStore())
        await vm.select(.rose)
        #expect(server.methods.isEmpty)
        #expect(vm.selected == .neutral)
    }

    @Test("the accent remembers the last tone across launches")
    func modelRemembersTone() {
        let defaults = defaults()
        let model = ColorToneModel(defaults: defaults)
        #expect(model.tone == .neutral)
        model.apply(.orange)
        #expect(ColorToneModel(defaults: defaults).tone == .orange)
    }

    @Test("the accent follows the computer's tone, and keeps its own when the computer can't be read")
    func modelRefreshesFromComputer() async {
        let server = SettingsPageTestServer(rows: [Self.row(tone: "yellow")])
        let (client, _) = server.makeClient()
        let model = ColorToneModel(defaults: defaults())
        await model.refresh(apiClient: client)
        #expect(model.tone == .yellow)

        let failing = SettingsPageTestServer(rows: [Self.row(tone: "violet")], getStatus: 500)
        await model.refresh(apiClient: failing.makeClient("failing").0)
        #expect(model.tone == .yellow)
    }
}
