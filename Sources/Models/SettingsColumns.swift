import Foundation

/// `settings.personality` (the desktop's `PersonalitySchema`). The five style fields are plain strings, not enums,
/// so a value the desktop adds later still decodes and is written back as read.
public struct PersonalitySettings: Codable, Equatable, Sendable {
    public var nickname: String?
    public var occupation: String?
    public var aboutYou: String?
    public var baseStyle: String
    public var warm: String
    public var enthusiastic: String
    public var headersAndLists: String
    public var emoji: String
    public var customInstructions: String?
    public var unmodelledFields: [String: JSONValue]

    public init(
        nickname: String? = nil,
        occupation: String? = nil,
        aboutYou: String? = nil,
        baseStyle: String = "default",
        warm: String = "default",
        enthusiastic: String = "default",
        headersAndLists: String = "default",
        emoji: String = "default",
        customInstructions: String? = nil,
        unmodelledFields: [String: JSONValue] = [:]
    ) {
        self.nickname = nickname
        self.occupation = occupation
        self.aboutYou = aboutYou
        self.baseStyle = baseStyle
        self.warm = warm
        self.enthusiastic = enthusiastic
        self.headersAndLists = headersAndLists
        self.emoji = emoji
        self.customInstructions = customInstructions
        self.unmodelledFields = unmodelledFields
    }

    private static let modelledKeys: Set<String> = [
        "nickname", "occupation", "aboutYou", "baseStyle", "warm", "enthusiastic", "headersAndLists", "emoji",
        "customInstructions",
    ]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let defaults = PersonalitySettings()
        nickname = c.lenient(String.self, forKey: "nickname")
        occupation = c.lenient(String.self, forKey: "occupation")
        aboutYou = c.lenient(String.self, forKey: "aboutYou")
        baseStyle = c.lenient(String.self, forKey: "baseStyle") ?? defaults.baseStyle
        warm = c.lenient(String.self, forKey: "warm") ?? defaults.warm
        enthusiastic = c.lenient(String.self, forKey: "enthusiastic") ?? defaults.enthusiastic
        headersAndLists = c.lenient(String.self, forKey: "headersAndLists") ?? defaults.headersAndLists
        emoji = c.lenient(String.self, forKey: "emoji") ?? defaults.emoji
        customInstructions = c.lenient(String.self, forKey: "customInstructions")
        unmodelledFields = c.unmodelledFields(except: Self.modelledKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encodeUnmodelled(unmodelledFields)
        try c.encodeIfPresent(nickname, forKey: "nickname")
        try c.encodeIfPresent(occupation, forKey: "occupation")
        try c.encodeIfPresent(aboutYou, forKey: "aboutYou")
        try c.encode(baseStyle, forKey: "baseStyle")
        try c.encode(warm, forKey: "warm")
        try c.encode(enthusiastic, forKey: "enthusiastic")
        try c.encode(headersAndLists, forKey: "headersAndLists")
        try c.encode(emoji, forKey: "emoji")
        try c.encodeIfPresent(customInstructions, forKey: "customInstructions")
    }
}

/// `settings.memory` (the desktop's `MemorySchema`). The two limits are stored unvalidated by the server, so they
/// are carried as read; the page that edits them clamps (50–95, 2–24).
public struct MemorySettings: Codable, Equatable, Sendable {
    public var autoCapture: Bool
    public var useInChat: Bool
    public var lcmEnabled: Bool
    public var contextWindowPercent: Double?
    public var freshTailSize: Double?
    public var unmodelledFields: [String: JSONValue]

    public init(
        autoCapture: Bool = true,
        useInChat: Bool = true,
        lcmEnabled: Bool = true,
        contextWindowPercent: Double? = nil,
        freshTailSize: Double? = nil,
        unmodelledFields: [String: JSONValue] = [:]
    ) {
        self.autoCapture = autoCapture
        self.useInChat = useInChat
        self.lcmEnabled = lcmEnabled
        self.contextWindowPercent = contextWindowPercent
        self.freshTailSize = freshTailSize
        self.unmodelledFields = unmodelledFields
    }

    private static let modelledKeys: Set<String> = [
        "autoCapture", "useInChat", "lcmEnabled", "contextWindowPercent", "freshTailSize",
    ]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        autoCapture = c.lenient(Bool.self, forKey: "autoCapture") ?? true
        useInChat = c.lenient(Bool.self, forKey: "useInChat") ?? true
        lcmEnabled = c.lenient(Bool.self, forKey: "lcmEnabled") ?? true
        contextWindowPercent = c.lenient(Double.self, forKey: "contextWindowPercent")
        freshTailSize = c.lenient(Double.self, forKey: "freshTailSize")
        unmodelledFields = c.unmodelledFields(except: Self.modelledKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encodeUnmodelled(unmodelledFields)
        try c.encode(autoCapture, forKey: "autoCapture")
        try c.encode(useInChat, forKey: "useInChat")
        try c.encode(lcmEnabled, forKey: "lcmEnabled")
        try c.encodeIfPresent(contextWindowPercent, forKey: "contextWindowPercent")
        try c.encodeIfPresent(freshTailSize, forKey: "freshTailSize")
    }
}

/// `settings.tools` (the desktop's `ToolsSchema`): wire names of the built-in tools the user switched off.
public struct ToolsSettings: Codable, Equatable, Sendable {
    public var disabledTools: [String]
    public var unmodelledFields: [String: JSONValue]

