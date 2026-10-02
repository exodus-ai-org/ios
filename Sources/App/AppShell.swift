import ChatFeature
import HealthFeature
import NetworkingKit
import PhilharmonicFeature
import SettingsFeature
import SwiftUI
import WidgetKitShared

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
    let widgetWriter: WidgetSnapshotWriter
    /// A widget's link, waiting for the shell: it is taken as soon as the shell is on screen.
    let pendingLink: PendingLink

    @State private var activeChat = ActiveChat.new()
    @State private var isSidebarOpen = false
    @State private var workspace: AppWorkspace = .chat
    /// Settings, and the page it opens on. One value, so the page arrives with the presentation itself: two flags let
    /// the first presentation read a stale page and open on the root.
    @State private var settings: SettingsRoute?
    /// Bumped when Settings closes so the sidebar reloads Recents from the (possibly new) server.
    @State private var recentsReloadToken = 0
    /// A question from Health waiting for its new chat to open and send it.
    @State private var pendingAsk: (chatId: String, text: String)?
    /// A widget's prompt for its new chat's composer, never sent by itself.
    @State private var draft: (chatId: String, text: String)?
    /// A widget's question for Health's ask box.
    @State private var healthAsk: String?
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
                onOpenSettings: { settings = .root },
                onDeleteChat: { id in
                    // The deleted chat was the one on screen: leave it for a fresh one, drawer stays open.
                    if id == activeChat.id { activeChat = .new() }
                },
                onRenameChat: { id, title in
                    // The renamed chat is the one on screen: `ChatDetailView` picks this up from
                    // its own `title` argument changing, via `.onChange` (its `chatId` does not
                    // change, so it is never recreated by this).
                    if id == activeChat.id { activeChat.title = title }
                },
                onRecentsChange: { widgetWriter.recentsChanged($0) }
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
                        // Health has its own menu there; a new chat is in the drawer.
                        if workspace != .health {
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
        }
        .sheet(
            item: $settings,
            onDismiss: { recentsReloadToken += 1 }
        ) { route in
            SettingsView(apiClient: apiClient, serverConfig: serverConfig, opensMemory: route == .memory)
        }
        // The workspace actually changing, once (apple-design §13): `workspace` only changes when
        // a row not already selected is tapped, so re-tapping the active row fires nothing. And
        // today .chat and .health are selectable (AppWorkspace.isAvailable).
        .sensoryFeedback(.selection, trigger: workspace)
        // What is on screen, as the system's current activity: a screenshot is titled after it (the share
        // sheet's header, and the file's name when it reaches a computer).
        .userActivity(ExodusActivity.viewing) { activity in
            activity.title = sceneTitle
            activity.isEligibleForHandoff = false
            activity.isEligibleForSearch = false
            activity.isEligibleForPrediction = false
        }
        // The desktop may have picked another tone meanwhile.
        .task { await toneModel?.refresh(apiClient: apiClient) }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await toneModel?.refresh(apiClient: apiClient) } }
        }
        // Initial too: a link that arrived behind the unlock or pairing gate is opened once the shell appears.
        .onChange(of: pendingLink.link, initial: true) {
            guard let link = pendingLink.take() else { return }
            open(link)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace {
        case .chat:
            ChatDetailView(
                chatId: activeChat.id, title: activeChat.title, apiClient: apiClient,
                streamManager: streamManager, serverConfig: serverConfig,
                initialMessage: pendingAsk?.chatId == activeChat.id ? pendingAsk?.text : nil,
                onInitialMessageSent: { pendingAsk = nil },
                initialDraft: draft?.chatId == activeChat.id ? draft?.text : nil,
                onInitialDraftUsed: { draft = nil }
            )
            // A different chat is a different view model.
            .id(activeChat.id)
            .environment(
                \.openMemorySettings,
                OpenMemorySettingsAction {
                    settings = .memory
                })
        case .health:
            HealthRootView(
                apiClient: apiClient, onGlanceChange: { widgetWriter.healthChanged($0) }, initialAsk: healthAsk,
                onInitialAskUsed: { healthAsk = nil }
            ) { text in
                let chat = ActiveChat.new()
                pendingAsk = (chat.id, text)
                activeChat = chat
                workspace = .chat
            }
        case .philharmonic:
            PhilharmonicPlaceholderView()
        }
    }

    /// The title of what is on screen: the chat's, else the workspace's.
    private var sceneTitle: String {
        switch workspace {
        case .chat:
            let title = activeChat.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty
                ? String(localized: "chat:sidebar.newChat", defaultValue: "New chat") : title
        case .health, .philharmonic:
            return String(localized: workspace.title)
        }
    }

    private func select(id: String, title: String?) {
        pendingAsk = nil
        healthAsk = nil
        activeChat = ActiveChat(id: id, title: title)
        // A chat picked from the drawer is shown, whichever workspace was open.
        workspace = .chat
        setSidebar(open: false)
    }

    private func startNewChat() {
        pendingAsk = nil
        healthAsk = nil
        activeChat = .new()
        workspace = .chat
        setSidebar(open: false)
    }

    /// Where a widget's link leads. Settings closes first: whatever the link opens is under it.
    private func open(_ link: DeepLink) {
        settings = nil
        switch link {
        case .newChat(let prompt):
            startNewChat()
            // An empty draft still focuses the composer: the link is "ask something".
            draft = (activeChat.id, prompt ?? "")
        case .chat(let id):
            // The title comes with the history (the chat already on screen keeps its own); an unknown id shows the
            // server's error in the chat, and the drawer still lists the rest.
            select(id: id, title: id == activeChat.id ? activeChat.title : nil)
        case .health(let ask):
            pendingAsk = nil
            healthAsk = ask
            workspace = .health
            setSidebar(open: false)
        }
    }

    private func setSidebar(open: Bool) {
        withAnimation(drawerAnimation(reduceMotion: reduceMotion)) { isSidebarOpen = open }
    }
}

/// Where Settings opens: its root, or the Memory page (from a chat's used-memories sheet).
enum SettingsRoute: String, Identifiable {
    case root, memory

    var id: String { rawValue }
}

/// The app's `NSUserActivity` types (also listed under `NSUserActivityTypes` in the Info.plist).
enum ExodusActivity {
    static let viewing = "app.yancey.exodus.viewing"
}
