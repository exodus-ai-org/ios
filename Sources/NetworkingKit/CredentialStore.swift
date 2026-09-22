import Foundation
import LocalAuthentication
import Security

public enum CredentialError: Error, Equatable, Sendable {
    /// The Keychain item requires a device passcode; without one it cannot exist.
    case passcodeNotSet
    /// Face ID / passcode was cancelled or failed.
    case cancelled
    case keychain(OSStatus)
}

public protocol CredentialStoring: Sendable {
    /// Reads the credential, prompting Face ID (or the passcode) to do so.
    func load(reason: String) async throws -> PairedServer?
    func save(_ server: PairedServer) throws
    func clear() throws
    /// Whether a credential is stored — answered without prompting.
    var exists: Bool { get }
}

/// One Keychain item, readable only after Face ID or the device passcode, only
/// on this device, never in a backup or in iCloud. A device with no passcode
/// cannot hold it — so it cannot pair.
public final class KeychainCredentialStore: CredentialStoring {
    private static let service = "app.yancey.exodus.pairing"
    private static let account = "paired-server"

    public init() {}

    /// Face ID as enrolled now, or the device passcode. `biometryCurrentSet`
    /// (rather than `biometryAny`) means a newly enrolled face does not inherit
    /// access; the passcode still does, so Face ID failing is not a lock-out.
    public static func accessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryCurrentSet, .or, .devicePasscode], &error)
        else { throw CredentialError.passcodeNotSet }
        return control
    }

    static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func addQuery(for data: Data) throws -> [String: Any] {
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessControl as String] = try accessControl()
        return query
    }

    public var exists: Bool {
        var query = Self.baseQuery()
        let context = LAContext()
        context.interactionNotAllowed = true  // look, don't prompt
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // Present but locked behind Face ID reads as "interaction not allowed".
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    public func load(reason: String) async throws -> PairedServer? {
        let context = LAContext()
        context.localizedReason = reason
        var query = Self.baseQuery()
        query[kSecReturnData as String] = true
        query[kSecUseAuthenticationContext as String] = context
        // SecItemCopyMatching blocks while the Face ID sheet is up.
        nonisolated(unsafe) let frozen = query
        return try await Task.detached {
            var item: CFTypeRef?
            let status = SecItemCopyMatching(frozen as CFDictionary, &item)
            switch status {
            case errSecSuccess:
                guard let data = item as? Data else { return nil }
                return try JSONDecoder().decode(PairedServer.self, from: data)
            case errSecItemNotFound:
                return nil
            case errSecUserCanceled, errSecAuthFailed:
                throw CredentialError.cancelled
            default:
                throw CredentialError.keychain(status)
            }
        }.value
    }

    public func save(_ server: PairedServer) throws {
        let data = try JSONEncoder().encode(server)
        SecItemDelete(Self.baseQuery() as CFDictionary)
        let status = SecItemAdd(try Self.addQuery(for: data) as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(Self.baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychain(status)
        }
    }
}

/// For tests, previews and UI tests: same contract, no Keychain, no prompt.
public final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var server: PairedServer?

    public init(_ server: PairedServer? = nil) { self.server = server }

    public var exists: Bool { lock.withLock { server != nil } }
    public func load(reason: String) async throws -> PairedServer? { lock.withLock { server } }
    public func save(_ server: PairedServer) throws { lock.withLock { self.server = server } }
    public func clear() throws { lock.withLock { server = nil } }
}
