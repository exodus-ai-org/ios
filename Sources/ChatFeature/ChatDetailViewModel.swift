import Foundation
import Models
import NetworkingKit
import Observation

@MainActor
@Observable
public final class ChatDetailViewModel {
    public let chatId: String
    public private(set) var messages: [ChatMessage] = []
    public private(set) var status: ChatStatus = .idle
    public var composerText: String = ""
    public private(set) var chatTitle: String?
    public var errorMessage: String?
    /// True once the transcript is known: history loaded, or re-attached to an in-flight turn.
    /// Nothing is sent before that — the prior turns of a POST are the LLM context when the
    /// server's LCM feature is off, and the desktop does not render a chat before its history.
    public private(set) var hasLoadedHistory = false
    /// Whether this chat already had messages when it was first opened. A chat that was empty then
    /// is a new chat and keeps "New chat" in the title bar until the server sends a generated
    /// title; without this the title changed twice in one turn — to "Chat" the instant the first
    /// message was sent, and to the generated title a few seconds later.
    ///
    /// Only the first `loadHistory` can know this. A view model that re-attached to a turn already
    /// in flight never saw a history, and a chat you are in the middle of a turn in is one you just
    /// started, so leaving it `false` is right there too.
    private var openedWithMessages = false

    private let apiClient: APIClient
    private let streamManager: ChatStreamManager
    private let serverConfig: ServerConfigStore

    public init(
        chatId: String, title: String? = nil, apiClient: APIClient, streamManager: ChatStreamManager,
        serverConfig: ServerConfigStore
    ) {
        self.chatId = chatId
        self.chatTitle = Self.oneLine(title)
        self.apiClient = apiClient
        self.streamManager = streamManager
        self.serverConfig = serverConfig
    }

    public var isTurnInFlight: Bool { status == .submitted || status == .streaming }

    /// True while a turn is in flight and nothing the assistant said is at the end of the
    /// transcript yet: from tapping send until the server's first assistant message, and again
    /// after a tool result. The view shows a "…" bubble so the screen is not dead in the meantime.
    public var showsPendingRow: Bool { isTurnInFlight && messages.last?.role != "assistant" }

    public var canSend: Bool {
        hasLoadedHistory && !isTurnInFlight
            && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True for a loaded, empty chat with nothing in flight: the view shows its greeting. Never true
    /// before the history is known, so opening a chat does not flash the greeting.
    public var showsEmptyState: Bool { hasLoadedHistory && messages.isEmpty && !isTurnInFlight }

    /// What the title bar shows: the chat's own title, cut to a length a title bar can carry, else
    /// "New chat" for a chat that was empty when it was opened and "Chat" for one that was opened
    /// with messages and has no title yet.
    public var displayTitle: String {
        guard let chatTitle else {
            return openedWithMessages ? String(localized: "Chat") : String(localized: "New chat")
        }
        return Self.shortened(chatTitle)
    }

    public func onAppear() async {
        if await streamManager.isStreaming(chatId), let updates = await streamManager.attach(chatId) {
            hasLoadedHistory = true
            status = .streaming
            await consume(updates)
        } else {
            await loadHistory()
        }
    }

    public func loadHistory() async {
        guard !isTurnInFlight else { return }  // a reload would replace the reply that is being streamed
        do {
            let rows: [ChatMessage] = try await apiClient.get("/api/v1/chat/\(chatId)")
            messages = ChatHistoryRows.uiMessages(from: rows)
            // Only the first load says what this chat was; a later pull-to-refresh sees the turns
            // that have happened since and must not turn a new chat into an old one.
            if !hasLoadedHistory { openedWithMessages = !messages.isEmpty }
            hasLoadedHistory = true
        } catch {
            // SwiftUI cancels a view's `.task` when the view goes away; that is not a failure.
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func sendMessage() async {
        guard canSend else { return }
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        composerText = ""

        let userMessage = ChatMessage.userMessage(
            id: UUID().uuidString.lowercased(), text: text, timestampMs: Date().timeIntervalSince1970 * 1000)
        messages.append(userMessage)
        status = .submitted  // disable the composer now, before the first stream update arrives

        let updates = await streamManager.send(chatId: chatId, messages: messages, serverConfig: serverConfig)
        await consume(updates)
    }

    /// Ends the turn in flight (the Stop button): the partial reply stays, and no error is shown.
    /// `consume` receives the manager's `.status(.idle)` and `.finished` and ends by itself.
    /// Does nothing when this view model has no turn in flight, so an idle view model can never
    /// cancel a turn that belongs to someone else.
    public func stop() async {
        guard isTurnInFlight else { return }
        await streamManager.cancel(chatId)
    }

    private func consume(_ updates: AsyncStream<ChatStreamUpdate>) async {
        for await update in updates {
            switch update {
            case .messages(let messages):
                self.messages = messages
            case .status(let status):
                self.status = status
            case .title(let title):
                chatTitle = Self.oneLine(title) ?? chatTitle
            case .finished(let messages):
                self.messages = messages
                status = .idle
            case .failed(let message):
                errorMessage = message
                status = .error
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// A chat title on one line; nil when there is nothing to show. Real titles can be long and multi-line.
    private static func oneLine(_ title: String?) -> String? {
        guard let collapsed = title?.collapsedWhitespace, !collapsed.isEmpty else { return nil }
        return collapsed
    }

    /// Generated titles are not bounded — the owner's history holds one of 1211 characters — while a
    /// title bar shows about thirty. Handed the whole string, the bar stops centring the title and
    /// stretches it across the toolbar buttons, so the displayed text is cut here. `chatTitle` keeps
    /// the server's text as it came.
    private static let displayTitleLimit = 80

    private static func shortened(_ title: String) -> String {
        guard title.count > displayTitleLimit else { return title }
        return title.prefix(displayTitleLimit).trimmingCharacters(in: .whitespaces) + "…"
    }
}
