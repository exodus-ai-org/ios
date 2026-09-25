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
    /// Keys the phone does not model, written back as read: `providerConfig` is replaced whole on save.
    public var unmodelledFields: [String: JSONValue]

    public init(
        contextWindow: Double? = nil,
        maxOutputTokens: Double? = nil,
        reasoningLevels: [String] = [],
        cost: ModelCost? = nil,
        unmodelledFields: [String: JSONValue] = [:]
    ) {
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.reasoningLevels = reasoningLevels
        self.cost = cost
        self.unmodelledFields = unmodelledFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contextWindow, maxOutputTokens, reasoningLevels, cost
    }

    /// Tolerant on purpose: the desktop's schema defaults `reasoningLevels` to `[]` and its server
    /// stores whatever settings are posted, so a stored snapshot can lack any key. A strict decode
    /// would fail the whole `SettingsSnapshot`, and the phone could then never load or save
    /// settings. Encoding writes the four keys (`nil` optionals omitted) plus any key it did not model.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contextWindow = try container.decodeIfPresent(Double.self, forKey: .contextWindow)
        maxOutputTokens = try container.decodeIfPresent(Double.self, forKey: .maxOutputTokens)
        reasoningLevels = try container.decodeIfPresent([String].self, forKey: .reasoningLevels) ?? []
        cost = try container.decodeIfPresent(ModelCost.self, forKey: .cost)
        unmodelledFields = try decoder.container(keyedBy: AnyCodingKey.self)
            .unmodelledFields(except: Set(CodingKeys.allCases.map(\.rawValue)))
    }

    public func encode(to encoder: Encoder) throws {
        var unmodelled = encoder.container(keyedBy: AnyCodingKey.self)
        try unmodelled.encodeUnmodelled(unmodelledFields)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(contextWindow, forKey: .contextWindow)
        try container.encodeIfPresent(maxOutputTokens, forKey: .maxOutputTokens)
        try container.encode(reasoningLevels, forKey: .reasoningLevels)
        try container.encodeIfPresent(cost, forKey: .cost)
    }
}

public struct ProviderConfig: Codable, Equatable, Sendable {
    public var provider: String?
    public var model: String?
    public var modelSnapshot: ModelSnapshot?
    /// Keys the phone does not model, written back as read: the server replaces the column whole.
    public var unmodelledFields: [String: JSONValue]

    public init(
        provider: String? = nil, model: String? = nil, modelSnapshot: ModelSnapshot? = nil,
        unmodelledFields: [String: JSONValue] = [:]
    ) {
        self.provider = provider
        self.model = model
        self.modelSnapshot = modelSnapshot
        self.unmodelledFields = unmodelledFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case provider, model, modelSnapshot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        modelSnapshot = try container.decodeIfPresent(ModelSnapshot.self, forKey: .modelSnapshot)
        unmodelledFields = try decoder.container(keyedBy: AnyCodingKey.self)
            .unmodelledFields(except: Set(CodingKeys.allCases.map(\.rawValue)))
    }

    public func encode(to encoder: Encoder) throws {
        var unmodelled = encoder.container(keyedBy: AnyCodingKey.self)
        try unmodelled.encodeUnmodelled(unmodelledFields)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(modelSnapshot, forKey: .modelSnapshot)
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
    /// Keys the phone does not model, written back as read: the server replaces the column whole.
    public var unmodelledFields: [String: JSONValue]

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
        ollamaBaseUrl: String? = nil,
        unmodelledFields: [String: JSONValue] = [:]
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
        self.unmodelledFields = unmodelledFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case openaiApiKey, openaiBaseUrl, azureOpenaiApiKey, azureOpenAiEndpoint, azureOpenAiApiVersion
        case anthropicApiKey, anthropicBaseUrl, googleGeminiApiKey, googleGeminiBaseUrl, xAiApiKey, xAiBaseUrl
        case ollamaBaseUrl
    }

    private static var fields: [(CodingKeys, WritableKeyPath<ProvidersConfig, String?>)] { [
        (.openaiApiKey, \.openaiApiKey), (.openaiBaseUrl, \.openaiBaseUrl), (.azureOpenaiApiKey, \.azureOpenaiApiKey),
        (.azureOpenAiEndpoint, \.azureOpenAiEndpoint), (.azureOpenAiApiVersion, \.azureOpenAiApiVersion),
        (.anthropicApiKey, \.anthropicApiKey), (.anthropicBaseUrl, \.anthropicBaseUrl),
        (.googleGeminiApiKey, \.googleGeminiApiKey), (.googleGeminiBaseUrl, \.googleGeminiBaseUrl),
        (.xAiApiKey, \.xAiApiKey), (.xAiBaseUrl, \.xAiBaseUrl), (.ollamaBaseUrl, \.ollamaBaseUrl),
    ] }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for (key, keyPath) in Self.fields {
            self[keyPath: keyPath] = try container.decodeIfPresent(String.self, forKey: key)
        }
        unmodelledFields = try decoder.container(keyedBy: AnyCodingKey.self)
            .unmodelledFields(except: Set(CodingKeys.allCases.map(\.rawValue)))
    }

    public func encode(to encoder: Encoder) throws {
        var unmodelled = encoder.container(keyedBy: AnyCodingKey.self)
        try unmodelled.encodeUnmodelled(unmodelledFields)
        var container = encoder.container(keyedBy: CodingKeys.self)
        for (key, keyPath) in Self.fields {
            try container.encodeIfPresent(self[keyPath: keyPath], forKey: key)
        }
    }

    /// The twelve key and address fields, in the schema's order.
    public static var fieldKeyPaths: [WritableKeyPath<ProvidersConfig, String?>] { fields.map(\.1) }

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

    /// The address the provider is reached at: the base URL, Azure's endpoint, Ollama's server.
    public func baseUrl(for provider: AiProviders) -> String? {
        switch provider {
        case .openAiGpt: return openaiBaseUrl
        case .azureOpenAi: return azureOpenAiEndpoint
        case .anthropicClaude: return anthropicBaseUrl
        case .googleGemini: return googleGeminiBaseUrl
        case .xaiGrok: return xAiBaseUrl
        case .ollama: return ollamaBaseUrl
        }
    }

    public func settingBaseUrl(_ url: String?, for provider: AiProviders) -> ProvidersConfig {
        var copy = self
        switch provider {
        case .openAiGpt: copy.openaiBaseUrl = url
        case .azureOpenAi: copy.azureOpenAiEndpoint = url
        case .anthropicClaude: copy.anthropicBaseUrl = url
        case .googleGemini: copy.googleGeminiBaseUrl = url
        case .xaiGrok: copy.xAiBaseUrl = url
        case .ollama: copy.ollamaBaseUrl = url
        }
        return copy
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

    private enum CodingKeys: String, CodingKey {
        case id, displayName, snapshot
    }

    /// Only `id` is required: a catalog the desktop stored without a name or a snapshot still lists the model.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = container.lenient(String.self, forKey: .displayName) ?? id
        snapshot = container.lenient(ModelSnapshot.self, forKey: .snapshot) ?? ModelSnapshot()
    }
}

