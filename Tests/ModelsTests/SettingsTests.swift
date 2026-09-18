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
              "personality": {"baseStyle": "default"},
              "memory": {"autoCapture": true}
            }
            """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: json)
        #expect(snapshot.id == "global")
        #expect(snapshot.providerConfig?.provider == "Anthropic Claude")
        #expect(snapshot.providers?.anthropicApiKey == "sk-ant-xyz")
    }

    @Test("SettingsPatch encodes only id/providerConfig/providers")
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
