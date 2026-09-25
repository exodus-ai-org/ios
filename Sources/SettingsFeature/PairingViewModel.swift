import Foundation
import Models
import NetworkingKit
import Observation

/// Pairing this device with the computer: takes what the camera or the
/// clipboard produced, and drives `ServerConnection`.
@MainActor
@Observable
public final class PairingViewModel {
    public private(set) var isPaired: Bool
    public private(set) var computerName: String?
    public private(set) var isWorking = false
    /// Shown in an alert; nil when there is nothing to report.
    public private(set) var errorMessage: String?
    /// The underlying error, for the alert's second paragraph — the thing to
    /// quote when asking for help. Not localized: it is a code, not copy.
    public private(set) var errorDetail: String?

    private let connection: ServerConnection
    private let deviceName: String
    private let session: URLSession?

    /// `session` is for tests; by default pairing goes through the connection's
    /// own pinned session.
    public init(connection: ServerConnection, deviceName: String, session: URLSession? = nil) {
        self.connection = connection
        self.deviceName = deviceName
        self.session = session
        self.isPaired = connection.isPaired
        self.computerName = connection.serverName
    }

    /// `text` is whatever was scanned or pasted. Returns whether pairing succeeded.
    @discardableResult
    public func pair(from text: String?) async -> Bool {
        guard let text, let link = PairingLink(string: text) else {
            fail(
                String(
                    localized: "ios:settings.pairing.notAPairingCode", defaultValue: "That is not an Exodus pairing code.",
                    comment: "Error: the scanned or pasted text is not a pairing link from the Exodus desktop app. Exodus is the app's name."),
                detail: nil)
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await connection.pair(link, deviceName: deviceName, session: session)
            refresh()
            return true
        } catch let error as HTTPError {
            fail(error.message, detail: "HTTP \(error.statusCode) \(error.code)")
        } catch let error as CredentialError {
            // The credential needs a passcode-protected Keychain item to live in.
            fail(
                String(
                    localized: "ios:settings.pairing.passcodeRequired",
                    defaultValue: "Set a passcode on this device to pair with your computer.",
                    comment: "Error: pairing stores a credential that iOS only allows on a device with a passcode."),
                detail: String(describing: error))
        } catch {
            let nsError = error as NSError
            fail(
                String(
                    localized: "ios:settings.pairing.unreachable",
                    defaultValue: "Could not reach your computer. Make sure both devices are on the same network.",
                    comment: "Error: none of the computer's addresses answered while pairing."),
                detail: "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
        }
        return false
    }

    public func clearError() {
        errorMessage = nil
        errorDetail = nil
    }

    private func fail(_ message: String, detail: String?) {
        errorMessage = message
        errorDetail = detail
    }

    public func unpair() {
        connection.unpair()
        refresh()
    }

    private func refresh() {
        isPaired = connection.isPaired
        computerName = connection.serverName
    }
}