/// `settings.modelCatalog` (the desktop's `ModelCatalogSchema`): each provider's last fetched model list, keyed by
/// the `AiProviders` value. Lists are kept as stored, so one the phone did not refetch is written back unchanged.
public struct ModelCatalog: Codable, Equatable, Sendable {
    public var lists: [String: JSONValue]

    public init(lists: [String: JSONValue] = [:]) {
        self.lists = lists
    }

    public init(from decoder: Decoder) throws {
        lists = try [String: JSONValue](from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encodeUnmodelled(lists)
    }

    /// The provider's stored list, skipping any entry without an `id`; nil when none is stored.
    public func models(for provider: AiProviders) -> [CachedModelEntry]? {
        guard case .array(let items) = lists[provider.rawValue] else { return nil }
        return items.compactMap { item in
            guard let data = try? JSONEncoder().encode(item) else { return nil }
            return try? JSONDecoder().decode(CachedModelEntry.self, from: data)
        }
    }

    public func setting(_ models: [CachedModelEntry], for provider: AiProviders) -> ModelCatalog {
        var copy = self
        if let data = try? JSONEncoder().encode(models), let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            copy.lists[provider.rawValue] = value
        }
        return copy
    }
}

/// The row `GET /api/v1/settings` returns, as far as the phone reads it. Every column decodes leniently: a stored
/// row can lack any key or hold one the desktop wrote in another shape, and one bad column must not make the
/// whole row, and with it every Settings page, unreadable. A column that cannot be read is `nil` and is listed in
/// `unreadableColumns`, so no page mistakes it for an empty one and writes over it.
public struct SettingsSnapshot: Decodable, Sendable {
    public var id: String
    public var providerConfig: ProviderConfig?
    public var providers: ProvidersConfig?
    public var personality: PersonalitySettings?
    public var memory: MemorySettings?
    public var tools: ToolsSettings?
    public var modelCatalog: ModelCatalog?
    /// The desktop's `colorTone` as stored; `ColorTone(stored:)` reads it. A scalar the phone may replace whole,
    /// so a value of another type is simply nil rather than an unreadable column.
    public var colorTone: String?
    /// ISO-8601 string (or nil = never backed up). Carried only so a write can echo it.
    public var lastBackupAt: String?
    /// Columns present in the row that could not be decoded: shown as unreadable, never written over.
    public var unreadableColumns: Set<String>

    public init(
        id: String,
        providerConfig: ProviderConfig? = nil,
        providers: ProvidersConfig? = nil,
        personality: PersonalitySettings? = nil,
        memory: MemorySettings? = nil,
        tools: ToolsSettings? = nil,
        modelCatalog: ModelCatalog? = nil,
        colorTone: String? = nil,
        lastBackupAt: String? = nil,
        unreadableColumns: Set<String> = []
    ) {
        self.id = id
        self.providerConfig = providerConfig
        self.providers = providers
        self.personality = personality
        self.memory = memory
        self.tools = tools
        self.modelCatalog = modelCatalog
        self.colorTone = colorTone
        self.lastBackupAt = lastBackupAt
        self.unreadableColumns = unreadableColumns
    }

    private enum CodingKeys: String, CodingKey {
        case id, providerConfig, providers, personality, memory, tools, modelCatalog, colorTone, lastBackupAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        var unreadable: Set<String> = []
        func column<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            guard container.contains(key), (try? container.decodeNil(forKey: key)) == false else { return nil }
            do {
                return try container.decode(type, forKey: key)
            } catch {
                unreadable.insert(key.stringValue)
                return nil
            }
        }
        providerConfig = column(ProviderConfig.self, .providerConfig)
        providers = column(ProvidersConfig.self, .providers)
        personality = column(PersonalitySettings.self, .personality)
        memory = column(MemorySettings.self, .memory)
        tools = column(ToolsSettings.self, .tools)
        modelCatalog = column(ModelCatalog.self, .modelCatalog)
        colorTone = container.lenient(String.self, forKey: .colorTone)
        lastBackupAt = container.lenient(String.self, forKey: .lastBackupAt)
        unreadableColumns = unreadable
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
