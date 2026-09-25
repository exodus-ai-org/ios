import Foundation
import MarkdownKit
import Models
import NetworkingKit
import Synchronization
import SwiftUI
import Testing
import UIKit

@testable import ChatFeature

// Desktop shapes (src/main/lib/ai/calling-tools/computer-use.ts, computer/session.ts): a live frame is the partial
// result row of `tool_update`, `details` = `{step, action?, thumbnail?, awaitingHuman?, sessionId}`; the end is
// `{sessionId, outcome, steps, summary}` with the final screenshot as an image block of `content`; or `{error}`.

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func user(_ id: String) -> ChatMessage {
    decode(#"{"id":"\#(id)","runId":"\#(id)","role":"user","content":"q","timestamp":1}"#)
}

private func call(_ id: String, _ run: String, _ callId: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"assistant","content":[{"type":"toolCall","id":"\#(callId)","name":"computer_use","arguments":{"task":"Export the sheet","target":"Numbers"}}],"stopReason":"toolUse","timestamp":2}"#
    )
}

private func frame(
    _ id: String, _ run: String, _ callId: String, step: Int, action: String? = "click", thumbnail: String? = nil,
    question: String? = nil
) -> ChatMessage {
    var details = #""sessionId":"cu_1","step":\#(step)"#
    if let action { details += #","action":"\#(action)""# }
    if let thumbnail { details += #","thumbnail":"\#(thumbnail)""# }
    if let question { details += #","awaitingHuman":{"question":"\#(question)"}"# }
    return decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"toolResult","toolCallId":"\#(callId)","toolName":"computer_use","content":[],"details":{\#(details)},"isError":false,"timestamp":3}"#
    )
}

private func finished(
    _ id: String, _ run: String, _ callId: String, details: String = doneDetails, image: String? = nil,
    mimeType: String = "image/png"
) -> ChatMessage {
    let picture = image.map { #",{"type":"image","data":"\#($0)","mimeType":"\#(mimeType)"}"# } ?? ""
    return decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"toolResult","toolCallId":"\#(callId)","toolName":"computer_use","content":[{"type":"text","text":"Exported."}\#(picture)],"details":\#(details),"isError":false,"timestamp":3}"#
    )
}

private func failedCall(_ id: String, _ run: String, _ callId: String, text: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"toolResult","toolCallId":"\#(callId)","toolName":"computer_use","content":[{"type":"text","text":"\#(text)"}],"details":null,"isError":true,"timestamp":3}"#
    )
}

private func answer(_ id: String, _ run: String, _ text: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"assistant","content":[{"type":"text","text":"\#(text)"}],"stopReason":"stop","timestamp":4}"#
    )
}

private let doneDetails = #"{"sessionId":"cu_1","outcome":"success","steps":9,"summary":"Exported the sheet."}"#

private func segments(_ messages: [ChatMessage]) -> [Segment] {
    var cache = RunGrouper.Cache()
    return RunGrouper.group(messages, cache: &cache)
}

private func cards(_ messages: [ChatMessage]) -> [ToolCard] {
    segments(messages).flatMap { segment -> [ToolCard] in
        if case .assistantTurn(let turn) = segment { turn.toolCards } else { [] }
    }
}

private func model(_ messages: [ChatMessage]) throws -> ComputerUseCardModel {
    try #require(cards(messages).first?.content.computerUse)
}

