import Foundation

/// `UserDefaults` itself is thread-safe but not marked `Sendable` by Foundation;
/// this type has no other mutable state, so `@unchecked` is a deliberate,
/// narrow override, not a blanket escape hatch.
public final class ServerConfigStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private static let key = "exodus.serverURL"
    private static let defaultBaseURL = "http://localhost:60223"

    /// The paired computer, when there is one. Set once at start-up.
    public var connection: ServerConnection?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// The manually entered address — what the Simulator uses to reach the
    /// computer's plain loopback listener. A device cannot: it has to pair.
    public var manualBaseURLString: String {
        get { userDefaults.string(forKey: Self.key) ?? Self.defaultBaseURL }
        set { userDefaults.set(newValue, forKey: Self.key) }
    }

    /// Where requests go: the paired computer (HTTPS, pinned) once unlocked,
    /// otherwise the manual address.
    public var baseURLString: String {
        get { connection?.baseURLString ?? manualBaseURLString }
        set { manualBaseURLString = newValue }
    }

    /// Where requests may go, best first — see `ServerConnection.baseURLCandidates`.
    /// Unpaired, just the manual address.
    public var baseURLCandidates: [String] {
        let paired = connection?.baseURLCandidates ?? []
        return paired.isEmpty ? [manualBaseURLString] : paired
    }

    /// `Authorization` for the paired computer; nil for the manual address.
    public var authorization: String? { connection?.authorization }
}
