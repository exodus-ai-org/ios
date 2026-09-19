import Foundation
import Testing

@testable import Models

@Suite("Settings wire types")
struct SettingsTests {
    @Test("AiProviders raw values match the server's enum strings exactly")
    func providerRawValues() {
        #expect(AiProviders.openAiGpt.rawValue == "OpenAI GPT")
        #expect(AiProviders.azureOpenAi.rawValue == "Azure OpenAI")
        #expect(AiProviders.anthropicClaude.rawValue == "Anthropic Claude")
        #expect(AiProviders.googleGemini.rawValue == "Google Gemini")
        #expect(AiProviders.xaiGrok.rawValue == "xAI Grok")
        #expect(AiProviders.ollama.rawValue == "Ollama")
    }

    @Test("decodes GET /api/settings, ignoring fields this client doesn't model")
    func decodesSettingsSnapshot() throws {
        let json = """
            {
              "id": "global",
              "providerConfig": {"provider": "Anthropic Claude", "model": "claude-sonnet-5"},
              "providers": {"anthropicApiKey": "sk-ant-xyz"},
              "lastBackupAt": "2026-09-18T12:00:00.000Z",
              "personality": {"baseStyle": "default"},
              "memory": {"autoCapture": true}
            }
            """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: json)
        #expect(snapshot.id == "global")
        #expect(snapshot.providerConfig?.provider == "Anthropic Claude")
        #expect(snapshot.providers?.anthropicApiKey == "sk-ant-xyz")
        #expect(snapshot.lastBackupAt == "2026-09-18T12:00:00.000Z")
    }

    @Test("a null lastBackupAt (never backed up) decodes to nil")
    func decodesNullLastBackupAt() throws {
        let json = #"{"id":"global","lastBackupAt":null}"#.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: json)
        #expect(snapshot.lastBackupAt == nil)
    }

    @Test("SettingsPatch encodes id/providerConfig/providers, and lastBackupAt only when set")
    func encodesSettingsPatch() throws {
        let patch = SettingsPatch(
            id: "global",
            providerConfig: ProviderConfig(provider: "Anthropic Claude", model: "claude-sonnet-5", modelSnapshot: nil),
            providers: ProvidersConfig().settingApiKey("sk-ant-xyz", for: .anthropicClaude)
        )
        let data = try JSONEncoder().encode(patch)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["id"] as? String == "global")
        let providerConfig = obj?["providerConfig"] as? [String: Any]
        #expect(providerConfig?["provider"] as? String == "Anthropic Claude")
        let providers = obj?["providers"] as? [String: Any]
        #expect(providers?["anthropicApiKey"] as? String == "sk-ant-xyz")
        #expect(obj?.keys.contains("lastBackupAt") == false)
    }

    @Test("SettingsPatch echoes lastBackupAt so the server's unconditional write doesn't null it")
    func settingsPatchEchoesLastBackupAt() throws {
        let patch = SettingsPatch(
            id: "global", providerConfig: nil, providers: nil, lastBackupAt: "2026-09-18T12:00:00.000Z")
        let data = try JSONEncoder().encode(patch)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["lastBackupAt"] as? String == "2026-09-18T12:00:00.000Z")
    }

    @Test("ProvidersConfig.apiKey(for:) and settingApiKey(_:for:) round-trip every provider")
    func providersConfigAccessors() {
        // Every provider except Ollama has a settable API key field (Ollama has
        // no `ollamaApiKey` in ProvidersSchema — it runs unauthenticated
        // locally, only `ollamaBaseUrl` exists).
        for provider in AiProviders.allCases where provider != .ollama {
            let updated = ProvidersConfig().settingApiKey("k-\(provider.rawValue)", for: provider)
            #expect(updated.apiKey(for: provider) == "k-\(provider.rawValue)")
        }
    }

    @Test("Ollama has no API key field by design — set/get are both no-ops")
    func ollamaHasNoApiKey() {
        let updated = ProvidersConfig().settingApiKey("k-Ollama", for: .ollama)
        #expect(updated.apiKey(for: .ollama) == nil)
        #expect(updated == ProvidersConfig())
    }

    // MARK: - ModelSnapshot tolerates missing keys (the server persists posted settings without validation)

    @Test("an empty snapshot object decodes to the defaults instead of throwing")
    func emptyModelSnapshotDecodesToDefaults() throws {
        let snapshot = try JSONDecoder().decode(ModelSnapshot.self, from: Data("{}".utf8))
        #expect(snapshot == ModelSnapshot())
        #expect(snapshot.reasoningLevels == [])
        #expect(snapshot.contextWindow == nil)
        #expect(snapshot.maxOutputTokens == nil)
        #expect(snapshot.cost == nil)
    }

    @Test("a snapshot whose every field is null decodes to the defaults")
    func nullModelSnapshotFieldsDecodeToDefaults() throws {
        let json = #"{"contextWindow":null,"maxOutputTokens":null,"reasoningLevels":null,"cost":null}"#
        let snapshot = try JSONDecoder().decode(ModelSnapshot.self, from: Data(json.utf8))
        #expect(snapshot == ModelSnapshot())
    }

    @Test("a snapshot with only some keys keeps those values and defaults the rest")
    func partialModelSnapshotKeepsWhatIsThere() throws {
        let json = #"{"contextWindow":200000,"cost":{"input":3,"output":15}}"#
        let snapshot = try JSONDecoder().decode(ModelSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.contextWindow == 200000)
        #expect(snapshot.cost == ModelCost(input: 3, output: 15))
        #expect(snapshot.maxOutputTokens == nil)
        #expect(snapshot.reasoningLevels == [])
    }

    @Test("a full snapshot round-trips through encode and decode unchanged, with all four keys on the wire")
    func fullModelSnapshotRoundTrips() throws {
        let original = ModelSnapshot(
            contextWindow: 200000, maxOutputTokens: 8192, reasoningLevels: ["off", "low", "high"],
            cost: ModelCost(input: 3, output: 15))
        let data = try JSONEncoder().encode(original)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["contextWindow", "maxOutputTokens", "reasoningLevels", "cost"])
        #expect(try JSONDecoder().decode(ModelSnapshot.self, from: data) == original)
    }

    @Test("a default snapshot still encodes reasoningLevels as an empty array and round-trips")
    func defaultModelSnapshotRoundTrips() throws {
        let data = try JSONEncoder().encode(ModelSnapshot())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["reasoningLevels"] as? [Any])?.isEmpty == true)
        #expect(try JSONDecoder().decode(ModelSnapshot.self, from: data) == ModelSnapshot())
    }

    @Test("a settings snapshot whose stored modelSnapshot lacks reasoningLevels still decodes")
    func settingsSnapshotWithLegacyModelSnapshotDecodes() throws {
        let json = """
            {
              "id": "global",
              "providerConfig": {
                "provider": "Anthropic Claude",
                "model": "claude-sonnet-5",
                "modelSnapshot": {"contextWindow": 200000, "maxOutputTokens": 8192, "cost": {"input": 3, "output": 15}}
              },
              "providers": {"anthropicApiKey": "sk-ant-xyz"}
            }
            """
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.providerConfig?.provider == "Anthropic Claude")
        #expect(snapshot.providerConfig?.modelSnapshot?.contextWindow == 200000)
        #expect(snapshot.providerConfig?.modelSnapshot?.reasoningLevels == [])
        #expect(snapshot.providers?.anthropicApiKey == "sk-ant-xyz")
    }

    @Test("a catalog entry whose snapshot lacks reasoningLevels still decodes")
    func catalogEntryWithoutReasoningLevelsDecodes() throws {
        let json = #"{"models":[{"id":"m1","displayName":"Model One","snapshot":{}}]}"#
        let response = try JSONDecoder().decode(ListModelsResponse.self, from: Data(json.utf8))
        #expect(response.models.map(\.id) == ["m1"])
        #expect(response.models[0].snapshot == ModelSnapshot())
    }

    @Test("decodes a live model catalog response")
    func decodesListModelsResponse() throws {
        let json = """
            {"models":[{"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"contextWindow":200000,"maxOutputTokens":8192,"reasoningLevels":["off","low"],"cost":{"input":3,"output":15}}}]}
            """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ListModelsResponse.self, from: json)
        #expect(response.models.count == 1)
        #expect(response.models[0].id == "claude-sonnet-5")
        #expect(response.models[0].snapshot.reasoningLevels == ["off", "low"])
    }
}
