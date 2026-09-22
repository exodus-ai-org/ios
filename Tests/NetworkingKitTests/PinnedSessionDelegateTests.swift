import Foundation
import Testing

@testable import NetworkingKit

@Suite("PinnedSessionDelegate")
struct PinnedSessionDelegateTests {
    /// A self-signed P-256 certificate (CN=Exodus), DER, generated with openssl.
    static let certificateDER = Data(
        base64Encoded:
            "MIICBzCCAawCCQDnpUWfTIixVDAKBggqhkjOPQQDAjARMQ8wDQYDVQQDDAZFeG9kdXMwHhcNMjYwOTE5MjA0NzEwWhcNMzYwOTE2MjA0NzEwWjARMQ8wDQYDVQQDDAZFeG9kdXMwggFLMIIBAwYHKoZIzj0CATCB9wIBATAsBgcqhkjOPQEBAiEA/////wAAAAEAAAAAAAAAAAAAAAD///////////////8wWwQg/////wAAAAEAAAAAAAAAAAAAAAD///////////////wEIFrGNdiqOpPns+u9VXaYhrxlHQawzFOw9jvOPD4n0mBLAxUAxJ02CIbnBJNqZnjhE50mt4GffpAEQQRrF9Hy4SxCR/i85uVjpEDydwN9gS3rM6D0oTlF2JjClk/jQuL+Gn+bjufrSnwPnhYrzjNXazFezsu2QGg3v1H1AiEA/////wAAAAD//////////7zm+q2nF56E87nKwvxjJVECAQEDQgAEAXOyliOeliZ/N2p+n5fuUF9ITWc0rwI5/PBRkbDXi5r9aOXf1AiVmGyIDpfUFLN/7noGGz9Pk+oRGN3c6V+0ezAKBggqhkjOPQQDAgNJADBGAiEAsuwPVeA2BRcxaCtP9D0oyr83arDupBGj3dRfgMrKPP8CIQDfAaVmKvx86zxH32mGJsYQ2pBhUf1j1+TkhaYIQybX5g=="
    )!
    /// What the desktop computes for it: base64url SHA-256 of the DER
    /// (`createHash('sha256').update(der).digest('base64url')`).
    static let expectedPin = "iFPGh-gkg7woHX5TL_tThSLXY3iU1vY89qsN83J_TIs"

    @Test("computes the same fingerprint the desktop puts in the QR code")
    func fingerprintMatchesDesktop() {
        #expect(PinnedSessionDelegate.fingerprint(ofDER: Self.certificateDER) == Self.expectedPin)
    }

    @Test("the fixture is a certificate Security.framework accepts")
    func fixtureIsACertificate() {
        #expect(SecCertificateCreateWithData(nil, Self.certificateDER as CFData) != nil)
    }

    @Test("trusts the pinned certificate")
    func trustsThePin() {
        #expect(PinnedSessionDelegate.decide(pin: Self.expectedPin, leafDER: Self.certificateDER))
    }

    @Test("trusts nothing else")
    func trustsNothingElse() {
        let other = String(repeating: "A", count: 43)
        #expect(!PinnedSessionDelegate.decide(pin: other, leafDER: Self.certificateDER))
        // Unpaired: no pin, so no TLS server is trusted at all.
        #expect(!PinnedSessionDelegate.decide(pin: nil, leafDER: Self.certificateDER))
        #expect(!PinnedSessionDelegate.decide(pin: "", leafDER: Self.certificateDER))
        #expect(!PinnedSessionDelegate.decide(pin: Self.expectedPin, leafDER: nil))
    }
}
