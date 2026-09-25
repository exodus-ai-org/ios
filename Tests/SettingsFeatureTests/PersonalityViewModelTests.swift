import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

@MainActor
@Suite("Personality")
struct PersonalityViewModelTests {
    private static let row = #"""
        {"id":"global","lastBackupAt":"2026-09-18T12:00:00.000Z",
         "personality":{"nickname":"Y","occupation":"","baseStyle":"candid","warm":"more","emoji":"less",
           "customInstructions":"Be brief.","futureField":{"a":1}}}
        """#

    @Test("load() fills the form from the column; an empty stored string reads as an empty field")
    func loadFillsForm() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = PersonalityViewModel(store: server.makeStore())
        await vm.load()
        #expect(vm.hasLoaded)
        #expect(vm.nickname == "Y")
        #expect(vm.occupation == "")
        #expect(vm.baseStyle == "candid")
        #expect(vm.warm == "more")
        #expect(vm.enthusiastic == "default")
        #expect(vm.emoji == "less")
        #expect(vm.customInstructions == "Be brief.")
        #expect(vm.hasChanges == false)
    }

    @Test("save posts exactly id, lastBackupAt and the whole personality column, keeping keys this app does not model")
    func savePayload() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = PersonalityViewModel(store: server.makeStore())
        await vm.load()
        vm.nickname = ""
        vm.occupation = "Designer"
        vm.headersAndLists = "less"
        #expect(vm.hasChanges)
        #expect(await vm.save())

        let body = try server.onlyPostBody()
        #expect(Set(body.keys) == ["id", "lastBackupAt", "personality"])
        #expect(body["lastBackupAt"] as? String == "2026-09-18T12:00:00.000Z")
        let personality = try #require(body["personality"] as? [String: Any])
        #expect(personality["nickname"] == nil)
        #expect(personality["occupation"] as? String == "Designer")
        #expect(personality["baseStyle"] as? String == "candid")
        #expect(personality["headersAndLists"] as? String == "less")
        #expect(personality["customInstructions"] as? String == "Be brief.")
        #expect((personality["futureField"] as? [String: Any])?["a"] as? Int == 1)
        #expect(vm.hasChanges == false)
    }

    @Test("save re-reads the column first: what the desktop changed since the load is kept, the user's edits win")
    func saveIsReadModifyWrite() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = PersonalityViewModel(store: server.makeStore())
        await vm.load()
        server.serve(rows: [
            #"{"id":"global","lastBackupAt":null,"personality":{"nickname":"Desktop","baseStyle":"quirky","tone":"x"}}"#
        ])
        vm.warm = "less"
        #expect(await vm.save())
        #expect(server.methods == ["GET", "GET", "POST"])
        let body = try server.onlyPostBody()
        #expect(body["lastBackupAt"] is NSNull)
        let personality = try #require(body["personality"] as? [String: Any])
        #expect(personality["tone"] as? String == "x")
        #expect(personality["futureField"] == nil)
        #expect(personality["nickname"] as? String == "Desktop")
        #expect(personality["baseStyle"] as? String == "quirky")
        #expect(personality["customInstructions"] == nil)
        #expect(personality["warm"] as? String == "less")
        #expect(vm.nickname == "Desktop")
    }

    @Test("pull to refresh keeps the fields edited here and takes the rest from the computer")
    func refreshKeepsEdits() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = PersonalityViewModel(store: server.makeStore())
        await vm.load()
        vm.warm = "less"
        server.serve(rows: [#"{"id":"global","personality":{"nickname":"Desktop","warm":"more","emoji":"more"}}"#])
        await vm.refresh()
        #expect(vm.warm == "less")
        #expect(vm.nickname == "Desktop")
        #expect(vm.emoji == "more")
        #expect(vm.hasChanges)
        #expect(server.postBodies.isEmpty)

        vm.warm = "more"
        #expect(vm.hasChanges == false)
    }

    @Test("a personality column the phone cannot read is an error state, and nothing can be saved over it")
    func unreadableColumnIsNotSaved() async throws {
        let server = SettingsPageTestServer(rows: [#"{"id":"global","personality":"candid"}"#])
        let vm = PersonalityViewModel(store: server.makeStore())
        await vm.load()
        #expect(vm.hasLoaded == false)
        #expect(vm.errorMessage?.contains("can't read") == true)
        vm.nickname = "Y"
        #expect(await vm.save() == false)
        #expect(server.postBodies.isEmpty)
    }

    @Test("a style value the desktop added later is written back as read")
    func unknownEnumValueSurvives() async throws {
        let server = SettingsPageTestServer(rows: [#"{"id":"global","personality":{"baseStyle":"poetic","emoji":"lots"}}"#])
        let vm = PersonalityViewModel(store: server.makeStore())
        await vm.load()
        #expect(vm.baseStyle == "poetic")
        vm.nickname = "Z"
        #expect(await vm.save())
        let personality = try #require(try server.onlyPostBody()["personality"] as? [String: Any])
        #expect(personality["baseStyle"] as? String == "poetic")
        #expect(personality["emoji"] as? String == "lots")
    }

    @Test("a row with no personality column starts from the schema's defaults")
    func missingColumnStartsFromDefaults() async throws {
        let server = SettingsPageTestServer(rows: [#"{"id":"global"}"#])
        let vm = PersonalityViewModel(store: server.makeStore())
        await vm.load()
        #expect(vm.baseStyle == "default" && vm.warm == "default" && vm.nickname.isEmpty)
        vm.emoji = "more"
        #expect(await vm.save())
        let personality = try #require(try server.onlyPostBody()["personality"] as? [String: Any])
        #expect(Set(personality.keys) == ["baseStyle", "warm", "enthusiastic", "headersAndLists", "emoji"])
        #expect(personality["emoji"] as? String == "more")
    }

    @Test("the pickers offer exactly the schema's enums")
    func enumsMatchSchema() {
        #expect(PersonalityViewModel.baseStyles == [
            "default", "professional", "friendly", "candid", "quirky", "efficient", "cynical",
        ])
        #expect(PersonalityViewModel.levels == ["default", "more", "less"])
    }

    @Test("save before a load refuses and sends nothing")
    func saveBeforeLoadRefuses() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = PersonalityViewModel(store: server.makeStore())
        vm.nickname = "Y"
        #expect(await vm.save() == false)
        #expect(vm.errorMessage == "Connect to the server and load its settings before saving.")
        #expect(server.methods.isEmpty)
    }

    @Test("a failed save reports the error and keeps the edits")
    func failedSaveKeepsEdits() async throws {
        let server = SettingsPageTestServer(rows: [Self.row], postStatus: 500)
        let vm = PersonalityViewModel(store: server.makeStore())
        await vm.load()
        vm.occupation = "Pilot"
        #expect(await vm.save() == false)
        #expect(vm.errorMessage != nil)
        #expect(vm.occupation == "Pilot")
        #expect(vm.hasChanges)
    }

    @Test("a failed load reports the error and leaves the form unloaded")
    func failedLoad() async throws {
        let server = SettingsPageTestServer(
            rows: [#"{"type":"error","error":{"code":"INTERNAL","message":"down"}}"#], getStatus: 500)
        let vm = PersonalityViewModel(store: server.makeStore())
        await vm.load()
        #expect(vm.hasLoaded == false)
        #expect(vm.errorMessage != nil)
    }
}
