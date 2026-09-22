import CryptoKit
import Foundation

/// Trust exactly one certificate: the one whose fingerprint came with the
/// pairing QR code. No CA chain (it is self-signed) and no host-name check (the
/// computer is reached by IP, `.local` or tailnet name alike) — the pin *is* the
/// identity, and it is checked during the TLS handshake, before a byte of any
/// request (or its bearer token) is sent.
///
/// With no pin there is nothing to trust: an unpaired app is never talked into
/// HTTPS by anyone. Plain `http://` — the Simulator reaching the computer's
/// loopback listener — raises no challenge and is unaffected.
public final class PinnedSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    private let pin: @Sendable () -> String?

    /// `pin` is read at each handshake, so pairing and unpairing take effect
    /// without rebuilding the session.
    public init(pin: @escaping @Sendable () -> String?) {
        self.pin = pin
    }

    /// base64url (unpadded) SHA-256 of a certificate's DER — the same value the
    /// desktop computes in `fingerprintOf` (`src/main/lib/lan/certificate.ts`).
    public static func fingerprint(ofDER der: Data) -> String {
        Data(SHA256.hash(data: der)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decide(pin: String?, leafDER: Data?) -> Bool {
        guard let pin, !pin.isEmpty, let leafDER else { return false }
        return fingerprint(ofDER: leafDER) == pin
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        let der = leaf.map { SecCertificateCopyData($0) as Data }
        if Self.decide(pin: pin(), leafDER: der) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
