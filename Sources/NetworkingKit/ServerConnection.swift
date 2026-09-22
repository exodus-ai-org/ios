import Foundation
import Models

/// The paired computer, once Face ID has released it. Held in memory only:
/// `lock()` — called after five minutes in the background — forgets it, and the
/// next use goes back through the Keychain, and so through Face ID.
///
/// While unpaired (or locked) it contributes nothing, and the app talks to the
/// plain address in `ServerConfigStore` — the Simulator reaching the computer's
/// loopback listener.
public final class ServerConnection: @unchecked Sendable {
    /// How long the app may sit in the background before it locks.
    public static let backgroundGrace: TimeInterval = 300

    private let store: CredentialStoring
    private let state = NSLock()
    private var server: PairedServer?
    /// The pin to trust while pairing, before there is a stored server.
    private var pendingPin: String?

    public init(store: CredentialStoring) {
        self.store = store
    }

    /// The one session everything that talks to the computer should use: it
    /// trusts the pinned certificate and nothing else (see `PinnedSessionDelegate`).
    /// Plain-http requests — the Simulator on the manual address — pass through it
    /// untouched. The pin is read at each handshake, so pairing and unpairing take
    /// effect without a new session.
    public private(set) lazy var session: URLSession = URLSession(
        configuration: .default,
        delegate: PinnedSessionDelegate(pin: { [weak self] in self?.pin }),
        delegateQueue: nil)

    /// A credential exists (it may still be locked behind Face ID).
    public var isPaired: Bool { store.exists }
    public var isUnlocked: Bool { state.withLock { server != nil } }
    public var serverName: String? { state.withLock { server?.name } }
    public var currentHost: String? { state.withLock { server?.orderedHosts.first } }

    /// What `PinnedSessionDelegate` trusts right now.
    public var pin: String? { state.withLock { pendingPin ?? server?.fingerprint } }
    public var authorization: String? { state.withLock { server.map { "Bearer \($0.token)" } } }
    public var baseURLString: String? { baseURLCandidates.first }

    /// Every address the computer can be reached at, best first: the one that
    /// answered last time, then the rest in QR-code order — the LAN address on
    /// the home Wi-Fi, the tailnet address from anywhere else. Callers try them
    /// in turn (see `APIClient`) and report back through `noteReachable`.
    public var baseURLCandidates: [String] {
        state.withLock { server.map { s in s.orderedHosts.map { s.baseURLString(host: $0) } } ?? [] }
    }

    /// Reads the credential — this is the Face ID prompt.
    public func unlock(reason: String) async throws {
        let loaded = try await store.load(reason: reason)
        state.withLock { server = loaded }
    }

    public func lock() {
        state.withLock { server = nil }
    }

    /// Forget the computer: revoked there (a 401), or unpaired here.
    public func unpair() {
        try? store.clear()
        lock()
    }

    /// Remember which address worked, so it is tried first next time.
    public func noteReachable(host: String) {
        let updated: PairedServer? = state.withLock {
            guard var current = server, current.lastGoodHost != host, current.hosts.contains(host)
            else { return nil }
            current.lastGoodHost = host
            server = current
            return current
        }
        if let updated { try? store.save(updated) }
    }

    private struct PairRequest: Encodable {
        let code: String
        let deviceName: String
    }

    private struct PairResponse: Decodable {
        let deviceId: String
        let token: String
    }

    /// Trades the QR code's one-time code for a token, trying each address the
    /// code listed until one answers. Uses the pinned `session` unless a test
    /// passes its own — the pin it trusts meanwhile is the one the QR code named.
    public func pair(_ link: PairingLink, deviceName: String, session: URLSession? = nil) async throws {
        let session = session ?? self.session
        state.withLock { pendingPin = link.fingerprint }
        defer { state.withLock { pendingPin = nil } }

        var lastError: Error = URLError(.cannotConnectToHost)
        for host in link.hosts {
            let authority = host.contains(":") ? "[\(host)]" : host
            guard let url = URL(string: "https://\(authority):\(link.port)/api/v1/pair") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 6)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                PairRequest(code: link.code, deviceName: deviceName))

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                lastError = error  // unreachable by this address — try the next
                continue
            }
            guard let http = response as? HTTPURLResponse else { continue }
            guard http.statusCode == 200 else {
                // The computer answered: the code is wrong, spent or expired.
                // Another address will say the same.
                throw HTTPError(
                    statusCode: http.statusCode, code: "PAIRING_FAILED",
                    message: String(
                        localized: "This pairing code is no longer valid. Show a new one on your computer."))
            }
            let reply = try JSONDecoder().decode(PairResponse.self, from: data)
            let paired = PairedServer(
                hosts: link.hosts, port: link.port, fingerprint: link.fingerprint, name: link.name,
                deviceId: reply.deviceId, token: reply.token, lastGoodHost: host)
            try store.save(paired)
            state.withLock { server = paired }
            return
        }
        throw lastError
    }
}
