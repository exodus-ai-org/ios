import NetworkingKit
import SettingsFeature
import SwiftUI

struct RootView: View {
    @State private var showSettings = false
    private let apiClient: APIClient
    private let serverConfig: ServerConfigStore

    init() {
        let config = ServerConfigStore()
        serverConfig = config
        apiClient = APIClient(serverConfig: config)
    }

    var body: some View {
        Button("Open Settings") { showSettings = true }
            .sheet(isPresented: $showSettings) {
                SettingsView(apiClient: apiClient, serverConfig: serverConfig)
            }
    }
}

#Preview {
    RootView()
}
