import Foundation

/// The links a widget opens the app with. Anything else — another scheme, an unknown path, a prompt too long — is not
/// a link, and the app ignores it.
public enum DeepLink: Equatable, Sendable {
    /// A fresh chat, its composer pre-filled when there is a prompt. Never sent by itself.
    case newChat(prompt: String?)
    case chat(id: String)
    /// Health, its ask box pre-filled when there is a question.
    case health(ask: String?)

    public static let scheme = "exodus"
    public static let maxPrompt = 500

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .newChat(let prompt):
            parts.host = "chat"
            parts.path = "/new"
            parts.queryItems = prompt.map { [URLQueryItem(name: "prompt", value: $0)] }
        case .chat(let id):
            parts.host = "chat"
            parts.path = "/" + id
        case .health(let ask):
            parts.host = "health"
            parts.queryItems = ask.map { [URLQueryItem(name: "ask", value: $0)] }
        }
        // `URLQueryItem` escapes `&`, `=`, `%` and `#` in a value but leaves `+`, which form decoders read as a
        // space; only `+` is escaped here, so the value reads back whole.
        parts.percentEncodedQuery = parts.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        func query(_ name: String) -> String?? {
            let value = parts.queryItems?.first { $0.name == name }?.value
            guard let value, !value.isEmpty else { return .some(nil) }
            return value.count > Self.maxPrompt ? nil : .some(value)
        }
        switch (parts.host, path) {
        case ("chat", ["new"]):
            guard let prompt = query("prompt") else { return nil }
            self = .newChat(prompt: prompt)
        case ("chat", let path) where path.count == 1 && Self.isAcceptableChatId(path[0]):
            self = .chat(id: path[0])
        case ("health", []):
            guard let ask = query("ask") else { return nil }
            self = .health(ask: ask)
        default:
            return nil
        }
    }

    /// The id goes into `/api/v1/chat/<id>/…`: only the characters of a UUID-like id, never `/` or `..`. The same
    /// rule as `DeepResearchStore.isAcceptableId` in ChatFeature, which this module cannot reach.
    static func isAcceptableChatId(_ id: String) -> Bool {
        (1...64).contains(id.count)
            && id.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "_" }
    }
}
