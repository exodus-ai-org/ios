#if DEBUG
import Foundation
import Models
import NetworkingKit
import SwiftUI

/// DEBUG-only: `-MessageGallery` shows fake runs through the real transcript rows; `-MessageGalleryExpanded` opens
/// every timeline and card; `-MessageGallerySection N` scrolls to run N and `-MessageGalleryEnd` to the last answer's
/// action bar; `-MessageGallerySheet [N]` opens the Sources sheet of the last run (at source N when given) and
/// `-MessageGallerySheetEmpty` the one of a run without sources; `-MessageGalleryNotice info|warning|long` shows the
/// notice banner; `-MessageGalleryReadAloud loading|playing` shows read-aloud in that state on the last answer (a tap
/// on any speaker walks through the states, with no sound). Run 1 has read two memories and carries a settled
/// approval, run 2 waits for one, and the run before last searched sixty results: what stands under an answer, and
/// the timeline's pills, as a chat has them.
public enum MessageGalleryLaunch {
    public static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGallery") }
    static var expanded: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGalleryExpanded") }
    /// A number, or a name of the interactive blocks' runs (`MessageGalleryFixtures.namedSection`).
    static var section: Int? {
        value(after: "-MessageGallerySection").flatMap { Int($0) ?? MessageGalleryFixtures.namedSection($0) }
    }
    static var scrollsToEnd: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGalleryEnd") }
    static var opensSheet: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGallerySheet") }
    static var opensEmptySheet: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGallerySheetEmpty") }
    static var sheetMarker: Int? { value(after: "-MessageGallerySheet").flatMap { Int($0) } }
    /// `-MessageGallerySheetRun N`: the sheet is that of run N's last answer instead of the last run's.
    static var sheetRun: Int? {
        value(after: "-MessageGallerySheetRun").flatMap { Int($0) }.flatMap { MessageGalleryFixtures.runs.indices.contains($0) ? $0 : nil }
    }
    static var readAloud: String? { value(after: "-MessageGalleryReadAloud") }
    /// `-MessageGalleryCopied`: every action row shows its checkmark, as just after Copy.
    static var copied: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGalleryCopied") }
    /// `-MessageGalleryQuote`: the composer with a quote set, as "Ask Exodus" leaves it.
    static var quote: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGalleryQuote") }
    static var notice: StreamNotice? {
        switch value(after: "-MessageGalleryNotice") {
        case "info": StreamNotice(level: .info, message: "Search results are limited to the last 12 months for this chat.")
        case "warning": StreamNotice(level: .warning, message: "The Places key has expired, so place details were skipped for this itinerary.")
        case "long":
            StreamNotice(
                level: .warning,
                message:
                    "The map provider rate-limited this request 3 times, so the itinerary was built from cached places only. Ask again in a minute to refresh opening hours, photos and ratings for every stop on the route.")
        default: nil
        }
    }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}

public struct MessageGalleryView: View {
    @State private var sheet: SourcesSheetModel?
    @State private var notice = MessageGalleryLaunch.notice
    @State private var readAloud = GalleryReadAloud.model()
    @State private var memory = GalleryFoot.memory()
    @State private var approvals = GalleryFoot.approvals()
    @Environment(\.accentGlyph) private var accentGlyph
    @Environment(\.toneAccent) private var toneAccent
    @Environment(\.toneInk) private var toneInk
    @Environment(\.colorScheme) private var colorScheme
    private let runs = MessageGalleryFixtures.runs.map(PreparedRun.init)

    public init() {}

    private struct PreparedRun {
        let run: MessageGalleryFixtures.Run
        let segments: [Segment]
        let streamingTurnId: String?
        let showsTyping: Bool

