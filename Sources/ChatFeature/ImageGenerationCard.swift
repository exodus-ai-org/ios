import SwiftUI
import UIKit

extension EnvironmentValues {
    /// The turn these cards belong to is still streaming: a pending call is running, not stopped.
    @Entry var toolCardsAreLive = false
    /// How generated images are fetched; the chat screen gives one bound to its paired session.
    @Entry var generatedImageLoader: GeneratedImageLoader?
}

/// An `image_generation` call from the moment it is made, like the desktop's card: a dither field while it runs, the
/// image resolving out of a blur in the same frame when it lands, the error state when the tool failed. A finished
/// image opens full screen.
struct ImageGenerationCard: View {
    let model: ImageGenerationCardModel
    @State private var viewer: ImageViewerPage?
    @Environment(\.generatedImageLoader) private var loader

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.frames.count > 1 {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    frames
                }
            } else {
                frames.frame(maxWidth: 240)
            }
            if case .failed(let message?) = model.status {
                FileCardError(message: message, horizontalInset: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $viewer) { page in
            ImageViewer(pages: Self.viewerPages(model, tapped: page) { (loader?.cache ?? .shared).image(for: $0) }, start: page.id)
        }
    }

    private var frames: some View {
        ForEach(model.frames) { frame in
            GeneratedImageFrame(model: model, frame: frame) { viewer = ImageViewerPage(id: frame.id, image: $0) }
        }
    }

    /// Only images already in memory: the viewer never loads anything of its own. The tapped frame's own image stands
    /// in when memory pressure has evicted it from the cache, so the viewer never opens empty.
    nonisolated static func viewerPages(
        _ model: ImageGenerationCardModel, tapped: ImageViewerPage, cached: (GeneratedImageSource) -> UIImage?
    ) -> [ImageViewerPage.Content] {
        model.frames.compactMap { frame in
            let own = frame.id == tapped.id ? tapped.image : nil
            guard let source = frame.source, let image = cached(source) ?? own else { return nil }
            return ImageViewerPage.Content(
                id: frame.id, image: image, caption: frame.revisedPrompt ?? (model.prompt.isEmpty ? nil : model.prompt))
        }
    }
}

struct ImageViewerPage: Identifiable {
    struct Content: Identifiable {
        enum Source {
            /// Already in memory (a generated image).
            case ready(UIImage)
            /// A search image: fetched full size when the page shows, its grid thumbnail standing in meanwhile.
            case search(SearchGallery.Picture)
        }

        let id: Int
        let source: Source
        let caption: String?
        /// The page the image came from, opened in the browser.
        var link: URL?

        init(id: Int, image: UIImage, caption: String?) {
            self.init(id: id, source: .ready(image), caption: caption)
        }

        init(id: Int, source: Source, caption: String?, link: URL? = nil) {
            self.id = id
            self.source = source
            self.caption = caption
            self.link = link
        }
    }

    let id: Int
    /// The tapped image as its frame holds it (a generated image), for when the cache no longer has it.
    var image: UIImage?
}

/// One frame with its status line: the field while it forms, then the image (or why there is none).
struct GeneratedImageFrame: View {
    let model: ImageGenerationCardModel
    let frame: ImageGenerationCardModel.Frame
    let open: (UIImage?) -> Void

    @State private var image: UIImage?
    @State private var load = GeneratedImageLoadState.idle
    @State private var requested = false
    @State private var attempt = 0
    @Environment(\.toolCardsAreLive) private var isLive
    @Environment(\.generatedImageLoader) private var loader
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct LoadKey: Equatable {
        let source: GeneratedImageSource?
        let complete: Bool
        let requested: Bool
        let attempt: Int
    }

    private var status: ImageFrameStatus {
        ImageGenerationRules.frameStatus(
            card: model.status, isLive: isLive, source: frame.source, load: shown == nil ? load : .loaded,
            requested: requested)
    }

