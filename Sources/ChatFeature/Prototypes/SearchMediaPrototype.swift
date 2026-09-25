#if DEBUG
import Models
import SwiftUI
import UIKit

/// The search media foot is real: this group draws `RunFootView(.media)` from a turn the grouper built out of a
/// desktop-shaped `web_search` result, with a stand-in loader serving drawn images. `-CardPrototypesMediaViewer` opens
/// the viewer on launch.
struct ProtoSearchMediaSection: View {
    @State private var loader: SearchMediaLoader?
    @State private var viewer: ImageViewerPage?

    private static let opensViewer = ProcessInfo.processInfo.arguments.contains("-CardPrototypesMediaViewer")

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            UserBubble(text: "Show me the Northern Lights over Tromsø")
            if loader != nil {
                ProtoInReply(state: "Six images and three videos (tap an image; a video opens the browser)") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verbatim: "The aurora is strongest over Tromsø between September and March, on clear nights away from the city lights.")
                        RunFootView(foot: Self.foot(), section: .media)
                    }
                }
                ProtoInReply(state: "One image from a host the run's results did not carry (waits for a tap); one that fails") {
                    RunFootView(foot: Self.foot(trustedHost: "pages.example", count: 2), section: .media)
                }
            }
        }
        .environment(\.searchMediaLoader, loader ?? .shared)
        .task { prepare() }
        .fullScreenCover(item: $viewer) { page in
            ImageViewer(pages: Self.pages, start: page.id)
                .environment(\.searchMediaLoader, loader ?? .shared)
        }
    }

    private static func foot(trustedHost: String? = nil, count: Int = 6) -> RunFoot {
        let images = (0..<count).map { index in
            let host = index == 0 && trustedHost != nil ? "tracker.example" : "pages.example"  // l10n:ignore: fixture URLs
            let title = ["Aurora over the fjord", "Green curtains above Tromsø", "Lights over the cathedral", "Kvaløya beach at night", "Reflections in the harbour", "Aurora corona"][index]
            let thumb = index == 1 && trustedHost != nil ? "https://pages.example/broken.jpg" : "https://\(host)/thumb/\(index).jpg"  // l10n:ignore: fixture URLs
            return #"{"kind":"image","title":"\#(title)","url":"https://pages.example/full/\#(index).jpg","thumbnailUrl":"\#(thumb)","sourceUrl":"https://pages.example/article/\#(index)","source":"visitnorway.example"}"#
        }
        let videos = trustedHost != nil ? [] : [
            #"{"kind":"video","title":"Northern Lights in real time — Tromsø, Norway (4K)","url":"https://www.youtube.com/watch?v=aurora1","sourceUrl":"https://www.youtube.com/watch?v=aurora1","thumbnailUrl":"https://pages.example/video/0.jpg","duration":"12:34","creator":"Arctic Skies","views":1284000,"publisher":"YouTube"}"#,
            #"{"kind":"video","title":"How to photograph the aurora","url":"https://vimeo.example/2","sourceUrl":"https://vimeo.example/2","thumbnailUrl":"https://pages.example/video/1.jpg","duration":"8:02","source":"Vimeo","views":5400}"#,
            #"{"kind":"video","title":"Tromsø aurora forecast explained","url":"https://www.youtube.com/watch?v=aurora3","sourceUrl":"https://www.youtube.com/watch?v=aurora3","duration":"3:15","creator":"NRK"}"#,
        ]
        let details = #"[{"rank":1,"link":"https://pages.example/article","title":"Aurora","snippet":"a","media":[\#((images + videos).joined(separator: ","))]}]"#
        let messages = [
            #"{"id":"u","runId":"u","role":"user","content":"q","timestamp":1}"#,
            #"{"id":"t","runId":"u","role":"toolResult","toolCallId":"k","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":\#(details),"isError":false,"timestamp":3}"#,
        ].map { try! JSONDecoder().decode(ChatMessage.self, from: Data($0.utf8)) }
        var cache = RunGrouper.Cache()
        let turn = RunGrouper.group(messages, cache: &cache).compactMap { segment -> AssistantTurn? in
            if case .assistantTurn(let turn) = segment { turn } else { nil }
        }.first
        var foot = turn?.foot ?? RunFoot()
        if let trustedHost { foot.gallery.trustedURLs = foot.gallery.trustedURLs.filter { $0.host() == trustedHost } }
        return foot
    }

    private static var pages: [ImageViewerPage.Content] {
        foot().gallery.images.enumerated().map { index, picture in
            ImageViewerPage.Content(id: index, source: .search(picture), caption: picture.title, link: picture.sourceURL)
        }
    }

    private func prepare() {
        guard loader == nil else { return }
        let posters = (0..<8).map { Self.render(seed: $0) }
        loader = SearchMediaLoader(
            fetch: { url in
                let path = url.path()
                if path.contains("broken") { throw URLError(.notConnectedToInternet) }
                // The full image of #2 is gone: the viewer keeps its thumbnail and says so.
                if path.hasSuffix("full/2.jpg") { throw URLError(.fileDoesNotExist) }
                let digit = path.last(where: \.isNumber).flatMap { Int(String($0)) } ?? 0
                return posters[(digit + (path.contains("video") ? 3 : 0)) % posters.count]
            }, cache: SearchMediaCache())
        if Self.opensViewer { viewer = ImageViewerPage(id: 0) }
    }

    private static func render(seed: Int) -> Data {
        let colors: [[Color]] = [
            [.indigo, .teal, .green], [.black, .indigo, .mint], [.purple, .blue, .green], [.blue, .cyan, .mint],
            [.black, .purple, .pink], [.indigo, .green, .yellow], [.teal, .blue, .black], [.purple, .mint, .black],
        ]
        let view = ZStack {
            LinearGradient(colors: colors[seed % colors.count], startPoint: .top, endPoint: .bottom)
            Ellipse()
                .fill(Color.black.opacity(0.85))
                .frame(width: 900, height: 220)
                .offset(y: 230)
        }
        .frame(width: 640, height: 426)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage?.jpegData(compressionQuality: 0.85) ?? Data()
    }
}
#endif