    public init(disabledTools: [String] = [], unmodelledFields: [String: JSONValue] = [:]) {
        self.disabledTools = disabledTools
        self.unmodelledFields = unmodelledFields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        disabledTools = c.lenient([String].self, forKey: "disabledTools") ?? []
        unmodelledFields = c.unmodelledFields(except: ["disabledTools"])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encodeUnmodelled(unmodelledFields)
        try c.encode(disabledTools, forKey: "disabledTools")
    }
}

/// One jsonb column of the `settings` row the phone may write. `POST /api/v1/settings` replaces a column whole,
/// so a column is only ever written as a complete value.
public struct SettingsColumn<Value: Codable & Equatable & Sendable> {
    public let name: String
    public let keyPath: WritableKeyPath<SettingsSnapshot, Value?>
    /// What a page starts from when the stored row has no such column yet.
    public let emptyValue: Value

    public func assigning(_ value: Value) -> SettingsColumnValue {
        let keyPath = keyPath
        return SettingsColumnValue(name: name, value: value) { $0[keyPath: keyPath] = value }
    }
}

extension SettingsColumn where Value == ProviderConfig {
    public static var providerConfig: Self { Self(name: "providerConfig", keyPath: \.providerConfig, emptyValue: .init()) }
}

extension SettingsColumn where Value == ProvidersConfig {
    public static var providers: Self { Self(name: "providers", keyPath: \.providers, emptyValue: .init()) }

    /// Writes `value`, with each of `cleared`'s keys posted as an explicit `null` (the desktop's "clear") when it has none.
    public func assigning(_ value: Value, clearing cleared: Set<AiProviders>) -> SettingsColumnValue {
        let keyPath = keyPath
        return SettingsColumnValue(name: name, value: ProvidersClearingWrite(config: value, cleared: cleared)) {
            $0[keyPath: keyPath] = value
        }
    }
}

/// A providers column whose cleared keys are sent as `null` rather than left out; the server treats both as unset.
struct ProvidersClearingWrite: Encodable, Sendable {
    let config: ProvidersConfig
    let cleared: Set<AiProviders>

    func encode(to encoder: Encoder) throws {
        try config.encode(to: encoder)
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for provider in AiProviders.allCases where cleared.contains(provider) && config.apiKey(for: provider) == nil {
            guard let path = SecretDestinations.keyPath(for: provider) else { continue }
            try container.encodeNil(forKey: AnyCodingKey(String(path.dropFirst("providers.".count))))
        }
    }
}

extension SettingsColumn where Value == PersonalitySettings {
    public static var personality: Self { Self(name: "personality", keyPath: \.personality, emptyValue: .init()) }
}

extension SettingsColumn where Value == MemorySettings {
    public static var memory: Self { Self(name: "memory", keyPath: \.memory, emptyValue: .init()) }
}

extension SettingsColumn where Value == ToolsSettings {
    public static var tools: Self { Self(name: "tools", keyPath: \.tools, emptyValue: .init()) }
}

extension SettingsColumn where Value == ModelCatalog {
    public static var modelCatalog: Self { Self(name: "modelCatalog", keyPath: \.modelCatalog, emptyValue: .init()) }
}

extension SettingsColumn where Value == String {
    /// A text column, not jsonb: the value is the tone's raw name.
    public static var colorTone: Self { Self(name: "colorTone", keyPath: \.colorTone, emptyValue: ColorTone.neutral.rawValue) }
}

/// A column with the value to write, and how to apply it to a snapshot once the write succeeded.
public struct SettingsColumnValue {
    public let name: String
    public let value: any Encodable & Sendable
    public let apply: (inout SettingsSnapshot) -> Void
}

/// The body of `POST /api/v1/settings`: `id`, `lastBackupAt` and the columns being written, nothing else. The
/// server sets exactly the columns present and writes `lastBackupAt` on every call (`value ? new Date(value) :
/// null`), so both `id` and `lastBackupAt` are always sent as last read, `null` included.
public struct SettingsWriteBody: Encodable, Sendable {
    public let id: String
    public let lastBackupAt: String?
    public let columns: [(name: String, value: any Encodable & Sendable)]

    public init(id: String, lastBackupAt: String?, columns: [(name: String, value: any Encodable & Sendable)]) {
        self.id = id
        self.lastBackupAt = lastBackupAt
        self.columns = columns
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(id, forKey: "id")
        if let lastBackupAt {
            try c.encode(lastBackupAt, forKey: "lastBackupAt")
        } else {
            try c.encodeNil(forKey: "lastBackupAt")
        }
        for column in columns {
            try c.encode(column.value, forKey: AnyCodingKey(column.name))
        }
    }
}

struct AnyCodingKey: CodingKey, ExpressibleByStringLiteral {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init(stringLiteral value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer {
    /// The value, or nil when the key is absent, null or holds something of another type.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

extension KeyedDecodingContainer where Key == AnyCodingKey {
    func unmodelledFields(except modelled: Set<String>) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        for key in allKeys where !modelled.contains(key.stringValue) {
            if let value = lenient(JSONValue.self, forKey: key) { fields[key.stringValue] = value }
        }
        return fields
    }
}

extension KeyedEncodingContainer where Key == AnyCodingKey {
    mutating func encodeUnmodelled(_ fields: [String: JSONValue]) throws {
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            try encode(value, forKey: AnyCodingKey(key))
        }
    }
}
