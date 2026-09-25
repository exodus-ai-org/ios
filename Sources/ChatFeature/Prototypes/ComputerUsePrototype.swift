#if DEBUG
import Models
import SwiftUI
import UIKit

/// The computer use card is real now: this group draws `ComputerUseCard` from `ToolCard`s built the way the transcript
/// builds them, with frames fed to a frame store the way the chat's view model feeds it while a session streams
/// (drawn PNG screenshots, base64 like the desktop's `thumbnail`) and a stand-in remote.
/// `-CardPrototypesComputerViewer` opens the full-screen viewer on the finished run's frames at launch.
struct ProtoComputerUseSection: View {
    @State private var store: ComputerUseFrameStore?
    @State private var shots: [String] = []
    @State private var viewer: ImageViewerPage?

    private static let opensViewer = ProcessInfo.processInfo.arguments.contains("-CardPrototypesComputerViewer")
    private static let actions = ["activate", "click", "click", "click", "click", "type", "click"]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            UserBubble(text: ProtoFixtures.computerTask)
            if store != nil, !shots.isEmpty {
                states
            }
        }
        .environment(\.computerUseFrames, store)
        .environment(\.computerUseRemote, Self.remote)
        .task { await prepare() }
        .fullScreenCover(item: $viewer) { page in
            if let strip = store?.filmstrip(for: "k4") {
                ImageViewer(
                    pages: strip.shots.enumerated().map { index, shot in
                        ImageViewerPage.Content(
                            id: index, image: shot.image, caption: ComputerUseRules.stepLine(shot.step, action: shot.action))
                    },
                    start: page.id)
            }
        }
    }

    @ViewBuilder
    private var states: some View {
        ProtoInReply(state: "Starting: the call is made, no frame yet") {
            Self.cards([Self.call("k0")]).environment(\.toolCardsAreLive, true)
        }
        ProtoInReply(state: "Running: the latest frame, live (tap to open every frame kept)") {
            Self.cards([Self.call("k1"), Self.frame("k1", step: 4)]).environment(\.toolCardsAreLive, true)
        }
        ProtoInReply(state: "Waiting for you (askHuman): answer here or on the computer") {
            Self.cards([Self.call("k2"), Self.frame("k2", step: 6, question: ProtoFixtures.computerQuestion)])
                .environment(\.toolCardsAreLive, true)
        }
        ProtoInReply(
            state: "Done, watched live: the filmstrip", header: "Worked for 1 min 12 sec",
            answer: "Done — Q3 Revenue.pdf is on your Desktop."
        ) {
            Self.cards([Self.call("k4"), Self.result("k4", ProtoFixtures.computerDoneDetails, image: shots.last)])
        }
        ProtoInReply(state: "Done, reopened from history: the final screen only") {
            Self.cards([Self.call("k5"), Self.result("k5", ProtoFixtures.computerDoneDetails, image: shots.last)])
        }
        ProtoInReply(state: "Stuck") {
            Self.cards([Self.call("k6"), Self.result("k6", ProtoFixtures.computerStuckDetails, image: shots[2])])
        }
        ProtoInReply(state: "Stopped mid-session (the run was stopped)") {
            Self.cards([Self.call("k7"), Self.frame("k7", step: 3)])
        }
        ProtoInReply(state: "Refused: not on the allowlist") {
            Self.cards([Self.call("k8"), Self.result("k8", ProtoFixtures.computerErrorDetails, image: nil)])
        }
        ProtoInReply(state: "Tool error") {
            Self.cards([
                Self.call("k9"),
                Self.message(
                    #"{"id":"t-k9","runId":"u","role":"toolResult","toolCallId":"k9","toolName":"computer_use","content":[{"type":"text","text":"Computer session failed: the helper exited"}],"details":null,"isError":true,"timestamp":3}"#
                ),
            ])
        }
    }

    private static let remote = ComputerUseRemote(
        answer: { _, _ in try await Task.sleep(for: .milliseconds(400)) },
        stop: { try await Task.sleep(for: .milliseconds(400)) })

    private static func cards(_ messages: [ChatMessage]) -> some View {
        let cards = toolCards(messages)
        return VStack(alignment: .leading) {
            ForEach(cards, id: \.renderKey) { ToolCardView(card: $0) }
        }
    }

    private static func toolCards(_ messages: [ChatMessage]) -> [ToolCard] {
        segments(messages).flatMap { segment -> [ToolCard] in
            if case .assistantTurn(let turn) = segment { turn.toolCards } else { [] }
        }
    }

    private static func segments(_ messages: [ChatMessage]) -> [Segment] {
        var cache = RunGrouper.Cache()
        return RunGrouper.group(
            [message(#"{"id":"u","runId":"u","role":"user","content":"do it","timestamp":1}"#)] + messages, cache: &cache)
    }

    private static func call(_ id: String) -> ChatMessage {
        message(
            #"{"id":"a-\#(id)","runId":"u","role":"assistant","content":[{"type":"toolCall","id":"\#(id)","name":"computer_use","arguments":{"task":"\#(ProtoFixtures.computerTask)","target":"\#(ProtoFixtures.computerTarget)"}}],"stopReason":"toolUse","timestamp":2}"#
        )
    }

    /// A live frame as `tool_update` sends it: the partial result row, its details the frame.
    private static func frame(_ id: String, step: Int, thumbnail: String? = nil, question: String? = nil) -> ChatMessage {
        var details = #""sessionId":"cu_7f3a","step":\#(step),"action":"\#(actions[(step - 1) % actions.count])""#
        if let thumbnail { details += #","thumbnail":"\#(thumbnail)""# }
        if let question { details += #","awaitingHuman":{"question":"\#(question)"}"# }
        return message(
            #"{"id":"t-\#(id)","runId":"u","role":"toolResult","toolCallId":"\#(id)","toolName":"computer_use","content":[],"details":{\#(details)},"isError":false,"timestamp":3}"#
        )
    }

    private static func result(_ id: String, _ details: String, image: String?) -> ChatMessage {
        let picture = image.map { #",{"type":"image","data":"\#($0)","mimeType":"image/png"}"# } ?? ""
        return message(
            #"{"id":"t-\#(id)","runId":"u","role":"toolResult","toolCallId":"\#(id)","toolName":"computer_use","content":[{"type":"text","text":"summary"}\#(picture)],"details":\#(details),"isError":false,"timestamp":3}"#
        )
    }

    private static func message(_ json: String) -> ChatMessage {
        try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    }

    /// Streams the sessions' frames into the store as the chat's view model would.
    private func prepare() async {
        guard store == nil else { return }
        let drawn = (1...8).map { Self.render(step: $0) }
        let store = ComputerUseFrameStore(sessionCapacity: 8)
        for (id, steps) in [("k1", 1...4), ("k2", 1...5), ("k4", 1...7), ("k7", 1...3)] {
            for step in steps {
                store.ingest(Self.segments([Self.call(id), Self.frame(id, step: step, thumbnail: drawn[step - 1])]))
            }
        }
        await store.settle()
        self.store = store
        shots = drawn
        if Self.opensViewer {
            try? await Task.sleep(for: .milliseconds(400))
            viewer = ImageViewerPage(id: 6)
        }
    }

    private static func render(step: Int) -> String {
        let renderer = ImageRenderer(
            content: ProtoScreenshot(step: step, highlight: CGPoint(x: 0.3 + 0.07 * Double(step % 5), y: 0.45))
                .frame(width: 640, height: 400))
        renderer.scale = 1
        return renderer.uiImage?.pngData()?.base64EncodedString() ?? ""
    }
}

extension ProtoFixtures {
    static let computerQuestion =
        "Numbers asks for a password to export this sheet. Type it on the computer, then tell me to continue."
    static let computerDoneDetails =
        #"{"sessionId":"cu_7f3a","outcome":"success","steps":9,"summary":"Exported “Q3 Revenue” as Q3 Revenue.pdf on the Desktop (2 pages)."}"#
    static let computerStuckDetails =
        #"{"sessionId":"cu_91bc","outcome":"stuck","steps":25,"summary":"The Export dialog kept reopening after Save; I stopped after 25 steps without exporting."}"#
    static let computerErrorDetails = #"{"error":"not-allowed"}"#
}
#endif
