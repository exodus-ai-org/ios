import Foundation
import Testing

@testable import NetworkingKit

@Suite("PairingLink")
struct PairingLinkTests {
    /// As the desktop's `buildPairingLink` writes it (URLSearchParams: `,` → %2C, space → `+`).
    static let valid =
        "exodus://pair?h=192.168.1.10%2Cmac.local&p=63129&c=abc-DEF_123&f=VldKaXWVm4PXpwRHg9LDxh0tcUW5A5sOgwTVeSyjWtM&n=Yancey%27s+Mac+%26+Co"

    @Test("parses every field of a link the desktop wrote")
    func parsesEveryField() throws {
        let link = try #require(PairingLink(string: Self.valid))
        #expect(link.hosts == ["192.168.1.10", "mac.local"])
        #expect(link.port == 63129)
        #expect(link.code == "abc-DEF_123")
        #expect(link.fingerprint == "VldKaXWVm4PXpwRHg9LDxh0tcUW5A5sOgwTVeSyjWtM")
        #expect(link.name == "Yancey's Mac & Co")
    }

    @Test("tolerates the whitespace a paste brings along")
    func trimsWhitespace() {
        #expect(PairingLink(string: "  \(Self.valid)\n") != nil)
    }

    @Test("falls back to the first host when the computer sent no name")
    func nameFallsBackToHost() throws {
        let link = try #require(PairingLink(string: "exodus://pair?h=10.0.0.2&p=63129&c=x&f=y"))
        #expect(link.name == "10.0.0.2")
    }

    @Test(
        "rejects anything that is not a complete pairing link",
        arguments: [
            "https://pair?h=a&p=63129&c=x&f=y&n=z",  // wrong scheme
            "exodus://other?h=a&p=63129&c=x&f=y&n=z",  // wrong host
            "exodus://pair?p=63129&c=x&f=y&n=z",  // no hosts
            "exodus://pair?h=&p=63129&c=x&f=y&n=z",  // empty hosts
            "exodus://pair?h=a&p=notaport&c=x&f=y&n=z",  // bad port
            "exodus://pair?h=a&p=70000&c=x&f=y&n=z",  // port out of range
            "exodus://pair?h=a&p=63129&f=y&n=z",  // no code
            "exodus://pair?h=a&p=63129&c=x&n=z",  // no fingerprint
            "not a url",
            ""
        ])
    func rejects(_ string: String) {
        #expect(PairingLink(string: string) == nil)
    }
}

@Suite("PairedServer")
struct PairedServerTests {
    private func server(lastGoodHost: String? = nil) -> PairedServer {
        PairedServer(
            hosts: ["10.0.0.2", "mac.local"], port: 63129, fingerprint: "f", name: "Mac",
            deviceId: "d", token: "t", lastGoodHost: lastGoodHost)
    }

    @Test("tries the host that answered last time first")
    func ordersHosts() {
        #expect(server().orderedHosts == ["10.0.0.2", "mac.local"])
        #expect(server(lastGoodHost: "mac.local").orderedHosts == ["mac.local", "10.0.0.2"])
        #expect(server(lastGoodHost: "gone.local").orderedHosts == ["10.0.0.2", "mac.local"])
    }

    @Test("builds an https base URL, bracketing IPv6")
    func baseURL() {
        #expect(server().baseURLString(host: "mac.local") == "https://mac.local:63129")
        #expect(server().baseURLString(host: "fe80::1") == "https://[fe80::1]:63129")
    }

    @Test("survives a round trip through JSON — it is stored as JSON in the Keychain")
    func codable() throws {
        let original = server(lastGoodHost: "mac.local")
        let decoded = try JSONDecoder().decode(
            PairedServer.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
