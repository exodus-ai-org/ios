import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

@MainActor
@Suite("AI Providers: addresses")
struct ProviderAddressTests {
    private static let row = #"""
        {"id":"global","lastBackupAt":"2026-09-18T12:00:00.000Z",
         "providerConfig":{"provider":"OpenAI GPT","model":"gpt-5"},
         "providers":{"openaiApiKey":"sk-oai","openaiBaseUrl":"https://proxy.example.com/v1",
           "anthropicBaseUrl":"https://claude.example.com","azureOpenAiEndpoint":"https://r.openai.azure.com/openai/deployments/m",
           "azureOpenAiApiVersion":"2024-12-01-preview","ollamaBaseUrl":"http://mac.local:11434"}}
        """#

    private func loadedViewModel(_ server: SettingsPageTestServer, suite: String = #function) async -> SettingsViewModel {
        let (client, config) = server.makeClient(suite)
        let vm = SettingsViewModel(apiClient: client, serverConfig: config, store: SettingsStore(apiClient: client))
        await vm.loadSettings()
        return vm
    }

    @Test("each provider shows its own address, and switching keeps what was typed for the one left")
    func addressFollowsProvider() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loadedViewModel(server)
        #expect(vm.baseURLText == "https://proxy.example.com/v1")
        vm.baseURLText = "https://edited.example.com/v1"
        vm.select(provider: .anthropicClaude)
        #expect(vm.baseURLText == "https://claude.example.com")
        vm.select(provider: .azureOpenAi)
        #expect(vm.baseURLText == "https://r.openai.azure.com/openai/deployments/m")
        #expect(vm.azureApiVersionText == "2024-12-01-preview")
        vm.select(provider: .ollama)
        #expect(vm.baseURLText == "http://mac.local:11434")
        vm.select(provider: .googleGemini)
        #expect(vm.baseURLText == "")
        vm.select(provider: .openAiGpt)
        #expect(vm.baseURLText == "https://edited.example.com/v1")
    }

    @Test("save writes every provider's address, trimmed, an emptied one as absent; the moved OpenAI key is posted null")
    func saveWritesAddresses() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loadedViewModel(server)
        vm.baseURLText = "  https://edited.example.com/v1 \n"
        vm.select(provider: .anthropicClaude)
        vm.baseURLText = "   "
        vm.select(provider: .xaiGrok)
        vm.baseURLText = "https://api.x.ai/v1"
        vm.select(provider: .azureOpenAi)
        vm.azureApiVersionText = " 2025-01-01 "
        vm.select(provider: .openAiGpt)
        #expect(await vm.save())

        let body = try server.onlyPostBody()
        #expect(Set(body.keys) == ["id", "lastBackupAt", "providerConfig", "providers"])
        let providers = try #require(body["providers"] as? [String: Any])
        #expect(providers["openaiBaseUrl"] as? String == "https://edited.example.com/v1")
        #expect(providers["anthropicBaseUrl"] == nil)
        #expect(providers["xAiBaseUrl"] as? String == "https://api.x.ai/v1")
        #expect(providers["azureOpenAiEndpoint"] as? String == "https://r.openai.azure.com/openai/deployments/m")
        #expect(providers["azureOpenAiApiVersion"] as? String == "2025-01-01")
        #expect(providers["ollamaBaseUrl"] as? String == "http://mac.local:11434")
        // The desktop's destination rule: the saved key does not follow its address to another host.
        #expect(providers["openaiApiKey"] is NSNull)
        #expect(vm.lastSaveClearedKeys == [.openAiGpt])
        #expect(vm.baseURLText == "https://edited.example.com/v1")
    }

    @Test("an address that is not a URL blocks the save, names its provider and posts nothing")
    func invalidAddressBlocksSave() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loadedViewModel(server)
        vm.select(provider: .googleGemini)
        vm.baseURLText = "generativelanguage.googleapis.com"
        vm.select(provider: .openAiGpt)
        #expect(await vm.save() == false)
        #expect(vm.errorMessage?.contains("Google Gemini") == true)
        #expect(server.methods == ["GET"])
        #expect(vm.selectedProvider == .openAiGpt)
    }

    @Test("Ollama's address is a plain string on the desktop, so it is not checked")
    func ollamaAddressIsNotValidated() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loadedViewModel(server)
        vm.select(provider: .ollama)
        vm.baseURLText = "mac.local:11434/v1"
        #expect(await vm.save())
        let providers = try #require(try server.onlyPostBody()["providers"] as? [String: Any])
        #expect(providers["ollamaBaseUrl"] as? String == "mac.local:11434/v1")
    }

    @Test(
        "provider URLs are checked like the desktop's zod url()",
        arguments: [
            ("https://api.openai.com/v1", true), ("localhost:9200", true), ("http://192.168.1.2:11434", true),
            ("ftp://x.y", true), ("mailto:a@b.c", true), ("api.openai.com", false), ("http://", false),
            ("https://a b.com", false),
        ])
    func urlRuleMatchesDesktop(text: String, valid: Bool) {
        #expect(SettingsViewModel.isValidProviderURL(text) == valid)
    }

    @Test("the model list is asked for at the provider's own address")
    func fetchModelsSendsTheAddress() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loadedViewModel(server)
        await vm.fetchModels()
        let body = try #require(server.lastBody(to: "/api/v1/settings/models"))
        #expect(body["baseUrl"] as? String == "https://proxy.example.com/v1")
        vm.select(provider: .googleGemini)
        vm.apiKeyText = "AIza-1"
        await vm.fetchModels()
        #expect(server.lastBody(to: "/api/v1/settings/models")?["baseUrl"] == nil)
    }

    @Test("Azure has no model list on the desktop: its deployment name is typed, never fetched")
    func azureDoesNotListModels() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loadedViewModel(server)
        vm.select(provider: .azureOpenAi)
        vm.apiKeyText = "az-key"
        #expect(vm.providerListsModels == false)
        #expect(vm.canFetchModels == false)
        vm.select(provider: .anthropicClaude)
        #expect(vm.providerListsModels)
    }

    @Test("a provider save keeps keys this app does not model, in providerConfig, its snapshot and providers")
    func saveKeepsUnmodelledProviderKeys() async throws {
        let server = SettingsPageTestServer(rows: [#"""
            {"id":"global","providerConfig":{"provider":"OpenAI GPT","model":"gpt-5","routing":"auto",
               "modelSnapshot":{"contextWindow":1000,"reasoningLevels":[],"knowledgeCutoff":"2026-01"}},
             "providers":{"openaiApiKey":"sk","mistralApiKey":"m-1"}}
            """#])
        let vm = await loadedViewModel(server)
        vm.baseURLText = "https://proxy.example.com/v1"
        #expect(await vm.save())
        let body = try server.onlyPostBody()
        let config = try #require(body["providerConfig"] as? [String: Any])
        #expect(config["routing"] as? String == "auto")
        #expect((config["modelSnapshot"] as? [String: Any])?["knowledgeCutoff"] as? String == "2026-01")
        let providers = try #require(body["providers"] as? [String: Any])
        #expect(providers["mistralApiKey"] as? String == "m-1")
        #expect(providers["openaiBaseUrl"] as? String == "https://proxy.example.com/v1")
    }

    @Test("the page's placeholders are the desktop's")
    func placeholders() {
        #expect(ProviderSettingsPage.baseURLPlaceholder(.openAiGpt) == "https://api.openai.com/v1")
        #expect(ProviderSettingsPage.baseURLPlaceholder(.anthropicClaude) == "https://api.anthropic.com")
        #expect(ProviderSettingsPage.baseURLPlaceholder(.googleGemini) == "https://generativelanguage.googleapis.com")
        #expect(ProviderSettingsPage.baseURLPlaceholder(.xaiGrok) == "https://api.x.ai/v1")
        #expect(ProviderSettingsPage.baseURLPlaceholder(.ollama) == "http://localhost:11434")
        #expect(ProviderSettingsPage.keyPlaceholder(.anthropicClaude) == "sk-ant-...")
        #expect(ProviderSettingsPage.keyPlaceholder(.azureOpenAi) == nil)
    }
}
