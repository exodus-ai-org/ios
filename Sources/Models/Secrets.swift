import Foundation

/// The computer hands every stored secret out as a mask (exodus `src/main/lib/secrets/mask.ts`): `"•••• " + last4`
/// for a value of 12 characters or more, `"••••"` for a shorter one, `null` for none. A mask posted back means
/// "unchanged"; `null` clears.
public enum SecretMask {
    public static let bullets = "••••"
    private static let minLengthForTail = 12

    /// Either mask shape — `"••••"` or `"•••• "` followed by four characters.
    public static func looksLikeMask(_ value: String?) -> Bool {
        guard let value else { return false }
        if value == bullets { return true }
        let prefix = bullets + " "
        guard value.hasPrefix(prefix) else { return false }
        return value.dropFirst(prefix.count).unicodeScalars.count == 4
    }

    /// The desktop's `maskSecret`: what a value looks like once it has left the computer. The length is the desktop's
    /// (`value.length`, UTF-16 units); the tail is four code points, the unit `looksLikeMask` counts on both sides.
    public static func mask(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard value.utf16.count >= minLengthForTail else { return bullets }
        return "\(bullets) \(String(String.UnicodeScalarView(value.unicodeScalars.suffix(4))))"
    }

    /// The four characters a saved key is shown by, or nil when it is too short to show any (`"••••"`).
    /// A value that is not a mask (a computer from before masking) is judged by the same rule.
    public static func lastFour(of value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let masked = looksLikeMask(value) ? value : (mask(value) ?? bullets)
        guard masked != bullets else { return nil }
        return String(masked.dropFirst(bullets.count + 1))
    }
}

/// The desktop's destination rule (`SECRET_DESTINATIONS`, `secrets/registry.ts`): a stored key goes only to the address
/// it was saved with. A write that moves the address while the key is posted as its mask clears the key.
public enum SecretDestinations {
    /// The address each provider's key is sent to when its base URL is unset (`PROVIDER_BASE_URL`).
    public static func fallbackBaseURL(for provider: AiProviders) -> String? {
        switch provider {
        case .openAiGpt: "https://api.openai.com/v1"
        case .anthropicClaude: "https://api.anthropic.com"
        case .googleGemini: "https://generativelanguage.googleapis.com/v1beta"
        case .xaiGrok: "https://api.x.ai/v1"
        case .azureOpenAi, .ollama: nil
        }
    }

    /// The settings path of each provider's key (`PROVIDER_KEY_FIELD`), as `needsReentry` names it.
    public static func keyPath(for provider: AiProviders) -> String? {
        switch provider {
        case .openAiGpt: "providers.openaiApiKey"
        case .azureOpenAi: "providers.azureOpenaiApiKey"
        case .anthropicClaude: "providers.anthropicApiKey"
        case .googleGemini: "providers.googleGeminiApiKey"
        case .xaiGrok: "providers.xAiApiKey"
        case .ollama: nil
        }
    }

    /// The desktop's `normalizeBaseUrl` (`@exodus/shared/utils/base-url`): trimmed, scheme and host lowercased, no
    /// trailing slash, the query kept; nil for an empty one.
    public static func normalizeBaseURL(_ url: String?) -> String? {
        guard let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme,
            trimmed.contains("://"), let host = components.host, !host.isEmpty
        else {
            return trimmed.replacing(/\/+$/, with: "")
        }
        var authority = host.lowercased()
        if host.contains(":"), !host.hasPrefix("[") { authority = "[\(authority)]" }
        if let port = components.port, port != defaultPort(scheme.lowercased()) { authority += ":\(port)" }
        let path = removingDotSegments(components.percentEncodedPath).replacing(/\/+$/, with: "")
        var result = "\(scheme.lowercased())://\(authority)\(path)"
        if let query = components.percentEncodedQuery, !query.isEmpty { result += "?\(query)" }
        return result
    }

    /// Whether moving `provider`'s address from `before` to `after` takes its saved key away from where it was saved.
    public static func moves(_ provider: AiProviders, from before: String?, to after: String?) -> Bool {
        let fallback = fallbackBaseURL(for: provider)
        let from = normalizeBaseURL(before) ?? normalizeBaseURL(fallback)
        let to = normalizeBaseURL(after) ?? normalizeBaseURL(fallback)
        return from != to
    }