        init(_ run: MessageGalleryFixtures.Run) {
            self.run = run
            segments = MessageGalleryFixtures.segments(run.json)
            streamingTurnId = TranscriptRules.streamingTurnId(segments: segments, isTurnInFlight: run.inFlight)
            showsTyping = TranscriptRules.showsTypingIndicator(
                segments: segments, lastMessage: run.lastMessage, isTurnInFlight: run.inFlight)
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 36) {
                        ForEach(Array(runs.enumerated()), id: \.offset) { index, prepared in
                            VStack(alignment: .leading, spacing: 24) {
                                Text(verbatim: "\(index) · \(prepared.run.title)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tint)
                                TranscriptRows(
                                    segments: prepared.segments, streamingTurnId: prepared.streamingTurnId,
                                    showsTypingIndicator: prepared.showsTyping, liveError: nil,
                                    actions: actions(for: index))
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, TranscriptRows.endRoom)
                    .id(TranscriptRows.endID)
                }
                .task {
                    if MessageGalleryLaunch.opensSheet, let run = MessageGalleryLaunch.sheetRun.map({ runs[$0] }) ?? runs.last {
                        sheet = sourcesSheet(in: run, turnId: nil, marker: MessageGalleryLaunch.sheetMarker)
                    } else if MessageGalleryLaunch.opensEmptySheet, let first = runs.first {
                        sheet = sourcesSheet(in: first, turnId: nil, marker: nil)
                    }
                    if MessageGalleryLaunch.scrollsToEnd {
                        try? await Task.sleep(for: .milliseconds(300))
                        proxy.scrollTo(TranscriptRows.endID, anchor: .bottom)
                        return
                    }
                    guard let section = MessageGalleryLaunch.section else { return }
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo(section, anchor: .top)
                }
            }
            .navigationTitle(Text(verbatim: "Messages"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaBar(edge: .bottom) {
                if MessageGalleryLaunch.notice != nil {
                    NoticeStack(notice: notice, onDismiss: { notice = nil }) { standInComposer }
                } else if MessageGalleryLaunch.quote {
                    standInComposer
                } else if let state = ComposerGalleryState.launch {
                    ComposerGalleryBar(state: state)
                }
            }
        }
        .sheet(item: $sheet) {
            SourcesSheet(model: $0)
                .environment(\.searchMediaLoader, GalleryIcons.loader)
        }
        .environment(\.timelineStartsExpanded, MessageGalleryLaunch.expanded)
        .environment(\.searchMediaLoader, GalleryIcons.loader)
        .environment(\.readAloud, readAloud)
        .environment(\.memoryFoot, memory)
        .environment(\.runApprovals, approvals)
        .task {
            guard MessageGalleryLaunch.readAloud != nil, let last = runs.last,
                case .assistantTurn(let turn)? = last.segments.last
            else { return }
            await GalleryReadAloud.start(on: readAloud, turn: turn)
        }
    }

    /// Only the last run is the transcript's end, so only its answer carries Regenerate.
    private func actions(for index: Int) -> TranscriptActions {
        let prepared = runs[index]
        var regenerable: String?
        if index == runs.count - 1 || prepared.run.offersRetry, case .assistantTurn(let turn)? = prepared.segments.last {
            regenerable = turn.id
        }
        return TranscriptActions(
            regenerableTurnId: regenerable, regenerate: {},
            showSources: { turnId, marker in
                sheet = sourcesSheet(in: prepared, turnId: turnId, marker: marker)
            },
            // A block can be filled in here; Submit sends nothing.
            canAnswer: true, sendAnswer: { _ in })
    }

    /// The sheet of a turn of the run: the one named, else the run's last.
    private func sourcesSheet(in prepared: PreparedRun, turnId: String?, marker: Int?) -> SourcesSheetModel? {
        for segment in prepared.segments.reversed() {
            if case .assistantTurn(let turn) = segment, turnId == nil || turn.id == turnId {
                return SourcesSheetModel(turn: turn, marker: marker)
            }
        }
        return nil
    }

    /// The composer's silhouette, so the banner is seen where it sits in the chat.
    private var standInComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if MessageGalleryLaunch.quote {
                ComposerQuote(text: "大金（6367）已经卖出，不再算持仓。", onRemove: {})  // l10n:ignore: gallery fixture
            }
            standInRow
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var standInRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text("ios:chat.composer.placeholder")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            // Styled as the real send button, enabled.
            Button {} label: {
                Label("chat:composer.send", systemImage: "arrow.up")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(colorScheme == .dark ? accentGlyph : .white)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            // As the chat's: the ink with a white arrow in light, the fill and its glyph in dark.
            .tint(colorScheme == .dark ? toneAccent : toneInk)
        }
    }
}

/// Read aloud with no computer and no sound: the audio "arrives" after a moment and "plays" for a few seconds. Under
/// `-MessageGalleryReadAloud` the state asked for is held, so a screenshot finds it.
@MainActor
enum GalleryReadAloud {
    private final class SilentPlayer: SpeechPlayer {
        let length: Duration
        private var playing: Task<Void, Never>?

