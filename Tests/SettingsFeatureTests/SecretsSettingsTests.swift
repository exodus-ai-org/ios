import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

/// The Providers page against a computer that hands keys out as masks (exodus `secrets/`), and the Settings notice.
@MainActor
@Suite("Secrets: masked keys on the Providers page")
struct SecretsSettingsTests {
    /// As `GET /api/v1/settings` answers since masking: the Anthropic key as its mask, OpenAI's too short to show.
    private static let row = #"""
        {"id":"global","lastBackupAt":null,
         "providerConfig":{"provider":"Anthropic Claude","model":"claude-sonnet-5"},
         "providers":{"anthropicApiKey":"•••• 7f3a","anthropicBaseUrl":"https://llm-proxy.example.com",
           "openaiApiKey":"••••"}}
        """#

    private func loaded(_ server: SettingsPageTestServer, suite: String = #function) async -> SettingsViewModel {
        let (client, config) = server.makeClient(suite)
        let vm = SettingsViewModel(apiClient: client, serverConfig: config, store: SettingsStore(apiClient: client))
        await vm.loadSettings()
        return vm
    }

    private func postedProviders(_ server: SettingsPageTestServer) throws -> [String: Any] {
        try #require(try server.onlyPostBody()["providers"] as? [String: Any])
    }

    @Test("a saved key is described, never put in the field; saving without typing posts the mask back (unchanged)")
    func unchangedSavePostsMask() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loaded(server)
        #expect(vm.apiKeyText == "")
        #expect(vm.savedKeyState == .saved(lastFour: "7f3a"))
        vm.modelText = "claude-opus-5"
        #expect(await vm.save())
        let providers = try postedProviders(server)
        #expect(providers["anthropicApiKey"] as? String == "•••• 7f3a")
        #expect(providers["openaiApiKey"] as? String == "••••")
        vm.select(provider: .openAiGpt)
        #expect(vm.savedKeyState == .saved(lastFour: nil))
        #expect(vm.apiKeyText == "")
    }

    @Test("typing replaces the saved key; once saved it is held only as its mask")
    func typingReplaces() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loaded(server)
        vm.apiKeyText = "sk-ant-new-key-0123"
        #expect(vm.savedKeyState == .replacing(hadKey: true))
        #expect(await vm.save())
        #expect(try postedProviders(server)["anthropicApiKey"] as? String == "sk-ant-new-key-0123")
        #expect(vm.apiKeyText == "")
        #expect(vm.savedKeyState == .saved(lastFour: "0123"))
    }

    @Test("a key typed here and saved is not kept in memory, not even as the model list's key")
    func typedKeyNotKept() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        server.route(
            "POST", "/api/v1/settings/models",
            [(200, #"{"models":[{"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"reasoningLevels":[]}}]}"#)])
        let vm = await loaded(server)
        vm.apiKeyText = "sk-ant-typed-secret-9876"
        await vm.fetchModels()
        #expect(vm.availableModels.count == 1)
        #expect(await vm.save())
        var dumped = ""
        dump(vm, to: &dumped)
        #expect(dumped.contains("•••• 9876"))
        #expect(dumped.contains("sk-ant-typed-secret-9876") == false)
        await vm.fetchModelsIfStale()
        #expect(server.requests(under: "/api/v1/settings/models").count == 2, "the saved key is a new key for the list")
    }

    @Test("Clear posts null; Keep takes a pending Clear back")
    func clearPostsNull() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loaded(server)
        vm.clearKey()
        #expect(vm.savedKeyState == .willClear)
        vm.keepSavedKey()
        #expect(vm.savedKeyState == .saved(lastFour: "7f3a"))
        #expect(vm.hasUnsavedChanges == false)
        vm.clearKey()
        #expect(await vm.save())
        let providers = try postedProviders(server)
        #expect(providers["anthropicApiKey"] is NSNull)
        #expect(providers["openaiApiKey"] as? String == "••••")
        #expect(vm.savedKeyState == .none)
    }

    @Test("the address says it clears the key only while one is saved, and a real move is told from a cosmetic edit")
    func destinationHint() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loaded(server)
        #expect(vm.addressGuardsSavedKey)
        #expect(vm.addressMovesSavedKey == false)
        vm.baseURLText = "HTTPS://LLM-proxy.example.com/"
        #expect(vm.addressMovesSavedKey == false)
        vm.baseURLText = "https://gateway.example.net"
        #expect(vm.addressMovesSavedKey)
        vm.apiKeyText = "sk-ant-typed"
        #expect(vm.addressGuardsSavedKey == false)
        vm.apiKeyText = ""
        vm.select(provider: .googleGemini)
        #expect(vm.addressGuardsSavedKey == false)
        vm.select(provider: .ollama)
        #expect(vm.addressGuardsSavedKey == false)
    }

    @Test("saving a moved address posts the saved key as null, stays to ask for it, and typing a key ends the ask")
    func movedAddressClearsKey() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loaded(server)
        vm.baseURLText = "https://gateway.example.net"
        #expect(await vm.save())
        let providers = try postedProviders(server)
        #expect(providers["anthropicApiKey"] is NSNull)
        #expect(providers["anthropicBaseUrl"] as? String == "https://gateway.example.net")
        #expect(providers["openaiApiKey"] as? String == "••••")
        #expect(vm.lastSaveClearedKeys == [.anthropicClaude])
        #expect(vm.keyNeedsReentry(status: nil))
        vm.apiKeyText = "sk-ant-for-the-gateway"
        #expect(vm.keyNeedsReentry(status: nil) == false)
        vm.apiKeyText = ""
        #expect(vm.keyNeedsReentry(status: nil) == false)
    }

    @Test("a cosmetic edit of the address keeps the key (posted as its mask)")
    func cosmeticEditKeepsKey() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loaded(server)
        vm.baseURLText = "https://LLM-proxy.example.com/"
        #expect(await vm.save())
        #expect(try postedProviders(server)["anthropicApiKey"] as? String == "•••• 7f3a")
        #expect(vm.lastSaveClearedKeys.isEmpty)
    }

    @Test("the computer's needsReentry asks for a key that is not saved; a saved one is not asked for")
    func needsReentryFromStatus() async throws {
        let server = SettingsPageTestServer(rows: [
            #"{"id":"global","providerConfig":{"provider":"OpenAI GPT"},"providers":{"anthropicApiKey":"•••• 7f3a"}}"#
        ])
        let vm = await loaded(server)
        let status = SecretsStatus(encryption: .on, needsReentry: ["providers.openaiApiKey", "providers.anthropicApiKey"])
        #expect(vm.keyNeedsReentry(status: status))
        vm.select(provider: .anthropicClaude)
        #expect(vm.keyNeedsReentry(status: status) == false)
        vm.select(provider: .xaiGrok)
        #expect(vm.keyNeedsReentry(status: status) == false)
    }

    @Test("the model list is asked for with the saved key's mask; a SECRET_REENTRY_REQUIRED on apiKey shows under the key")
    func inlineReentry() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        server.route(
            "POST", "/api/v1/settings/models",
            [(
                400,
                #"{"type":"error","error":{"code":"SECRET_REENTRY_REQUIRED","message":"The base URL differs from the saved one: re-enter the API key to use it with a new base URL","params":{"field":"apiKey"}}}"#
            )])
        let vm = await loaded(server)
        vm.baseURLText = "https://gateway.example.net"
        await vm.fetchModels()
        let body = try #require(server.lastBody("POST", "/api/v1/settings/models"))
        #expect(body["apiKey"] as? String == "•••• 7f3a")
        #expect(body["baseUrl"] as? String == "https://gateway.example.net")
        #expect(vm.keyReentryMessage == SettingsViewModel.keyReentryText)
        #expect(vm.errorMessage == nil)
        vm.baseURLText = "https://llm-proxy.example.com"
        #expect(vm.keyReentryMessage == nil)
    }

    @Test("a quiet fetch still shows the re-entry ask; any other error of a quiet fetch stays quiet")
    func quietFetch() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        server.route(
            "POST", "/api/v1/settings/models",
            [
                (400, #"{"type":"error","error":{"code":"SECRET_REENTRY_REQUIRED","message":"m","params":{"field":"apiKey"}}}"#),
                (500, #"{"type":"error","error":{"code":"INTERNAL","message":"down"}}"#),
            ])
        let vm = await loaded(server)
        await vm.fetchModels(quietly: true)
        #expect(vm.keyReentryMessage != nil)
        vm.apiKeyText = "sk-typed"
        #expect(vm.keyReentryMessage == nil)
        await vm.fetchModels(quietly: true)
        #expect(vm.keyReentryMessage == nil)
        #expect(vm.errorMessage == nil)
    }
}

@MainActor
@Suite("Secrets: the Settings notice")
struct SecretsNoticeTests {
    @Test("names read as the desktop's notice names them; provider keys open Providers, the rest stay on the computer")
    func mapping() {
        let items = SecretNoticeItem.items(for: [
            "providers.openaiApiKey", "webSearch.braveApiKey", "mcp:github:env.GITHUB_TOKEN", "future.secret",
        ])
        #expect(items.map(\.title) == ["OpenAI API key", "Brave Search API key", "MCP server “github”: env.GITHUB_TOKEN", "future.secret"])
        #expect(items.map(\.page) == [.providers, nil, nil, nil])
        #expect(SecretNoticeItem.items(for: ["providers.azureOpenaiApiKey"]).first?.page == .providers)
        #expect(SecretNoticeItem.items(for: ["s3.secretAccessKey"]).first?.title == "Amazon S3 secret access key")
    }

    @Test("each provider key's line names its provider, since the jump opens Providers on the active one")
    func linesNameTheProvider() {
        let names = [
            "providers.openaiApiKey": "OpenAI", "providers.azureOpenaiApiKey": "Azure OpenAI",
            "providers.anthropicApiKey": "Anthropic", "providers.googleGeminiApiKey": "Gemini", "providers.xAiApiKey": "xAI",
        ]
        for (key, provider) in names {
            let item = SecretNoticeItem.items(for: [key])[0]
            #expect(item.page == .providers)
            #expect(item.title.contains(provider), "\(key): \(item.title)")
        }
    }

    @Test("a jump from the notice, then Save, leaves the active provider and model as the computer has them")
    func jumpThenSaveKeepsProvider() async throws {
        let server = SettingsPageTestServer(rows: [
            #"{"id":"global","providerConfig":{"provider":"Anthropic Claude","model":"claude-sonnet-5"},"providers":{"anthropicApiKey":"•••• 1234"}}"#
        ])
        let (client, config) = server.makeClient()
        let vm = SettingsViewModel(apiClient: client, serverConfig: config, store: SettingsStore(apiClient: client))
        await vm.loadSettings()
        var path: [SettingsPage] = []
        let xai = SecretNoticeItem.items(for: ["providers.xAiApiKey"])[0]
        SecretNoticeJump.open(xai, path: &path, settings: vm)
        #expect(path == [.providers])
        #expect(vm.selectedProvider == .anthropicClaude)
        #expect(vm.modelText == "claude-sonnet-5")
        #expect(await vm.save())
        let posted = try server.onlyPostBody()
        let providerConfig = try #require(posted["providerConfig"] as? [String: Any])
        #expect(providerConfig["provider"] as? String == "Anthropic Claude")
        #expect(providerConfig["model"] as? String == "claude-sonnet-5")
    }

    @Test("the status is read from the computer; a computer without the route shows no notice")
    func load() async throws {
        let server = SettingsPageTestServer(rows: [#"{"id":"global"}"#])
        server.route(
            "GET", "/api/v1/settings/secrets-status",
            [
                (200, #"{"encryption":"unavailable","needsReentry":["providers.xAiApiKey"]}"#),
                (500, #"{"type":"error","error":{"code":"INTERNAL","message":"down"}}"#),
                (404, #"{"type":"error","error":{"code":"NOT_FOUND","message":"no"}}"#),
            ])
        let model = SecretsStatusModel(apiClient: server.makeClient().0)
        await model.load()
        #expect(model.status == SecretsStatus(encryption: .unavailable, needsReentry: ["providers.xAiApiKey"]))
        await model.load()
        #expect(model.status?.needsReentry == ["providers.xAiApiKey"], "a failed read keeps what was shown")
        await model.load()
        #expect(model.status == nil)
    }
}
