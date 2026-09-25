import Foundation
import Models
import NetworkingKit
import Observation

@MainActor
@Observable
public final class ChatDetailViewModel {
    public let chatId: String
    public private(set) var messages: [ChatMessage] = [] {
        didSet { segments = RunGrouper.group(messages, cache: &segmentCache) }
    }
    public private(set) var segments: [Segment] = []
    @ObservationIgnored private var segmentCache = RunGrouper.Cache()
    public private(set) var status: ChatStatus = .idle
    public var composerText: String = ""
    /// Bumped to ask the composer to take focus ("This is wrong" under a used memory).
    public private(set) var composerFocusRequest = 0
    public private(set) var chatTitle: String?
    public var errorMessage: String?
    /// The stream failure of the run this client watched fail; a reload hands the error back to the rows.
    public private(set) var liveRunError: LiveRunError?
    /// Bumped on every failure, so a second failure with the same text still triggers the error haptic.
    public private(set) var failureCount = 0
    /// The heads-up a tool asked the server to relay, shown over the composer for a few seconds. The text is the
    /// server's own: shown as it is, never translated.
    public private(set) var notice: StreamNotice?
    /// True once the transcript is known: history loaded, or re-attached to an in-flight turn.
    /// Nothing is sent before that — the prior turns of a POST are the LLM context when the
    /// server's LCM feature is off, and the desktop does not render a chat before its history.
    public private(set) var hasLoadedHistory = false
    /// Whether this chat already had messages when it was first opened. A chat that was empty then
    /// is a new chat and keeps "New chat" in the title bar until the server sends a generated
    /// title; without this the title changed twice in one turn — to "Chat" the instant the first
    /// message was sent, and to the generated title a few seconds later.
    ///
    /// Only the first `loadHistory` sets this. A view model that re-attached to a turn already in
    /// flight never loaded a history, so it leaves this `false` and would call an old chat new —
    /// which only shows when that chat has no title at all, and a chat opened from the sidebar
    /// carries its title into `init`, so the re-attach path does not normally reach this fallback.
    private var openedWithMessages = false

    /// Bumped exactly once each time the user's own tap starts a turn — a plain counter so a
    /// `sensoryFeedback` trigger changes on every send, including a second send in the same chat.
    /// Never bumped by `loadHistory` or by `onAppear`'s re-attach to a turn already running (that
    /// sets `status` directly, not through here), and never by a tap `canSend` rejects.
    public private(set) var sendCount = 0
    /// Bumped exactly once when `stop()` actually cancelled a live turn — that is, when
    /// `ChatStreamManager.cancel(_:)` itself reports it found and stopped something. Not bumped
    /// merely because this view model *thought* a turn was in flight: `isTurnInFlight` mirrors the
    /// manager's state only up to the last update this view model has drained, and a turn can
    /// finish or fail on the manager side (removing its entry) before that drain catches up, since
    /// the manager's own update is only buffered until the `for await` loop in `consume` gets to
    /// it. Trusting the local flag alone here would occasionally mislabel a turn that had already
    /// finished normally as "stopped" — see `ChatStreamManagerTests` for `cancel`'s own coverage of
    /// this. Waiting for the manager's answer, rather than deciding synchronously on the tap, is
    /// the price of that correctness.
    public private(set) var stopCount = 0
    /// Bumped exactly once when a turn's stream ends with the server's own `.finished` and the user
    /// did not press Stop for it — a normal completion. Not bumped for a stopped turn, a failed
    /// turn, or a re-attach whose `consume` never receives a `.finished` at all.
    public private(set) var completedTurnCount = 0
    /// True while the turn in flight was ended by `stop()`, so `consume`'s `.finished` (the manager
    /// sends one for a stop too, see `ChatStreamManager.cancel`) is not counted as a normal
    /// completion. Reset at the start of every new send.
    private var turnWasStopped = false

    private let apiClient: APIClient
    /// The frames of computer_use sessions streamed here, kept for the finished card's filmstrip.
    @ObservationIgnored var computerUseFrames: ComputerUseFrameStore = .shared
    /// The tool calls paused for an answer on this chat's stream; the run's foot reads its own run from it.
    @ObservationIgnored let approvals: RunApprovalStore
    /// Which memories each run read, the memory list the strips compare with, and Undo; the run's foot reads its own run.
    @ObservationIgnored let memoryFoot: MemoryFootStore
    private let streamManager: ChatStreamManager
    private let serverConfig: ServerConfigStore
    private let noticeLifetime: Duration
    private let noticeSleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var noticeClearTask: Task<Void, Never>?