    /// WHATWG's path parsing (what `new URL` does): `.` and `..` segments (also `%2e`) resolved, never above the root.
    static func removingDotSegments(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        var output: [Substring] = []
        let count = segments.count
        for (index, segment) in segments.enumerated() {
            let lowered = segment.lowercased()
            let isLast = index == count - 1
            if lowered == ".." || lowered == ".%2e" || lowered == "%2e." || lowered == "%2e%2e" {
                if !output.isEmpty { output.removeLast() }
                if isLast { output.append("") }
            } else if lowered == "." || lowered == "%2e" {
                if isLast { output.append("") }
            } else {
                output.append(segment)
            }
        }
        return "/" + output.joined(separator: "/")
    }

    private static func defaultPort(_ scheme: String) -> Int? {
        switch scheme {
        case "http": 80
        case "https": 443
        default: nil
        }
    }
}

/// `GET /api/v1/settings/secrets-status` (exodus `secrets/status.ts`): whether secrets are encrypted at rest, and the
/// stored ones to enter again — those that no longer decrypt and those a change of address cleared.
public struct SecretsStatus: Decodable, Equatable, Sendable {
    public enum Encryption: Equatable, Sendable {
        case on, unavailable
        case other(String)
    }

    public var encryption: Encryption
    /// A settings path (`providers.openaiApiKey`) or an MCP label (`mcp:<server>:env.GITHUB_TOKEN`).
    public var needsReentry: [String]

    public init(encryption: Encryption, needsReentry: [String]) {
        self.encryption = encryption
        self.needsReentry = needsReentry
    }

    private enum CodingKeys: String, CodingKey { case encryption, needsReentry }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .encryption)
        switch raw {
        case "on": encryption = .on
        case "unavailable": encryption = .unavailable
        default: encryption = .other(raw)
        }
        let names = (try? container.decodeIfPresent([JSONValue].self, forKey: .needsReentry)) ?? []
        var seen = Set<String>()
        needsReentry = names.compactMap {
            guard case .string(let name) = $0, !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }
}

/// One name from `needsReentry`, read the way the desktop's notice reads it (`secrets-notices.tsx`).
public enum SecretReentryName: Equatable, Sendable {
    /// A settings registry path the desktop has a name for.
    case setting(SettingSecret)
    /// `mcp:<server>:<column>.<name>` (or `url` / `args`); a server name may hold a colon, a column never does.
    case mcp(server: String, field: String)
    /// Anything else, shown as sent.
    case unknown(String)

    public enum SettingSecret: String, CaseIterable, Sendable {
        case openaiApiKey = "providers.openaiApiKey"
        case azureOpenaiApiKey = "providers.azureOpenaiApiKey"
        case anthropicApiKey = "providers.anthropicApiKey"
        case googleGeminiApiKey = "providers.googleGeminiApiKey"
        case xAiApiKey = "providers.xAiApiKey"
        case googleApiKey = "googleCloud.googleApiKey"
        case braveApiKey = "webSearch.braveApiKey"
        case elasticsearchPassword = "fullTextSearch.elasticsearch.password"
        case knowledgeBaseApiKey = "knowledgeBase.apiKey"
        case s3AccessKeyId = "s3.accessKeyId"
        case s3SecretAccessKey = "s3.secretAccessKey"
        case legacyMcpServers = "mcpServers"

        /// The provider whose key this is, when it is one.
        public var provider: AiProviders? {
            AiProviders.allCases.first { SecretDestinations.keyPath(for: $0) == rawValue }
        }
    }

    public init(_ name: String) {
        if let setting = SettingSecret(rawValue: name) {
            self = .setting(setting)
        } else if let match = name.wholeMatch(of: /mcp:(.+):((?:env|headers|extraConfig)\..+|url|args)/) {
            self = .mcp(server: String(match.1), field: String(match.2))
        } else {
            self = .unknown(name)
        }
    }
}

extension ProvidersConfig {
    /// Every key as the computer would hand it out: a key typed on the phone and just saved is not kept in plaintext.
    public func maskingKeys() -> ProvidersConfig {
        var copy = self
        for provider in AiProviders.allCases {
            if let key = apiKey(for: provider), !SecretMask.looksLikeMask(key) {
                copy = copy.settingApiKey(SecretMask.mask(key), for: provider)
            }
        }
        return copy
    }
}
