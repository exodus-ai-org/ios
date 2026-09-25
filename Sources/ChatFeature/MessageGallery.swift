#if DEBUG
import Foundation
import Models
import NetworkingKit
import SwiftUI

/// DEBUG-only: `-MessageGallery` shows fake runs through the real transcript rows; `-MessageGalleryExpanded` opens
/// every timeline and card; `-MessageGallerySection N` scrolls to run N and `-MessageGalleryEnd` to the last answer's
/// action bar; `-MessageGallerySheet [N]` opens the Sources sheet of the last run (at source N when given) and
/// `-MessageGallerySheetEmpty` the one of a run without sources; `-MessageGalleryNotice info|warning|long` shows the
/// notice banner.
public enum MessageGalleryLaunch {
    public static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGallery") }
    static var expanded: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGalleryExpanded") }
    static var section: Int? { value(after: "-MessageGallerySection").flatMap { Int($0) } }
    static var scrollsToEnd: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGalleryEnd") }
    static var opensSheet: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGallerySheet") }
    static var opensEmptySheet: Bool { ProcessInfo.processInfo.arguments.contains("-MessageGallerySheetEmpty") }
    static var sheetMarker: Int? { value(after: "-MessageGallerySheet").flatMap { Int($0) } }
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
    @Environment(\.accentGlyph) private var accentGlyph
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
                    .padding(.vertical, 12)
                }
                .task {
                    if MessageGalleryLaunch.opensSheet, let last = runs.last {
                        sheet = sourcesSheet(in: last, turnId: nil, marker: MessageGalleryLaunch.sheetMarker)
                    } else if MessageGalleryLaunch.opensEmptySheet, let first = runs.first {
                        sheet = sourcesSheet(in: first, turnId: nil, marker: nil)
                    }
                    if MessageGalleryLaunch.scrollsToEnd {
                        try? await Task.sleep(for: .milliseconds(300))
                        proxy.scrollTo(runs.count - 1, anchor: .bottom)
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
                }
            }
        }
        .sheet(item: $sheet) { SourcesSheet(model: $0) }
        .environment(\.timelineStartsExpanded, MessageGalleryLaunch.expanded)
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
            })
    }

    private func sourcesSheet(in prepared: PreparedRun, turnId: String?, marker: Int?) -> SourcesSheetModel? {
        for segment in prepared.segments {
            if case .assistantTurn(let turn) = segment, turnId == nil || turn.id == turnId {
                return SourcesSheetModel(turn: turn, marker: marker)
            }
        }
        return nil
    }

    /// The composer's silhouette, so the banner is seen where it sits in the chat.
    private var standInComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text("ios:chat.composer.placeholder")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            // Styled as the real send button, enabled.
            Button {} label: {
                Label("chat:composer.send", systemImage: "arrow.up")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(accentGlyph)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

enum MessageGalleryFixtures {
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
        Run(title: "Thinking + web search + terminal", json: #"""
            [{"id":"u2","runId":"u2","role":"user","content":"Is Swift 6.2 out, and what does `swift --version` say here?","timestamp":1000},
             {"id":"a2","runId":"u2","role":"assistant","content":[{"type":"thinking","thinking":"**Checking the release**\nI should search for the Swift 6.2 announcement, then run the compiler locally."},{"type":"toolCall","id":"k1","name":"web_search","arguments":{"query":"Swift 6.2 release"}}],"stopReason":"toolUse","timestamp":2000},
             {"id":"t1","runId":"u2","role":"toolResult","toolCallId":"k1","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":[{"rank":1,"link":"https://www.swift.org/blog/swift-6.2-released/","title":"Swift 6.2 Released","snippet":"","hostname":"www.swift.org"},{"rank":2,"link":"https://developer.apple.com/xcode/","title":"Xcode","snippet":"","hostname":"developer.apple.com"},{"rank":3,"link":"https://forums.swift.org/t/6-2","title":"Forums","snippet":"","hostname":"forums.swift.org"}],"isError":false,"timestamp":3000},
             {"id":"a3","runId":"u2","role":"assistant","content":[{"type":"toolCall","id":"k2","name":"terminal","arguments":{"command":"swift --version"}}],"stopReason":"toolUse","timestamp":4000},
             {"id":"t2","runId":"u2","role":"toolResult","toolCallId":"k2","toolName":"terminal","content":[{"type":"text","text":"{}"}],"details":{"command":"swift --version","cwd":"/Users/me/.exodus/workspace/c1","exitCode":0,"stdout":"swift-driver version: 1.127\nApple Swift version 6.2 (swiftlang-6.2.0.19.9)\nTarget: arm64-apple-macosx26.0","stderr":""},"isError":false,"timestamp":5000},
             {"id":"a4","runId":"u2","role":"assistant","content":[{"type":"text","text":"Yes — Swift 6.2 is out \#u{3010}1-source\#u{3011} and ships with the current Xcode \#u{3010}2-source\#u{3011}. Your machine already runs it:\n\n```\nApple Swift version 6.2\n```"}],"stopReason":"stop","durationMs":12400,"timestamp":6000}]
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
        Run(title: "Sources: two searches, one turn", json: #"""
            [{"id":"u6","runId":"u6","role":"user","content":"What changed in Swift 6.2, and how does it affect concurrency?","timestamp":1000},
             {"id":"a9","runId":"u6","role":"assistant","content":[{"type":"thinking","thinking":"**Two searches**\nThe release notes first, then the concurrency proposal."},{"type":"toolCall","id":"k6","name":"web_search","arguments":{"query":"Swift 6.2 release notes"}}],"stopReason":"toolUse","timestamp":2000},
             {"id":"t5","runId":"u6","role":"toolResult","toolCallId":"k6","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":[
               {"rank":1,"link":"https://www.swift.org/blog/swift-6.2-released/","title":"Swift 6.2 Released","siteName":"Swift.org","hostname":"www.swift.org","age":"2 weeks ago","snippet":"Swift 6.2 makes concurrency easier to adopt, with approachable defaults, a new @concurrent attribute and better tooling for migration."},
               {"rank":2,"link":"https://developer.apple.com/videos/play/wwdc2025/245/","title":"What's new in Swift - WWDC25","hostname":"developer.apple.com","snippet":"Highlights of the language, from InlineArray and Span to the new module selectors and strict memory safety."},
               {"rank":3,"link":"https://www.hackingwithswift.com/articles/281/what-is-new-in-swift-6-2","title":"The complete, exhaustive and slightly overwhelming guide to every single change in the Swift 6.2 release, with examples","hostname":"www.hackingwithswift.com","snippet":"Paul Hudson walks through every feature that landed in Swift 6.2 with runnable code, from default actor isolation to the new Task naming APIs and everything in between."},
               {"rank":4,"link":"https://forums.swift.org/t/swift-6-2-release-thread/80001","title":"Swift 6.2 release thread","hostname":"forums.swift.org"},
               {"rank":5,"link":"javascript:alert(1)","title":"A link the app will not open","hostname":"example.com","snippet":"The scheme is not one a source may use, so this row is shown but is not tappable."}],"isError":false,"timestamp":3000},
             {"id":"a10","runId":"u6","role":"assistant","content":[{"type":"toolCall","id":"k7","name":"web_search","arguments":{"query":"Swift 6.2 approachable concurrency"}}],"stopReason":"toolUse","timestamp":4000},
             {"id":"t6","runId":"u6","role":"toolResult","toolCallId":"k7","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":[
               {"rank":1,"link":"https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md","title":"SE-0466: Control default actor isolation inference","siteName":"GitHub","hostname":"github.com","snippet":"Introduces a per-module setting that infers @MainActor for declarations without explicit isolation."},
               {"rank":2,"link":"https://www.swift.org/migration/documentation/migrationguide/","title":"Swift 6 migration guide","hostname":"www.swift.org","snippet":"How to turn on strict concurrency checking and fix what it finds, one module at a time."}],"isError":false,"timestamp":5000},
             {"id":"a11","runId":"u6","role":"assistant","content":[{"type":"text","text":"Swift 6.2 is mostly about making concurrency **approachable**:\n\n- New modules can default to `@MainActor`, so single-threaded code needs no annotations \u30101-source\u3011\n- `@concurrent` marks the functions that really should leave the caller's actor \u30101-source\u3011\n- The release also adds `InlineArray` and `Span` \u30102-source\u3011\n\nThe migration guide is still the best place to start \u30102-source\u3011, and the full change list is long \u30103-source\u3011."}],"stopReason":"stop","durationMs":9200,"timestamp":6000}]
            """#),
    ]
}
#endif
