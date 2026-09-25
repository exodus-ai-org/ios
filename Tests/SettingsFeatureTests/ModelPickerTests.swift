import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

@MainActor
@Suite("AI Providers: the model picker and its list")
struct ModelPickerTests {
    private static let catalog = #"""
        [{"id":"claude-opus-5","displayName":"Claude Opus 5","snapshot":{"contextWindow":1000000,"reasoningLevels":["high"]}},
         {"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"contextWindow":200000,"reasoningLevels":[]}}]
        """#
    /// The row with the desktop's stored lists: Anthropic's, and an OpenAI one with a key this app does not model.
    private static let withCatalog = #"""
        {"id":"global","lastBackupAt":null,
         "providerConfig":{"provider":"Anthropic Claude","model":"claude-sonnet-5"},
         "providers":{"anthropicApiKey":"sk-ant-1","anthropicBaseUrl":"https://proxy.example.com"},
         "modelCatalog":{"Anthropic Claude":\#(catalog),
           "OpenAI GPT":[{"id":"gpt-5.6","displayName":"GPT-5.6","snapshot":{"reasoningLevels":[]},"tier":"pro"}]}}
        """#
    private static let withoutCatalog = #"""
        {"id":"global","lastBackupAt":null,
         "providerConfig":{"provider":"Anthropic Claude","model":"claude-sonnet-5"},
         "providers":{"anthropicApiKey":"sk-ant-1"}}
        """#
    private static let fetched = #"""
        {"models":[{"id":"claude-haiku-5","displayName":"Claude Haiku 5","snapshot":{"contextWindow":200000,"reasoningLevels":[]}},
                   {"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"reasoningLevels":[]}}]}
        """#

    private func loadedViewModel(_ server: SettingsPageTestServer, suite: String = #function) async -> SettingsViewModel {
        let (client, config) = server.makeClient(suite)
        let vm = SettingsViewModel(apiClient: client, serverConfig: config)
        await vm.loadSettings()
        return vm
    }

    @Test("the computer's stored list fills the picker on load, without asking the provider")
    func storedListFillsPicker() async throws {
        let server = SettingsPageTestServer(rows: [Self.withCatalog])
        let vm = await loadedViewModel(server)
        #expect(vm.availableModels.map(\.id) == ["claude-opus-5", "claude-sonnet-5"])
        #expect(vm.availableModels.first?.displayName == "Claude Opus 5")
        #expect(vm.modelText == "claude-sonnet-5")
        await vm.fetchModelsIfStale()
        #expect(server.requests(under: "/api/v1/settings/models").isEmpty)
    }

    @Test("each provider keeps its own list across a switch")
    func listSurvivesProviderSwitch() async throws {
        let server = SettingsPageTestServer(rows: [Self.withCatalog])
        let vm = await loadedViewModel(server)
        vm.select(provider: .openAiGpt)
        #expect(vm.availableModels.map(\.id) == ["gpt-5.6"])
        vm.select(provider: .anthropicClaude)
        #expect(vm.availableModels.count == 2)
        #expect(vm.modelText == "claude-sonnet-5")
    }

    @Test("a fetch posts the form's provider, key and address, and stores that list alone in modelCatalog")
    func fetchPostsFormAndStoresList() async throws {
        let server = SettingsPageTestServer(rows: [Self.withCatalog])
        server.route("POST", "/api/v1/settings/models", [(200, Self.fetched)])
        let vm = await loadedViewModel(server)
        vm.apiKeyText = "sk-ant-typed"
        await vm.fetchModels()

        let request = try #require(server.lastBody("POST", "/api/v1/settings/models"))
        #expect(request["provider"] as? String == "Anthropic Claude")
        #expect(request["apiKey"] as? String == "sk-ant-typed")
        #expect(request["baseUrl"] as? String == "https://proxy.example.com")
        #expect(vm.availableModels.map(\.id) == ["claude-haiku-5", "claude-sonnet-5"])

        let body = try server.onlyPostBody()
        #expect(Set(body.keys) == ["id", "lastBackupAt", "modelCatalog"])
        let catalog = try #require(body["modelCatalog"] as? [String: Any])
        let anthropic = try #require(catalog["Anthropic Claude"] as? [[String: Any]])
        #expect(anthropic.map { $0["id"] as? String } == ["claude-haiku-5", "claude-sonnet-5"])
        // The key typed for the fetch is never part of the stored list.
        #expect(String(data: try JSONSerialization.data(withJSONObject: catalog), encoding: .utf8)?.contains("sk-ant") == false)
        let openAI = try #require(catalog["OpenAI GPT"] as? [[String: Any]])
        #expect(openAI.first?["tier"] as? String == "pro")
    }

    @Test("the model picked from the list is saved with that entry's snapshot")
    func pickedModelIsSavedWithSnapshot() async throws {
        let server = SettingsPageTestServer(rows: [Self.withCatalog])
        let vm = await loadedViewModel(server)
        vm.modelText = "claude-opus-5"
        #expect(await vm.save())
        let body = try server.onlyPostBody()
        let config = try #require(body["providerConfig"] as? [String: Any])
        #expect(config["provider"] as? String == "Anthropic Claude")
        #expect(config["model"] as? String == "claude-opus-5")
        let snapshot = try #require(config["modelSnapshot"] as? [String: Any])
        #expect(snapshot["contextWindow"] as? Int == 1_000_000)
        #expect(snapshot["reasoningLevels"] as? [String] == ["high"])
    }

    @Test("the saved model is what the page shows when it is opened again")
    func savedModelSurvivesReload() async throws {
        let server = SettingsPageTestServer(rows: [Self.withCatalog])
        let vm = await loadedViewModel(server)
        vm.modelText = "claude-opus-5"
        #expect(await vm.save())

        // The computer now holds what was posted.
        var row = try #require(try JSONSerialization.jsonObject(with: Data(Self.withCatalog.utf8)) as? [String: Any])
        for (key, value) in try server.onlyPostBody() { row[key] = value }
        let written = String(data: try JSONSerialization.data(withJSONObject: row), encoding: .utf8)!
        server.serve(rows: [written])

        await vm.reloadIfUnchanged()
        #expect(vm.modelText == "claude-opus-5")
        #expect(vm.hasUnsavedChanges == false)

        let reopened = await loadedViewModel(server, suite: "reopened")
        #expect(reopened.modelText == "claude-opus-5")
        #expect(reopened.availableModels.map(\.id).contains("claude-opus-5"))
        #expect(reopened.isModelStale == false)
    }

    @Test("a failed fetch keeps showing the saved model; only a fetch the user asked for reports it")
    func failedFetchKeepsSavedModel() async throws {
        let server = SettingsPageTestServer(rows: [Self.withoutCatalog])
        server.route(
            "POST", "/api/v1/settings/models",
            [(400, #"{"type":"error","error":{"code":"VALIDATION_FAILED","message":"Invalid API key"}}"#)])
        let vm = await loadedViewModel(server)
        #expect(vm.hasCatalog == false)

        await vm.fetchModelsIfStale()
        #expect(server.requests(under: "/api/v1/settings/models").count == 1)
        #expect(vm.errorMessage == nil)
        #expect(vm.modelText == "claude-sonnet-5")
        #expect(vm.availableModels.isEmpty)

        await vm.fetchModels()
        #expect(vm.errorMessage?.contains("Invalid API key") == true)
        #expect(vm.modelText == "claude-sonnet-5")
        #expect(server.methods.filter { $0 == "POST" }.isEmpty)
    }

    @Test("a new key refetches the list; the same key does not")
    func changedKeyRefetches() async throws {
        let server = SettingsPageTestServer(rows: [Self.withCatalog])
        server.route("POST", "/api/v1/settings/models", [(200, Self.fetched)])
        let vm = await loadedViewModel(server)
        await vm.fetchModelsIfStale()
        #expect(server.requests(under: "/api/v1/settings/models").isEmpty)
        vm.apiKeyText = "sk-ant-new"
        await vm.fetchModelsIfStale()
        #expect(server.requests(under: "/api/v1/settings/models").count == 1)
        await vm.fetchModelsIfStale()
        #expect(server.requests(under: "/api/v1/settings/models").count == 1)
    }

    @Test("a saved model the provider no longer lists is kept and flagged")
    func staleModelIsFlagged() async throws {
        let server = SettingsPageTestServer(rows: [Self.withCatalog])
        server.route("POST", "/api/v1/settings/models", [(200, #"{"models":[{"id":"claude-opus-5","displayName":"Opus"}]}"#)])
        let vm = await loadedViewModel(server)
        #expect(vm.isModelStale == false)
        await vm.fetchModels()
        #expect(vm.modelText == "claude-sonnet-5")
        #expect(vm.isModelStale)
    }

    @Test("a list the computer cannot take stays on the phone for the session")
    func listStaysWhenStoringFails() async throws {
        let server = SettingsPageTestServer(rows: [Self.withCatalog], postStatus: 500)
        server.route("POST", "/api/v1/settings/models", [(200, Self.fetched)])
        let vm = await loadedViewModel(server)
        await vm.fetchModels()
        #expect(vm.errorMessage == nil)
        await vm.refresh()
        #expect(vm.availableModels.map(\.id) == ["claude-haiku-5", "claude-sonnet-5"])
    }
}