    /// `noticeLifetime` is how long a notice stays up; `noticeSleep` waits it out — a test hands in one it controls.
    public init(
        chatId: String, title: String? = nil, apiClient: APIClient, streamManager: ChatStreamManager,
        serverConfig: ServerConfigStore, noticeLifetime: Duration = .seconds(6),
        noticeSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.chatId = chatId
        self.chatTitle = Self.oneLine(title)
        self.apiClient = apiClient
        self.streamManager = streamManager
        self.serverConfig = serverConfig
        self.noticeLifetime = noticeLifetime
        self.noticeSleep = noticeSleep
        self.approvals = RunApprovalStore(apiClient: apiClient)
        self.memoryFoot = MemoryFootStore(apiClient: apiClient)
        memoryFoot.onWrong = { [weak self] text in self?.prefillComposer(text) }
    }

    /// Puts `text` in the composer, replacing what was there (as the desktop does), and asks for focus.
    func prefillComposer(_ text: String) {
        composerText = text
        composerFocusRequest += 1
    }

    /// Which memories each run of this chat read, for the runs loaded from history (a live run's arrive on its stream).
    public func loadMemoryUsage() async {
        guard hasLoadedHistory, !messages.isEmpty else { return }
        await memoryFoot.loadUsage(chatId: chatId)
    }

    public var isTurnInFlight: Bool { status == .submitted || status == .streaming }

    /// The three dots: nothing of the reply is on screen yet, or its answer has started and it waits on a tool.
    public var showsPendingRow: Bool {
        TranscriptRules.showsTypingIndicator(
            segments: segments, lastMessage: messages.last, isTurnInFlight: isTurnInFlight)
    }

    /// The turn whose markdown and timeline are live: the last one, while a turn is in flight.
    public var streamingTurnId: String? {
        TranscriptRules.streamingTurnId(segments: segments, isTurnInFlight: isTurnInFlight)
    }

    /// A stream failure is shown at the foot of its run, so the alert is kept for everything else.
    public var showsErrorAlert: Bool { errorMessage != nil && liveRunError == nil }

    public var canSend: Bool {
        hasLoadedHistory && !isTurnInFlight
            && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The answer that carries Regenerate: the last one, once nothing is in flight.
    public var regenerableTurnId: String? {
        TurnActions.regenerableTurnId(
            segments: segments, hasLoadedHistory: hasLoadedHistory, isTurnInFlight: isTurnInFlight)
    }

    /// A run that failed before any step has no turn to carry Regenerate; its error line offers it instead.
    public var canRetryOrphanError: Bool {
        TurnActions.canRetryOrphan(
            segments: segments, liveError: liveRunError, hasLoadedHistory: hasLoadedHistory,
            isTurnInFlight: isTurnInFlight)
    }

    public var canRegenerate: Bool { regenerableTurnId != nil || canRetryOrphanError }

    /// True for a loaded, empty chat with nothing in flight: the view shows its greeting. Never true
    /// before the history is known, so opening a chat does not flash the greeting.
    public var showsEmptyState: Bool { hasLoadedHistory && messages.isEmpty && !isTurnInFlight }

    /// What the title bar shows: the chat's own title, cut to a length a title bar can carry, else
    /// "New chat" for a chat that was empty when it was opened and "Chat" for one that was opened
    /// with messages and has no title yet.
    public var displayTitle: String {
        guard let chatTitle else {
            return openedWithMessages
                ? String(
                    localized: "chat:toast.chatFallbackTitle", defaultValue: "Chat",
                    comment: "Title of an open conversation that has no name yet.")
                : String(
                    localized: "ios:chat.detail.newChatTitle", defaultValue: "New chat",
                    comment: "Title bar of a conversation that was empty when it was opened.")
        }
        return Self.shortened(chatTitle)
    }

    /// Applies a title set from outside this chat's own turn/streaming lifecycle — the sidebar's
    /// long-press rename, while this chat happens to be the one on screen. Same normalisation as a
    /// generated title (one line, never blank); a blank rename is rejected before it gets here, but
    /// `nil` (no rename in flight) does nothing rather than clearing a real title.
    public func applyExternalRename(_ title: String?) {
        guard let normalised = Self.oneLine(title) else { return }
        chatTitle = normalised
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
            memoryFoot.prune(keeping: Set(messages.map { $0.runId ?? $0.id }))
            clearRunError()
            // Only the first load says what this chat was; a later pull-to-refresh sees the turns
            // that have happened since and must not turn a new chat into an old one.
            if !hasLoadedHistory { openedWithMessages = !messages.isEmpty }
            hasLoadedHistory = true
        } catch {
            // SwiftUI cancels a view's `.task` when the view goes away; that is not a failure.
            guard !isCancellation(error) else { return }
            errorMessage = error.localizedDescription
            failureCount += 1
        }
    }

