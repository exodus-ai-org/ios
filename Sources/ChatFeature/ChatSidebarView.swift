import Models
import NetworkingKit
import SwiftUI

/// Tighter than the system's 16 pt: a row is about 44 pt at the default text size instead of 52,
/// which is still the 44 pt touch target and fits more chats on screen. With the separators hidden
/// the list reads as one column of titles, like the ChatGPT app's sidebar.
private let sidebarRowInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

/// One selectable sidebar row — a Recents chat or a search result.
///
/// The padding is part of the row's own hit area and the list row itself gets no insets, so the
/// whole cell selects the chat; `listRowInsets` would pad *around* the content shape and leave the
/// edges of the row to the list. `minHeight` keeps the shape at the 44 pt touch target even at a
/// small text size, where the content alone would be shorter than the list's minimum row height.
///
/// Not a `Button`: one inside a `List` fires on touch-up wherever the finger ended up, so a left
/// swipe over a row closed the drawer and opened that chat at the same time. A `TapGesture` fails as
/// soon as the finger moves, which leaves the swipe to the drawer — and what the `Button` gave
/// VoiceOver is spelled out instead, the trait plus an activation action.
private struct SidebarRow: ViewModifier {
    let isSelected: Bool
    let select: () -> Void
    /// A finger down on the row, tracked purely for the background tint below — it never wins the
    /// touch itself.
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(sidebarRowInsets)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
            // A same-priority, zero-distance drag purely for visual state: `.simultaneously` means
            // it never competes with `onTapGesture` above or the drawer's own pan for the touch, it
            // only reports when a finger is down. The only acknowledgment a row not built as a
            // `Button` (see the note above) would otherwise give at all.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(
                isPressed ? Color.primary.opacity(0.06)
                    : isSelected ? Color.accentColor.opacity(0.12) : Color.clear
            )
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select() }
    }
}

