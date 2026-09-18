import NetworkingKit
import SwiftUI

@main
struct ExodusApp: App {
    private let serverConfig: ServerConfigStore
    private let apiClient: APIClient
    private let streamManager: ChatStreamManager

    init() {
        let config = ServerConfigStore()
        serverConfig = config
        apiClient = APIClient(serverConfig: config)
        streamManager = ChatStreamManager()
    }

    var body: some Scene {
        WindowGroup {
            RootView(apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig)
        }
    }
}
