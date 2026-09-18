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

    private let apiClient: APIClient
    private let streamManager: ChatStreamManager
    private let serverConfig: ServerConfigStore

    public init(chatId: String, apiClient: APIClient, streamManager: ChatStreamManager, serverConfig: ServerConfigStore) {
        self.chatId = chatId
        self.apiClient = apiClient
        self.streamManager = streamManager
        self.serverConfig = serverConfig
    }

    public var isTurnInFlight: Bool { status == .submitted || status == .streaming }

    public var canSend: Bool {
        hasLoadedHistory && !isTurnInFlight
            && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var displayTitle: String { chatTitle ?? (messages.isEmpty ? "New Chat" : "Chat") }

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
            let rows: [ChatMessage] = try await apiClient.get("/api/chat/\(chatId)")
            messages = ChatHistoryRows.uiMessages(from: rows)
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

    private func consume(_ updates: AsyncStream<ChatStreamUpdate>) async {
        for await update in updates {
            switch update {
            case .messages(let messages):
                self.messages = messages
            case .status(let status):
                self.status = status
            case .title(let title):
                chatTitle = title
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
}