        init(length: Duration) { self.length = length }

        func play(_ audio: Data, finished: @escaping @MainActor () -> Void) throws {
            playing?.cancel()
            playing = Task { [length] in
                guard (try? await Task.sleep(for: length)) != nil else { return }
                finished()
            }
        }

        func stop() {
            playing?.cancel()
            playing = nil
        }
    }

    static func model() -> ReadAloudModel {
        let held = MessageGalleryLaunch.readAloud
        let wait: Duration = held == "loading" ? .seconds(600) : held == "playing" ? .zero : .seconds(1.5)
        return ReadAloudModel(
            fetch: { _ in
                try await Task.sleep(for: wait)
                return Data()
            }, player: SilentPlayer(length: held == "playing" ? .seconds(600) : .seconds(4)))
    }

    static func start(on model: ReadAloudModel, turn: AssistantTurn) async {
        await model.toggle(id: turn.id, text: SpeechText.prose(turn.body))
    }
}

/// What stands under an answer in a chat, with no computer behind it: the memories two runs read, an approval
/// that was given and one that waits.
@MainActor
enum GalleryFoot {
    static func memory() -> MemoryFootStore {
        let store = MemoryFootStore(
            client: .init(
                entries: { ProtoFixtures.currentMemories }, usage: { _ in [:] },
                undo: { changes in MemoryUndoResult(undone: changes.map(\.id), skipped: []) }))
        store.applyUsed(runId: "u2", memories: ProtoFixtures.usedMemories)
        store.applyUsed(runId: "u6", memories: ProtoFixtures.usedMemories)
        return store
    }