    /// The loaded image, or one another view already put in the cache (no flash of the field on a re-appearance).
    private var shown: UIImage? {
        if let image { return image }
        guard model.status == .complete, let source = frame.source else { return nil }
        return (loader?.cache ?? .shared).image(for: source)
    }

    var body: some View {
        let current = self.status
        VStack(alignment: .leading, spacing: 8) {
            canvas(current)
            statusLine(current)
        }
        .task(id: LoadKey(source: frame.source, complete: model.status == .complete, requested: requested, attempt: attempt)) {
            await fetch()
        }
    }

    /// The image resolving out of a blur, as on the desktop; only a fade with Reduce Motion.
    private var imageTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition(BlurReplaceTransition(configuration: .downUp)).combined(with: .scale(scale: 1.015))
    }

    private func canvas(_ status: ImageFrameStatus) -> some View {
        // The frame's shape is fixed first; the image fills and is cropped to it (the desktop's object-cover).
        Rectangle()
            .fill(.fill.tertiary)
            .aspectRatio(frame.aspectRatio, contentMode: .fit)
            .overlay {
                if let shown, status == .complete {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFill()
                        .transition(imageTransition)
                }
            }
            .overlay {
                if status.isActive {
                    ImageFormingField()
                        .opacity(status == .refining ? 0.7 : 1)
                        .transition(.opacity)
                }
            }
            .overlay { overlay(status) }
        .overlay(alignment: .topTrailing) {
            if let resolution = model.resolution, status != .complete {
                Text(verbatim: resolution)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: .capsule)
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.3), value: status)
        .contentShape(.rect)
        .onTapGesture { if status == .complete { open(shown) } }
        .accessibilityElement(children: status == .complete ? .ignore : .contain)
        .accessibilityLabel(accessibilityLabel(status))
        .accessibilityAddTraits(status == .complete ? [.isImage, .isButton] : .isImage)
        .accessibilityHint(status == .complete ? Text("ios:chat.card.image.openHint") : Text(verbatim: ""))
        .accessibilityAction { if status == .complete { open(shown) } }
    }

    @ViewBuilder
    private func overlay(_ status: ImageFrameStatus) -> some View {
        switch status {
        case .askToLoad(let host):
            VStack(spacing: 8) {
                Image(systemName: "photo").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(verbatim: host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Button("ios:chat.markdown.loadImage") { requested = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding()
        case .loadFailed:
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark").font(.title2).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Button("ios:chat.markdown.loadImageRetry") {
                    load = .idle
                    attempt += 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
        case .unavailable, .error:
            Image(systemName: status == .error ? "photo.badge.exclamationmark" : "photo")  // l10n:ignore: SF Symbol names
                .font(.title2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        default:
            EmptyView()
        }
    }

    private func statusLine(_ status: ImageFrameStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(verbatim: ImageGenerationText.status(status))
                    .contentTransition(.opacity)
            } icon: {
                statusIcon(status)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(status == .error ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            if !model.prompt.isEmpty {
                Text(ImageGenerationText.quotedPrompt(model.prompt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusIcon(_ status: ImageFrameStatus) -> some View {
        switch status {
        case .generating, .refining:
            Image(systemName: "square.grid.2x2.fill")
                .foregroundStyle(.tint)
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
        case .complete:
            Image(systemName: "checkmark").foregroundStyle(.tint)
        case .error:
            Image(systemName: "exclamationmark.circle")
        case .unavailable, .loadFailed, .askToLoad:
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
    }

    private func accessibilityLabel(_ status: ImageFrameStatus) -> Text {
        if status == .complete {
            let alt = frame.revisedPrompt ?? (model.prompt.isEmpty ? nil : model.prompt)
            return alt.map { Text(verbatim: $0) } ?? Text("chat:imageGeneration.generatedImageAlt")
        }
        let text = ImageGenerationText.status(status)
        return Text(verbatim: model.prompt.isEmpty ? text : ImageGenerationText.labelWithPrompt(status: text, prompt: model.prompt))
    }

    private func fetch() async {
        guard model.status == .complete, let source = frame.source, shown == nil else { return }
        if case .remote(_, _, true) = source, !requested { return }
        guard let loader else {
            load = .failed(.failed)
            return
        }
        load = .loading
        do {
            let loaded = try await loader.load(source)
            image = loaded
            load = .loaded
        } catch let failure as GeneratedImageLoader.Failure {
            load = .failed(failure)
        } catch {
            load = .idle
        }
    }
}

enum ImageGenerationText {
    static func status(_ status: ImageFrameStatus) -> String {
        switch status {
        case .generating:
            String(localized: "chat:imageGeneration.status.generating", defaultValue: "Generating image", comment: "Image card status.")
        case .refining:
            String(localized: "chat:imageGeneration.status.refining", defaultValue: "Refining details", comment: "Image card status.")
        case .complete, .askToLoad:
            String(localized: "chat:imageGeneration.status.complete", defaultValue: "Image ready", comment: "Image card status.")
        case .error:
            String(localized: "chat:imageGeneration.status.error", defaultValue: "Generation failed", comment: "Image card status.")
        case .unavailable, .loadFailed:
            String(localized: "chat:imageGeneration.status.unavailable", defaultValue: "Image unavailable", comment: "Image card status.")
        }
    }

    static var generatedImageAlt: String {
        String(localized: "chat:imageGeneration.generatedImageAlt", defaultValue: "Generated image", comment: "A generated image with no prompt.")
    }

    static func quotedPrompt(_ prompt: String) -> String {
        String(localized: "chat:imageGeneration.quotedPrompt", defaultValue: "“\(prompt)”", comment: "An image's prompt, quoted.")
    }

    static func labelWithPrompt(status: String, prompt: String) -> String {
        String(
            localized: "chat:imageGeneration.labelWithPrompt", defaultValue: "\(status): \(prompt)",
            comment: "VoiceOver label of a generated image frame: its status, then its prompt.")
    }
}

/// The desktop's dither field, drawn by the `imageForming` Metal shader over the tone. Runs at up to 30 fps while it is
/// on screen; with Reduce Motion it is one still frame (the status line says what is happening).
struct ImageFormingField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isVisible)) { context in
            let time = reduceMotion ? 0 : Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
            field(time: time)
        }
        .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func field(time: Float) -> some View {
        if let library = ImageFormingShader.library {
            Rectangle()
                .fill(.tint)
                .visualEffect { content, proxy in
                    content.colorEffect(library.imageForming(.float2(proxy.size), .float(time)))
                }
        } else {
            LinearGradient(colors: [.accentColor.opacity(0.22), .accentColor.opacity(0.06)], startPoint: .top, endPoint: .bottom)
        }
    }
}

enum ImageFormingShader {
    private final class Marker {}

    /// Tuist builds ChatFeature's `.metal` into the `ExodusIos_ChatFeature` resource bundle, copied into the app. Looked
    /// up by hand (not `Bundle.module`, which traps when the bundle is missing): no bundle, no shader, a plain wash.
    static let library: ShaderLibrary? = {
        let name = "ExodusIos_ChatFeature.bundle"
        for base in [Bundle.main.resourceURL, Bundle(for: Marker.self).resourceURL] {
            guard let url = base?.appendingPathComponent(name), let bundle = Bundle(url: url),
                bundle.url(forResource: "default", withExtension: "metallib") != nil
            else { continue }
            return ShaderLibrary.bundle(bundle)
        }
        return nil
    }()
}

/// Full screen: pinch or double-tap to zoom, swipe between images, the caption (a generated image's revised prompt)
/// or the source page's link (a search image), Share (which also saves to Photos) for an image already in memory.
struct ImageViewer: View {
    let pages: [ImageViewerPage.Content]
    @State private var selection: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(pages: [ImageViewerPage.Content], start: Int) {
        self.pages = pages
        _selection = State(initialValue: Self.startSelection(pages.map(\.id), start: start))
    }

    /// The tapped page from the first frame (never page one first, then a jump); the first page when it is gone.
    nonisolated static func startSelection(_ ids: [Int], start: Int) -> Int {
        ids.contains(start) ? start : ids.first ?? start
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(pages) { page in
                    VStack(spacing: 12) {
                        switch page.source {
                        case .ready(let image):
                            ZoomableImage(image: image, label: page.caption)
                        case .search(let picture):
                            SearchViewerImage(picture: picture)
                        }
                        if let link = page.link {
                            sourceLink(link, title: page.caption)
                        } else if let caption = page.caption {
                            ScrollView {
                                Text(verbatim: caption)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 120)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding()
                    .padding(.bottom, pages.count > 1 ? 28 : 0)
                    .tag(page.id)
                }
            }
            // The system dots are white, and all but lost on the light background; these follow the colour scheme.
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay(alignment: .bottom) {
                if pages.count > 1 {
                    ImageViewerPageIndicator(ids: pages.map(\.id), selection: selection)
                }
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
                if let page = pages.first(where: { $0.id == selection }) ?? pages.first,
                    case .ready(let uiImage) = page.source
                {
                    ToolbarItem(placement: .primaryAction) {
                        let image = Image(uiImage: uiImage)
                        ShareLink(
                            item: image,
                            preview: SharePreview(
                                page.caption ?? ImageGenerationText.generatedImageAlt, image: image))
                    }
                }
            }
        }
    }

    private func sourceLink(_ link: URL, title: String?) -> some View {
        Button {
            openURL(link)
        } label: {
            Label {
                Text(verbatim: title.flatMap { $0.isEmpty ? nil : $0 } ?? link.host() ?? link.absoluteString)
                    .lineLimit(2)
            } icon: {
                Image(systemName: "arrow.up.right.square")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("ios:chat.message.sources.openHint"))
    }
}

struct ZoomableImage: View {
    let image: UIImage
    let label: String?
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var pan: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale * pinch)
            .offset(x: offset.width + pan.width, y: offset.height + pan.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(.rect)
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = min(max(scale * value.magnification, 1), 5)
                        if scale == 1 { offset = .zero }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .updating($pan) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    },
                isEnabled: scale > 1
            )
            .onTapGesture(count: 2) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    scale = scale > 1 ? 1 : 2.5
                    offset = .zero
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(label.map { Text(verbatim: $0) } ?? Text("chat:imageGeneration.generatedImageAlt"))
            .accessibilityZoomAction { action in
                scale = action.direction == .zoomIn ? min(scale + 1, 5) : max(scale - 1, 1)
                if scale == 1 { offset = .zero }
            }
    }
}

/// Which page the viewer shows: dots for a few pages, "3 of 24" for many.
struct ImageViewerPageIndicator: View {
    let ids: [Int]
    let selection: Int

    static let maxDots = 10

    var body: some View {
        let position = (ids.firstIndex(of: selection) ?? 0) + 1
        Group {
            if ids.count <= Self.maxDots {
                HStack(spacing: 8) {
                    ForEach(ids, id: \.self) { id in
                        Circle()
                            .fill(id == selection ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .frame(width: 7, height: 7)
                    }
                }
            } else {
                Text(verbatim: PageIndexText.position(position, of: ids.count))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.fill.quaternary, in: .capsule)
        .padding(.bottom, 8)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: PageIndexText.position(position, of: ids.count)))
    }
}

enum PageIndexText {
    /// "2 of 9", in the language's own order (ja and ko put the total first).
    static func position(_ index: Int, of total: Int) -> String {
        String(
            localized: "chat:placeDetail.pagination", defaultValue: "\(index.formatted()) of \(total.formatted())",
            comment: "Which page of several is shown (a stop of the day, an image in the viewer): its number, then how many.")
    }
}
