import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import SettingsFeature

private final class SettingsMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SettingsMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// The mock handler runs on a URLProtocol thread, so the bodies it sees are recorded
/// behind a lock and asserted from the test afterwards (an `#expect` inside a handler
/// could silently never run).
private final class BodyRecorder: Sendable {
    private let storage = Mutex<[String: [Data]]>([:])

    func record(_ data: Data, for path: String) {
        storage.withLock { $0[path, default: []].append(data) }
    }

    func bodies(for path: String) -> [Data] {
        storage.withLock { $0[path] ?? [] }
    }

    /// The JSON object of the one and only body posted to `path`.
    func onlyJSONBody(for path: String) throws -> [String: Any] {
        let all = bodies(for: path)
        try #require(all.count == 1)
        let object = try JSONSerialization.jsonObject(with: all[0])
        return try #require(object as? [String: Any])
    }
}

/// Holds one request in the mock handler until the test lets it go, so a test can act while that
/// request is provably in flight. No sleeps: the test polls `waitUntilStarted()` and calls
/// `release()`. Every wait is bounded, so a failing test cannot hang.
private final class RequestGate: Sendable {
    private let started = Mutex(false)
    private let gate = DispatchSemaphore(value: 0)

    /// Called from the mock handler (URLProtocol thread): announce the request, then block until released.
    func arriveAndWait() {
        started.withLock { $0 = true }
        _ = gate.wait(timeout: .now() + 10)
    }

    func release() { gate.signal() }

    /// Suspends the test until the handler holds the request; fails (never hangs) after 10 seconds.
    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !started.withLock({ $0 }) {
            try #require(ContinuousClock.now < deadline, "the request never reached the mock handler")
            await Task.yield()
        }
    }
}

