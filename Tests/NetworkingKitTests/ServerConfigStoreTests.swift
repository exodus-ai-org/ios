import Foundation
import Testing

@testable import NetworkingKit

@Suite("ServerConfigStore", .serialized)
struct ServerConfigStoreTests {
    private static let key = "exodus.serverURL"

    /// An isolated `UserDefaults` suite, emptied first (a previous run may have left values behind).
    private func makeDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("a fresh store reads the default desktop address and does not write it")
    func freshStoreReadsTheDefault() {
        let suite = "ServerConfigStoreTests.fresh"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ServerConfigStore(userDefaults: defaults)
        #expect(store.baseURLString == "http://localhost:60223")
        // Reading the default must not persist it, or a later change of the default would never apply.
        #expect(defaults.object(forKey: Self.key) == nil)
    }

    @Test("setting the address persists it under exodus.serverURL, and a second store on the same suite reads it")
    func settingPersistsUnderTheKey() {
        let suite = "ServerConfigStoreTests.persist"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ServerConfigStore(userDefaults: defaults)
        store.baseURLString = "http://192.168.1.10:8080"

        // Read through the suite itself, not through the store under test.
        #expect(defaults.string(forKey: Self.key) == "http://192.168.1.10:8080")
        #expect(store.baseURLString == "http://192.168.1.10:8080")
        #expect(ServerConfigStore(userDefaults: defaults).baseURLString == "http://192.168.1.10:8080")
    }

    @Test("setting the address again replaces the stored value")
    func settingAgainReplaces() {
        let suite = "ServerConfigStoreTests.replace"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ServerConfigStore(userDefaults: defaults)
        store.baseURLString = "http://192.168.1.10:8080"
        store.baseURLString = "http://my-mac.local:60223"

        #expect(defaults.string(forKey: Self.key) == "http://my-mac.local:60223")
        #expect(ServerConfigStore(userDefaults: defaults).baseURLString == "http://my-mac.local:60223")
    }
}
