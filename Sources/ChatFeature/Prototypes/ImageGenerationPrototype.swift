#if DEBUG
import Models
import SwiftUI
import UIKit

/// The image generation card is real now: this group draws `ImageGenerationCard` from `ToolCard`s built the way the
/// transcript builds them (the running one from a pending call), with a stand-in loader serving drawn images.
/// `-CardPrototypesImageViewer` opens the full-screen viewer on launch.
struct ProtoImageGenerationSection: View {
    @State private var loader: GeneratedImageLoader?
    @State private var viewer: ImageViewerPage.Content?
    @State private var inline = ""

    private static let opensViewer = ProcessInfo.processInfo.arguments.contains("-CardPrototypesImageViewer")

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            UserBubble(text: ProtoFixtures.imagePrompt)
            if loader != nil {
                states
            }
        }
        .environment(\.generatedImageLoader, loader)
        .task { prepare() }
        .fullScreenCover(item: $viewer) { page in
            ImageViewer(pages: [page], start: page.id)
        }
    }

    @ViewBuilder
    private var states: some View {
        ProtoInReply(state: "Running (the dither field; still with Reduce Motion)") {
            Self.cards([Self.call("k1")]).environment(\.toolCardsAreLive, true)
        }
        ProtoInReply(state: "Finished; its image still on the way (refining)") {
            Self.cards([Self.call("k2"), Self.result("k2", ProtoFixtures.imageDetails(["slow.png"]))])
        }
        ProtoInReply(state: "Done · one image, 1024 × 1536 (tap to open)", header: "Worked for 18 sec") {
            Self.cards([Self.call("k3"), Self.result("k3", ProtoFixtures.imageDetails(["a.png"]))])
        }
        ProtoInReply(state: "Done · two square images") {
            Self.cards([
                Self.call("k4"),
                Self.result("k4", ProtoFixtures.imageDetails(["b.png", "c.png"], size: "1024x1024", width: 1024, height: 1024)),
            ])
        }
        ProtoInReply(state: "Legacy row: a data: URL") {
            Self.cards([Self.call("k5"), Self.result("k5", #"{"images":[{"url":"\#(inline)"}]}"#)])
        }
        ProtoInReply(state: "Legacy row: a DALL·E link (tap to load; it has expired)") {
            Self.cards([
                Self.call("k6"), Self.result("k6", #"{"images":[{"url":"https://oaidalleapiprodscus.invalid/img-1.png?sig=x"}]}"#),
            ])
        }
        ProtoInReply(state: "Gone on the computer (404) → unavailable") {
            Self.cards([Self.call("k7"), Self.result("k7", ProtoFixtures.imageDetails(["gone.png"]))])
        }
        ProtoInReply(state: "No connection → retry") {
            Self.cards([Self.call("k8"), Self.result("k8", ProtoFixtures.imageDetails(["offline.png"]))])
        }
        ProtoInReply(state: "Stopped before the image came") {
            Self.cards([Self.call("k9")])
        }
        ProtoInReply(state: "Tool error") {
            Self.cards([
                Self.call("k10"),
                Self.message(
                    #"{"id":"t-k10","runId":"u","role":"toolResult","toolCallId":"k10","toolName":"image_generation","content":[{"type":"text","text":"\#(ProtoFixtures.imageError)"}],"details":null,"isError":true,"timestamp":3}"#
                ),
            ])
        }
    }

    private static func cards(_ messages: [ChatMessage]) -> some View {
        var cache = RunGrouper.Cache()
        let segments = RunGrouper.group(
            [message(#"{"id":"u","runId":"u","role":"user","content":"draw","timestamp":1}"#)] + messages, cache: &cache)
        let cards = segments.flatMap { segment -> [ToolCard] in
            if case .assistantTurn(let turn) = segment { turn.toolCards } else { [] }
        }
        return VStack(alignment: .leading) {
            ForEach(cards, id: \.renderKey) { ToolCardView(card: $0) }
        }
    }

    private static func call(_ id: String) -> ChatMessage {
        message(
            #"{"id":"a-\#(id)","runId":"u","role":"assistant","content":[{"type":"toolCall","id":"\#(id)","name":"image_generation","arguments":{"prompt":"\#(ProtoFixtures.imagePrompt)"}}],"stopReason":"toolUse","timestamp":2}"#
        )
    }

    private static func result(_ id: String, _ details: String) -> ChatMessage {
        message(
            #"{"id":"t-\#(id)","runId":"u","role":"toolResult","toolCallId":"\#(id)","toolName":"image_generation","content":[{"type":"text","text":"ok"}],"details":\#(details),"isError":false,"timestamp":3}"#
        )
    }

    private static func message(_ json: String) -> ChatMessage {
        try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    }

    private func prepare() {
        guard loader == nil else { return }
        let portrait = Self.render(seed: 0, size: CGSize(width: 512, height: 768))
        let square = Self.render(seed: 1, size: CGSize(width: 512, height: 512))
        let warm = Self.render(seed: 2, size: CGSize(width: 384, height: 384))
        inline = "data:image/png;base64,\(warm.base64EncodedString())"
        loader = GeneratedImageLoader(
            fetchMedia: { path in
                if path.hasSuffix("gone.png") { throw HTTPError(statusCode: 404, code: "NOT_FOUND", message: "") }
                if path.hasSuffix("offline.png") { throw URLError(.notConnectedToInternet) }
                if path.hasSuffix("slow.png") { try await Task.sleep(for: .seconds(3600)) }
                if path.hasSuffix("b.png") { return square }
                return path.hasSuffix("c.png") ? warm : portrait
            },
            fetchRemote: { _ in throw URLError(.fileDoesNotExist) }, cache: GeneratedImageCache())
        if Self.opensViewer, let image = UIImage(data: portrait) {
            viewer = ImageViewerPage.Content(id: 0, image: image, caption: ProtoFixtures.imageRevised)
        }
    }

    private static func render(seed: Int, size: CGSize) -> Data {
        let renderer = ImageRenderer(content: ProtoPoster(seed: seed).frame(width: size.width, height: size.height))
        renderer.scale = 1
        return renderer.uiImage?.pngData() ?? Data()
    }
}

/// A drawn "generated image": a gradient sky, a sun, a hill and a lighthouse.
private struct ProtoPoster: View {
    let seed: Int

    var body: some View {
        let colors: [Color] =
            switch seed % 3 {
            case 0: [.orange, .pink, .purple]
            case 1: [.teal, .blue, .indigo]
            default: [.yellow, .orange, .red]
            }
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: size.width * 0.28)
                    .position(x: size.width * 0.7, y: size.height * 0.4)
                Ellipse()
                    .fill(Color(red: 0.12, green: 0.35, blue: 0.2))
                    .frame(width: size.width * 1.6, height: size.height * 0.4)
                    .position(x: size.width * 0.3, y: size.height * 0.95)
                Rectangle()
                    .fill(.white)
                    .frame(width: size.width * 0.07, height: size.height * 0.28)
                    .position(x: size.width * 0.25, y: size.height * 0.66)
            }
        }
    }
}
#endif
