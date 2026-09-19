import ChatFeature
import NetworkingKit
import PhilharmonicFeature
import SettingsFeature
import SwiftUI

/// The chat on screen. A new chat is a fresh lowercased UUID with no title; the server creates the
/// chat when the first message is sent.
struct ActiveChat: Equatable {
    var id: String
    var title: String?

    static func new() -> ActiveChat { ActiveChat(id: UUID().uuidString.lowercased(), title: nil) }
}

/// The app's root: a drawer whose sidebar lists chats and whose card shows the active chat.
struct AppShell: View {
    let apiClient: APIClient
    let streamManager: ChatStreamManager
    let serverConfig: ServerConfigStore

    @State private var activeChat = ActiveChat.new()
    @State private var isSidebarOpen = false
    @State private var workspace: AppWorkspace = .chat
    @State private var showSettings = false
    /// Bumped when Settings closes so the sidebar reloads Recents from the (possibly new) server.
    @State private var recentsReloadToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SideDrawer(isOpen: $isSidebarOpen) {
            ChatSidebarView(
                apiClient: apiClient,
                activeChatId: activeChat.id,
                isOpen: isSidebarOpen,
                reloadToken: recentsReloadToken,
                onSelectChat: { id, title in select(id: id, title: title) },
                onNewChat: { startNewChat() },
                onOpenSettings: { showSettings = true },
                onDeleteChat: { id in
                    // The deleted chat was the one on screen: leave it for a fresh one, drawer stays open.
                    if id == activeChat.id { activeChat = .new() }
                }
            ) {
                ForEach(AppWorkspace.allCases) { option in
                    WorkspaceRow(option: option, isSelected: option == workspace) {
                        workspace = option
                        setSidebar(open: false)
                    }
                }
            }
        } content: {
            NavigationStack {
                detail
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                setSidebar(open: !isSidebarOpen)
                            } label: {
                                if isSidebarOpen {
                                    Label("Close sidebar", systemImage: "sidebar.leading")
                                } else {
                                    Label("Open sidebar", systemImage: "sidebar.leading")
                                }
                            }
                            .accessibilityIdentifier("sidebarToggle")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                startNewChat()
                            } label: {
                                Label("New chat", systemImage: "square.and.pencil")
                            }
                            .accessibilityIdentifier("topNewChat")
                        }
                    }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { recentsReloadToken += 1 }) {
            SettingsView(apiClient: apiClient, serverConfig: serverConfig)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace {
        case .chat:
            ChatDetailView(
                chatId: activeChat.id, title: activeChat.title, apiClient: apiClient,
                streamManager: streamManager, serverConfig: serverConfig
            )
            // A different chat is a different view model.
            .id(activeChat.id)
        case .philharmonic:
            PhilharmonicPlaceholderView()
        }
    }

    private func select(id: String, title: String?) {
        activeChat = ActiveChat(id: id, title: title)
        setSidebar(open: false)
    }

    private func startNewChat() {
        activeChat = .new()
        setSidebar(open: false)
    }

    private func setSidebar(open: Bool) {
        withAnimation(drawerAnimation(reduceMotion: reduceMotion)) { isSidebarOpen = open }
    }
}
