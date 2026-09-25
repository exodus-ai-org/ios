import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import MarkdownKit

@Suite("MarkdownLinkPolicy")
struct MarkdownLinkPolicyTests {
    private func action(_ string: String) -> MarkdownLinkAction {
        MarkdownLinkPolicy.action(for: URL(string: string)!)
    }

    @Test("web and mail links open", arguments: [
        "https://example.com/a?b=c", "http://example.com", "HTTPS://EXAMPLE.COM", "Http://example.com",
        "mailto:someone@example.com", "mailto:someone@example.com?subject=Hi&body=there", "MAILTO:a@b.c",
    ])
    func allowed(url: String) {
        #expect(action(url) == .open(URL(string: url)!))
    }

    @Test("every other scheme is discarded", arguments: [
        "javascript:alert(1)", "tel:+15551234567", "sms:+15551234567&body=hi", "facetime:+15551234567",
        "shortcuts://run-shortcut?name=Exfiltrate&input=secret", "file:///etc/passwd", "someapp://do/thing",
        "exodus://pair?c=1", "relative/path.html", "/absolute/path", "#fragment", "www.example.com",
    ])
    func discarded(url: String) {
        #expect(action(url) == .discard)
    }

    @Test("citation links route to the chip callback")
    func citation() {
        #expect(action("exodus-cite://4") == .citation(4))
        #expect(action("exodus-cite://x") == .discard)
    }
}

@Suite("MarkdownLinkRouter")
@MainActor
struct MarkdownLinkRouterTests {
    @Test("routes citations, opens allowed links, drops the rest")
    func routing() {
        let router = MarkdownLinkRouter()
        var cited: [Int] = []
        var opened: [URL] = []
        router.onCitationTap = { cited.append($0) }
        router.openURL = { opened.append($0) }

        _ = router.handle(URL(string: "exodus-cite://2")!)
        _ = router.handle(URL(string: "https://example.com")!)
        _ = router.handle(URL(string: "tel:123")!)
        _ = router.handle(URL(string: "shortcuts://run-shortcut?name=x")!)

        #expect(cited == [2])
        #expect(opened == [URL(string: "https://example.com")!])
    }

    @Test("the action is built once, handlers can change behind it")
    func stableAction() {
        let router = MarkdownLinkRouter()
        var first = 0
        var second = 0
        router.onCitationTap = { _ in first += 1 }
        _ = router.action
        _ = router.handle(URL(string: "exodus-cite://1")!)
        router.onCitationTap = { _ in second += 1 }
        _ = router.handle(URL(string: "exodus-cite://1")!)
        #expect(first == 1)
        #expect(second == 1)
    }
}

@Suite("MarkdownStreamModel first read")
@MainActor
struct MarkdownStreamModelRenderTests {
    @Test("the first read yields blocks with exactly one parse, the next none")
    func firstRead() {
        let model = MarkdownStreamModel()
        let text = "# Title\n\nBody \u{3010}1-source\u{3011}\n\n- item"
        let blocks = model.blocks(for: text, isStreaming: false)
        #expect(blocks.count == 3)
        #expect(model.lastUpdateParseCount == 1)
        #expect(model.citations(for: text, isStreaming: false) == [1])
        #expect(model.lastUpdateParseCount == 0)
        #expect(model.blocks(for: text, isStreaming: false) == blocks)
        #expect(model.lastUpdateParseCount == 0)
    }

    @Test("blocks and citations for the same text are consistent")
    func consistent() {
        let model = MarkdownStreamModel()
        _ = model.blocks(for: "a \u{3010}1-source\u{3011}", isStreaming: true)
        let rendered = model.rendered(for: "a \u{3010}1-source\u{3011} b \u{3010}2-source\u{3011}", isStreaming: true)
        #expect(rendered.citations == [1, 2])
        #expect(model.citations(for: "a \u{3010}1-source\u{3011} b \u{3010}2-source\u{3011}", isStreaming: true) == [1, 2])
    }

    @Test("update after a read publishes the same blocks without parsing again")
    func updateAfterRead() {
        let model = MarkdownStreamModel()
        let blocks = model.blocks(for: "one\n\ntwo \u{3010}3-source\u{3011}", isStreaming: false)
        model.update(text: "one\n\ntwo \u{3010}3-source\u{3011}", isStreaming: false)
        #expect(model.lastUpdateParseCount == 0)
        #expect(model.blocks == blocks)
        #expect(model.citations == [3])
    }
}

