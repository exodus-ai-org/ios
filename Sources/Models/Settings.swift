import Foundation

public struct ModelCost: Codable, Equatable, Sendable {
    public var input: Double
    public var output: Double

    public init(input: Double, output: Double) {
        self.input = input
        self.output = output
    }
}

public struct ModelSnapshot: Codable, Equatable, Sendable {
    public var contextWindow: Double?
    public var maxOutputTokens: Double?
    public var reasoningLevels: [String]
    public var cost: ModelCost?

    public init(
        contextWindow: Double? = nil,
        maxOutputTokens: Double? = nil,
        reasoningLevels: [String] = [],
        cost: ModelCost? = nil
    ) {
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.reasoningLevels = reasoningLevels
        self.cost = cost
    }

    /// Tolerant on purpose: the desktop's schema defaults `reasoningLevels` to `[]` and its server
    /// stores whatever settings are posted, so a stored snapshot can lack any key. A strict decode
    /// would fail the whole `SettingsSnapshot`, and the phone could then never load or save
    /// settings. Encoding stays the synthesized one (all four keys, `nil` optionals omitted).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contextWindow = try container.decodeIfPresent(Double.self, forKey: .contextWindow)
        maxOutputTokens = try container.decodeIfPresent(Double.self, forKey: .maxOutputTokens)
        reasoningLevels = try container.decodeIfPresent([String].self, forKey: .reasoningLevels) ?? []
        cost = try container.decodeIfPresent(ModelCost.self, forKey: .cost)
    }
}

public struct ProviderConfig: Codable, Equatable, Sendable {
    public var provider: String?
    public var model: String?
    public var modelSnapshot: ModelSnapshot?

    public init(provider: String? = nil, model: String? = nil, modelSnapshot: ModelSnapshot? = nil) {
        self.provider = provider
        self.model = model
        self.modelSnapshot = modelSnapshot
    }
}

public struct ProvidersConfig: Codable, Equatable, Sendable {
    public var openaiApiKey: String?
    public var openaiBaseUrl: String?
    public var azureOpenaiApiKey: String?
    public var azureOpenAiEndpoint: String?
    public var azureOpenAiApiVersion: String?
    public var anthropicApiKey: String?
    public var anthropicBaseUrl: String?
    public var googleGeminiApiKey: String?
    public var googleGeminiBaseUrl: String?
    public var xAiApiKey: String?
    public var xAiBaseUrl: String?
    public var ollamaBaseUrl: String?

    public init(
        openaiApiKey: String? = nil,
        openaiBaseUrl: String? = nil,
        azureOpenaiApiKey: String? = nil,
        azureOpenAiEndpoint: String? = nil,
        azureOpenAiApiVersion: String? = nil,
        anthropicApiKey: String? = nil,
        anthropicBaseUrl: String? = nil,
        googleGeminiApiKey: String? = nil,
        googleGeminiBaseUrl: String? = nil,
        xAiApiKey: String? = nil,
        xAiBaseUrl: String? = nil,
        ollamaBaseUrl: String? = nil
    ) {
        self.openaiApiKey = openaiApiKey
        self.openaiBaseUrl = openaiBaseUrl
        self.azureOpenaiApiKey = azureOpenaiApiKey
        self.azureOpenAiEndpoint = azureOpenAiEndpoint
        self.azureOpenAiApiVersion = azureOpenAiApiVersion
        self.anthropicApiKey = anthropicApiKey
        self.anthropicBaseUrl = anthropicBaseUrl
        self.googleGeminiApiKey = googleGeminiApiKey
        self.googleGeminiBaseUrl = googleGeminiBaseUrl
        self.xAiApiKey = xAiApiKey
        self.xAiBaseUrl = xAiBaseUrl
        self.ollamaBaseUrl = ollamaBaseUrl
    }

    public func apiKey(for provider: AiProviders) -> String? {
        switch provider {
        case .openAiGpt: return openaiApiKey
        case .azureOpenAi: return azureOpenaiApiKey
        case .anthropicClaude: return anthropicApiKey
        case .googleGemini: return googleGeminiApiKey
        case .xaiGrok: return xAiApiKey
        case .ollama: return nil
        }
    }

    public func settingApiKey(_ key: String?, for provider: AiProviders) -> ProvidersConfig {
        var copy = self
        switch provider {
        case .openAiGpt: copy.openaiApiKey = key
        case .azureOpenAi: copy.azureOpenaiApiKey = key
        case .anthropicClaude: copy.anthropicApiKey = key
        case .googleGemini: copy.googleGeminiApiKey = key
        case .xaiGrok: copy.xAiApiKey = key
        case .ollama: break
        }
        return copy
    }
}

public struct CachedModelEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var snapshot: ModelSnapshot

    public init(id: String, displayName: String, snapshot: ModelSnapshot) {
        self.id = id
        self.displayName = displayName
        self.snapshot = snapshot
    }
}

public struct SettingsSnapshot: Decodable, Sendable {
    public var id: String
    public var providerConfig: ProviderConfig?
    public var providers: ProvidersConfig?
    /// ISO-8601 string (or nil = never backed up). Carried only so `SettingsPatch` can echo it.
    public var lastBackupAt: String?
}

public struct SettingsPatch: Encodable, Sendable {
    public var id: String
    public var providerConfig: ProviderConfig?
    public var providers: ProvidersConfig?
    /// The server writes `lastBackupAt` unconditionally on every `POST /api/settings`
    /// (`lastBackupAt ? new Date(lastBackupAt) : null`), so the value read from the
    /// `SettingsSnapshot` must be sent back or the desktop's "last backup" is nulled.
    public var lastBackupAt: String?

    public init(id: String, providerConfig: ProviderConfig?, providers: ProvidersConfig?, lastBackupAt: String? = nil) {
        self.id = id
        self.providerConfig = providerConfig
        self.providers = providers
        self.lastBackupAt = lastBackupAt
    }
}

public struct ListModelsRequest: Encodable, Sendable {
    public var provider: String
    public var apiKey: String?
    public var baseUrl: String?
    public var apiVersion: String?

    public init(provider: String, apiKey: String?, baseUrl: String?, apiVersion: String?) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.apiVersion = apiVersion
    }
}

public struct ListModelsResponse: Decodable, Sendable {
    public var models: [CachedModelEntry]
}
