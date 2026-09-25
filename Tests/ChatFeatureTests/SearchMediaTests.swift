import Foundation
import ImageIO
import UniformTypeIdentifiers
import MarkdownKit
import Models
import Synchronization
import SwiftUI
import Testing
import UIKit

@testable import ChatFeature

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func value(_ json: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private func searchResult(_ id: String, _ run: String, _ details: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"toolResult","toolCallId":"k-\#(id)","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":\#(details),"isError":false,"timestamp":3}"#
    )
}

private func user(_ id: String) -> ChatMessage {
    decode(#"{"id":"\#(id)","runId":"\#(id)","role":"user","content":"q","timestamp":1}"#)
}

private func answer(_ id: String, _ run: String, _ text: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"assistant","content":[{"type":"text","text":"\#(text)"}],"stopReason":"stop","timestamp":4}"#
    )
}

private func turn(_ messages: [ChatMessage]) -> AssistantTurn? {
    var cache = RunGrouper.Cache()
    return RunGrouper.group(messages, cache: &cache).compactMap { segment -> AssistantTurn? in
        if case .assistantTurn(let turn) = segment { turn } else { nil }
    }.first
}

private func media(_ items: [String]) -> [WebSearchMedia] {
    items.compactMap { WebSearchMedia(json: value($0)) }
}