/// The drawer's content: workspaces, Recents, and an inline search. It owns its `NavigationStack`, so
/// the title and the search button are native; the bottom bar is a `safeAreaBar` of its own, because a
/// bottom-bar toolbar item cannot show a labelled button. Rows have no swipe actions (a left swipe
/// closes the drawer); a chat is deleted from its long-press menu.
public struct ChatSidebarView<Workspaces: View>: View {
    @State private var list: ChatListViewModel
    @State private var search: ChatSearchViewModel
    @State private var isSearching = false
    /// Bumped exactly once when a chat's delete succeeds and its row leaves the list — a plain
    /// counter so `sensoryFeedback` fires with the row's removal, not when the context menu opens
    /// and not for a failed delete (which raises `list.showsErrorAlert` instead).
    @State private var deletedTrigger = 0

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
                        // On the rows, not on the `Section`: a section passes the hidden separator down
                        // but keeps the insets to itself.
                        Section {
                            workspaces
                                .listRowSeparator(.hidden)
                                .listRowInsets(sidebarRowInsets)
                        }
                    }
                    Section("Recents") {
                        ForEach(list.chats) { chat in
                            row(for: chat)
                        }
                        recentsStateRow
                    }
                }
            }
            .listStyle(.plain)
            // The insets alone do not shrink a row below the list's own minimum, which is what held
            // the rows at 52 pt. 44 pt is the touch-target floor, never less.
            .environment(\.defaultMinListRowHeight, 44)
            // The bottom bar is not a system `.bottomBar`, so it does not get the scroll edge
            // effect for free: without it the rows print through the pill and the gear, and at
            // an accessibility text size a title is chopped mid-word by them.
            .scrollEdgeEffectStyle(.hard, for: .bottom)
            .overlay { searchStateOverlay }
            // Spinner, empty state, failure and results all cross-fade instead of cutting — the
            // Recents block only when a load finishes, search on every phase it can be in while a
            // query is live (apple-design: preventing a jarring change).
            .animation(.easeOut(duration: 0.15), value: list.chats.isEmpty)
            .animation(.easeOut(duration: 0.15), value: search.phase)
            .animation(.easeOut(duration: 0.15), value: search.isSearching)
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
            .safeAreaBar(edge: .bottom) {
                if !isSearching {
                    bottomBar
                }
            }
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
            // Haptics: the causal event only — the alert's own appearance, and a delete once the
            // row is actually gone (apple-design §13). Neither fires for the tap that opens the
            // context menu, and a failed delete gets only the error haptic above.
            .sensoryFeedback(trigger: list.showsErrorAlert) { old, new in
                !old && new ? .error : nil
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: deletedTrigger)
        }
    }

    // MARK: - Rows

    private func row(for chat: ChatSummary) -> some View {
        Text(chat.title.collapsedWhitespace)
            .lineLimit(1)
            // The selected tint lives inside `SidebarRow` now, alongside the press tint: applying
            // `.listRowBackground` again out here would simply replace whichever one it set.
            .modifier(
                SidebarRow(isSelected: chat.id == activeChatId) { onSelectChat(chat.id, chat.title) })
            // Closes over this row's chat, so nothing indexes `list.chats` after a concurrent load.
            .contextMenu {
                Button(role: .destructive) {
                    Task {
                        if await list.delete(chat) {
                            deletedTrigger += 1
                            onDeleteChat(chat.id)
                        }
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
                // Title and snippet are one element to VoiceOver, as the button's label used to be.
                .accessibilityElement(children: .combine)
                .modifier(SidebarRow(isSelected: false) { onSelectChat(result.id, result.title) })
            }
        }
    }

    // MARK: - States

    /// A row of the Recents section, not an overlay of the whole list: the list carries the workspace
    /// rows now, and a centred overlay covered them — at an accessibility text size it printed "Can't
    /// load chats" straight across Chat and Philharmonic.
    @ViewBuilder
    private var recentsStateRow: some View {
        if list.chats.isEmpty {
            Group {
                // Not loaded yet reads as "loading", never as "No chats yet".
                if list.isLoading || !list.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
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
                        // A list row makes its buttons plain, which would leave Retry looking like
                        // static text; `.borderless` gives it the tint back.
                        Button("Retry") { Task { await list.load() } }
                            .buttonStyle(.borderless)
                    }
                } else {
                    ContentUnavailableView("No chats yet", systemImage: "message")
                }
            }
            .transition(.opacity)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    /// Search mode keeps its overlay: the results it would cover are the ones it replaces, and the
    /// spinner over stale results while a new query runs is the point.
    @ViewBuilder
    private var searchStateOverlay: some View {
        if isSearching && search.hasQuery {
            switch search.phase {
            // A retry shows the spinner too, so Retry gives feedback and the failure view is not
            // on screen while it runs. Earlier results stay visible while a new query is in flight.
            case .idle where search.isSearching, .failed where search.isSearching:
                ProgressView()
                    .accessibilityLabel("Searching")
                    .transition(.opacity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Search failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { search.retry() }
                }
                .transition(.opacity)
            case .empty:
                ContentUnavailableView("No results", systemImage: "magnifyingglass")
                    .transition(.opacity)
            case .idle, .results:
                EmptyView()
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
    }

    /// A bar of its own, not `ToolbarItem(placement: .bottomBar)`: a bottom-bar item ignores
    /// `.labelStyle(.titleAndIcon)` and rendered New chat as a bare compose glyph, while the design
    /// asks for a labelled pill next to the round gear.
    private var bottomBar: some View {
        HStack {
            Button(action: onNewChat) {
                Label("New chat", systemImage: "square.and.pencil")
                    .labelStyle(.titleAndIcon)
                    // The longest translation ("Nouvelle conversation") must fit on one line next to
                    // the gear, in a sidebar that is a fraction of the screen wide.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("sidebarNewChat")
            Spacer(minLength: 12)
            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("sidebarSettings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // A bar, like a toolbar: it stops growing where a toolbar would. The sidebar is a fixed
        // fraction of the screen, and "Nouvelle conversation" next to the gear only fits on one line
        // up to about this size; past it the title would truncate. The list itself still scales.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func leaveSearch() {
        withAnimation(.snappy) { isSearching = false }
        search.reset()
    }
}
