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
