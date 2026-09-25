import Foundation
import Security
import Testing

@testable import NetworkingKit

@Suite("CredentialStore")
struct CredentialStoreTests {
    private let server = PairedServer(
        hosts: ["10.0.0.2"], port: 63129, fingerprint: "f", name: "Mac",
        deviceId: "d", token: "secret-token")

    @Test("the in-memory store keeps the contract: save, load, clear")
    func inMemoryRoundTrip() async throws {
        let store = InMemoryCredentialStore()
        #expect(!store.exists)
        #expect(try await store.load(reason: "test") == nil)

        try store.save(server)
        #expect(store.exists)
        #expect(try await store.load(reason: "test") == server)

        try store.clear()
        #expect(!store.exists)
        #expect(try await store.load(reason: "test") == nil)
    }

    @Test("the Keychain item is gated by Face ID or passcode, and never leaves this device")
    func keychainPolicy() throws {
        let query = try KeychainCredentialStore.addQuery(for: Data("x".utf8))

        #expect(query[kSecAttrAccessControl as String] != nil)
        // Access control carries the accessibility class; setting both is an error.
        #expect(query[kSecAttrAccessible as String] == nil)
        // Not synced to iCloud Keychain.
        #expect(query[kSecAttrSynchronizable as String] == nil)
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
    }
}
