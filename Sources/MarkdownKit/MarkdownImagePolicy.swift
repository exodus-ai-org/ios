import Foundation

/// Whether images in model-written markdown load by themselves. A remote image URL can be a tracking
/// pixel or carry data out in its query string (prompt injection), so on the phone it waits for a tap.
/// Change `current` to flip the whole app.
public enum MarkdownImagePolicy: Sendable {
    case tapToLoadRemote
    case autoLoadRemote
    case blockRemote

    public static let current: MarkdownImagePolicy = .tapToLoadRemote

    /// Largest decoded `data:` payload shown inline.
    static let inlineByteCap = 2 * 1024 * 1024

    public enum Decision: Equatable, Sendable {
        /// Load now: a `data:` image under the cap, or a remote one when the policy allows it.
        case load(URL)
        /// Show a card that loads the remote image on tap.
        case askToLoad(URL, host: String)
        /// Nothing to load: a relative or unknown URL, an oversized `data:` image, or remote images are off.
        case unavailable
    }

    public func decision(for source: String) -> Decision {
        guard let url = URL(string: source), let scheme = url.scheme?.lowercased() else { return .unavailable }
        switch scheme {
        case "data":
            return Self.inlinePayloadSize(source).map { $0 <= Self.inlineByteCap } == true ? .load(url) : .unavailable
        case "http", "https":
            guard let host = url.host(), !host.isEmpty else { return .unavailable }
            switch self {
            case .autoLoadRemote: return .load(url)
            case .tapToLoadRemote: return .askToLoad(url, host: host)
            case .blockRemote: return .unavailable
            }
        default:
            return .unavailable
        }
    }

    /// The decoded size of a `data:` URL's payload, estimated from its text without decoding it.
    static func inlinePayloadSize(_ source: String) -> Int? {
        guard let comma = source.firstIndex(of: ",") else { return nil }
        let header = source[..<comma].lowercased()
        let payload = source[source.index(after: comma)...]
        guard header.hasSuffix(";base64") else { return payload.utf8.count }
        let padding = payload.reversed().prefix { $0 == "=" }.count
        return payload.utf8.count / 4 * 3 - padding
    }
}
