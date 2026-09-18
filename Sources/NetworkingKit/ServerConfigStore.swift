import Foundation

/// `UserDefaults` itself is thread-safe but not marked `Sendable` by Foundation;
/// this type has no other mutable state, so `@unchecked` is a deliberate,
/// narrow override, not a blanket escape hatch.
public final class ServerConfigStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private static let key = "exodus.serverURL"
    private static let defaultBaseURL = "http://localhost:60223"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var baseURLString: String {
        get { userDefaults.string(forKey: Self.key) ?? Self.defaultBaseURL }
        set { userDefaults.set(newValue, forKey: Self.key) }
    }
}