/// Installs a handler that answers by method + path and records every POST body.
private func serve(
    settings: String = #"{"id":"global"}"#,
    settingsStatus: Int = 200,
    models: String = #"{"models":[]}"#,
    modelsStatus: Int = 200,
    modelsGate: RequestGate? = nil,
    postSettingsStatus: Int = 200,
    postSettingsBody: String = "{}",
    recorder: BodyRecorder
) {
    SettingsMockURLProtocol.handler = { request in
        let path = request.url?.path ?? ""
        if request.httpMethod == "POST" {
            recorder.record(try request.httpBodyStreamData(), for: path)
        }
        switch (request.httpMethod, path) {
        case ("GET", "/api/settings"):
            return (settingsStatus, Data(settings.utf8))
        case ("POST", "/api/settings/models"):
            modelsGate?.arriveAndWait()
            return (modelsStatus, Data(models.utf8))
        case ("POST", "/api/settings"):
            return (postSettingsStatus, Data(postSettingsBody.utf8))
        default:
            return (404, Data(#"{"type":"error","error":{"code":"NOT_FOUND","message":"no route"}}"#.utf8))
        }
    }
}

@MainActor
@Suite("SettingsViewModel", .serialized)
struct SettingsViewModelTests {
    /// What the desktop has saved: Anthropic selected with a model snapshot, an OpenAI key
    /// for a provider that is not selected, and a last-backup timestamp.
    private static let loadedSettingsJSON = #"""
        {"id":"global",
         "providerConfig":{"provider":"Anthropic Claude","model":"claude-sonnet-5",
           "modelSnapshot":{"contextWindow":200000,"maxOutputTokens":64000,"reasoningLevels":["low","high"],"cost":{"input":3,"output":15}}},
         "providers":{"anthropicApiKey":"sk-ant-1","openaiApiKey":"sk-oai-2"},
         "lastBackupAt":"2026-09-18T12:00:00.000Z"}
        """#

    private func makeViewModel(_ suite: String = #function) -> (SettingsViewModel, ServerConfigStore) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let client = APIClient(session: SettingsMockURLProtocol.makeSession(), serverConfig: config)
        return (SettingsViewModel(apiClient: client, serverConfig: config), config)
    }

    private static let notLoadedMessage = "Connect to the server and load its settings before saving."
    private static let serverUnavailableJSON = #"{"type":"error","error":{"code":"INTERNAL","message":"Server unavailable"}}"#
    private static let claudeCatalogJSON = #"{"models":[{"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"reasoningLevels":[]}}]}"#
    private static let ollamaCatalogJSON = #"{"models":[{"id":"llama3","displayName":"Llama 3","snapshot":{"reasoningLevels":[]}}]}"#

    /// Starts `fetchModels()` for `provider` with `apiKey`, holds that request in flight in the mock
    /// handler while `duringRequest` runs, then lets the response through and waits for `fetchModels()`
    /// to finish. The test only proceeds once the handler really holds the request.
    private func fetchModelsInterrupted(
        provider: AiProviders = .anthropicClaude,
        apiKey: String = "sk-ant-xyz",
        modelsStatus: Int = 200,
        models: String = Self.claudeCatalogJSON,
        by duringRequest: (SettingsViewModel) -> Void
    ) async throws -> (vm: SettingsViewModel, recorder: BodyRecorder) {
        let recorder = BodyRecorder()
        let gate = RequestGate()
        serve(models: models, modelsStatus: modelsStatus, modelsGate: gate, recorder: recorder)
        let (vm, _) = makeViewModel()
        vm.select(provider: provider)
        vm.apiKeyText = apiKey
        let fetch = Task { await vm.fetchModels() }
        defer { gate.release() }  // also on the failure path, so the handler thread is never left blocked
        try await gate.waitUntilStarted()
        duringRequest(vm)
        gate.release()
        await fetch.value
        return (vm, recorder)
    }

    @Test("loadSettings populates the selected provider, model, and API key")
    func loadSettingsPopulatesForm() async throws {
        serve(settings: Self.loadedSettingsJSON, recorder: BodyRecorder())
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        #expect(vm.selectedProvider == .anthropicClaude)
        #expect(vm.modelText == "claude-sonnet-5")
        #expect(vm.apiKeyText == "sk-ant-1")
        #expect(vm.errorMessage == nil)
    }

    @Test("fetchModels posts the provider and key, and populates availableModels from the live catalog")
    func fetchModelsPopulatesCatalog() async throws {
        let recorder = BodyRecorder()
        serve(
            models: #"{"models":[{"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"reasoningLevels":[]}}]}"#,
            recorder: recorder)
        let (vm, _) = makeViewModel()
        vm.apiKeyText = "sk-ant-xyz"
        await vm.fetchModels()
        #expect(vm.availableModels.count == 1)
        #expect(vm.availableModels[0].id == "claude-sonnet-5")
        #expect(vm.errorMessage == nil)
        let body = try recorder.onlyJSONBody(for: "/api/settings/models")
        #expect(body["provider"] as? String == "Anthropic Claude")
        #expect(body["apiKey"] as? String == "sk-ant-xyz")
    }

    @Test("save() posts only id/providerConfig/providers and reports success")
    func saveSendsPartialPatch() async throws {
        let recorder = BodyRecorder()
        serve(recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()  // save() refuses without a loaded server state
        vm.apiKeyText = "sk-ant-xyz"
        vm.modelText = "claude-sonnet-5"
        let success = await vm.save()
        #expect(success)
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        #expect(Set(body.keys) == ["id", "providerConfig", "providers"])
        #expect(body["id"] as? String == "global")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        #expect(providerConfig["provider"] as? String == "Anthropic Claude")
        #expect(providerConfig["model"] as? String == "claude-sonnet-5")
        #expect(providerConfig.keys.contains("modelSnapshot") == false)
        let providers = try #require(body["providers"] as? [String: Any])
        #expect(providers["anthropicApiKey"] as? String == "sk-ant-xyz")
    }

    @Test("save() echoes the loaded lastBackupAt so the server does not null the desktop's timestamp")
    func saveEchoesLastBackupAt() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        #expect(body["lastBackupAt"] as? String == "2026-09-18T12:00:00.000Z")
    }

    @Test("save() keeps the model snapshot the desktop saved when provider and model are unchanged")
    func savePreservesLoadedModelSnapshot() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        let snapshot = try #require(providerConfig["modelSnapshot"] as? [String: Any])
        #expect(snapshot["contextWindow"] as? Double == 200_000)
        #expect(snapshot["maxOutputTokens"] as? Double == 64_000)
        #expect(snapshot["reasoningLevels"] as? [String] == ["low", "high"])
        let cost = try #require(snapshot["cost"] as? [String: Any])
        #expect(cost["input"] as? Double == 3)
        #expect(cost["output"] as? Double == 15)
    }

    @Test("save() sends the snapshot of the catalog entry the user picked, not the stale loaded one")
    func savePicksCatalogSnapshotForChosenModel() async throws {
        let recorder = BodyRecorder()
        serve(
            settings: Self.loadedSettingsJSON,
            models: #"{"models":[{"id":"claude-opus-5","displayName":"Claude Opus 5","snapshot":{"contextWindow":1000000,"reasoningLevels":["high"]}}]}"#,
            recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        await vm.fetchModels()
        vm.modelText = "claude-opus-5"
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        #expect(providerConfig["model"] as? String == "claude-opus-5")
        let snapshot = try #require(providerConfig["modelSnapshot"] as? [String: Any])
        #expect(snapshot["contextWindow"] as? Double == 1_000_000)
    }

    @Test("save() attaches no snapshot to a model the desktop has no snapshot for")
    func saveDropsSnapshotForAnUnknownModel() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        vm.modelText = "some-custom-model"
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        #expect(providerConfig["model"] as? String == "some-custom-model")
        #expect(providerConfig.keys.contains("modelSnapshot") == false)
    }

    @Test("save() attaches no snapshot when the provider changed, even if the new provider uses the same model name")
    func saveDropsSnapshotWhenOnlyTheProviderChanged() async throws {
        // OpenAI and Azure OpenAI share model names, so a matching model id alone must not carry
        // the snapshot the desktop saved for OpenAI over to Azure.
        let recorder = BodyRecorder()
        serve(
            settings: #"{"id":"global","providerConfig":{"provider":"OpenAI GPT","model":"gpt-4o","modelSnapshot":{"contextWindow":128000,"maxOutputTokens":16384,"reasoningLevels":[]}},"providers":{"openaiApiKey":"sk-oai-2"}}"#,
            recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        vm.select(provider: .azureOpenAi)
        vm.modelText = "gpt-4o"  // the very model name the desktop saved for OpenAI
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        #expect(providerConfig["provider"] as? String == "Azure OpenAI")
        #expect(providerConfig["model"] as? String == "gpt-4o")
        #expect(providerConfig.keys.contains("modelSnapshot") == false)
    }

    @Test("switching provider swaps the key and model, clears the catalog, and switching back restores them")
    func switchingProviderSwapsKeyAndResetsModel() async throws {
        serve(
            settings: Self.loadedSettingsJSON,
            models: #"{"models":[{"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"reasoningLevels":[]}}]}"#,
            recorder: BodyRecorder())
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        await vm.fetchModels()
        #expect(vm.availableModels.count == 1)

        vm.select(provider: .openAiGpt)
        #expect(vm.selectedProvider == .openAiGpt)
        #expect(vm.apiKeyText == "sk-oai-2")
        #expect(vm.modelText == "")
        #expect(vm.availableModels.isEmpty)

        vm.select(provider: .anthropicClaude)
        #expect(vm.apiKeyText == "sk-ant-1")
        #expect(vm.modelText == "claude-sonnet-5")
    }

    @Test("saving after a provider switch never copies the previous provider's key into the new one")
    func savingAfterSwitchNeverCopiesTheOldKey() async throws {
        let recorder = BodyRecorder()
        serve(
            settings: #"{"id":"global","providerConfig":{"provider":"Anthropic Claude","model":"claude-sonnet-5"},"providers":{"anthropicApiKey":"sk-ant-1"}}"#,
            recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        vm.select(provider: .openAiGpt)
        #expect(vm.apiKeyText == "")
        vm.modelText = "gpt-x"
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        #expect(providerConfig["provider"] as? String == "OpenAI GPT")
        let providers = try #require(body["providers"] as? [String: Any])
        #expect(providers["anthropicApiKey"] as? String == "sk-ant-1")
        #expect(providers.keys.contains("openaiApiKey") == false)
    }

    @Test("clearing the key field removes that provider's key and leaves the other providers' keys alone")
    func clearingAKeyRemovesOnlyThatKey() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        vm.apiKeyText = ""
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providers = try #require(body["providers"] as? [String: Any])
        #expect(providers.keys.contains("anthropicApiKey") == false)
        #expect(providers["openaiApiKey"] as? String == "sk-oai-2")
    }

    @Test("Ollama needs no API key: no key field, and the model list can be fetched without one")
    func ollamaNeedsNoApiKey() async throws {
        let recorder = BodyRecorder()
        serve(recorder: recorder)
        let (vm, _) = makeViewModel()
        #expect(vm.providerUsesApiKey)
        #expect(vm.canFetchModels == false)  // Anthropic, no key typed yet

        vm.select(provider: .ollama)
        #expect(vm.providerUsesApiKey == false)
        #expect(vm.canFetchModels)
        await vm.fetchModels()
        let body = try recorder.onlyJSONBody(for: "/api/settings/models")
        #expect(body["provider"] as? String == "Ollama")
        #expect(body.keys.contains("apiKey") == false)
    }

    @Test("a bare host:port is normalized to an http:// address, stored, and shown back")
    func saveServerURLNormalizes() async throws {
        let cases: [(input: String, expected: String)] = [
            ("192.168.1.10:60223", "http://192.168.1.10:60223"),
            ("  http://mac.local:60223/  ", "http://mac.local:60223"),
            ("https://exodus.example.com", "https://exodus.example.com"),
        ]
        for (input, expected) in cases {
            let (vm, config) = makeViewModel()
            vm.serverURLText = input
            #expect(vm.saveServerURL(), "\(input) should be accepted")
            #expect(config.baseURLString == expected)
            #expect(vm.serverURLText == expected)
            #expect(vm.errorMessage == nil)
        }
    }

    @Test("an unusable server address is refused with a message and the stored one is left untouched")
    func saveServerURLRejectsGarbage() async throws {
        for input in ["", "   ", "http://", "://", "ftp://host"] {
            let (vm, config) = makeViewModel()
            vm.serverURLText = input
            #expect(vm.saveServerURL() == false, "\(input.debugDescription) should be refused")
            #expect(vm.errorMessage != nil)
            #expect(config.baseURLString == "http://localhost:60223")
        }
    }

    @Test("a transport failure is shown as a human message, not a URLError dump")
    func transportErrorUsesAHumanMessage() async throws {
        SettingsMockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        let message = try #require(vm.errorMessage)
        #expect(message == URLError(.cannotConnectToHost).localizedDescription)
        // A `String(describing:)` dump reads `Error Domain=NSURLErrorDomain Code=-1004 …` (possibly wrapped in
        // `URLError(_nsError: …)`). Match `Domain=`, not the bare word "URLError": the human fallback
        // "(NSURLErrorDomain error -1004.)" contains that word too.
        #expect(message.contains("Domain=") == false)
    }

    @Test("a failed save surfaces the server's error message")
    func saveSurfacesServerError() async throws {
        serve(
            postSettingsStatus: 400,
            postSettingsBody: #"{"type":"error","error":{"code":"VALIDATION_FAILED","message":"Invalid setting configuration"}}"#,
            recorder: BodyRecorder())
        let (vm, _) = makeViewModel()
        await vm.loadSettings()  // save() refuses without a loaded server state
        let success = await vm.save()
        #expect(success == false)
        #expect(vm.errorMessage == "Invalid setting configuration")
    }

    // MARK: Never write to a server whose settings were not loaded (ruling 8)

    @Test("save() is refused and posts nothing when the settings failed to load")
    func saveIsRefusedWhenTheLoadFailed() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.serverUnavailableJSON, settingsStatus: 500, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        #expect(vm.hasLoadedSettings == false)
        #expect(vm.errorMessage == "Server unavailable")

        vm.apiKeyText = "sk-ant-xyz"  // what a first-run user types after the failed load
        vm.modelText = "claude-sonnet-5"
        #expect(await vm.save() == false)
        #expect(vm.errorMessage == Self.notLoadedMessage)
        #expect(recorder.bodies(for: "/api/settings").isEmpty)
    }

    @Test("save() is refused and posts nothing when settings were never loaded")
    func saveIsRefusedBeforeAnyLoad() async throws {
        let recorder = BodyRecorder()
        serve(recorder: recorder)
        let (vm, _) = makeViewModel()
        #expect(vm.hasLoadedSettings == false)
        vm.apiKeyText = "sk-ant-xyz"
        #expect(await vm.save() == false)
        #expect(vm.errorMessage == Self.notLoadedMessage)
        #expect(recorder.bodies(for: "/api/settings").isEmpty)
    }

    @Test("a failed reload clears the loaded state, so save() is refused again")
    func saveIsRefusedAfterAFailedReload() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        #expect(vm.hasLoadedSettings)

        serve(settings: Self.serverUnavailableJSON, settingsStatus: 500, recorder: recorder)
        await vm.loadSettings()
        #expect(vm.hasLoadedSettings == false)
        #expect(await vm.save() == false)
        #expect(recorder.bodies(for: "/api/settings").isEmpty)
    }

    @Test("a new server address has to be loaded before anything is saved to it")
    func changingTheServerAddressRequiresAReloadBeforeSaving() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, config) = makeViewModel()
        await vm.loadSettings()
        #expect(vm.hasLoadedSettings)

        vm.serverURLText = "192.168.1.10:60223"
        #expect(vm.saveServerURL())
        #expect(config.baseURLString == "http://192.168.1.10:60223")
        #expect(vm.hasLoadedSettings == false)
        #expect(await vm.save() == false)
        #expect(recorder.bodies(for: "/api/settings").isEmpty)

        await vm.loadSettings()  // "Connect": load the new server's settings
        #expect(vm.hasLoadedSettings)
        #expect(await vm.save())
        _ = try recorder.onlyJSONBody(for: "/api/settings")  // exactly one POST: the save after the reload
    }

    @Test("saving the address that is already stored leaves the loaded state alone")
    func savingTheSameServerAddressKeepsTheLoadedState() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, config) = makeViewModel()
        await vm.loadSettings()
        #expect(vm.hasLoadedSettings)

        // The stored default, typed with a trailing slash: it normalizes to what is already stored.
        vm.serverURLText = "http://localhost:60223/"
        #expect(vm.saveServerURL())
        #expect(config.baseURLString == "http://localhost:60223")
        #expect(vm.hasLoadedSettings)
        #expect(await vm.save())
    }

    // MARK: A model list is applied only if it is still the current one (ruling 9)

    @Test("a model list that arrives after the provider was switched is ignored", .timeLimit(.minutes(1)))
    func aModelListForAnotherProviderIsIgnored() async throws {
        // Ollama needs no key, so the OpenAI form it is switched to has the same (empty) key:
        // only the provider tells the two apart.
        let (vm, recorder) = try await fetchModelsInterrupted(
            provider: .ollama, apiKey: "", models: Self.ollamaCatalogJSON
        ) { vm in
            vm.select(provider: .openAiGpt)
        }
        // The request that was in flight was for Ollama ...
        let body = try recorder.onlyJSONBody(for: "/api/settings/models")
        #expect(body["provider"] as? String == "Ollama")
        // ... so its catalog must not appear under OpenAI, and nothing else about OpenAI changed.
        #expect(vm.selectedProvider == .openAiGpt)
        #expect(vm.availableModels.isEmpty)
        #expect(vm.apiKeyText == "")
        #expect(vm.modelText == "")
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoadingModels == false)
    }

    @Test("a model list requested with a key the user has since edited is ignored", .timeLimit(.minutes(1)))
    func aModelListRequestedWithAnEditedKeyIsIgnored() async throws {
        let (vm, recorder) = try await fetchModelsInterrupted { vm in
            vm.apiKeyText = "sk-ant-xyz-edited"
        }
        let body = try recorder.onlyJSONBody(for: "/api/settings/models")
        #expect(body["apiKey"] as? String == "sk-ant-xyz")
        #expect(vm.availableModels.isEmpty)
        #expect(vm.apiKeyText == "sk-ant-xyz-edited")
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoadingModels == false)
    }

    @Test("a failed model-list request that is no longer current does not show its error", .timeLimit(.minutes(1)))
    func aStaleModelListFailureIsNotShown() async throws {
        let (vm, _) = try await fetchModelsInterrupted(
            modelsStatus: 401,
            models: #"{"type":"error","error":{"code":"UNAUTHORIZED","message":"Invalid API key"}}"#
        ) { vm in
            vm.select(provider: .openAiGpt)
        }
        #expect(vm.selectedProvider == .openAiGpt)
        #expect(vm.errorMessage == nil)  // the Anthropic key's error must not be shown under OpenAI
        #expect(vm.availableModels.isEmpty)
        #expect(vm.isLoadingModels == false)
    }

    // MARK: Keys typed per provider survive provider switches (ruling 1)

    @Test("keys typed for two providers are both saved")
    func typedKeysForSeveralProvidersAreAllSaved() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()  // Anthropic selected; loaded keys are sk-ant-1 and sk-oai-2
        vm.apiKeyText = "sk-ant-typed"  // replaces the loaded Anthropic key
        vm.select(provider: .openAiGpt)
        vm.apiKeyText = "sk-oai-typed"  // replaces the loaded OpenAI key
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providers = try #require(body["providers"] as? [String: Any])
        #expect(providers["anthropicApiKey"] as? String == "sk-ant-typed")
        #expect(providers["openaiApiKey"] as? String == "sk-oai-typed")
    }

    @Test("switching back restores the key typed for that provider, not the one that was loaded")
    func switchingBackRestoresTheTypedKey() async throws {
        serve(settings: Self.loadedSettingsJSON, recorder: BodyRecorder())
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        vm.apiKeyText = "sk-ant-typed"
        vm.select(provider: .openAiGpt)
        vm.apiKeyText = "sk-oai-typed"

        vm.select(provider: .anthropicClaude)
        #expect(vm.apiKeyText == "sk-ant-typed")
        vm.select(provider: .openAiGpt)
        #expect(vm.apiKeyText == "sk-oai-typed")
    }
}

extension URLRequest {
    fileprivate func httpBodyStreamData() throws -> Data {
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