private func image(_ url: String, thumb: String? = nil, title: String = "I") -> String {
    let thumbnail = thumb.map { #","thumbnailUrl":"\#($0)""# } ?? ""
    return #"{"kind":"image","title":"\#(title)","url":"\#(url)","sourceUrl":"https://pages.example/a"\#(thumbnail)}"#
}

private func video(_ url: String, thumb: String? = nil) -> String {
    let thumbnail = thumb.map { #","thumbnailUrl":"\#($0)""# } ?? ""
    return #"{"kind":"video","title":"V","url":"\#(url)","sourceUrl":"\#(url)","duration":"12:34","creator":"Chan","views":4500000\#(thumbnail)}"#
}

func searchPNG(width: Int = 1200, height: Int = 800) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

private let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>"#.utf8)
private let pdf = Data("%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF".utf8)

@Suite("Search media: what a run's results give the foot")
struct SearchGalleryTests {
    @Test("images and videos by kind, in result order, de-duplicated by URL; the thumbnail falls back to the image")
    func extraction() {
        let items = media([
            image("https://a.example/1.jpg", thumb: "https://imgs.search.example/t1"),
            video("https://www.youtube.com/watch?v=1", thumb: "https://i.ytimg.example/1.jpg"),
            image("https://b.example/2.png"),
            image("https://a.example/1.jpg", thumb: "https://imgs.search.example/other"),
            video("https://www.youtube.com/watch?v=1"),
            video("https://vimeo.example/2"),
        ])
        let gallery = SearchGallery(media: items)
        #expect(gallery.images.map(\.preview.absoluteString) == ["https://imgs.search.example/t1", "https://b.example/2.png"])
        #expect(gallery.images.map { $0.url?.absoluteString } == ["https://a.example/1.jpg", "https://b.example/2.png"])
        #expect(gallery.images.first?.sourceURL?.absoluteString == "https://pages.example/a")
        #expect(gallery.videos.map(\.url.absoluteString) == ["https://www.youtube.com/watch?v=1", "https://vimeo.example/2"])
        #expect(gallery.videos.first?.thumbnail?.absoluteString == "https://i.ytimg.example/1.jpg")
        #expect(gallery.videos.last?.thumbnail == nil)
    }

    @Test("capped: 24 images and 12 videos at most")
    func caps() {
        let images = (0..<40).map { image("https://a.example/\($0).jpg") }
        let videos = (0..<20).map { video("https://v.example/\($0)") }
        let gallery = SearchGallery(media: media(images + videos))
        #expect(gallery.images.count == SearchGallery.imageCap)
        #expect(SearchGallery.imageCap == 24)
        #expect(gallery.videos.count == SearchGallery.videoCap)
        #expect(SearchGallery.videoCap == 12)
        #expect(gallery.images.last?.url?.absoluteString == "https://a.example/23.jpg")
    }

    @Test("https only: an image with nothing fetchable over https is dropped; a video that no link may open is dropped")
    func httpsOnly() {
        let gallery = SearchGallery(media: media([
                image("http://plain.example/1.jpg"),
                image("http://plain.example/2.jpg", thumb: "https://imgs.search.example/2"),
                image("https://user:pw@creds.example/3.jpg"),
                image("ftp://files.example/4.jpg"),
                video("javascript:alert(1)"),
                video("https://v.example/ok", thumb: "http://plain.example/thumb.jpg"),
            ]))
        #expect(gallery.images.map(\.preview.absoluteString) == ["https://imgs.search.example/2"])
        #expect(gallery.images.first?.url == nil)
        #expect(gallery.videos.map(\.url.absoluteString) == ["https://v.example/ok"])
        #expect(gallery.videos.first?.thumbnail == nil)
        #expect(SearchMediaPolicy.fetchableURL("http://a.example/x.png") == nil)
        #expect(SearchMediaPolicy.fetchableURL("https://a.example/x.png") != nil)
        #expect(SearchMediaPolicy.fetchableURL("https:///x.png") == nil)
    }

    @Test("the grouper builds the gallery with the turn, from every search of the run")
    func builtWithTheTurn() throws {
        let first =
            #"[{"rank":1,"link":"https://Pages.Example/a","title":"A","snippet":"a","media":[\#(image("https://a.example/1.jpg"))]}]"#
        let second =
            #"[{"rank":1,"link":"https://other.example/b","hostname":"news.example","title":"B","snippet":"b","media":[\#(image("https://a.example/1.jpg")),\#(video("https://v.example/1"))]}]"#
        let built = try #require(
            turn([user("u1"), searchResult("s1", "u1", first), searchResult("s2", "u1", second), answer("a1", "u1", "Hi")]))
        #expect(built.foot.gallery.images.count == 1)
        #expect(built.foot.gallery.videos.count == 1)
        #expect(built.foot.gallery.trustedURLs == [URL(string: "https://a.example/1.jpg")!])
        #expect(try #require(turn([user("u2"), answer("a2", "u2", "Hi")])).foot.gallery.isEmpty)
    }
}

@Suite("Search media: which images load without a tap")
struct SearchMediaPolicyTests {
    private let trusted: Set<URL> = [URL(string: "https://imgs.search.example/t1")!, URL(string: "https://pages.example/x.png")!]

    @Test("a URL the run's own results returned loads; any other URL waits for a tap, same host or not; plain http never")
    func urlRule() throws {
        let exact = try #require(URL(string: "https://imgs.search.example/t1"))
        #expect(SearchMediaPolicy.decision(for: exact, trustedURLs: trusted) == .load(exact))
        let sibling = try #require(URL(string: "https://imgs.search.example/t2"))
        #expect(SearchMediaPolicy.decision(for: sibling, trustedURLs: trusted) == .askToLoad(sibling, host: "imgs.search.example"))
        let foreign = try #require(URL(string: "https://tracker.example/pixel.png"))
        #expect(SearchMediaPolicy.decision(for: foreign, trustedURLs: trusted) == .askToLoad(foreign, host: "tracker.example"))
        let plain = try #require(URL(string: "http://pages.example/x.png"))
        #expect(SearchMediaPolicy.decision(for: plain, trustedURLs: trusted) == .refused)
        let creds = try #require(URL(string: "https://me:secret@pages.example/x.png"))
        #expect(SearchMediaPolicy.decision(for: creds, trustedURLs: trusted) == .refused)
    }

    @Test("the trusted set is the media's own image and thumbnail URLs: never a page, a source link or a web_fetch")
    func trustedURLs() throws {
        let item = image("https://cdn.example/1.jpg", thumb: "https://imgs.search.example/t")
        let gallery = SearchGallery(media: media([item, image("http://plain.example/2.jpg")]))
        #expect(
            gallery.trustedURLs == [URL(string: "https://cdn.example/1.jpg")!, URL(string: "https://imgs.search.example/t")!])
        let fetched = #"{"rank":2,"link":"https://fetched.example/page","title":"F","snippet":"f"}"#
        let run = [
            user("u1"),
            searchResult(
                "s1", "u1", #"[{"rank":1,"link":"https://pages.example/a","title":"A","snippet":"a","media":[\#(item)]}]"#),
            decode(
                #"{"id":"f1","runId":"u1","role":"toolResult","toolCallId":"kf","toolName":"web_fetch","content":[{"type":"text","text":"ok"}],"details":\#(fetched),"isError":false,"timestamp":3}"#),
            answer("a1", "u1", "Hi"),
        ]
        let built = try #require(turn(run))
        #expect(built.sources.map(\.link).contains("https://fetched.example/page"))
        #expect(built.foot.gallery.trustedURLs == [URL(string: "https://cdn.example/1.jpg")!, URL(string: "https://imgs.search.example/t")!])
    }

    @Test("raster formats only: PNG and JPEG decode, SVG, PDF and HTML never do")
    func rasterOnly() throws {
        #expect(SearchMediaPolicy.isRaster(searchPNG(width: 4, height: 4)))
        let jpeg = try #require(UIImage(data: searchPNG(width: 4, height: 4))?.jpegData(compressionQuality: 0.8))
        #expect(SearchMediaPolicy.isRaster(jpeg))
        #expect(!SearchMediaPolicy.isRaster(svg))
        #expect(!SearchMediaPolicy.isRaster(pdf))
        #expect(!SearchMediaPolicy.isRaster(Data("<html><img src=x></html>".utf8)))
        #expect(!SearchMediaPolicy.isRaster(Data()))
        let tiff = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(tiff, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(UIImage(data: searchPNG(width: 4, height: 4))?.cgImage), nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(!SearchMediaPolicy.isRaster(tiff as Data))
    }
}

/// Records every request the loader's own session sends: the URL and the headers a paired request would carry.
final class SearchImageProtocol: URLProtocol, @unchecked Sendable {
    struct Seen: Sendable {
        let url: String
        let authorization: String?
        let cookie: String?
    }

    static let seen = Mutex<[Seen]>([])
    static let bodies = Mutex<[String: (type: String, data: Data)]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.seen.withLock {
            $0.append(
                Seen(
                    url: url.absoluteString, authorization: request.value(forHTTPHeaderField: "Authorization"),
                    cookie: request.value(forHTTPHeaderField: "Cookie")))
        }
        let body = Self.bodies.withLock { $0[url.host() ?? ""] } ?? ("image/png", searchPNG())
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": body.type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Search media: the loader", .serialized)
struct SearchMediaLoaderTests {
    @Test("the session sends no token and no cookie, even with a cookie stored for that host, and keeps nothing")
    func neverThePairedSession() async throws {
        let host = "\(UUID().uuidString.lowercased()).example"
        let cookie = try #require(
            HTTPCookie(properties: [.domain: host, .path: "/", .name: "session", .value: "abc", .secure: "TRUE"]))
        HTTPCookieStorage.shared.setCookie(cookie)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        let loader = SearchMediaLoader(loader: MarkdownImageLoader(protocolClasses: [SearchImageProtocol.self]))
        let url = try #require(URL(string: "https://\(host)/photo.png"))
        let image = try await loader.load(url, maxPixelSize: 300)
        #expect(image.size.width <= 360)
        let seen = SearchImageProtocol.seen.withLock { $0 }.filter { $0.url == url.absoluteString }
        #expect(seen.count == 1)
        #expect(seen.first?.authorization == nil)
        #expect(seen.first?.cookie == nil)

        let configuration = MarkdownImageLoader.sessionConfiguration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.httpAdditionalHeaders == nil)
    }

    @Test("plain http is refused before any request")
    func refusesHTTP() async throws {
        let fetched = Mutex(0)
        let loader = SearchMediaLoader(
            fetch: { _ in
                fetched.withLock { $0 += 1 }
                return searchPNG()
            }, cache: SearchMediaCache())
        let url = try #require(URL(string: "http://pages.example/x.png"))
        await #expect(throws: SearchMediaLoader.Failure.refused) { try await loader.load(url, maxPixelSize: 300) }
        #expect(fetched.withLock { $0 } == 0)
    }

    @Test("an SVG served as an image is refused; a PNG is downsampled under the cap and then served from memory")
    func rasterAndCache() async throws {
        let fetched = Mutex(0)
        let loader = SearchMediaLoader(
            fetch: { url in
                fetched.withLock { $0 += 1 }
                return url.path().hasSuffix(".svg") ? svg : searchPNG(width: 4000, height: 3000)
            }, cache: SearchMediaCache())
        let vector = try #require(URL(string: "https://pages.example/x.svg"))
        await #expect(throws: SearchMediaLoader.Failure.notRaster) { try await loader.load(vector, maxPixelSize: 300) }
        let photo = try #require(URL(string: "https://pages.example/x.png"))
        let image = try await loader.load(photo, maxPixelSize: 9000)
        #expect(image.size.width <= CGFloat(SearchMediaLoader.fullPixelCap))
        let again = try await loader.load(photo, maxPixelSize: 9000)
        #expect(again === image)
        #expect(loader.cached(photo, maxPixelSize: 9000) === image)
        #expect(fetched.withLock { $0 } == 2)
    }

    @Test("a failed download is a failure; cancellation is rethrown")
    func failures() async throws {
        let url = try #require(URL(string: "https://pages.example/x.png"))
        let failing = SearchMediaLoader(fetch: { _ in throw URLError(.notConnectedToInternet) }, cache: SearchMediaCache())
        await #expect(throws: SearchMediaLoader.Failure.failed) { try await failing.load(url, maxPixelSize: 300) }
        let cancelled = SearchMediaLoader(fetch: { _ in throw URLError(.cancelled) }, cache: SearchMediaCache())
        await #expect(throws: CancellationError.self) { try await cancelled.load(url, maxPixelSize: 300) }
    }
}

@MainActor
@Suite("Search media: drawn at the run foot")
struct SearchMediaRenderTests {
    private static let details =
        #"[{"rank":1,"link":"https://pages.example/a","title":"A","snippet":"a","media":[\#(image("https://pages.example/1.jpg", title: "One")),\#(image("https://pages.example/2.jpg", title: "Two")),\#(image("https://tracker.example/3.png", title: "Three")),\#(image("https://pages.example/4.jpg")),\#(video("https://v.example/1", thumb: "https://pages.example/v1.jpg"))]}]"#

    @Test("a settled turn with media is not rebuilt while a later turn streams, and its view compares equal")
    func renderGuard() throws {
        let settled = [user("u1"), searchResult("s1", "u1", Self.details), answer("a1", "u1", "Done"), user("u2")]
        var cache = RunGrouper.Cache()
        let first = RunGrouper.group(settled + [answer("b1", "u2", "S")], cache: &cache)
        let built = cache.builtTurnCount
        var last = first
        for text in ["St", "Str", "Stre"] {
            last = RunGrouper.group(settled + [answer("b1", "u2", text)], cache: &cache)
        }
        #expect(cache.builtTurnCount == built + 3)
        let before = try #require(first.compactMap { if case .assistantTurn(let t) = $0 { t } else { nil } }.first)
        let after = try #require(last.compactMap { if case .assistantTurn(let t) = $0 { t } else { nil } }.first)
        #expect(before.foot.gallery.images.count == 4)
        #expect(before.foot.gallery == after.foot.gallery)
        #expect(
            AssistantTurnView(turn: before, isStreaming: false, error: nil)
                == AssistantTurnView(turn: after, isStreaming: false, error: nil, regenerate: { print("new") }))
    }

    private func draw(_ foot: RunFoot) async throws -> [String] {
        let fetched = Mutex<[String]>([])
        let loader = SearchMediaLoader(
            fetch: { url in
                fetched.withLock { $0.append(url.absoluteString) }
                return searchPNG(width: 64, height: 48)
            }, cache: SearchMediaCache())
        let root = VStack { RunFootView(foot: foot, section: .media) }
            .environment(\.searchMediaLoader, loader)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        window.isHidden = true
        return fetched.withLock { $0 }
    }

    @Test("the grid fetches the three thumbnails it shows and the video's, once each, all from the run's own results")
    func hostedGrid() async throws {
        let built = try #require(turn([user("u1"), searchResult("s1", "u1", Self.details), answer("a1", "u1", "Done")]))
        let urls = try await draw(built.foot)
        #expect(
            Set(urls) == [
                "https://pages.example/1.jpg", "https://pages.example/2.jpg", "https://tracker.example/3.png",
                "https://pages.example/v1.jpg",
            ])
        #expect(urls.count == 4)
    }

    @Test("a thumbnail outside the trusted set is not fetched until tapped")
    func hostedForeignHost() async throws {
        var foot = try #require(turn([user("u1"), searchResult("s1", "u1", Self.details), answer("a1", "u1", "Done")])).foot
        foot.gallery.trustedURLs = foot.gallery.trustedURLs.filter { $0.host() == "pages.example" }
        let urls = try await draw(foot)
        #expect(!urls.contains("https://tracker.example/3.png"))
        #expect(urls.contains("https://pages.example/1.jpg"))
    }

    @Test("a video's line: the channel, else the site, then compact views")
    func videoMeta() {
        let gallery = SearchGallery(media: media([video("https://v.example/1")]))
        let meta = SearchVideoCards.meta(gallery.videos[0])
        #expect(meta?.hasPrefix("Chan · ") == true)
        #expect(meta?.hasSuffix(" views") == true)
        #expect(SearchMediaText.video("Cats") == "Video: Cats")
        #expect(SearchMediaText.showAll(8) == "Show all 8 images")
    }
}
