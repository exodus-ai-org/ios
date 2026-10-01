import Foundation
import Models
import NetworkingKit
import Testing

@testable import ChatFeature

@Suite("Artifact preview: the sandbox scheme and when it falls back")
struct ArtifactPreviewTests {
    private func request(_ string: String) -> ArtifactSandboxRoute.Request? {
        ArtifactSandboxRoute.apiRequest(for: URL(string: string)!)
    }

    @Test("a sandbox URL is the same path under the API's sandbox route")
    func mapsToAPIPath() {
        #expect(
            request("exodus-artifact://sandbox/src/renderer/sub-apps/artifacts/index.html")
                == .init(path: "/api/v1/artifacts/sandbox/src/renderer/sub-apps/artifacts/index.html", query: []))
        #expect(request("exodus-artifact://sandbox/assets/artifacts-Bm1q5Gz5.js")?.path
            == "/api/v1/artifacts/sandbox/assets/artifacts-Bm1q5Gz5.js")
        #expect(ArtifactSandboxRoute.pageURL.absoluteString
            == "exodus-artifact://sandbox/src/renderer/sub-apps/artifacts/index.html")
        #expect(request(ArtifactSandboxRoute.pageURL.absoluteString)?.path == ArtifactSandboxRoute.pageAPIPath)
    }

    @Test("a query (the dev server's `?v=`) is passed on")
    func keepsQuery() {
        #expect(request("exodus-artifact://sandbox/@vite/client?v=abc")
            == .init(path: "/api/v1/artifacts/sandbox/@vite/client", query: [URLQueryItem(name: "v", value: "abc")]))
    }

    @Test(
        "anything but a plain build path is refused",
        arguments: [
            "https://sandbox/assets/a.js",
            "exodus-artifact://elsewhere/assets/a.js",
            "exodus-artifact://sandbox/",
            "exodus-artifact://sandbox/assets/..%2F..%2Fsecret",
            "exodus-artifact://sandbox/%2e%2e/secret",
            "exodus-artifact://sandbox/assets/%00.js",
            "exodus-artifact://sandbox/assets//a.js",
            "exodus-artifact://sandbox/assets/a%20b.js",
            "exodus-artifact://sandbox/assets/a%5Cb.js",
        ])
    func refuses(_ url: String) {
        #expect(request(url) == nil)
    }

    @Test("the web view is told the computer's content type, or bytes when it gave none")
    func passesTypeThrough() {
        let url = URL(string: "exodus-artifact://sandbox/assets/a.js")!
        let js = ArtifactSandboxRoute.response(
            for: url, file: FetchedFile(data: Data("x".utf8), contentType: "text/javascript; charset=utf-8"))
        #expect(js.statusCode == 200)
        #expect(js.value(forHTTPHeaderField: "Content-Type") == "text/javascript; charset=utf-8")
        #expect(js.mimeType == "text/javascript")
        #expect(js.value(forHTTPHeaderField: "Content-Length") == "1")
        let bare = ArtifactSandboxRoute.response(for: url, file: FetchedFile(data: Data(), contentType: nil))
        #expect(bare.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
    }

    @Test("only the sandbox and blank documents may be navigated to")
    func navigation() {
        #expect(ArtifactSandboxRoute.allowsNavigation(to: ArtifactSandboxRoute.pageURL))
        #expect(ArtifactSandboxRoute.allowsNavigation(to: URL(string: "about:blank")))
        #expect(!ArtifactSandboxRoute.allowsNavigation(to: URL(string: "https://example.com")))
        #expect(!ArtifactSandboxRoute.allowsNavigation(to: URL(string: "exodus-artifact://other/x")))
        #expect(!ArtifactSandboxRoute.allowsNavigation(to: URL(string: "exodus://pair?c=1")))
        #expect(!ArtifactSandboxRoute.allowsNavigation(to: nil))
    }

    @Test("an id is one path segment")
    func idSegment() {
        #expect(ArtifactSandboxRoute.pathSegment("0b1c-ab_9") == "0b1c-ab_9")
        #expect(ArtifactSandboxRoute.pathSegment("../x") == "%2E%2E%2Fx")
    }

    // MARK: Fallback

    private func run(_ events: [ArtifactPreviewEvent]) -> ArtifactPreviewPhase {
        events.reduce(.loading) { ArtifactPreviewRules.next($0, on: $1) }
    }

    @Test("ready, then rendered, shows the artifact")
    func renders() {
        #expect(run([.sandboxReady, .rendered]) == .rendered)
        #expect(run([.sandboxReady]) == .loading)
    }

    @Test("a 404 for the page is a computer from before phones could preview; another failure is unreachable")
    func pageFailures() {
        #expect(run([.pageFailed(status: 404)]) == .fallback(.outdatedComputer))
        #expect(run([.pageFailed(status: 500)]) == .fallback(.unreachable))
        #expect(run([.pageFailed(status: nil)]) == .fallback(.unreachable))
        #expect(run([.unavailable]) == .fallback(.unreachable))
    }

    @Test("the first fallback stays: WebKit's own failure after ours does not change the reason")
    func firstFallbackWins() {
        #expect(run([.pageFailed(status: 404), .pageFailed(status: nil)]) == .fallback(.outdatedComputer))
        #expect(run([.renderFailed("boom"), .rendered]) == .fallback(.renderFailed("boom")))
    }

    @Test("no answer in time falls back; a timeout after the render does not")
    func timeout() {
        #expect(run([.sandboxReady, .timedOut]) == .fallback(.unreachable))
        #expect(run([.sandboxReady, .rendered, .timedOut]) == .rendered)
    }

    @Test("an error, before or after the render, falls back with the sandbox's message")
    func renderErrors() {
        #expect(run([.sandboxReady, .renderFailed("x is not defined")]) == .fallback(.renderFailed("x is not defined")))
        #expect(run([.sandboxReady, .rendered, .renderFailed(nil)]) == .fallback(.renderFailed(nil)))
        #expect(run([.rendered, .pageFailed(status: 404)]) == .rendered)
    }

    @Test("the status of a failure is the computer's, when it answered")
    func status() {
        #expect(ArtifactPreviewRules.status(of: HTTPError(statusCode: 404, code: "X", message: "")) == 404)
        #expect(ArtifactPreviewRules.status(of: URLError(.timedOut)) == nil)
    }

    @Test("the message shown is its first line, kept short")
    func displayMessage() {
        #expect(ArtifactPreviewRules.displayMessage("TypeError: x\n    at Revenue") == "TypeError: x")
        #expect(ArtifactPreviewRules.displayMessage("  \n") == nil)
        #expect(ArtifactPreviewRules.displayMessage(nil) == nil)
        #expect(ArtifactPreviewRules.displayMessage(String(repeating: "a", count: 400))?.count == 301)
    }

    @Test("a resize does not change how the render went")
    func resizeKeepsPhase() {
        #expect(run([.resized(300)]) == .loading)
        #expect(run([.rendered, .resized(300)]) == .rendered)
    }

    // MARK: The bridge's messages

    @Test("the sandbox's messages read as events; anything else is ignored")
    func parsesMessages() {
        #expect(ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-ready"]) == .sandboxReady)
        #expect(ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-rendered"]) == .rendered)
        #expect(
            ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-error", "message": "boom"])
                == .renderFailed("boom"))
        #expect(
            ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-error", "message": NSNull()])
                == .renderFailed(nil))
        #expect(ArtifactPreviewEvent.from(message: ["type": "theme"]) == nil)
        #expect(ArtifactPreviewEvent.from(message: "artifact-sandbox-ready") == nil)
        #expect(ArtifactPreviewEvent.from(message: ["kind": "artifact-sandbox-ready"]) == nil)
    }

    @Test("a size is its height in points; one without a usable height is ignored")
    func parsesSize() {
        #expect(ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-size", "height": 312]) == .resized(312))
        #expect(
            ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-size", "height": 98.5]) == .resized(98.5))
        #expect(ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-size", "height": NSNull()]) == nil)
        #expect(ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-size", "height": "300"]) == nil)
        #expect(ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-size", "height": -1]) == nil)
        #expect(ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-size", "height": Double.nan]) == nil)
        #expect(ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-size", "height": true]) == nil)
        #expect(ArtifactPreviewEvent.from(message: ["type": "artifact-sandbox-size"]) == nil)
    }

    // MARK: The asset cache

    private func cacheKey(_ url: String) -> String? {
        request(url).flatMap(ArtifactSandboxCache.key(for:))
    }

    @Test("a built asset is kept, under a flat name that is the same for the same path")
    func cachesAssets() throws {
        let key = try #require(cacheKey("exodus-artifact://sandbox/assets/artifacts-CN-2EpYa.js"))
        #expect(key.count == 64)
        #expect(key.allSatisfy { $0.isHexDigit })
        #expect(cacheKey("exodus-artifact://sandbox/assets/artifacts-CN-2EpYa.js") == key)
        #expect(cacheKey("exodus-artifact://sandbox/assets/useControlled-b4vTsN15.css") != key)
    }

    @Test(
        "the page, any HTML, a dev server's module and a request with a query are never kept",
        arguments: [
            "exodus-artifact://sandbox/src/renderer/sub-apps/artifacts/index.html",
            "exodus-artifact://sandbox/assets/page.html",
            "exodus-artifact://sandbox/assets/PAGE.HTM",
            "exodus-artifact://sandbox/src/renderer/sub-apps/artifacts/main.tsx",
            "exodus-artifact://sandbox/@vite/client",
            "exodus-artifact://sandbox/assets/a.js?v=1",
        ])
    func doesNotCache(_ url: String) {
        #expect(request(url) != nil)
        #expect(cacheKey(url) == nil)
    }

    @Test("a key cannot leave the cache's directory, whatever the path")
    func keyIsFlat() {
        let key = ArtifactSandboxCache.key(
            for: .init(path: ArtifactSandboxRoute.apiPrefix + "assets/../../../etc/passwd", query: []))
        #expect(key.map { !$0.contains("/") && !$0.contains(".") } == true)
    }

    @Test("a kept file reads back with its type; HTML is not written; a miss is nil")
    func cacheRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "artifact-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ArtifactSandboxCache(directory: directory)
        let js = FetchedFile(data: Data("export {}".utf8), contentType: "text/javascript; charset=utf-8")
        await cache.write(js, for: "a")
        #expect(await cache.read("a") == js)
        await cache.write(FetchedFile(data: Data("<p>".utf8), contentType: "text/html; charset=utf-8"), for: "b")
        #expect(await cache.read("b") == nil)
        #expect(await cache.read("missing") == nil)
        let bare = FetchedFile(data: Data([1, 2]), contentType: nil)
        await cache.write(bare, for: "c")
        #expect(await cache.read("c") == bare)
    }

    // MARK: The card in the chat

    private func inline(_ events: [ArtifactPreviewEvent]) -> ArtifactInlineState {
        var state = ArtifactInlineState()
        for event in events { state.apply(event) }
        return state
    }

    @Test("the card holds a placeholder's room until the artifact says how tall it is")
    func placeholderHeight() {
        #expect(inline([]).height == ArtifactInlineState.placeholderHeight)
        // The sandbox's "waiting" line, before the render, does not size the card.
        #expect(inline([.resized(20)]).height == ArtifactInlineState.placeholderHeight)
        #expect(inline([.rendered, .resized(312.2)]).height == 313)
    }

    @Test("the height stays within the limits; past the top it fades")
    func clampsHeight() {
        let tall = inline([.rendered, .resized(900)])
        #expect(tall.height == ArtifactInlineState.maxHeight)
        #expect(tall.overflows)
        let exact = inline([.rendered, .resized(ArtifactInlineState.maxHeight)])
        #expect(!exact.overflows)
        #expect(inline([.rendered, .resized(0)]).height == ArtifactInlineState.minHeight)
    }

    @Test("a new web view loads again at the height the card had; a fallback stays")
    func reloadKeepsHeight() {
        var state = inline([.rendered, .resized(300)])
        state.reload()
        #expect(state.phase == .loading)
        #expect(state.height == 300)
        state.apply(.resized(10))
        #expect(state.height == 300)
        var failed = inline([.pageFailed(status: 404)])
        failed.reload()
        #expect(failed.phase == .fallback(.outdatedComputer))
    }

    @Test("full screen is offered unless the card knows it would not show")
    func offersFullScreen() {
        #expect(inline([]).offersFullScreen)
        #expect(inline([.rendered]).offersFullScreen)
        #expect(!inline([.pageFailed(status: nil)]).offersFullScreen)
        #expect(!inline([.renderFailed("x")]).offersFullScreen)
        // It rendered, then threw on a tap: full screen starts it afresh.
        #expect(inline([.rendered, .renderFailed("x")]).offersFullScreen)
    }

    @Test("only a few web views live at once; a freed place goes to the first card waiting")
    func liveSlots() {
        var slots = ArtifactLiveSlots(limit: 2)
        let ids = (0..<4).map { _ in UUID() }
        ids.forEach { slots.want($0) }
        #expect(slots.holders == [ids[0], ids[1]])
        #expect(slots.waiting == [ids[2], ids[3]])
        slots.want(ids[0])
        #expect(slots.holders.count == 2)
        slots.drop(ids[0])
        #expect(slots.holders == [ids[1], ids[2]])
        slots.drop(ids[3])
        #expect(slots.waiting.isEmpty)
        slots.drop(UUID())
        #expect(slots.holders == [ids[1], ids[2]])
    }

    @Test("near the screen loads, far lets go, and between keeps what it has")
    func proximity() {
        let visible = CGRect(x: 0, y: 1000, width: 400, height: 800)
        func at(_ y: CGFloat) -> ArtifactProximity {
            ArtifactProximity.of(card: CGRect(x: 0, y: y, width: 400, height: 300), visible: visible)
        }
        #expect(at(1200) == .near)
        #expect(at(1700) == .near)
        #expect(at(2100) == .near)  // 300 below
        #expect(at(2600) == .between)  // 800 below
        #expect(at(3100) == .far)  // 1300 below
        #expect(at(300) == .near)  // 400 above
        #expect(at(-1000) == .far)
        #expect(ArtifactProximity.of(card: .zero, visible: nil) == .near)
    }

    @Test("a card back on screen asks for its place again unless it was last far")
    func slotOnAppear() {
        #expect(ArtifactProximity.near.slotChange == .want)
        #expect(ArtifactProximity.far.slotChange == .drop)
        #expect(ArtifactProximity.between.slotChange == nil)
        #expect(ArtifactProximity.slotChangeOnAppear(last: nil) == .want)
        #expect(ArtifactProximity.slotChangeOnAppear(last: .near) == .want)
        #expect(ArtifactProximity.slotChangeOnAppear(last: .between) == .want)
        #expect(ArtifactProximity.slotChangeOnAppear(last: .far) == nil)

        // Near, then gone (scrolled just off the lazy list), then back with the same geometry: no proximity change
        // fires, and the card still gets its web view back.
        var slots = ArtifactLiveSlots()
        let card = UUID()
        func apply(_ change: ArtifactSlotChange?) {
            switch change {
            case .want: slots.want(card)
            case .drop: slots.drop(card)
            case nil: break
            }
        }
        apply(ArtifactProximity.near.slotChange)
        slots.drop(card)  // onDisappear
        #expect(!slots.holds(card))
        apply(ArtifactProximity.slotChangeOnAppear(last: .near))
        #expect(slots.holds(card))
    }

    @Test("create_artifact's result reads its id, chat, title and code; one without an id is not an artifact")
    func decodesResult() throws {
        let json = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(#"{"type":"artifact","artifactId":"a","chatId":"c","title":"T","code":"export {}"}"#.utf8))
        #expect(ArtifactResult(json: json) == ArtifactResult(artifactId: "a", chatId: "c", title: "T", code: "export {}"))
        let noCode = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"artifact","artifactId":"a"}"#.utf8))
        #expect(ArtifactResult(json: noCode)?.code == "")
        let other = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"artifact","id":"a"}"#.utf8))
        #expect(ArtifactResult(json: other) == nil)
    }
}
