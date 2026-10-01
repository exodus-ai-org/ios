import ChatFeature
import HealthFeature
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
    /// Settings opens on its Memory page (from a chat's used-memories sheet).
    @State private var settingsOpensMemory = false
    /// Bumped when Settings closes so the sidebar reloads Recents from the (possibly new) server.
    @State private var recentsReloadToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ColorToneModel.self) private var toneModel: ColorToneModel?

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
                },
                onRenameChat: { id, title in
                    // The renamed chat is the one on screen: `ChatDetailView` picks this up from
                    // its own `title` argument changing, via `.onChange` (its `chatId` does not
                    // change, so it is never recreated by this).
                    if id == activeChat.id { activeChat.title = title }
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
                                    Label("ios:app.sidebar.close", systemImage: "sidebar.leading")
                                } else {
                                    Label("ios:app.sidebar.open", systemImage: "sidebar.leading")
                                }
                            }
                            .accessibilityIdentifier("sidebarToggle")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                startNewChat()
                            } label: {
                                Label("chat:sidebar.newChat", systemImage: "square.and.pencil")
                            }
                            .accessibilityIdentifier("topNewChat")
                        }
                    }
            }
        }
        .sheet(
            isPresented: $showSettings,
            onDismiss: {
                recentsReloadToken += 1
                settingsOpensMemory = false
            }
        ) {
            SettingsView(apiClient: apiClient, serverConfig: serverConfig, opensMemory: settingsOpensMemory)
        }
        // The workspace actually changing, once (apple-design §13): `workspace` only changes when
        // a row not already selected is tapped, so re-tapping the active row fires nothing. And
        // today .chat and .health are selectable (AppWorkspace.isAvailable).
        .sensoryFeedback(.selection, trigger: workspace)
        // The desktop may have picked another tone meanwhile.
        .task { await toneModel?.refresh(apiClient: apiClient) }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await toneModel?.refresh(apiClient: apiClient) } }
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
            .environment(
                \.openMemorySettings,
                OpenMemorySettingsAction {
                    settingsOpensMemory = true
                    showSettings = true
                })
        case .health:
            HealthRootView(apiClient: apiClient)
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
