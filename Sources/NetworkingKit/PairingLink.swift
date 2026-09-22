import Foundation

/// What the desktop's pairing QR code says: where Exodus is, the one-time code
/// that lets this device in, and the fingerprint of the only certificate to
/// trust. Built by `buildPairingLink` in the desktop's `src/main/lib/lan/pairing.ts`.
///
///     exodus://pair?h=192.168.1.10,mac.local&p=60224&c=<code>&f=<fingerprint>&n=<name>
public struct PairingLink: Equatable, Sendable {
    /// Addresses to try, in order: the computer's LAN IPs, then its `.local` name.
    public let hosts: [String]
    public let port: Int
    public let code: String
    /// base64url SHA-256 of the server certificate's DER — see `PinnedSessionDelegate`.
    public let fingerprint: String
    /// The computer's name, for display.
    public let name: String

    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme == "exodus", components.host == "pair"
        else { return nil }

        // The desktop encodes with URLSearchParams, where a space is `+`;
        // URLComponents decodes %XX but leaves `+` alone.
        func value(_ key: String) -> String? {
            components.percentEncodedQueryItems?
                .first { $0.name == key }?
                .value?
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding
        }

        let hosts = (value("h") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !hosts.isEmpty,
              let port = value("p").flatMap(Int.init), (1...65535).contains(port),
              let code = value("c"), !code.isEmpty,
              let fingerprint = value("f"), !fingerprint.isEmpty
        else { return nil }

        self.hosts = hosts
        self.port = port
        self.code = code
        self.fingerprint = fingerprint
        self.name = value("n").flatMap { $0.isEmpty ? nil : $0 } ?? hosts[0]
    }
}