@Suite("MarkdownImagePolicy")
struct MarkdownImagePolicyTests {
    private let remote = "https://example.com/pixel.png?q=secret"

    @Test("remote images wait for a tap by default")
    func tapToLoad() {
        #expect(MarkdownImagePolicy.current == .tapToLoadRemote)
        #expect(
            MarkdownImagePolicy.tapToLoadRemote.decision(for: remote)
                == .askToLoad(URL(string: remote)!, host: "example.com"))
        #expect(MarkdownImagePolicy.tapToLoadRemote.decision(for: "HTTP://example.com/a.png") != .unavailable)
    }

    @Test("the other policies")
    func otherPolicies() {
        #expect(MarkdownImagePolicy.autoLoadRemote.decision(for: remote) == .load(URL(string: remote)!))
        #expect(MarkdownImagePolicy.blockRemote.decision(for: remote) == .unavailable)
    }

    @Test("small data images load under every policy")
    func inlineData() {
        let source = "data:image/png;base64,iVBORw0KGgo="
        for policy in [MarkdownImagePolicy.tapToLoadRemote, .autoLoadRemote, .blockRemote] {
            #expect(policy.decision(for: source) == .load(URL(string: source)!))
        }
    }

    @Test("a data image over the cap is not loaded")
    func inlineCap() {
        let over = "data:image/png;base64," + String(repeating: "A", count: (MarkdownImagePolicy.inlineByteCap / 3 + 1) * 4)
        let under = "data:image/png;base64," + String(repeating: "A", count: MarkdownImagePolicy.inlineByteCap / 3 * 4)
        #expect(MarkdownImagePolicy.inlinePayloadSize(over)! > MarkdownImagePolicy.inlineByteCap)
        #expect(MarkdownImagePolicy.tapToLoadRemote.decision(for: over) == .unavailable)
        #expect(MarkdownImagePolicy.tapToLoadRemote.decision(for: under) != .unavailable)
    }

    @Test("relative, hostless and unknown schemes are unavailable", arguments: [
        "diagrams/missing.png", "/img.png", "file:///etc/passwd", "ftp://example.com/a.png", "https:///a.png",
        "javascript:alert(1)", "", "data:no-comma",
    ])
    func unavailable(source: String) {
        #expect(MarkdownImagePolicy.autoLoadRemote.decision(for: source) == .unavailable)
    }
}

