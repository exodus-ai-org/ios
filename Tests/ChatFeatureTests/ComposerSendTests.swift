import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

/// `body` as one chat page when `path` asks for a page and `body` is a bare array of rows; otherwise as it is.
private func composerWrap(_ body: Data, path: String) -> Data {
    let text = String(decoding: body, as: UTF8.self)
    guard path.hasSuffix("/page"), text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") else { return body }
    return Data(#"{"messages":\#(text),"sources":[],"questions":[],"hasOlder":false,"olderCursor":null}"#.utf8)
}

/// The computer, as far as a send needs it: a chat page (`history`, a bare array of rows) and an empty `done`.
private final class ComposerMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var history = "[]"
    static let sends = SendLog()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isSend = request.httpMethod == "POST" && request.url?.path == "/api/v1/chat"
        let body: Data
        if isSend {
            Self.sends.record(request.composerBody())
            body = Data("data: {\"type\":\"done\",\"messages\":[]}\n\n".utf8)
        } else {
            body = composerWrap(Data(Self.history.utf8), path: request.url?.path ?? "")
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: isSend ? ["Content-Type": "text/event-stream"] : nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The send bodies, recorded on URLProtocol's thread and read by the test.
private final class SendLog: Sendable {
    private let bodies = Mutex<[Data]>([])

    func record(_ body: Data) { bodies.withLock { $0.append(body) } }
    func reset() { bodies.withLock { $0.removeAll() } }
    var count: Int { bodies.withLock { $0.count } }

    /// The last send's JSON body.
    func last() throws -> [String: Any] {
        let data = try #require(bodies.withLock { $0.last })
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The last send's question: `message` in a protocol-2 body, else the last of `messages`.
    func lastQuestion() throws -> [String: Any] {
        let body = try last()
        return try #require((body["message"] as? [String: Any]) ?? (body["messages"] as? [[String: Any]])?.last)
    }

    /// The last send's question `content` as blocks; nil when it is a plain string.
    func lastBlocks() throws -> [[String: Any]]? {
        try lastQuestion()["content"] as? [[String: Any]]
    }
}

extension URLRequest {
    /// URLSession hands a protocol the body as a stream.
    fileprivate func composerBody() -> Data {
        guard let stream = httpBodyStream else { return httpBody ?? Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private let answeredChat = #"""
    [{"id":"u1","runId":"u1","chatId":"c1","role":"user","content":"hi","createdAt":"2026-09-18T12:00:00.000Z"},
     {"id":"a1","runId":"u1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"hello"}],"stopReason":"stop","createdAt":"2026-09-18T12:00:05.000Z"}]
    """#

@MainActor
@Suite("Composer send", .serialized)
struct ComposerSendTests {
    /// A chat over the mock, its history loaded; `history` is its rows.
    private func loadedViewModel(history: String = "[]", _ suite: String = #function) async -> ChatDetailViewModel {
        ComposerMockURLProtocol.history = history
        ComposerMockURLProtocol.sends.reset()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComposerMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let vm = ChatDetailViewModel(
            chatId: "c1", apiClient: APIClient(session: session, serverConfig: config),
            streamManager: ChatStreamManager(sseClient: SSEClient(session: session)), serverConfig: config)
        await vm.loadHistory()
        return vm
    }

    @Test("pictures alone can be sent, as image blocks, and leave the composer empty")
    func picturesAlone() async throws {
        let vm = await loadedViewModel()
        #expect(!vm.canSend)
        vm.attachments.append([PictureFixture.picture(1)])
        #expect(vm.canSend)
        await vm.sendMessage()
        let blocks = try #require(try ComposerMockURLProtocol.sends.lastBlocks())
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "image")
        #expect(blocks[0]["mimeType"] as? String == "image/jpeg")
        #expect(blocks[0]["data"] as? String == PictureFixture.picture(1).dataURL)
        #expect(vm.attachments.isEmpty)
    }

    @Test("text and pictures go in one message: the text first, then the pictures in pick order")
    func textAndPictures() async throws {
        let vm = await loadedViewModel()
        vm.composerText = "Which is warmer?"
        vm.attachments.append([PictureFixture.picture(1), PictureFixture.picture(2)])
        await vm.sendMessage()
        let blocks = try #require(try ComposerMockURLProtocol.sends.lastBlocks())
        #expect(blocks.map { $0["type"] as? String } == ["text", "image", "image"])
        #expect(blocks[0]["text"] as? String == "Which is warmer?")
        #expect(blocks[1]["data"] as? String == PictureFixture.picture(1).dataURL)
        #expect(blocks[2]["data"] as? String == PictureFixture.picture(2).dataURL)
        #expect(vm.composerText.isEmpty && vm.attachments.isEmpty)
    }

    @Test("blank text and no pictures send nothing")
    func nothingToSend() async {
        let vm = await loadedViewModel()
        vm.composerText = "  \n"
        #expect(!vm.canSend)
        await vm.sendMessage()
        #expect(ComposerMockURLProtocol.sends.count == 0)
    }

    @Test("a quote with pictures and nothing typed sends the quote as the text, then the pictures")
    func aQuoteWithPicturesAndNothingTypedSendsTheQuote() async throws {
        let vm = await loadedViewModel()
        vm.askAbout("Daikin was sold.")
        vm.attachments.append([PictureFixture.picture(1)])
        #expect(vm.canSend)
        await vm.sendMessage()
        let blocks = try #require(try ComposerMockURLProtocol.sends.lastBlocks())
        let quote = QuotedText.compose(quote: "Daikin was sold.", text: "").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(blocks.map { $0["type"] as? String } == ["text", "image"])
        #expect(blocks[0]["text"] as? String == quote)
        #expect(vm.quote == nil)
    }

    @Test("text alone is still a plain string, with no tools and no effort, when the session has no choices")
    func textAloneUnchanged() async throws {
        let vm = await loadedViewModel()
        vm.composerText = "hi"
        await vm.sendMessage()
        let body = try ComposerMockURLProtocol.sends.last()
        #expect(try ComposerMockURLProtocol.sends.lastQuestion()["content"] as? String == "hi")
        #expect((body["advancedTools"] as? [String]) == [])
        #expect(!body.keys.contains("reasoningEffort"))
    }

    @Test("the session's choices ride along: a reasoning level, then Deep Research")
    func choicesRideAlong() async throws {
        let vm = await loadedViewModel()
        let tools = ComposerTools()
        tools.adopt(reasoningLevels: ["off", "low", "high"])
        tools.setEffort(.high)
        vm.composerTools = tools
        vm.composerText = "think hard"
        await vm.sendMessage()
        var body = try ComposerMockURLProtocol.sends.last()
        #expect(body["reasoningEffort"] as? String == "high")
        #expect((body["advancedTools"] as? [String]) == [])

        tools.setDeepResearch(true)
        vm.composerText = "now research it"
        await vm.sendMessage()
        body = try ComposerMockURLProtocol.sends.last()
        #expect((body["advancedTools"] as? [String]) == ["Deep Research"])
        #expect(!body.keys.contains("reasoningEffort"))
    }

    @Test("Regenerate re-asks with the choices as they are at that moment")
    func regenerateTakesTheChoicesOfThatMoment() async throws {
        let vm = await loadedViewModel(history: answeredChat)
        let tools = ComposerTools()
        vm.composerTools = tools
        tools.setDeepResearch(true)
        #expect(vm.canRegenerate)
        await vm.regenerate()
        let body = try ComposerMockURLProtocol.sends.last()
        #expect((body["advancedTools"] as? [String]) == ["Deep Research"])
    }

    @Test("an unreadable picture is left out with a notice; the readable one stays")
    func unreadablePictures() async {
        let vm = await loadedViewModel()
        await vm.addPictures([Data("not a picture".utf8), PictureFixture.data(width: 40, height: 30), nil])
        #expect(vm.attachments.pictures.count == 1)
        #expect(vm.notice == StreamNotice(level: .warning, message: ComposerText.unreadable(2)))
    }

    @Test("picks past the limit are left out quietly, in pick order")
    func picksPastTheLimitAreLeftOutQuietly() async {
        let vm = await loadedViewModel()
        let waiting = (0..<8).map(PictureFixture.picture)
        vm.attachments.append(waiting)
        await vm.addPictures((0..<5).map { _ in PictureFixture.data(width: 40, height: 30) })
        #expect(vm.attachments.pictures.count == 10)
        #expect(Array(vm.attachments.pictures.prefix(8)) == waiting)
        #expect(vm.notice == nil)
    }

    @Test("picked pictures are loaded and prepared one at a time, each added as it is ready, and Send waits for them")
    func picturesArriveOneAtATime() async throws {
        let vm = await loadedViewModel()
        vm.composerText = "these"
        let seen = LoaderLog()
        let loaders: [ComposerPicture.Loader] = (0..<3).map { _ in
            { @MainActor in
                seen.states.append(.init(waiting: vm.attachments.pictures.count, preparing: vm.preparingPictures, canSend: vm.canSend))
                // A tap on Send now would leave the pictures not ready yet out of the message.
                await vm.sendMessage()
                return PictureFixture.data(width: 40, height: 30)
            }
        }
        await vm.addPictures(loaders)
        #expect(seen.states == [
            .init(waiting: 0, preparing: 3, canSend: false),
            .init(waiting: 1, preparing: 2, canSend: false),
            .init(waiting: 2, preparing: 1, canSend: false),
        ])
        #expect(ComposerMockURLProtocol.sends.count == 0)
        #expect(vm.attachments.pictures.count == 3)
        #expect(!vm.isPreparingPictures && vm.canSend)
    }

    @Test("once the composer is full, the picks left are not even loaded")
    func picksPastTheLimitAreNotLoaded() async {
        let vm = await loadedViewModel()
        vm.attachments.append((0..<9).map(PictureFixture.picture))
        let seen = LoaderLog()
        let loaders: [ComposerPicture.Loader] = (0..<3).map { _ in
            { @MainActor in
                seen.states.append(.init(waiting: vm.attachments.pictures.count, preparing: vm.preparingPictures, canSend: vm.canSend))
                return PictureFixture.data(width: 40, height: 30)
            }
        }
        await vm.addPictures(loaders)
        #expect(seen.states.count == 1)
        #expect(vm.attachments.pictures.count == 10)
        #expect(vm.preparingPictures == 0 && vm.notice == nil)
    }

    @Test("a picture can be taken out again")
    func removing() async {
        let vm = await loadedViewModel()
        let picture = PictureFixture.picture(1)
        vm.attachments.append([picture])
        vm.removePicture(picture.id)
        #expect(vm.attachments.isEmpty && !vm.canSend)
    }
}

/// What the composer looked like each time a picked picture started loading.
@MainActor
private final class LoaderLog {
    struct State: Equatable {
        let waiting: Int
        let preparing: Int
        let canSend: Bool
    }

    var states: [State] = []
}