    static func approvals() -> RunApprovalStore {
        let store = RunApprovalStore { _, _, decision in decision == .allow ? .allowed : .denied }
        let expiry = Date().addingTimeInterval(9 * 60 + 41)
        store.apply(
            .required(
                ApprovalRequest(
                    runId: "u2", toolCallId: "g1", toolName: "read_file", summary: "~/.config/gh/hosts.yml",
                    expiresAt: expiry)))
        store.apply(.resolved(runId: "u2", toolCallId: "g1", outcome: .allowed))
        store.apply(
            .required(
                ApprovalRequest(
                    runId: "u3", toolCallId: "g2", toolName: "read_file", summary: "~/.ssh/id_ed25519", expiresAt: expiry)))
        return store
    }
}

enum MessageGalleryFixtures {
    /// A search as a real one comes back: some sixty results, most of them from a dozen sites.
    static let manyResults: String = {
        let sites: [(name: String?, host: String, count: Int)] = [
            ("Yahoo! Finance", "finance.yahoo.com", 8), ("The Motley Fool", "www.fool.com", 5),
            ("StockAnalysis", "stockanalysis.com", 1), ("Rolling Out", "rollingout.com", 1),
            ("GuruFocus", "www.gurufocus.com", 1), ("CNN", "www.cnn.com", 2), ("Investing.com", "www.investing.com", 6),
            ("Lufkin Daily News", "lufkindailynews.com", 1), ("The Detroit News", "www.detroitnews.com", 1),
            ("24/7 Wall St.", "247wallst.com", 2), (nil, "www.reddit.com", 10), ("CNBC", "www.cnbc.com", 4),
            ("MarketBeat", "www.marketbeat.com", 3), ("Traders Union", "tradersunion.com", 3),
            (nil, "noicon.markets.example", 2), ("Nasdaq", "www.nasdaq.com", 1), ("Benzinga", "www.benzinga.com", 1),
        ]
        var rank = 0
        var details: [String] = []
        // Interleaved, as a search returns them: a site's results are not side by side.
        for round in 0..<10 {
            for site in sites where site.count > round {
                rank += 1
                let name = site.name.map { #","siteName":"\#($0)""# } ?? ""
                details.append(
                    #"{"rank":\#(rank),"link":"https://\#(site.host)/article/\#(round)","title":"Result \#(rank)","snippet":"","hostname":"\#(site.host)"\#(name)}"#)
            }
        }
        return #"""
            [{"id":"u9","runId":"u9","role":"user","content":"\#u{7814}\#u{7A76}\#u{4E0B}\#u{5FAE}\#u{8F6F}\#u{5468}\#u{4E94}\#u{6DA8}\#u{4E86} 3.66% \#u{7684}\#u{539F}\#u{56E0}","timestamp":1000},
             {"id":"a16","runId":"u9","role":"assistant","content":[{"type":"toolCall","id":"k12","name":"web_search","arguments":{"query":"Microsoft stock rose 3.66% Friday"}}],"stopReason":"toolUse","timestamp":2000},
             {"id":"t12","runId":"u9","role":"toolResult","toolCallId":"k12","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":[\#(details.joined(separator: ","))],"isError":false,"timestamp":3000},
             {"id":"a17","runId":"u9","role":"assistant","content":[{"type":"text","text":"\#u{540C}\#u{4E00}\#u{5468}\#u{7F8E}\#u{503A}\#u{6536}\#u{76CA}\#u{7387}\#u{98D9}\#u{5347}\#u{81F3}\#u{591A}\#u{5341}\#u{5E74}\#u{9AD8}\#u{4F4D}\#u{FF0C}\#u{7ED9}\#u{6574}\#u{4F53}\#u{79D1}\#u{6280}\#u{80A1}\#u{4F30}\#u{503C}\#u{5E26}\#u{6765}\#u{538B}\#u{529B}\#u{3010}8,9-source\#u{3011}\#u{3002}\#u{6280}\#u{672F}\#u{9762}\#u{4E0A}\#u{4E5F}\#u{6709}\#u{5206}\#u{6790}\#u{6307}\#u{51FA}\#u{FF0C}\#u{77ED}\#u{671F}\#u{53EF}\#u{80FD}\#u{6709}\#u{6574}\#u{7406}\#u{9700}\#u{6C42}\#u{3010}1-source\#u{3011}\#u{3002}"}],"stopReason":"stop","durationMs":34000,"timestamp":4000}]
            """#
    }()

    struct Run {
        let title: String
        let json: String
        var inFlight = false
        /// Its error line offers Regenerate, as the transcript's last run would.
        var offersRetry = false
        var lastMessage: ChatMessage? {
            (try? JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8)))?.last
        }
    }

    static func segments(_ json: String) -> [Segment] {
        let messages = (try? JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))) ?? []
        var cache = RunGrouper.Cache()
        return RunGrouper.group(rebased(messages), cache: &cache)
    }

    /// Fixture timestamps are small numbers; shifted, the last message is four minutes old, so the bar's time reads as a time of day.
    private static func rebased(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard let latest = messages.compactMap(\.timestampMs).max() else { return messages }
        let shift = Date().timeIntervalSince1970 * 1000 - 240_000 - latest
        return messages.map { message in
            var raw = message.raw
            if let timestamp = message.timestampMs { raw["timestamp"] = .number(timestamp + shift) }
            return ChatMessage(id: message.id, role: message.role, raw: raw)
        }
    }

    static let runs: [Run] = [
        Run(title: "Plain answer", json: #"""
            [{"id":"u1","runId":"u1","role":"user","content":"What's a good name for\na sourdough starter?","timestamp":1000},
             {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"A few ideas, from classic to silly:\n\n- **Clint Yeastwood**\n- *Bread Pitt*\n- `Doughbi-Wan`\n\nPick one that makes you smile when you feed it."}],"stopReason":"stop","durationMs":800,"timestamp":1200}]
            """#),
        Run(title: "Asked about a selection: the quote over the question", json: #"""
            [{"id":"u1","runId":"u1","role":"user","content":"> 大金（6367）已经卖出，不再算持仓。\n\n什么时候卖的？","timestamp":1000},
             {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"你在上个月底卖出的。"}],"stopReason":"stop","durationMs":600,"timestamp":1200}]
            """#),
        Run(title: "Thinking + web search + terminal", json: #"""
            [{"id":"u2","runId":"u2","role":"user","content":"Is Swift 6.2 out, and what does `swift --version` say here?","timestamp":1000},
             {"id":"a2","runId":"u2","role":"assistant","content":[{"type":"thinking","thinking":"**Checking the release**\nI should search for the Swift 6.2 announcement, then run the compiler locally."},{"type":"toolCall","id":"k1","name":"web_search","arguments":{"query":"Swift 6.2 release"}}],"stopReason":"toolUse","timestamp":2000},
             {"id":"t1","runId":"u2","role":"toolResult","toolCallId":"k1","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":[{"rank":1,"link":"https://www.swift.org/blog/swift-6.2-released/","title":"Swift 6.2 Released","snippet":"","hostname":"www.swift.org","favicon":"https://www.swift.org/icon.png"},{"rank":2,"link":"https://developer.apple.com/xcode/","title":"Xcode","snippet":"","hostname":"developer.apple.com","favicon":"https://developer.apple.com/icon.png"},{"rank":3,"link":"https://forums.swift.org/t/6-2","title":"Forums","snippet":"","hostname":"forums.swift.org"}],"isError":false,"timestamp":3000},
             {"id":"a3","runId":"u2","role":"assistant","content":[{"type":"toolCall","id":"k2","name":"terminal","arguments":{"command":"swift --version"}}],"stopReason":"toolUse","timestamp":4000},
             {"id":"t2","runId":"u2","role":"toolResult","toolCallId":"k2","toolName":"terminal","content":[{"type":"text","text":"{}"}],"details":{"command":"swift --version","cwd":"/Users/me/.exodus/workspace/c1","exitCode":0,"stdout":"swift-driver version: 1.127\nApple Swift version 6.2 (swiftlang-6.2.0.19.9)\nTarget: arm64-apple-macosx26.0","stderr":""},"isError":false,"timestamp":5000},
             {"id":"a4","runId":"u2","role":"assistant","content":[{"type":"text","text":"Yes — Swift 6.2 is out \#u{3010}1-source\#u{3011} and ships with the current Xcode \#u{3010}2-source\#u{3011}. Your machine already runs it:\n\n```\nApple Swift version 6.2\n```"}],"stopReason":"stop","durationMs":12400,"timestamp":6000}]
            """#),
        Run(title: "A <thinking> span saved in the answer's text: the timeline shows it", json: #"""
            [{"id":"ut1","runId":"ut1","role":"user","content":"国庆去北京玩三天，避开热门景点，帮我排个行程。","timestamp":1000},
             {"id":"at1","runId":"ut1","role":"assistant","content":[{"type":"text","text":"<thinking>国庆假期，北京，避开热门景点。三天，偏小众的胡同、园林和博物馆。用 map_itinerary 展示。</thinking>\n\n好的，下面是一份避开人潮的三天行程。"}],"stopReason":"stop","durationMs":4200,"timestamp":1200}]
            """#),
        Run(title: "Failed tool + MCP card", json: #"""
            [{"id":"u3","runId":"u3","role":"user","content":"Read notes.md and draw it as a diagram.","timestamp":1000},
             {"id":"a5","runId":"u3","role":"assistant","content":[{"type":"toolCall","id":"k3","name":"read_file","arguments":{"path":"~/notes.md"}},{"type":"toolCall","id":"k4","name":"drawio_create","arguments":{}}],"stopReason":"toolUse","timestamp":2000},
             {"id":"t3","runId":"u3","role":"toolResult","toolCallId":"k3","toolName":"read_file","content":[{"type":"text","text":"ENOENT: no such file or directory, open '~/notes.md'"}],"isError":true,"timestamp":3000},
             {"id":"t4","runId":"u3","role":"toolResult","toolCallId":"k4","toolName":"drawio_create","content":[{"type":"text","text":"created"}],"details":{"diagramId":"d-42","pages":1,"url":"https://app.diagrams.net/#d-42"},"isError":false,"timestamp":3500},
             {"id":"a6","runId":"u3","role":"assistant","content":[{"type":"text","text":"I couldn't find `notes.md` in your home folder, so I drew an empty diagram instead."}],"stopReason":"stop","durationMs":3100,"timestamp":4000}]
            """#),
        Run(title: "Streaming, pending tool", json: #"""
            [{"id":"u4","runId":"u4","role":"user","content":"List what's in my Downloads folder.","timestamp":1000},
             {"id":"a7","runId":"u4","role":"assistant","content":[{"type":"thinking","thinking":"**Listing the folder**\nA directory listing answers this directly."},{"type":"toolCall","id":"k5","name":"list_directory","arguments":{"path":"~/Downloads"}}],"stopReason":"toolUse","timestamp":2000}]
            """#, inFlight: true),
        Run(title: "Run ended in an error", json: #"""
            [{"id":"u5","runId":"u5","role":"user","content":"Summarise this week's news.","timestamp":1000},
             {"id":"a8","runId":"u5","role":"assistant","content":[{"type":"text","text":"Here is what happened this week"}],"stopReason":"error","errorMessage":"429 Too Many Requests: rate limit exceeded","timestamp":2000}]
            """#),
        Run(title: "Failed before answering, long output", json: #"""
            [{"id":"u7","runId":"u7","role":"user","content":"Run the test suite and tell me what broke.","timestamp":1000},
             {"id":"a11","runId":"u7","role":"assistant","content":[{"type":"toolCall","id":"k9","name":"terminal","arguments":{"command":"swift test --parallel"}}],"stopReason":"toolUse","timestamp":2000},
             {"id":"t9","runId":"u7","role":"toolResult","toolCallId":"k9","toolName":"terminal","content":[{"type":"text","text":"{}"}],"details":{"command":"swift test --parallel","cwd":"/Users/me/Code/app","exitCode":1,"stdout":"[1/20] Compiling Models\n[2/20] Compiling NetworkingKit\n[3/20] Compiling ChatFeature\n[4/20] Linking\nTest Suite 'All tests' started\nTest Case 'RunGrouperTests.order' passed\nTest Case 'RunGrouperTests.split' passed\nTest Case 'ToolPresentationTests.names' passed\nTest Case 'ToolPresentationTests.header' passed\nTest Case 'RecentTimestampTests.today' failed\nTest Case 'RecentTimestampTests.midnight' failed\nTest Case 'SourcesTests.host' passed\nTest Case 'SourcesTests.title' passed\nTest Case 'NoticeTests.blank' passed\nExecuted 14 tests, with 2 failures","stderr":"error: 2 tests failed"},"isError":false,"timestamp":3000},
             {"id":"a12","runId":"u7","role":"assistant","content":[],"stopReason":"error","errorMessage":"","timestamp":4000}]
            """#, offersRetry: true),
        Run(title: "Text, a card, more text: the run's own order", json: #"""
            [{"id":"u8","runId":"u8","role":"user","content":"What's in the project folder, and does it build?","timestamp":1000},
             {"id":"a13","runId":"u8","role":"assistant","content":[{"type":"text","text":"Let me list the folder first."},{"type":"toolCall","id":"k10","name":"terminal","arguments":{"command":"ls"}}],"stopReason":"toolUse","timestamp":2000},
             {"id":"t10","runId":"u8","role":"toolResult","toolCallId":"k10","toolName":"terminal","content":[{"type":"text","text":"{}"}],"details":{"command":"ls","cwd":"/Users/me/Code/app","exitCode":0,"stdout":"Package.swift\nSources\nTests","stderr":""},"isError":false,"timestamp":3000},
             {"id":"a14","runId":"u8","role":"assistant","content":[{"type":"text","text":"A Swift package, with its sources and its tests. Now the build:"},{"type":"toolCall","id":"k11","name":"terminal","arguments":{"command":"swift build"}}],"stopReason":"toolUse","timestamp":4000},
             {"id":"t11","runId":"u8","role":"toolResult","toolCallId":"k11","toolName":"terminal","content":[{"type":"text","text":"{}"}],"details":{"command":"swift build","cwd":"/Users/me/Code/app","exitCode":0,"stdout":"Build complete! (2.41s)","stderr":""},"isError":false,"timestamp":5000},
             {"id":"a15","runId":"u8","role":"assistant","content":[{"type":"text","text":"It builds cleanly, so there is **nothing to fix**."}],"stopReason":"stop","durationMs":5200,"timestamp":6000}]
            """#),
        Run(title: "A search with sixty results: a pill per site", json: manyResults),
        Run(title: "A second turn citing the first turn's search", json: #"""
            [{"id":"u10","runId":"u10","role":"user","content":"What is new in Swift 6.2?","timestamp":1000},
             {"id":"a18","runId":"u10","role":"assistant","content":[{"type":"toolCall","id":"k13","name":"web_search","arguments":{"query":"Swift 6.2 what is new"}}],"stopReason":"toolUse","timestamp":2000},
             {"id":"t13","runId":"u10","role":"toolResult","toolCallId":"k13","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":[
               {"rank":1,"link":"https://www.swift.org/blog/swift-6.2-released/","title":"Swift 6.2 Released","siteName":"Swift.org","hostname":"www.swift.org","snippet":"Swift 6.2 makes concurrency easier to adopt."},
               {"rank":2,"link":"https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md","title":"SE-0466: Control default actor isolation inference","siteName":"GitHub","hostname":"github.com","snippet":"A per-module setting that infers @MainActor."},
               {"rank":3,"link":"https://developer.apple.com/videos/play/wwdc2025/245/","title":"What's new in Swift - WWDC25","hostname":"developer.apple.com","snippet":"Highlights of the language."},
               {"rank":4,"link":"https://forums.swift.org/t/swift-6-2-release-thread/80001","title":"Swift 6.2 release thread","hostname":"forums.swift.org"}],"isError":false,"timestamp":3000},
             {"id":"a19","runId":"u10","role":"assistant","content":[{"type":"text","text":"Mostly approachable concurrency \#u{3010}1-source\#u{3011}."}],"stopReason":"stop","durationMs":4100,"timestamp":4000},
             {"id":"u11","runId":"u11","role":"user","content":"Which of those matters for my app's main actor?","timestamp":5000},
             {"id":"a20","runId":"u11","role":"assistant","content":[{"type":"text","text":"The default isolation setting \#u{3010}2-source\#u{3011}: with it a module's code is on the main actor unless it says otherwise \#u{3010}1,2-source\#u{3011}. The session walks through it \#u{3010}3-source\#u{3011}."}],"stopReason":"stop","durationMs":2300,"timestamp":6000}]
            """#),
        Run(title: "Sources: two searches, one turn", json: #"""
            [{"id":"u6","runId":"u6","role":"user","content":"What changed in Swift 6.2, and how does it affect concurrency?","timestamp":1000},
             {"id":"a9","runId":"u6","role":"assistant","content":[{"type":"thinking","thinking":"**Two searches**\nThe release notes first, then the concurrency proposal."},{"type":"toolCall","id":"k6","name":"web_search","arguments":{"query":"Swift 6.2 release notes"}}],"stopReason":"toolUse","timestamp":2000},
             {"id":"t5","runId":"u6","role":"toolResult","toolCallId":"k6","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":[
               {"rank":1,"link":"https://www.swift.org/blog/swift-6.2-released/","title":"Swift 6.2 Released","siteName":"Swift.org","hostname":"www.swift.org","favicon":"https://www.swift.org/icon.png","age":"2 weeks ago","snippet":"Swift 6.2 makes concurrency easier to adopt, with approachable defaults, a new @concurrent attribute and better tooling for migration."},
               {"rank":2,"link":"https://developer.apple.com/videos/play/wwdc2025/245/","title":"What's new in Swift - WWDC25","hostname":"developer.apple.com","favicon":"https://developer.apple.com/icon.png","snippet":"Highlights of the language, from InlineArray and Span to the new module selectors and strict memory safety."},
               {"rank":3,"link":"https://noicon.swiftweekly.example/articles/281/what-is-new-in-swift-6-2","title":"The complete, exhaustive and slightly overwhelming guide to every single change in the Swift 6.2 release, with examples","hostname":"noicon.swiftweekly.example","snippet":"Paul Hudson walks through every feature that landed in Swift 6.2 with runnable code, from default actor isolation to the new Task naming APIs and everything in between."},
               {"rank":4,"link":"https://forums.swift.org/t/swift-6-2-release-thread/80001","title":"Swift 6.2 release thread","hostname":"forums.swift.org"},
               {"rank":5,"link":"javascript:alert(1)","title":"A link the app will not open","hostname":"example.com","snippet":"The scheme is not one a source may use, so this row is shown but is not tappable."}],"isError":false,"timestamp":3000},
             {"id":"a10","runId":"u6","role":"assistant","content":[{"type":"toolCall","id":"k7","name":"web_search","arguments":{"query":"Swift 6.2 approachable concurrency"}}],"stopReason":"toolUse","timestamp":4000},
             {"id":"t6","runId":"u6","role":"toolResult","toolCallId":"k7","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":[
               {"rank":1,"link":"https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md","title":"SE-0466: Control default actor isolation inference","siteName":"GitHub","hostname":"github.com","favicon":"https://github.com/icon.png","snippet":"Introduces a per-module setting that infers @MainActor for declarations without explicit isolation."},
               {"rank":2,"link":"https://www.swift.org/migration/documentation/migrationguide/","title":"Swift 6 migration guide","hostname":"www.swift.org","favicon":"https://www.swift.org/icon.png","snippet":"How to turn on strict concurrency checking and fix what it finds, one module at a time."}],"isError":false,"timestamp":5000},
             {"id":"a11","runId":"u6","role":"assistant","content":[{"type":"text","text":"Swift 6.2 is mostly about making concurrency **approachable**:\n\n- New modules can default to `@MainActor`, so single-threaded code needs no annotations \u30101-source\u3011\n- `@concurrent` marks the functions that really should leave the caller's actor \u30101-source\u3011\n- The release also adds `InlineArray` and `Span` \u30102-source\u3011\n\nThe migration guide is still the best place to start \u30102-source\u3011, and the full change list is long \u30103-source\u3011."}],"stopReason":"stop","durationMs":9200,"timestamp":6000}]
            """#),
        Run(title: "Asked with pictures: one alone, then six with text", json: #"""
            [{"id":"u20","runId":"u20","role":"user","content":[{"type":"image","mimeType":"image/png","data":"\#(picture(.systemTeal, width: 480, height: 300))"}],"timestamp":1000},
             {"id":"a20","runId":"u20","role":"assistant","content":[{"type":"text","text":"A wide teal picture."}],"stopReason":"stop","timestamp":1200},
             {"id":"u21","runId":"u21","role":"user","content":[{"type":"text","text":"Which of these is warmest?"},{"type":"image","mimeType":"image/png","data":"\#(picture(.systemOrange, width: 300, height: 400))"},{"type":"image","mimeType":"image/png","data":"\#(picture(.systemIndigo, width: 400, height: 400))"},{"type":"image","mimeType":"image/png","data":"\#(picture(.systemPink, width: 300, height: 300))"},{"type":"image","mimeType":"image/png","data":"\#(picture(.systemGreen, width: 500, height: 200))"},{"type":"image","mimeType":"image/png","data":"\#(picture(.systemYellow, width: 200, height: 500))"},{"type":"image","mimeType":"image/png","data":"\#(picture(.systemRed, width: 300, height: 300))"}],"timestamp":1300},
             {"id":"a21","runId":"u21","role":"assistant","content":[{"type":"text","text":"The orange one."}],"stopReason":"stop","timestamp":1500}]
            """#),
    ] + bubbleRuns + interactiveRuns

    /// A flat picture as the desktop stores one: a PNG data URL.
    static func picture(_ color: UIColor, width: CGFloat, height: CGFloat) -> String {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}
#endif
