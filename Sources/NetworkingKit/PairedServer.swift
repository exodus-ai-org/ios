import Foundation

/// Everything this device keeps about the computer it is paired with. It lives
/// in the Keychain behind Face ID (see `CredentialStore`); `token` never leaves
/// it except as an `Authorization` header on the pinned TLS connection.
public struct PairedServer: Codable, Equatable, Sendable {
    public var hosts: [String]
    public var port: Int
    public var fingerprint: String
    public var name: String
    public var deviceId: String
    public var token: String
    /// The host that answered most recently, tried first next time.
    public var lastGoodHost: String?

    public init(
        hosts: [String], port: Int, fingerprint: String, name: String,
        deviceId: String, token: String, lastGoodHost: String? = nil
    ) {
        self.hosts = hosts
        self.port = port
        self.fingerprint = fingerprint
        self.name = name
        self.deviceId = deviceId
        self.token = token
        self.lastGoodHost = lastGoodHost
    }

    /// The host that answered last time first, then the rest in QR-code order.
    public var orderedHosts: [String] {
        guard let lastGoodHost, hosts.contains(lastGoodHost) else { return hosts }
        return [lastGoodHost] + hosts.filter { $0 != lastGoodHost }
    }

    public func baseURLString(host: String) -> String {
        // An IPv6 literal needs brackets in a URL.
        let authority = host.contains(":") ? "[\(host)]" : host
        return "https://\(authority):\(port)"
    }
}
