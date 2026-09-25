import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

private final class PairingMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PairingMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// A store that refuses to save, as the Keychain does on a device with no passcode.
private final class NoPasscodeStore: CredentialStoring, @unchecked Sendable {
    var exists: Bool { false }
    func load(reason: String) async throws -> PairedServer? { nil }
    func save(_ server: PairedServer) throws { throw CredentialError.passcodeNotSet }
    func clear() throws {}
}

@MainActor
@Suite("PairingViewModel", .serialized)
struct PairingViewModelTests {
    private static let link = "exodus://pair?h=10.0.0.2&p=63129&c=CODE&f=PIN&n=Studio+Mac"

    private func makeViewModel(store: CredentialStoring = InMemoryCredentialStore())
        -> (PairingViewModel, ServerConnection)
    {
        let connection = ServerConnection(store: store)
        let viewModel = PairingViewModel(
            connection: connection, deviceName: "Test iPhone",
            session: PairingMockURLProtocol.makeSession())
        return (viewModel, connection)
    }

    @Test("pairs from a scanned link and shows the computer's name")
    func pairs() async {
        PairingMockURLProtocol.handler = { _ in (200, Data(#"{"deviceId":"d","token":"T"}"#.utf8)) }
        let (viewModel, connection) = makeViewModel()
        #expect(!viewModel.isPaired)

        #expect(await viewModel.pair(from: Self.link))

        #expect(viewModel.isPaired)
        #expect(viewModel.computerName == "Studio Mac")
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isWorking)
        #expect(connection.authorization == "Bearer T")
    }

    @Test(
        "refuses anything that is not a pairing link, without touching the network",
        arguments: [nil, "", "https://example.com", "WIFI:S:home;T:WPA;P:secret;;"] as [String?])
    func rejectsForeignCodes(_ text: String?) async {
        PairingMockURLProtocol.handler = { _ in
            Issue.record("no request should be made")
            return (500, Data())
        }
        let (viewModel, _) = makeViewModel()

        #expect(!(await viewModel.pair(from: text)))
        #expect(viewModel.errorMessage == "That is not an Exodus pairing code.")
        #expect(!viewModel.isPaired)
    }

    @Test("tells the user when the computer refused the code")
    func refusedCode() async {
        PairingMockURLProtocol.handler = { _ in (403, Data("{}".utf8)) }
        let (viewModel, _) = makeViewModel()

        #expect(!(await viewModel.pair(from: Self.link)))
        #expect(
            viewModel.errorMessage
                == "This pairing code is no longer valid. Show a new one on your computer.")
        #expect(!viewModel.isPaired)
    }

    @Test("tells the user when the computer cannot be reached")
    func unreachable() async {
        PairingMockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let (viewModel, _) = makeViewModel()

        #expect(!(await viewModel.pair(from: Self.link)))
        #expect(
            viewModel.errorMessage
                == "Could not reach your computer. Make sure both devices are on the same network.")
    }

    @Test("asks for a passcode when the Keychain will not hold the credential")
    func needsPasscode() async {
        PairingMockURLProtocol.handler = { _ in (200, Data(#"{"deviceId":"d","token":"T"}"#.utf8)) }
        let (viewModel, _) = makeViewModel(store: NoPasscodeStore())

        #expect(!(await viewModel.pair(from: Self.link)))
        #expect(viewModel.errorMessage == "Set a passcode on this device to pair with your computer.")
        #expect(!viewModel.isPaired)
    }

    @Test("unpairs")
    func unpairs() async {
        PairingMockURLProtocol.handler = { _ in (200, Data(#"{"deviceId":"d","token":"T"}"#.utf8)) }
        let (viewModel, connection) = makeViewModel()
        await viewModel.pair(from: Self.link)

        viewModel.unpair()

        #expect(!viewModel.isPaired)
        #expect(viewModel.computerName == nil)
        #expect(connection.authorization == nil)
    }
}
