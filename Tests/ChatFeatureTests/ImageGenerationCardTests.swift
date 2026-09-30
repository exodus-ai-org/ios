import Foundation
import MarkdownKit
import Models
import NetworkingKit
import Synchronization
import SwiftUI
import Testing
import UIKit

@testable import ChatFeature

private func value(_ json: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func call(_ id: String, _ callId: String, _ prompt: String = "A lighthouse") -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"\#(callId)","name":"image_generation","arguments":{"prompt":"\#(prompt)"}}],"stopReason":"toolUse","timestamp":2}"#
    )
}

private func result(_ id: String, _ callId: String, details: String, isError: Bool = false, text: String = "ok") -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"u1","role":"toolResult","toolCallId":"\#(callId)","toolName":"image_generation","content":[{"type":"text","text":"\#(text)"}],"details":\#(details),"isError":\#(isError),"timestamp":3}"#
    )
}

private let user = decode(#"{"id":"u1","runId":"u1","role":"user","content":"draw","timestamp":1}"#)
private let chatId = "3f0c2a4e-1b7d-4c1e-9a55-0d2b8f6c7e11"
private let mediaId = "9b1e4d2c-6a3f-4e8b-8c7d-5f2a1b0c9d8e.png"

private func model(_ details: String, prompt: String? = "A lighthouse", policy: MarkdownImagePolicy = .tapToLoadRemote)
    -> ImageGenerationCardModel
{
    let call = DecodedCall(
        arguments: prompt.map { ImageGenerationArguments(json: .object(["prompt": .string($0)]))! },
        result: ImageGenerationResult(json: value(details))!)
    return ImageGenerationCardModel(call, policy: policy)
}

private func imageCards(_ messages: [ChatMessage]) -> [ToolCard] {
    var cache = RunGrouper.Cache()
    let segments = RunGrouper.group(messages, cache: &cache)
    return segments.flatMap { segment -> [ToolCard] in
        if case .assistantTurn(let turn) = segment { turn.toolCards.filter { $0.toolName == "image_generation" } } else { [] }
    }
}

private func pngData(width: Int = 4, height: Int = 6) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

@Suite("Image generation: where an image comes from")
struct ImageGenerationSourceTests {
    @Test("mediaId + chatId → the media route; mediaId without chatId (a Group image) → nothing")
    func media() {
        let frames = model(
            #"{"images":[{"mediaId":"\#(mediaId)","chatId":"\#(chatId)","mimeType":"image/png","dataUrl":"data:image/png;base64,AAAA"},{"mediaId":"\#(mediaId)","mimeType":"image/png"}]}"#
        ).frames
        #expect(frames[0].source == .media(path: "/api/v1/media/\(chatId)/\(mediaId)"))
        #expect(frames[1].source == nil)
    }

    @Test("a data URL is decoded in place; an https link follows the markdown's image policy")
    func legacy() {
        let details = #"{"images":[{"url":"data:image/png;base64,AAAA"},{"url":"https://oaidalle.invalid/img.png?sig=x"}]}"#
        let url = URL(string: "https://oaidalle.invalid/img.png?sig=x")!
        let tap = model(details, policy: .tapToLoadRemote).frames
        #expect(tap[0].source == .inline("data:image/png;base64,AAAA"))
        #expect(tap[1].source == .remote(url, host: "oaidalle.invalid", needsTap: true))
        #expect(model(details, policy: .autoLoadRemote).frames[1].source == .remote(url, host: "oaidalle.invalid", needsTap: false))
        #expect(model(details, policy: .blockRemote).frames[1].source == nil)
        #expect(MarkdownImagePolicy.current == .tapToLoadRemote)
    }

    @Test("the media path takes only the plain ids the desktop writes; anything else builds no URL")
    func mediaPath() {
        #expect(GeneratedImageSource.mediaPath(chatId: chatId, mediaId: mediaId) == "/api/v1/media/\(chatId)/\(mediaId)")
        #expect(GeneratedImageSource.mediaPath(chatId: "c1", mediaId: "a.jpeg") == "/api/v1/media/c1/a.jpeg")
        #expect(GeneratedImageSource.mediaPath(chatId: "c1", mediaId: "a.webp") == "/api/v1/media/c1/a.webp")
        for bad in ["../a.png", "a/b.png", "a.gif", "a.png/..", "%2e%2e.png", "a png.png", ".png", "a.png?x=1", ""] {
            #expect(GeneratedImageSource.mediaPath(chatId: "c1", mediaId: bad) == nil, "\(bad)")
        }
        for bad in ["..", "c/1", "c 1", "", "c1?x", String(repeating: "a", count: 65)] {
            #expect(GeneratedImageSource.mediaPath(chatId: bad, mediaId: "a.png") == nil, "\(bad)")
        }
        #expect(GeneratedImageSource.mediaPath(chatId: nil, mediaId: "a.png") == nil)
    }
}

@Suite("Image generation: the card model")
struct ImageGenerationCardModelTests {
    @Test("an image's own width/height set its frame; otherwise the requested size; otherwise square")
    func aspect() {
        let card = model(
            #"{"size":"1024x1536","images":[{"mediaId":"a.png","chatId":"c1","width":1536,"height":1024},{"mediaId":"b.png","chatId":"c1"}]}"#)
        #expect(card.frames.map(\.aspectRatio) == [1.5, 1024.0 / 1536.0])
        #expect(card.resolution == "1024 × 1536")
        #expect(card.status == .complete)
        let auto = model(#"{"size":"auto","images":[{"mediaId":"a.png","chatId":"c1"}]}"#)
        #expect(auto.frames[0].aspectRatio == 1)
        #expect(auto.resolution == nil)
        #expect(ImageGenerationCardModel.parseSize("0x10") == nil)
        #expect(ImageGenerationCardModel.parseSize(" 10x10") == nil)
        let size = ImageGenerationCardModel.parseSize("640x480")
        #expect(size?.width == 640 && size?.height == 480)
    }

    @Test("a result with no images is one frame with nothing to show, as the desktop's [{}]")
    func noImages() {
        let card = model(#"{"images":[]}"#)
        #expect(card.frames.count == 1)
        #expect(card.frames[0].source == nil)
        #expect(card.prompt == "A lighthouse")
    }

    @Test("revised prompts are kept per frame")
    func revised() {
        let card = model(#"{"images":[{"mediaId":"a.png","chatId":"c1","revisedPrompt":"A white lighthouse."}]}"#)
        #expect(card.frames[0].revisedPrompt == "A white lighthouse.")
    }
}

@Suite("Image generation: pending → complete in the transcript")
struct ImageGenerationPendingTests {
    @Test("a call with no result yet is a running card; its result replaces it under the same render key")
    func pendingThenComplete() throws {
        let running = try #require(imageCards([user, call("a1", "k1")]).first)
        #expect(running.isPending)
        #expect(running.renderKey == "call:k1")
        #expect(running.content.imageGeneration?.status == .generating)
        #expect(running.content.imageGeneration?.prompt == "A lighthouse")
        #expect(ToolCardRegistry.canDraw(running))

        let details = #"{"images":[{"mediaId":"\#(mediaId)","chatId":"\#(chatId)","mimeType":"image/png"}]}"#
        let done = try #require(imageCards([user, call("a1", "k1"), result("t1", "k1", details: details)]).first)
        #expect(!done.isPending)
        #expect(done.renderKey == running.renderKey)
        #expect(done.content.imageGeneration?.status == .complete)
        #expect(done.content.imageGeneration?.frames.first?.source == .media(path: "/api/v1/media/\(chatId)/\(mediaId)"))
    }

    @Test("a failed call is an error card with the tool's message; exactly one card per call")
    func failed() throws {
        let cards = imageCards([
            user, call("a1", "k1"), result("t1", "k1", details: "null", isError: true, text: "Image 1 of 1 could not be saved"),
        ])
        #expect(cards.count == 1)
        #expect(cards[0].content.imageGeneration?.status == .failed(message: "Image 1 of 1 could not be saved"))
        #expect(cards[0].renderKey == "call:k1")
    }

    @Test("a stopped run's forming image shows nothing, as on the desktop; while it streams it shows")
    func stoppedPendingHidden() throws {
        var cache = RunGrouper.Cache()
        let segments = RunGrouper.group([user, call("a1", "k1")], cache: &cache)
        guard case .assistantTurn(let turn)? = segments.last else {
            Issue.record("no turn")
            return
        }
        #expect(TranscriptRules.toolCards(turn, isStreaming: true).map(\.renderKey) == ["call:k1"])
        #expect(TranscriptRules.toolCards(turn, isStreaming: false).isEmpty)
        let failed = RunGrouper.group([user, call("a1", "k1"), result("t1", "k1", details: "null", isError: true)], cache: &cache)
        guard case .assistantTurn(let settled)? = failed.last else {
            Issue.record("no turn")
            return
        }
        #expect(TranscriptRules.toolCards(settled, isStreaming: false).count == 1, "a settled card stays")
    }

    @Test("image cards stand where their calls were made, like every card; a running one keeps its place")
    func imagesInCallOrder() throws {
        let both = decode(
            #"{"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"image_generation","arguments":{"prompt":"one"}},{"type":"toolCall","id":"k2","name":"terminal","arguments":{"command":"ls"}},{"type":"toolCall","id":"k3","name":"image_generation","arguments":{"prompt":"two"}}],"stopReason":"toolUse","timestamp":2}"#
        )
        let terminal = decode(
            #"{"id":"t2","runId":"u1","role":"toolResult","toolCallId":"k2","toolName":"terminal","content":[{"type":"text","text":"ok"}],"details":{"command":"ls","cwd":"/","exitCode":0,"stdout":"","stderr":""},"isError":false,"timestamp":3}"#
        )
        let details = #"{"images":[{"mediaId":"\#(mediaId)","chatId":"\#(chatId)","mimeType":"image/png"}]}"#
        var cache = RunGrouper.Cache()
        func keys(_ messages: [ChatMessage]) -> [String] {
            guard case .assistantTurn(let turn)? = RunGrouper.group(messages, cache: &cache).last else { return [] }
            return turn.toolCards.map(\.renderKey)
        }
        // k3 lands first, then the terminal; k1 is still forming. The calls were made k1, k2, k3.
        #expect(keys([user, both, result("t3", "k3", details: details), terminal]) == ["call:k1", "call:k2", "call:k3"])
        #expect(
            keys([user, both, result("t3", "k3", details: details), terminal, result("t1", "k1", details: details)])
                == ["call:k1", "call:k2", "call:k3"])
    }

    @Test("the viewer starts on the tapped page; the tapped frame's own image stands in for an evicted one")
    func viewerStartAndFallback() throws {
        #expect(ImageViewer.startSelection([0, 1, 2], start: 2) == 2)
        #expect(ImageViewer.startSelection([0, 2], start: 1) == 0)
        let card = model(
            #"{"images":[{"mediaId":"a.png","chatId":"c1"},{"mediaId":"b.png","chatId":"c1"}]}"#)
        let own = UIImage(data: pngData())!
        let evicted = ImageGenerationCard.viewerPages(card, tapped: ImageViewerPage(id: 1, image: own)) { _ in nil }
        #expect(evicted.map(\.id) == [1])
        guard case .ready(let image)? = evicted.first?.source else {
            Issue.record("no page")
            return
        }
        #expect(image === own)
        let cachedImage = UIImage(data: pngData())!
        let cached = ImageGenerationCard.viewerPages(card, tapped: ImageViewerPage(id: 1, image: own)) { _ in cachedImage }
        #expect(cached.map(\.id) == [0, 1])
    }

    @Test("only tools with a running state get a pending card")
    func onlyImages() {
        let terminal = decode(
            #"{"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"terminal","arguments":{"command":"ls"}}],"stopReason":"toolUse","timestamp":2}"#
        )
        var cache = RunGrouper.Cache()
        let segments = RunGrouper.group([user, terminal], cache: &cache)
        guard case .assistantTurn(let turn)? = segments.last else {
            Issue.record("no turn")
            return
        }
        #expect(turn.toolCards.isEmpty)
        #expect(turn.pendingToolCalls.map(\.name) == ["terminal"])
    }

    @Test("frame status: running, stopped, failed, loading, loaded, gone, retryable, waiting for a tap")
    func frameStatus() {
        typealias R = ImageGenerationRules
        let media = GeneratedImageSource.media(path: "/api/v1/media/c1/a.png")
        let remote = GeneratedImageSource.remote(URL(string: "https://x.invalid/a.png")!, host: "x.invalid", needsTap: true)
        #expect(R.frameStatus(card: .generating, isLive: true, source: nil, load: .idle, requested: false) == .generating)
        #expect(R.frameStatus(card: .generating, isLive: false, source: nil, load: .idle, requested: false) == .unavailable)
        #expect(R.frameStatus(card: .failed(message: "x"), isLive: true, source: nil, load: .idle, requested: false) == .error)
        #expect(R.frameStatus(card: .complete, isLive: false, source: nil, load: .idle, requested: false) == .unavailable)
        #expect(R.frameStatus(card: .complete, isLive: false, source: media, load: .loading, requested: false) == .refining)
        #expect(R.frameStatus(card: .complete, isLive: false, source: media, load: .loaded, requested: false) == .complete)
        #expect(
            R.frameStatus(card: .complete, isLive: false, source: media, load: .failed(.unavailable), requested: false)
                == .unavailable)
        #expect(
            R.frameStatus(card: .complete, isLive: false, source: media, load: .failed(.unauthorized), requested: false)
                == .unavailable)
        #expect(R.frameStatus(card: .complete, isLive: false, source: media, load: .failed(.failed), requested: false) == .loadFailed)
        #expect(
            R.frameStatus(card: .complete, isLive: false, source: remote, load: .idle, requested: false)
                == .askToLoad(host: "x.invalid"))
        #expect(R.frameStatus(card: .complete, isLive: false, source: remote, load: .idle, requested: true) == .refining)
    }

    @Test("the desktop's status copy, in English")
    func copy() {
        #expect(ImageGenerationText.status(.generating) == "Generating image")
        #expect(ImageGenerationText.status(.refining) == "Refining details")
        #expect(ImageGenerationText.status(.complete) == "Image ready")
        #expect(ImageGenerationText.status(.error) == "Generation failed")
        #expect(ImageGenerationText.status(.unavailable) == "Image unavailable")
        #expect(ImageGenerationText.status(.loadFailed) == "Image unavailable")
        #expect(ImageGenerationText.quotedPrompt("A cat") == "“A cat”")
        #expect(ImageGenerationText.labelWithPrompt(status: "Generating image", prompt: "A cat") == "Generating image: A cat")
    }
}

private final class MediaMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data, type) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class Requests: Sendable {
    private let log = Mutex<[(url: String, authorization: String?)]>([])
    func record(_ request: URLRequest) {
        log.withLock { $0.append((request.url?.absoluteString ?? "", request.value(forHTTPHeaderField: "Authorization"))) }
    }
    var all: [(url: String, authorization: String?)] { log.withLock { $0 } }
}

@Suite("Image generation: the loader over the paired session", .serialized)
struct GeneratedImageLoaderTests {
    private let path = "/api/v1/media/\(chatId)/\(mediaId)"

    private func pairedLoader(_ suite: String = #function) async throws -> (GeneratedImageLoader, ServerConnection) {
        let connection = ServerConnection(
            store: InMemoryCredentialStore(
                PairedServer(
                    hosts: ["10.0.0.2"], port: 63129, fingerprint: "PIN", name: "Mac", deviceId: "dev-1", token: "TOKEN")))
        try await connection.unlock(reason: "test")
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        config.connection = connection
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [MediaMockURLProtocol.self]
        let client = APIClient(session: URLSession(configuration: session), serverConfig: config)
        return (GeneratedImageLoader(apiClient: client, cache: GeneratedImageCache()), connection)
    }

    private func stub(_ status: Int, _ data: Data = Data(), type: String = "image/png") -> Requests {
        let requests = Requests()
        MediaMockURLProtocol.handler = { request in
            requests.record(request)
            return (status, data, type)
        }
        return requests
    }

    @Test("fetches the media route with the device's token, then serves the image from memory")
    func loadsWithTokenThenCaches() async throws {
        let (loader, _) = try await pairedLoader()
        let requests = stub(200, pngData())
        let source = GeneratedImageSource.media(path: path)

        let image = try await loader.load(source)
        #expect(image.size == CGSize(width: 4, height: 6))
        #expect(requests.all.count == 1)
        #expect(requests.all.first?.url == "https://10.0.0.2:63129\(path)")
        #expect(requests.all.first?.authorization == "Bearer TOKEN")

        let again = try await loader.load(source)
        #expect(again === image)
        #expect(loader.cached(source) === image)
        #expect(requests.all.count == 1)
    }

    @Test("404 → unavailable (the pairing stays); 401 → unauthorized (the device was revoked)")
    func statuses() async throws {
        let (loader, connection) = try await pairedLoader()
        let source = GeneratedImageSource.media(path: path)
        _ = stub(404, Data(#"{"type":"error","error":{"code":"NOT_FOUND","message":"gone"}}"#.utf8), type: "application/json")
        await #expect(throws: GeneratedImageLoader.Failure.unavailable) { try await loader.load(source) }
        #expect(connection.isPaired)

        _ = stub(401, type: "application/json")
        await #expect(throws: GeneratedImageLoader.Failure.unauthorized) { try await loader.load(source) }
        #expect(!connection.isPaired)
        #expect(loader.cached(source) == nil)
    }

    @Test("a 500 can be retried; bytes that are no image are unavailable")
    func retryableAndUndecodable() async throws {
        let (loader, _) = try await pairedLoader()
        let source = GeneratedImageSource.media(path: path)
        _ = stub(500, Data("boom".utf8), type: "text/plain")
        await #expect(throws: GeneratedImageLoader.Failure.failed) { try await loader.load(source) }
        _ = stub(200, Data("<html>".utf8), type: "image/png")
        await #expect(throws: GeneratedImageLoader.Failure.unavailable) { try await loader.load(source) }
        let requests = stub(200, pngData())
        _ = try await loader.load(source)
        #expect(requests.all.count == 1)
    }

    @Test("a data URL decodes without the network; a legacy link that fails is unavailable")
    func legacy() async throws {
        let fetched = Mutex(0)
        let loader = GeneratedImageLoader(
            fetchMedia: { _ in
                fetched.withLock { $0 += 1 }
                return Data()
            },
            fetchRemote: { _ in throw MarkdownImageLoadError403() }, cache: GeneratedImageCache())
        let inline = GeneratedImageSource.inline("data:image/png;base64,\(pngData().base64EncodedString())")
        #expect(try await loader.load(inline).size == CGSize(width: 4, height: 6))
        #expect(fetched.withLock { $0 } == 0)
        await #expect(throws: GeneratedImageLoader.Failure.unavailable) {
            try await loader.load(.inline("data:image/png,notbase64"))
        }
        let remote = GeneratedImageSource.remote(URL(string: "https://x.invalid/a.png")!, host: "x.invalid", needsTap: true)
        await #expect(throws: GeneratedImageLoader.Failure.unavailable) { try await loader.load(remote) }
    }

    @Test("a legacy link or data URL is decoded downsampled, never at full size; the desktop's own sizes keep every pixel")
    func downsampled() async throws {
        let wide = pngData(width: 3000, height: 30)
        let loader = GeneratedImageLoader(
            fetchMedia: { _ in pngData(width: 1536, height: 1024) }, fetchRemote: { _ in wide }, cache: GeneratedImageCache())
        let remote = GeneratedImageSource.remote(URL(string: "https://x.invalid/a.png")!, host: "x.invalid", needsTap: false)
        let inline = GeneratedImageSource.inline("data:image/png;base64,\(wide.base64EncodedString())")
        for source in [remote, inline] {
            let image = try await loader.load(source)
            #expect(image.size.width * image.scale == CGFloat(GeneratedImageLoader.maxPixelSize), "\(source)")
        }
        let media = try await loader.load(.media(path: "/api/v1/media/c1/a.png"))
        #expect(media.size.width * media.scale == 1536)
    }

    @Test("cancellation is not a failure")
    func cancellation() throws {
        let media = GeneratedImageSource.media(path: "/p")
        #expect(throws: CancellationError.self) { try GeneratedImageLoader.failure(for: CancellationError(), source: media) }
        #expect(throws: CancellationError.self) { try GeneratedImageLoader.failure(for: URLError(.cancelled), source: media) }
        #expect(try GeneratedImageLoader.failure(for: URLError(.timedOut), source: media) == .failed)
        #expect(try GeneratedImageLoader.failure(for: HTTPError(statusCode: 400, code: "BAD", message: ""), source: media) == .unavailable)
    }
}

private struct MarkdownImageLoadError403: Error {}

@MainActor
@Suite("Image generation: drawn in a window")
struct ImageGenerationHostedTests {
    @Test("running, finished and failed cards draw their own card with no diagnostics; a finished one fetches its image")
    func drawsAndFetches() async throws {
        let reports = Mutex<[String]>([])
        let diagnostics = RenderDiagnostics { scope, message, _ in reports.withLock { $0.append("\(scope): \(message)") } }
        let fetched = Mutex<[String]>([])
        let png = pngData()
        let loader = GeneratedImageLoader(
            fetchMedia: { path in
                fetched.withLock { $0.append(path) }
                return png
            },
            fetchRemote: { _ in Data() }, cache: GeneratedImageCache())
        let details = #"{"images":[{"mediaId":"\#(mediaId)","chatId":"\#(chatId)","mimeType":"image/png"}]}"#
        let cards =
            imageCards([user, call("a1", "k1")])
            + imageCards([user, call("a2", "k2"), result("t2", "k2", details: details)])
            + imageCards([user, call("a3", "k3"), result("t3", "k3", details: "null", isError: true, text: "failed")])
        #expect(cards.count == 3)
        #expect(cards.allSatisfy(ToolCardRegistry.canDraw))
        let root = VStack { ForEach(cards, id: \.renderKey) { ToolCardView(card: $0) } }
            .environment(\.renderDiagnostics, diagnostics)
            .environment(\.generatedImageLoader, loader)
            .environment(\.toolCardsAreLive, true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1400))
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        #expect(reports.withLock { $0 }.isEmpty)
        #expect(fetched.withLock { $0 } == ["/api/v1/media/\(chatId)/\(mediaId)"])
        #expect(loader.cached(.media(path: "/api/v1/media/\(chatId)/\(mediaId)")) != nil)
        window.isHidden = true
    }
}

/// Every `toolCardsAreLive` value the view tree writes, found by walking the built body (no rendering needed).
@MainActor
private func liveFlags(in value: Any) -> [Bool] {
    var found: [Bool] = []
    if let modifier = value as? _EnvironmentKeyWritingModifier<Bool>, modifier.keyPath == \EnvironmentValues.toolCardsAreLive {
        found.append(modifier.value)
    }
    for child in Mirror(reflecting: value).children { found += liveFlags(in: child.value) }
    return found
}

@MainActor
@Suite("Image generation: the turn tells its cards whether they are live (C3 L1)")
struct ToolCardsLiveFlagTests {
    @Test("AssistantTurnView sets toolCardsAreLive to exactly isStreaming, once, around its cards")
    func liveFlagFollowsStreaming() throws {
        var cache = RunGrouper.Cache()
        let segments = RunGrouper.group([user, call("a1", "k1")], cache: &cache)
        guard case .assistantTurn(let turn)? = segments.last else {
            Issue.record("no turn")
            return
        }
        for streaming in [true, false] {
            let view = AssistantTurnView(turn: turn, isStreaming: streaming, error: nil)
            #expect(liveFlags(in: view.body) == [streaming], "isStreaming: \(streaming)")
        }
    }
}