final class MockImageProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        var status = 200
        var contentType: String? = "image/png"
        var contentLength: Int?
        var chunks: [Data] = []
        var error: URLError?
    }

    static let stubs = Mutex<[String: Stub]>([:])

    static func stub(_ stub: Stub) -> URL {
        let host = "\(UUID().uuidString.lowercased()).test"
        stubs.withLock { $0[host] = stub }
        return URL(string: "https://\(host)/image")!
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "https" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = Self.stubs.withLock({ $0[url.host() ?? ""] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        var headers: [String: String] = [:]
        if let contentType = stub.contentType { headers["Content-Type"] = contentType }
        if let contentLength = stub.contentLength { headers["Content-Length"] = String(contentLength) }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in stub.chunks { client?.urlProtocol(self, didLoad: chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("MarkdownImageLoader")
struct MarkdownImageLoaderTests {
    private let loader = MarkdownImageLoader(protocolClasses: [MockImageProtocol.self])

    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test("limits")
    func limits() {
        #expect(MarkdownImageLoader.timeout == 15)
        #expect(MarkdownImageLoader.byteCap == 8 * 1024 * 1024)
    }

    @Test("an image loads and is downsampled to the display width")
    func loads() async throws {
        let url = MockImageProtocol.stub(.init(chunks: [Self.png(width: 1200, height: 600)]))
        let image = try await loader.load(url, maxPixelWidth: 300)
        #expect(image.cgImage.width == 300)
        #expect(image.cgImage.height == 150)
        #expect(image.sourcePixelWidth == 1200)
    }

    @Test("a body over the cap is refused while it streams in")
    func streamedCap() async {
        let chunk = Data(count: 1024 * 1024)
        let url = MockImageProtocol.stub(.init(chunks: Array(repeating: chunk, count: 9)))
        await #expect(throws: MarkdownImageLoadError.tooLarge) { try await loader.download(url) }
    }

    @Test("a declared length over the cap is refused before the body")
    func declaredCap() async {
        let url = MockImageProtocol.stub(.init(contentLength: 9 * 1024 * 1024, chunks: [Data(count: 10)]))
        await #expect(throws: MarkdownImageLoadError.tooLarge) { try await loader.download(url) }
    }

    @Test("a smaller cap is honoured")
    func customCap() async {
        let small = MarkdownImageLoader(protocolClasses: [MockImageProtocol.self], byteCap: 100)
        let url = MockImageProtocol.stub(.init(chunks: [Data(count: 60), Data(count: 60)]))
        await #expect(throws: MarkdownImageLoadError.tooLarge) { try await small.download(url) }
    }

    @Test("a non-image MIME type is rejected", arguments: ["text/html", "application/json", nil] as [String?])
    func notAnImage(contentType: String?) async {
        let url = MockImageProtocol.stub(.init(contentType: contentType, chunks: [Data("<html>".utf8)]))
        await #expect(throws: MarkdownImageLoadError.notAnImage) { try await loader.download(url) }
    }

    @Test("an HTTP error status is rejected")
    func badStatus() async {
        let url = MockImageProtocol.stub(.init(status: 404, chunks: [Data("nope".utf8)]))
        await #expect(throws: MarkdownImageLoadError.badStatus(404)) { try await loader.download(url) }
    }

    @Test("a timeout maps to timedOut, other failures to failed")
    func errors() async {
        let timedOut = MockImageProtocol.stub(.init(error: URLError(.timedOut)))
        await #expect(throws: MarkdownImageLoadError.timedOut) { try await loader.download(timedOut) }
        let offline = MockImageProtocol.stub(.init(error: URLError(.notConnectedToInternet)))
        await #expect(throws: MarkdownImageLoadError.failed) { try await loader.download(offline) }
    }

    @Test("a data: URL loads without the network")
    func dataURL() async throws {
        let source = "data:image/png;base64," + Self.png(width: 40, height: 20).base64EncodedString()
        let image = try await loader.load(URL(string: source)!, maxPixelWidth: 900)
        #expect(image.cgImage.width == 40)
    }

    @Test("downsampling bounds the pixel size and never upscales")
    func downsample() throws {
        let big = try MarkdownImageLoader.downsample(Self.png(width: 4000, height: 3000), maxPixelWidth: 600)
        #expect(big.cgImage.width <= 600)
        #expect(big.cgImage.height <= 450)
        let tall = try MarkdownImageLoader.downsample(Self.png(width: 100, height: 20000), maxPixelWidth: 1000)
        #expect(tall.cgImage.height <= MarkdownImageLoader.maximumPixelDimension)
        let small = try MarkdownImageLoader.downsample(Self.png(width: 50, height: 50), maxPixelWidth: 1000)
        #expect(small.cgImage.width == 50)
        #expect(throws: MarkdownImageLoadError.undecodable) {
            try MarkdownImageLoader.downsample(Data("not an image".utf8), maxPixelWidth: 100)
        }
    }
}

/// Answers every https request with a redirect to the same path over plain http.
final class DowngradeProtocol: URLProtocol, @unchecked Sendable {
    static let requested = Mutex<[String]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.requested.withLock { $0.append(url.absoluteString) }
        if url.scheme == "https" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.scheme = "http"
            let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": components.url!.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: components.url!), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MarkdownImageLoaderTests.png(width: 4, height: 4))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("MarkdownImageLoader: the session")
struct MarkdownImageSessionTests {
    @Test("remembers and sends nothing of the user's: no cookies, credentials or cache")
    func configuration() {
        let configuration = MarkdownImageLoader.sessionConfiguration()
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("an https image may not be redirected to plain http")
    func noDowngrade() async throws {
        let loader = MarkdownImageLoader(protocolClasses: [DowngradeProtocol.self])
        let url = URL(string: "https://\(UUID().uuidString.lowercased()).test/a.png")!
        await #expect(throws: MarkdownImageLoadError.self) { try await loader.download(url) }
        let followed = DowngradeProtocol.requested.withLock { $0 }.filter { $0.hasPrefix("http://") && $0.contains(url.host()!) }
        #expect(followed.isEmpty)
    }
}