/// A real PNG, base64 like the desktop's `thumbnail`.
private func png(width: Int = 40, height: Int = 25, white: CGFloat = 0.5) -> String {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
        UIColor(white: white, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    return image.pngData()!.base64EncodedString()
}

private func runningFrame(step: Int, thumbnail: String? = "x", action: String? = "click") -> ComputerUseFrame {
    let row = frame("t", "u", "k", step: step, action: action, thumbnail: thumbnail)
    guard case .running(let running)? = try? model([user("u"), call("a", "u", "k"), row]).phase else { fatalError("not a frame") }
    return running
}

/// Counts decodes and hands back a tiny image for anything but "bad".
private final class DecodeSpy: Sendable {
    private let log = Mutex<[String]>([])
    var calls: [String] { log.withLock { $0 } }

    var decode: @Sendable (String) async -> UIImage? {
        { [self] encoded in
            log.withLock { $0.append(encoded) }
            guard encoded != "bad" else { return nil }
            return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
        }
    }
}

@Suite("Computer use: the card's model, built with the turn")
struct ComputerUseModelTests {
    @Test("a live frame is a running card keyed by its call, with the task and target of the call")
    func runningFrameModel() throws {
        let running = try model([
            user("u"), call("a", "u", "k1"), frame("t", "u", "k1", step: 4, action: "type", thumbnail: "AAAA"),
        ])
        #expect(running.callId == "k1")
        #expect(running.task == "Export the sheet")
        #expect(running.target == "Numbers")
        #expect(running.sessionId == "cu_1")
        guard case .running(let live) = running.phase else {
            Issue.record("not running")
            return
        }
        #expect(live.step == 4)
        #expect(live.action == "type")
        #expect(live.thumbnail == "AAAA")
        #expect(live.awaitingHumanQuestion == nil)
        let asking = try model([user("u"), call("a", "u", "k1"), frame("t", "u", "k1", step: 6, question: "Type the password")])
        guard case .running(let waiting) = asking.phase else {
            Issue.record("not running")
            return
        }
        #expect(waiting.awaitingHumanQuestion == "Type the password")
    }

    @Test("a pending call draws a starting card; a finished one carries its outcome and the result's screenshot")
    func pendingAndFinished() throws {
        let pending = try #require(cards([user("u"), call("a", "u", "k1")]).first)
        #expect(pending.isPending)
        #expect(pending.renderKey == "call:k1")
        #expect(pending.content.computerUse?.phase == .starting)
        #expect(pending.content.computerUse?.callId == "k1")

        let done = try #require(cards([user("u"), call("a", "u", "k1"), finished("t", "u", "k1", image: "QUJD")]).first)
        #expect(done.renderKey == "call:k1")
        let doneModel = try #require(done.content.computerUse)
        #expect(doneModel.summary == "Exported the sheet.")
        #expect(doneModel.sessionId == "cu_1")
        #expect(doneModel.finalScreenshot == "data:image/png;base64,QUJD")
        guard case .finished(let outcome) = doneModel.phase else {
            Issue.record("not finished")
            return
        }
        #expect(outcome.outcome == "success")
        #expect(outcome.steps == 9)
    }

    @Test("only a raster image block is the final screenshot; none leaves the card without one")
    func finalScreenshotRules() throws {
        let svg = try model([user("u"), call("a", "u", "k"), finished("t", "u", "k", image: "PHN2Zz4=", mimeType: "image/svg+xml")])
        #expect(svg.finalScreenshot == nil)
        let html = try model([user("u"), call("a", "u", "k"), finished("t", "u", "k", image: "PGI+", mimeType: "text/html")])
        #expect(html.finalScreenshot == nil)
        let jpeg = try model([user("u"), call("a", "u", "k"), finished("t", "u", "k", image: "QUJD", mimeType: "image/jpeg")])
        #expect(jpeg.finalScreenshot == "data:image/jpeg;base64,QUJD")
        #expect(try model([user("u"), call("a", "u", "k"), finished("t", "u", "k")]).finalScreenshot == nil)
    }

    @Test("{error} is a refusal; a failed call keeps the tool's message")
    func errors() throws {
        let refused = try model([user("u"), call("a", "u", "k"), finished("t", "u", "k", details: #"{"error":"not-allowed"}"#)])
        #expect(refused.phase == .refused("not-allowed"))
        let failed = try model([user("u"), call("a", "u", "k"), failedCall("t", "u", "k", text: "Computer session failed: boom")])
        #expect(failed.phase == .failed("Computer session failed: boom"))
        #expect(failed.target == "Numbers")
    }

    @MainActor
    @Test("details that are no computer_use shape fall back to the generic card and are reported without the payload")
    func undecodable() throws {
        let card = try #require(cards([user("u"), call("a", "u", "k"), finished("t", "u", "k", details: #"{"secret":"x"}"#)]).first)
        #expect(card.content == .undecodable)
        guard case .generic(let issue) = ToolCardRegistry.resolve(card) else {
            Issue.record("drew a card from bad details")
            return
        }
        let reported = try #require(issue)
        #expect(reported.message == "Unreadable computer_use card shown as the generic card")
        #expect(!reported.message.contains("secret"))
    }

    @Test("computer_use is registered, draws failures and running calls")
    func registered() {
        #expect(ToolCardRegistry.hasCard(for: "computer_use"))
        #expect(ToolCardRegistry.drawsFailures(for: "computer_use"))
        #expect(ToolCardRegistry.drawsPending(for: "computer_use"))
    }
}

@Suite("Computer use: what the card shows")
struct ComputerUseRulesTests {
    private func card(_ phase: ComputerUseCardModel.Phase) -> ComputerUseCardModel {
        ComputerUseCardModel(callId: "k", arguments: nil, phase: phase)
    }

    private var stepFrame: ComputerUseFrame { runningFrame(step: 3) }

    private var askingFrame: ComputerUseFrame {
        let row = frame("t", "u", "k", step: 5, question: "Q?")
        guard case .running(let asking)? = try? model([user("u"), call("a", "u", "k"), row]).phase else { fatalError() }
        return asking
    }

    private var outcome: ComputerUseCardModel.Phase {
        let details = #"{"sessionId":"s","outcome":"stuck","steps":25,"summary":"x"}"#
        return (try? model([user("u"), call("a", "u", "k"), finished("t", "u", "k", details: details)]).phase) ?? .starting
    }

    @Test("status: running, its step, waiting for the user, the outcome; a run stopped mid-session reads as stopped")
    func status() {
        #expect(ComputerUseRules.status(card(.starting), isLive: true) == .starting)
        #expect(ComputerUseRules.status(card(.starting), isLive: false) == .stopped)
        #expect(ComputerUseRules.status(card(.running(stepFrame)), isLive: true) == .step(3))
        #expect(ComputerUseRules.status(card(.running(stepFrame)), isLive: false) == .stopped)
        #expect(ComputerUseRules.status(card(.running(askingFrame)), isLive: true) == .needsYou)
        #expect(ComputerUseRules.status(card(outcome), isLive: true) == .outcome("stuck"))
        #expect(ComputerUseRules.status(card(outcome), isLive: false) == .outcome("stuck"))
        #expect(ComputerUseRules.status(card(.refused("disabled")), isLive: true) == .error)
        #expect(ComputerUseRules.status(card(.failed(nil)), isLive: false) == .error)
    }

    @Test("the question and Stop only while the turn streams")
    func liveControls() {
        #expect(ComputerUseRules.question(card(.running(askingFrame)), isLive: true) == "Q?")
        #expect(ComputerUseRules.question(card(.running(askingFrame)), isLive: false) == nil)
        #expect(ComputerUseRules.question(card(.running(stepFrame)), isLive: true) == nil)
        #expect(ComputerUseRules.isRunning(card(.starting), isLive: true))
        #expect(ComputerUseRules.isRunning(card(.running(stepFrame)), isLive: true))
        #expect(!ComputerUseRules.isRunning(card(.running(stepFrame)), isLive: false))
        #expect(!ComputerUseRules.isRunning(card(outcome), isLive: true))
    }

    @Test("shots: live frame while running, filmstrip once frames were kept, the final screen from history, else none")
    func shots() {
        let running = card(.running(stepFrame))
        #expect(ComputerUseRules.shots(running, isLive: true, recorded: 3, hasFinal: false) == .live)
        #expect(ComputerUseRules.shots(running, isLive: true, recorded: 0, hasFinal: false) == .none)
        #expect(ComputerUseRules.shots(running, isLive: false, recorded: 3, hasFinal: false) == .filmstrip)
        #expect(ComputerUseRules.shots(card(outcome), isLive: false, recorded: 5, hasFinal: true) == .filmstrip)
        #expect(ComputerUseRules.shots(card(outcome), isLive: false, recorded: 0, hasFinal: true) == .single)
        #expect(ComputerUseRules.shots(card(outcome), isLive: false, recorded: 0, hasFinal: false) == .none)
        #expect(ComputerUseRules.shots(card(.refused("x")), isLive: false, recorded: 0, hasFinal: true) == .none)
    }

    @Test("copy: the desktop's wording, error codes explained, action kinds named, unknown ones shown as they came")
    func copy() {
        #expect(ComputerUseRules.statusText(.starting) == "running…")
        #expect(ComputerUseRules.statusText(.step(4)) == "step 4")
        #expect(ComputerUseRules.statusText(.needsYou) == "Needs you")
        #expect(ComputerUseRules.statusText(.outcome("success")) == "success")
        #expect(ComputerUseRules.statusText(.outcome("teleported")) == "teleported")
        #expect(ComputerUseRules.statusText(.stopped) == "aborted")
        #expect(ComputerUseRules.statusText(.error) == "error")
        #expect(ComputerUseRules.stepLine(3, action: "click") == "Step 3: Click")
        #expect(ComputerUseRules.stepLine(3, action: "hotkey") == "Step 3: Keyboard shortcut")
        #expect(ComputerUseRules.stepLine(3, action: "zoom") == "Step 3: zoom")
        #expect(ComputerUseRules.stepLine(7, action: nil) == "Step 7: …")
        #expect(ComputerUseRules.actionName("wheel") == "Scroll")
        #expect(ComputerUseRules.actionName("keyUp") == "Key press")
        #expect(ComputerUseRules.shotLabel(step: 2) == "Target window at step 2")
        #expect(ComputerUseRules.finalShotLabel == "Final screen")
        #expect(ComputerUseRules.sessionText("cu_1") == "session: cu_1")
        #expect(
            ComputerUseRules.errorText("not-allowed", target: "Numbers")
                == "“Numbers” isn’t on the Computer Use allowlist. Add it in Settings on the computer.")
        #expect(ComputerUseRules.errorText("disabled", target: "") == "Computer Use is turned off in Settings on the computer.")
        #expect(ComputerUseRules.errorText("self", target: "") == "Exodus can’t operate its own windows.")
        #expect(ComputerUseRules.errorText("helper crashed", target: "") == "helper crashed")
    }
}

@MainActor
@Suite("Computer use: frames kept on the phone while a session streams")
struct ComputerUseFramesTests {
    @Test("one decode per step, kept in step order whatever order they came in; frames without a screenshot are skipped")
    func orderAndDedupe() async {
        let spy = DecodeSpy()
        let strip = ComputerUseFilmstrip(capacity: 10, decode: spy.decode)
        await strip.record(runningFrame(step: 2))
        await strip.record(runningFrame(step: 1))
        await strip.record(runningFrame(step: 2))
        await strip.record(runningFrame(step: 3, thumbnail: nil))
        await strip.record(runningFrame(step: 4, action: nil))
        #expect(strip.shots.map(\.step) == [1, 2, 4])
        #expect(strip.shots.map(\.action) == ["click", "click", nil])
        #expect(strip.latest?.step == 4)
        #expect(spy.calls.count == 3)
    }

    @Test("bounded: the last N frames stay; one older than a full strip is never decoded; a bad image is dropped")
    func bounded() async {
        let spy = DecodeSpy()
        let strip = ComputerUseFilmstrip(capacity: 3, decode: spy.decode)
        for step in 1...5 { await strip.record(runningFrame(step: step)) }
        #expect(strip.shots.map(\.step) == [3, 4, 5])
        #expect(spy.calls.count == 5)
        await strip.record(runningFrame(step: 1, thumbnail: "late"))
        #expect(spy.calls.count == 5)
        await strip.record(runningFrame(step: 6, thumbnail: "bad"))
        #expect(strip.shots.map(\.step) == [3, 4, 5])
    }

    @Test("the store records the streaming run's frames only, decoding each once across repeated updates")
    func ingestLastRun() async {
        let spy = DecodeSpy()
        let store = ComputerUseFrameStore(decode: spy.decode)
        let earlier = [user("u1"), call("a1", "u1", "old"), frame("t1", "u1", "old", step: 1, thumbnail: "old-1")]
        for step in 1...3 {
            let messages = earlier + [user("u2"), call("a2", "u2", "k"), frame("t2", "u2", "k", step: step, thumbnail: "f\(step)")]
            store.ingest(segments(messages))
            store.ingest(segments(messages))
        }
        await store.settle()
        #expect(store.filmstrip(for: "old") == nil)
        #expect(store.filmstrip(for: "k")?.shots.map(\.step) == [1, 2, 3])
        #expect(spy.calls == ["f1", "f2", "f3"])
    }

    @Test("only the most recent sessions are kept")
    func sessionCapacity() async {
        let store = ComputerUseFrameStore(sessionCapacity: 2, decode: DecodeSpy().decode)
        for id in ["a", "b", "c"] { store.record(callId: id, frame: runningFrame(step: 1)) }
        await store.settle()
        #expect(store.keptSessions == ["b", "c"])
        #expect(store.filmstrip(for: "a") == nil)
        #expect(store.filmstrip(for: "c")?.shots.count == 1)
    }

    @Test("the final screenshot is decoded once and then served from memory")
    func finalScreenshot() async {
        let spy = DecodeSpy()
        let store = ComputerUseFrameStore(decode: spy.decode)
        #expect(store.cachedFinal(for: "k") == nil)
        let first = await store.finalScreenshot(for: "k", dataURL: "data:image/png;base64,QQ==")
        let second = await store.finalScreenshot(for: "k", dataURL: "data:image/png;base64,QQ==")
        #expect(first != nil)
        #expect(first === second)
        #expect(store.cachedFinal(for: "k") === first)
        #expect(spy.calls.count == 1)
    }

    @Test("decoding: base64 or a data URL, downsampled to the cap; garbage and oversize input give nothing")
    func decodeScreenshot() async throws {
        let wide = png(width: 1400, height: 875)
        let image = try #require(await ComputerUseFrameStore.decodeScreenshot(wide, maxPixelWidth: 800))
        #expect(image.cgImage?.width == 800)
        #expect(image.cgImage?.height == 500)
        let fromURL = await ComputerUseFrameStore.decodeScreenshot("data:image/png;base64,\(png())", maxPixelWidth: 800)
        #expect(fromURL?.cgImage?.width == 40)
        #expect(await ComputerUseFrameStore.decodeScreenshot("not base64 at all", maxPixelWidth: 800) == nil)
        #expect(await ComputerUseFrameStore.decodeScreenshot(Data("<svg/>".utf8).base64EncodedString(), maxPixelWidth: 800) == nil)
        let huge = String(repeating: "A", count: ComputerUseFrameStore.maxEncodedBytes + 4)
        #expect(await ComputerUseFrameStore.decodeScreenshot(huge, maxPixelWidth: 800) == nil)
    }
}

// MARK: - Over the network

private final class CUMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data) = try handler(request)
            let isStream = request.url?.path == "/api/v1/chat"
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": isStream ? "text/event-stream" : "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class Sent: Sendable {
    private let log = Mutex<[(line: String, body: Data)]>([])
    func record(_ request: URLRequest) {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        log.withLock { $0.append(("\(request.httpMethod ?? "") \(request.url?.path ?? "")", body)) }
    }
    var all: [(line: String, body: Data)] { log.withLock { $0 } }
}

private let okEnvelope = Data(#"{"type":"success","data":{"ok":true}}"#.utf8)

@MainActor
private func client(_ suite: String) -> (APIClient, URLSession, ServerConfigStore) {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let config = ServerConfigStore(userDefaults: defaults)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CUMockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return (APIClient(session: session, serverConfig: config), session, config)
}

@MainActor
@Suite("Computer use: over the network", .serialized)
struct ComputerUseNetworkTests {
    @Test("the remote answers the desktop's routes: the reply with its session, and Stop")
    func remote() async throws {
        let (api, _, _) = client(#function)
        let sent = Sent()
        CUMockURLProtocol.handler = { request in
            sent.record(request)
            return (200, okEnvelope)
        }
        let remote = ComputerUseRemote(apiClient: api)
        try await remote.answer("cu_1", "(done)")
        try await remote.stop()
        #expect(sent.all.map(\.line) == ["POST /api/v1/computer-use/answer", "POST /api/v1/computer-use/abort"])
        let body = try #require(JSONSerialization.jsonObject(with: sent.all[0].body) as? [String: String])
        #expect(body == ["sessionId": "cu_1", "answer": "(done)"])
        CUMockURLProtocol.handler = { _ in (500, Data(#"{"type":"error","error":{"code":"X","message":"no"}}"#.utf8)) }
        await #expect(throws: (any Error).self) { try await remote.stop() }
    }

    @Test("a streamed session's frames reach the view model's store as they arrive; the finished card keeps them")
    func viewModelKeepsFrames() async throws {
        let (api, session, config) = client(#function)
        let thumbnails = (1...3).map { png(white: CGFloat($0) / 4) }
        func update(_ step: Int) -> String {
            #"data: {"type":"message_update","message":{"id":"t1","role":"toolResult","toolCallId":"k1","toolName":"computer_use","content":[],"details":{"sessionId":"cu_1","step":\#(step),"action":"click","thumbnail":"\#(thumbnails[step - 1])"},"isError":false}}"#
                + "\n\n"
        }
        let call =
            #"data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"computer_use","arguments":{"task":"T","target":"Numbers"}}],"stopReason":"toolUse"}}"#
            + "\n\n"
        let end =
            #"data: {"type":"message_update","message":{"id":"t1","role":"toolResult","toolCallId":"k1","toolName":"computer_use","content":[{"type":"text","text":"ok"}],"details":{"sessionId":"cu_1","outcome":"success","steps":3,"summary":"Done"},"isError":false}}"#
            + "\n\n"
        let reply = call + update(1) + update(2) + update(2) + update(3) + end
        CUMockURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/chat" { return (200, Data(reply.utf8)) }
            return (200, Data("[]".utf8))
        }
        let store = ComputerUseFrameStore()
        let viewModel = ChatDetailViewModel(
            chatId: "c1", apiClient: api, streamManager: ChatStreamManager(sseClient: SSEClient(session: session)),
            serverConfig: config)
        viewModel.computerUseFrames = store
        await viewModel.loadHistory()
        viewModel.composerText = "Export"
        await viewModel.sendMessage()
        await store.settle()
        let strip = try #require(store.filmstrip(for: "k1"))
        #expect(strip.shots.map(\.step) == [1, 2, 3])
        #expect(strip.shots.allSatisfy { $0.image.cgImage?.width == 40 })
        guard case .assistantTurn(let turn)? = viewModel.segments.last else {
            Issue.record("no turn")
            return
        }
        guard case .finished = turn.toolCards.first?.content.computerUse?.phase else {
            Issue.record("the card did not finish")
            return
        }
    }
}

// MARK: - Drawn

private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var entries: [String] { lock.withLock { stored } }
    func append(_ entry: String) { lock.withLock { stored.append(entry) } }
}

@MainActor
@Suite("Computer use: drawn in a window", .serialized)
struct ComputerUseHostedTests {
    @Test("live, stopped, finished (from history), refused and failed cards draw their own card; history decodes its screen once")
    func hosted() async throws {
        let reports = Reports()
        let diagnostics = RenderDiagnostics { scope, message, _ in reports.append("\(scope): \(message)") }
        let spy = DecodeSpy()
        let store = ComputerUseFrameStore(decode: spy.decode)
        store.record(callId: "k1", frame: runningFrame(step: 1, thumbnail: "live-1"))
        await store.settle()
        let live = cards([user("u"), call("a", "u", "k1"), frame("t", "u", "k1", step: 2, question: "Continue?")])
        let history = cards([user("u"), call("a", "u", "k2"), finished("t", "u", "k2", image: png())])
        let refused = cards([user("u"), call("a", "u", "k3"), finished("t", "u", "k3", details: #"{"error":"disabled"}"#)])
        let failed = cards([user("u"), call("a", "u", "k4"), failedCall("t", "u", "k4", text: "boom")])
        let all = live + history + refused + failed
        #expect(all.count == 4)
        #expect(all.allSatisfy(ToolCardRegistry.canDraw))
        let root = VStack { ForEach(all, id: \.renderKey) { ToolCardView(card: $0) } }
            .environment(\.renderDiagnostics, diagnostics)
            .environment(\.computerUseFrames, store)
            .environment(\.computerUseRemote, ComputerUseRemote(answer: { _, _ in }, stop: {}))
            .environment(\.toolCardsAreLive, true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1800))
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        for _ in 0..<30 where store.cachedFinal(for: "k2") == nil {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(reports.entries.isEmpty)
        #expect(store.cachedFinal(for: "k2") != nil)
        #expect(spy.calls.filter { $0.hasPrefix("data:image/png") }.count == 1)
        window.isHidden = true
    }
}

// MARK: - Render guard

@MainActor
@Suite("Computer use: a settled session stays put while a later turn streams")
struct ComputerUseRenderTests {
    @Test("frames of a later session rebuild only its turn; the settled turn and its view compare equal")
    func settledStays() throws {
        let settled = [
            user("u1"), call("a1", "u1", "k1"), finished("t1", "u1", "k1", image: "QUJD"), answer("b1", "u1", "Done"),
            user("u2"), call("a2", "u2", "k2"),
        ]
        var cache = RunGrouper.Cache()
        let first = RunGrouper.group(settled + [frame("t2", "u2", "k2", step: 1, thumbnail: "f1")], cache: &cache)
        let built = cache.builtTurnCount
        var previous = first
        for step in 2...6 {
            let next = RunGrouper.group(
                settled + [frame("t2", "u2", "k2", step: step, thumbnail: "f\(step)")], cache: &cache)
            #expect(next.first { $0.id == "run:u1" } == previous.first { $0.id == "run:u1" })
            previous = next
        }
        #expect(cache.builtTurnCount == built + 5)
        guard case .assistantTurn(let before)? = first.first(where: { $0.id == "run:u1" }),
            case .assistantTurn(let after)? = previous.first(where: { $0.id == "run:u1" })
        else {
            Issue.record("no settled turn")
            return
        }
        #expect(before.toolCards.first?.content.computerUse?.finalScreenshot == "data:image/png;base64,QUJD")
        let lhs = AssistantTurnView(turn: before, isStreaming: false, error: nil, regenerate: {})
        let rhs = AssistantTurnView(turn: after, isStreaming: false, error: nil, regenerate: { print("new") })
        #expect(lhs == rhs)
        guard case .assistantTurn(let streaming)? = previous.last else {
            Issue.record("no streaming turn")
            return
        }
        guard case .running(let latest)? = streaming.toolCards.first?.content.computerUse?.phase else {
            Issue.record("not running")
            return
        }
        #expect(latest.step == 6)
    }
}

@MainActor
@Suite("Computer use: Answer and Stop send once")
struct ComputerUseControlStateTests {
    final class Sent: Sendable {
        let log = Mutex<[String]>([])
        func withLock<R>(_ body: (inout [String]) -> R) -> R { log.withLock { body(&$0) } }
    }

    private func remote(_ sent: Sent) -> ComputerUseRemote {
        ComputerUseRemote(
            answer: { id, text in sent.withLock { $0.append("answer \(id) \(text)") } },
            stop: { sent.withLock { $0.append("stop") } })
    }

    @Test("a double tap on Answer sends one answer; Stop while it is in flight sends nothing; afterwards both work")
    func doubleTapSendsOnce() async throws {
        let sent = Sent()
        let controls = ComputerUseControlState()
        controls.reply = " Yes "
        let first = try #require(controls.answer(remote(sent), sessionId: "cu_1", step: 3))
        #expect(controls.busy)
        #expect(controls.answer(remote(sent), sessionId: "cu_1", step: 3) == nil)
        #expect(controls.stop(remote(sent)) == nil)
        await first.value
        #expect(sent.withLock { $0 } == ["answer cu_1 Yes"])
        #expect(controls.answeredStep == 3)
        #expect(controls.reply.isEmpty)
        #expect(!controls.busy)

        let stop = try #require(controls.stop(remote(sent)))
        #expect(controls.stop(remote(sent)) == nil)
        await stop.value
        #expect(sent.withLock { $0 } == ["answer cu_1 Yes", "stop"])
    }

    @Test("an empty answer is sent as (done), as the desktop's Done — continue")
    func emptyAnswerIsDone() async throws {
        let sent = Sent()
        let controls = ComputerUseControlState()
        await controls.answer(remote(sent), sessionId: "cu_2", step: nil)?.value
        #expect(sent.withLock { $0 } == ["answer cu_2 (done)"])
    }
}

@MainActor
@Suite("Chat caches: nothing of an unpaired computer stays in memory", .serialized)
struct ChatCachesTests {
    @Test("clearAll empties the generated-image, search-image and screenshot caches the whole app shares")
    func clearAll() async {
        let image = UIImage(data: UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { _ in })!
        let source = GeneratedImageSource.media(path: "/api/v1/media/c1/clear-test.png")
        let url = URL(string: "https://example.com/clear-test.png")!
        GeneratedImageCache.shared.insert(image, for: source)
        SearchMediaCache.shared.insert(image, for: url, maxPixelSize: 120)
        _ = await ComputerUseFrameStore.shared.finalScreenshot(
            for: "clear-test", dataURL: "data:image/png;base64,\(image.pngData()!.base64EncodedString())")
        #expect(GeneratedImageCache.shared.image(for: source) != nil)
        #expect(ComputerUseFrameStore.shared.cachedFinal(for: "clear-test") != nil)

        ChatCaches.clearAll()
        #expect(GeneratedImageCache.shared.image(for: source) == nil)
        #expect(SearchMediaCache.shared.image(for: url, maxPixelSize: 120) == nil)
        #expect(ComputerUseFrameStore.shared.cachedFinal(for: "clear-test") == nil)
        #expect(ComputerUseFrameStore.shared.keptSessions.isEmpty)
    }
}
