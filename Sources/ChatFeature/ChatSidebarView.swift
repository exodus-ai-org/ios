import Models
import NetworkingKit
import SwiftUI

/// The drawer's content: workspaces, Recents, and an inline search. It owns its `NavigationStack`, so
/// the title, the search button and the bottom bar are native. Rows have no swipe actions (a left
/// swipe closes the drawer); a chat is deleted from its long-press menu.
public struct ChatSidebarView<Workspaces: View>: View {
    @State private var list: ChatListViewModel
    @State private var search: ChatSearchViewModel
    @State private var isSearching = false

    private let activeChatId: String
    private let isOpen: Bool
    private let reloadToken: Int
    private let onSelectChat: (String, String?) -> Void
    private let onNewChat: () -> Void
    private let onOpenSettings: () -> Void
    private let onDeleteChat: (String) -> Void
    private let workspaces: Workspaces

    /// A brand name: a plain `String`, shown as is and never looked up in the catalog.
    private static var appName: String { "Exodus" }

    public init(
        apiClient: APIClient,
        activeChatId: String,
        isOpen: Bool,
        reloadToken: Int,
        onSelectChat: @escaping (String, String?) -> Void,
        onNewChat: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onDeleteChat: @escaping (String) -> Void,
        @ViewBuilder workspaces: () -> Workspaces
    ) {
        _list = State(initialValue: ChatListViewModel(apiClient: apiClient))
        _search = State(initialValue: ChatSearchViewModel(apiClient: apiClient))
        self.activeChatId = activeChatId
        self.isOpen = isOpen
        self.reloadToken = reloadToken
        self.onSelectChat = onSelectChat
        self.onNewChat = onNewChat
        self.onOpenSettings = onOpenSettings
        self.onDeleteChat = onDeleteChat
        self.workspaces = workspaces()
    }

    public var body: some View {
        NavigationStack {
            List {
                if isSearching && search.hasQuery {
                    searchResultRows
                } else {
                    if !isSearching {
                        Section { workspaces }
                    }
                    Section("Recents") {
                        ForEach(list.chats) { chat in
                            row(for: chat)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay { overlayContent }
            .navigationTitle(isSearching ? "" : Self.appName)
            .navigationBarTitleDisplayMode(isSearching ? .inline : .large)
            .safeAreaBar(edge: .top) {
                if isSearching {
                    SidebarSearchBar(
                        text: Binding(get: { search.query }, set: { search.updateQuery($0) }),
                        onCancel: leaveSearch)
                }
            }
            .toolbar { sidebarToolbar }
            // Hidden while searching so it cannot ghost through the keyboard.
            .toolbarVisibility(isSearching ? .hidden : .visible, for: .bottomBar)
            // A full `load()`, not `refresh()`: this runs at launch and again after Settings closes, and
            // Settings can change the server address, so a silent refresh could leave the old server's
            // chats on screen.
            .task(id: reloadToken) { await list.load() }
            .refreshable { await list.load() }
            .onChange(of: isOpen) { _, nowOpen in
                if nowOpen {
                    Task { await list.refresh() }
                } else {
                    leaveSearch()
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { list.showsErrorAlert },
                    set: { if !$0 { list.errorMessage = nil } }
                )
            ) {
                Button("OK") {}
            } message: {
                Text(list.errorMessage ?? "")
            }
        }
    }

    // MARK: - Rows

    private func row(for chat: ChatSummary) -> some View {
        Text(chat.title.collapsedWhitespace)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Not a `Button`: one inside a `List` fires on touch-up wherever the finger ended up, so a
            // left swipe over a row closed the drawer and opened that chat at the same time. A
            // `TapGesture` fails as soon as the finger moves, which leaves the swipe to the drawer.
            .onTapGesture { onSelectChat(chat.id, chat.title) }
            .listRowBackground(chat.id == activeChatId ? Color.accentColor.opacity(0.12) : Color.clear)
            // What the `Button` gave VoiceOver, spelled out: the trait and an activation action.
            .accessibilityAddTraits(chat.id == activeChatId ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onSelectChat(chat.id, chat.title) }
            // Closes over this row's chat, so nothing indexes `list.chats` after a concurrent load.
            .contextMenu {
                Button(role: .destructive) {
                    Task {
                        if await list.delete(chat) { onDeleteChat(chat.id) }
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    private var searchResultRows: some View {
        if case .results(let results) = search.phase {
            ForEach(results) { result in
                VStack(alignment: .leading, spacing: 2) {
                    // The view model collapsed the title's whitespace when it grouped the hits.
                    Text(result.title)
                        .lineLimit(1)
                    if let snippet = result.snippet {
                        Text(snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // Same as the Recents rows: a tap selects, a swipe belongs to the drawer.
                .onTapGesture { onSelectChat(result.id, result.title) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onSelectChat(result.id, result.title) }
            }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var overlayContent: some View {
        if isSearching && search.hasQuery {
            switch search.phase {
            // A retry shows the spinner too, so Retry gives feedback and the failure view is not
            // on screen while it runs. Earlier results stay visible while a new query is in flight.
            case .idle where search.isSearching, .failed where search.isSearching:
                ProgressView()
                    .accessibilityLabel("Searching")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Search failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { search.retry() }
                }
            case .empty:
                ContentUnavailableView("No results", systemImage: "magnifyingglass")
            case .idle, .results:
                EmptyView()
            }
        } else if list.chats.isEmpty {
            // Not loaded yet reads as "loading", never as "No chats yet".
            if list.isLoading || !list.hasLoaded {
                ProgressView()
            } else if list.loadFailed {
                ContentUnavailableView {
                    Label("Can't load chats", systemImage: "wifi.exclamationmark")
                } description: {
                    // The error text lives here, not in an alert (see `showsErrorAlert`).
                    VStack(spacing: 4) {
                        if let message = list.errorMessage {
                            Text(message)
                        }
                        Text("Pull down or tap Retry to try again.")
                    }
                } actions: {
                    Button("Retry") { Task { await list.load() } }
                }
            } else {
                ContentUnavailableView("No chats yet", systemImage: "message")
            }
        }
    }

    // MARK: - Toolbar and search mode

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        if !isSearching {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) { isSearching = true }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("sidebarSearch")
            }
        }
        ToolbarItem(placement: .bottomBar) {
            Button(action: onNewChat) {
                Label("New chat", systemImage: "square.and.pencil")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("sidebarNewChat")
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("sidebarSettings")
        }
    }

    private func leaveSearch() {
        withAnimation(.snappy) { isSearching = false }
        search.reset()
    }
}
