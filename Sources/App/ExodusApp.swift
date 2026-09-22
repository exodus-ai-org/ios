import NetworkingKit
import SwiftUI

@main
struct ExodusApp: App {
    private let connection: ServerConnection
    private let serverConfig: ServerConfigStore
    private let apiClient: APIClient
    private let streamManager: ChatStreamManager

    init() {
        // One connection, and one URLSession — its own, which trusts only the
        // certificate this device was paired with — shared by everything that
        // talks to the computer. Unpaired (the Simulator), both are inert and
        // requests go to the plain manual address.
        let connection = ServerConnection(store: KeychainCredentialStore())
        let config = ServerConfigStore()
        config.connection = connection
        self.connection = connection
        serverConfig = config
        apiClient = APIClient(session: connection.session, serverConfig: config)
        streamManager = ChatStreamManager(sseClient: SSEClient(session: connection.session))
    }

    var body: some Scene {
        WindowGroup {
            UnlockGate(connection: connection) {
                AppShell(apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig)
            }
        }
    }
}
