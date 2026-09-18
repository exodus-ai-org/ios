import ChatFeature
import NetworkingKit
import PhilharmonicFeature
import SettingsFeature
import SwiftUI

struct RootView: View {
    let apiClient: APIClient
    let streamManager: ChatStreamManager
    let serverConfig: ServerConfigStore

    @State private var workspace: AppWorkspace = .chat
    @State private var path: [String] = []
    @State private var showSettings = false
    /// Bumped when the Settings sheet closes so the chat list reloads from the (possibly new) server.
    @State private var listReloadToken = 0

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch workspace {
                case .chat:
                    ChatListView(
                        apiClient: apiClient,
                        onSelectChat: { chatId in path.append(chatId) },
                        onNewChat: { chatId in path.append(chatId) }
                    )
                    .id(listReloadToken)
                case .philharmonic:
                    PhilharmonicPlaceholderView()
                }
            }
            .navigationDestination(for: String.self) { chatId in
                ChatDetailView(
                    chatId: chatId, apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(AppWorkspace.allCases) { option in
                            Button {
                                workspace = option
                            } label: {
                                if option == workspace {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else if option.isAvailable {
                                    Text(option.rawValue)
                                } else {
                                    Text("\(option.rawValue)(即将支持)")
                                }
                            }
                            .disabled(!option.isAvailable && option != workspace)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(workspace.rawValue).font(.headline)
                            Image(systemName: "chevron.down").font(.caption)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { listReloadToken += 1 }) {
            SettingsView(apiClient: apiClient, serverConfig: serverConfig)
        }
    }
}
