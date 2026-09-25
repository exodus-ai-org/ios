import Foundation

/// What a report may carry off the phone. Callers already pass only kinds, codes, paths and counts; this is the
/// second line: secrets that slipped into text are masked, URLs lose their query and credentials, attributes named
/// like a secret or a body are dropped, and everything is cut short.
public enum LogRedaction {
    static let maxScopeLength = 64
    static let maxMessageLength = 500
    static let maxValueLength = 500
    static let maxAttributes = 16
    static let redacted = "[redacted]"

    /// Attribute names whose value is never sent, whatever it holds.
    static let secretKeyFragments = [
        "key", "token", "secret", "password", "passcode", "authorization", "auth", "cookie", "pin", "fingerprint",
        "code", "body", "content", "prompt", "text", "message", "credential", "session", "query",
    ]
    /// Attribute names that contain a fragment above but are known to be harmless.
    static let allowedKeys: Set<String> = ["urlError", "errorType", "errorCode", "status", "path", "decoding"]

    static func entry(
        level: LogReporter.Level, scope: String, message: String, attributes: [String: LogReporter.Value]
    ) -> LogReporter.Entry {
        var safe: [String: LogReporter.Value] = [:]
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }).prefix(maxAttributes) {
            let name = String(key.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }.prefix(40))
            guard !name.isEmpty else { continue }
            if isSecretKey(name) {
                safe[name] = .string(redacted)
                continue
            }
            switch value {
            case .string(let text): safe[name] = .string(clean(text, limit: maxValueLength))
            case .number(let number): safe[name] = number.isFinite ? .number(number) : .string(String(number))
            }
        }
        let cleanedMessage = clean(message, limit: maxMessageLength)
        return LogReporter.Entry(
            level: level, scope: self.scope(scope), message: cleanedMessage.isEmpty ? "(no message)" : cleanedMessage,
            attributes: safe)
    }

    static func isSecretKey(_ name: String) -> Bool {
        if allowedKeys.contains(name) { return false }
        let lower = name.lowercased()
        return secretKeyFragments.contains { lower.contains($0) }
    }

    static func scope(_ raw: String) -> String {
        let kept = raw.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "._-/".contains($0)) }
        let trimmed = String(kept.prefix(maxScopeLength))
        return trimmed.isEmpty ? "app" : trimmed
    }

    /// Masks secrets and URL details in free text, then truncates.
    public static func clean(_ text: String, limit: Int = 500) -> String {
        var result = stripURLs(in: text)
        for (pattern, replacement) in secretPatterns {
            result = result.replacing(pattern, with: { _ in replacement })
        }
        guard result.count > limit else { return result }
        return String(result.prefix(limit - 1)) + "…"
    }

    nonisolated(unsafe) private static let secretPatterns: [(Regex<AnyRegexOutput>, String)] = [
        (try! Regex(#"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#), "Bearer \(redacted)"),
        (try! Regex(#"(?i)\b(api[_-]?key|token|secret|password|passcode|code|pin)(\s*[=:]\s*)\S+"#), redacted),
        (try! Regex(#"(?i)\b(sk|pk|rk|xai|gsk|ghp|gho|github_pat)[-_][A-Za-z0-9_-]{8,}"#), redacted),
        (try! Regex(#"\bAIza[0-9A-Za-z_-]{20,}"#), redacted),
        (try! Regex(#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9._-]+"#), redacted),
        (try! Regex(#"\b(?:[A-Fa-f0-9]{2}:){15,}[A-Fa-f0-9]{2}\b"#), redacted),
        (try! Regex(#"\b[A-Fa-f0-9]{32,}\b"#), redacted),
        (try! Regex(#"[A-Za-z0-9+_-]{40,}={0,2}"#), redacted),
    ]

    nonisolated(unsafe) private static let urlPattern = try! Regex(#"[A-Za-z][A-Za-z0-9+.-]*://[^\s"'<>]+"#)

    /// Every URL keeps its scheme, host, port and path only: no userinfo, query or fragment.
    public static func stripURLs(in text: String) -> String {
        text.replacing(urlPattern) { match in
            let raw = String(text[match.range])
            guard var components = URLComponents(string: raw), components.host != nil else {
                return raw.split(separator: "://", maxSplits: 1).first.map { "\($0)://\(redacted)" } ?? redacted
            }
            components.user = nil
            components.password = nil
            components.query = nil
            components.fragment = nil
            return components.string ?? redacted
        }
    }

    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        let (kind, context): (String, DecodingError.Context?) =
            switch error {
            case .typeMismatch(_, let context): ("typeMismatch", context)
            case .valueNotFound(_, let context): ("valueNotFound", context)
            case .keyNotFound(let key, let context): ("keyNotFound(\(key.stringValue))", context)
            case .dataCorrupted(let context): ("dataCorrupted", context)
            @unknown default: ("unknown", nil)
            }
        let where_ = context.map(path) ?? ""
        return String((where_.isEmpty ? kind : "\(kind) at \(where_)").prefix(200))
    }
}