    public func sendMessage() async {
        guard canSend else { return }
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        composerText = ""

        await startTurn(
            with: .userMessage(id: Self.newMessageId(), text: text, timestampMs: Self.nowMs))
    }

    /// Asks the last question again, as the desktop's `regenerate` does: a new user message with a new id (and so a new
    /// run) carrying the same content is appended, and the transcript so far — the previous answer included — is what is
    /// sent. Nothing is removed: the previous answer stays on screen and in the database, and the new one follows it.
    /// Does nothing while a turn is in flight, before the history is known, or when there is no question to repeat.
    public func regenerate() async {
        guard canRegenerate, let question = TurnActions.resendableUserMessage(in: segments) else { return }
        await startTurn(
            with: .userMessage(id: Self.newMessageId(), content: question.content, timestampMs: Self.nowMs))
    }

    /// The Sources sheet's content for one of the transcript's turns, at a citation chip's source when it names one.
    func sourcesSheet(forTurn turnId: String, marker: Int? = nil) -> SourcesSheetModel? {
        for segment in segments {
            if case .assistantTurn(let turn) = segment, turn.id == turnId {
                return SourcesSheetModel(turn: turn, marker: marker)
            }
        }
        return nil
    }

    /// Takes the notice off the screen now, and stops the timer that would have.
    public func dismissNotice() {
        noticeClearTask?.cancel()
        noticeClearTask = nil
        notice = nil
    }

    private func startTurn(with userMessage: ChatMessage) async {
        messages.append(userMessage)
        turnWasStopped = false
        clearRunError()
        dismissNotice()
        sendCount += 1
        status = .submitted  // disable the composer now, before the first stream update arrives

        let updates = await streamManager.send(chatId: chatId, messages: messages, serverConfig: serverConfig)
        await consume(updates)
    }

    /// The inline error and the alert text it stood in for go together, so neither outlives the other.
    private func clearRunError() {
        if liveRunError != nil { errorMessage = nil }
        liveRunError = nil
    }

    private func show(_ incoming: StreamNotice) {
        guard !incoming.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        noticeClearTask?.cancel()
        notice = incoming
        let (lifetime, sleep) = (noticeLifetime, noticeSleep)
        noticeClearTask = Task { [weak self] in
            try? await sleep(lifetime)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private static var nowMs: Double { Date().timeIntervalSince1970 * 1000 }
    private static func newMessageId() -> String { UUID().uuidString.lowercased() }

    /// Ends the turn in flight (the Stop button): the partial reply stays, and no error is shown.
    /// `consume` receives the manager's `.status(.idle)` and `.finished` and ends by itself.
    /// Does nothing when this view model has no turn in flight, so an idle view model can never
    /// cancel a turn that belongs to someone else.
    ///
    /// `isTurnInFlight` is only a locally cached mirror of the manager's state, so it can still
    /// read `true` for a moment after the turn has already finished or failed on the manager side
    /// (that update is sitting in the stream, not drained by `consume` yet). `cancel(_:)`'s own
    /// `Bool` is the one atomic answer for whether this call actually stopped anything; only then
    /// is this counted as a stop, so a turn that in truth already ended normally cannot be
    /// mislabeled here and have its real `.finished` wrongly excluded from `completedTurnCount`.
    public func stop() async {
        guard isTurnInFlight else { return }
        guard await streamManager.cancel(chatId) else { return }
        turnWasStopped = true
        stopCount += 1
    }

    private func consume(_ updates: AsyncStream<ChatStreamUpdate>) async {
        for await update in updates {
            switch update {
            case .messages(let messages):
                self.messages = messages
                computerUseFrames.ingest(segments)
            case .status(let status):
                self.status = status
            case .title(let title):
                chatTitle = Self.oneLine(title) ?? chatTitle
            case .notice(let notice):
                show(notice)
            case .approval(let event):
                approvals.apply(event)
            case .memoriesUsed(let runId, let memories):
                memoryFoot.applyUsed(runId: runId, memories: memories)
            case .memoryChanged:
                let run = messages.last { $0.role == "user" }
                memoryFoot.memoryChanged(inRun: run.map { $0.runId ?? $0.id })
            case .finished(let messages):
                self.messages = messages
                status = .idle
                if !turnWasStopped { completedTurnCount += 1 }
            case .failed(let message):
                if let run = messages.last(where: { $0.role == "user" }) {
                    liveRunError = LiveRunError(runId: run.runId ?? run.id, message: message)
                }
                errorMessage = message
                failureCount += 1
                status = .error
            }
        }
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
