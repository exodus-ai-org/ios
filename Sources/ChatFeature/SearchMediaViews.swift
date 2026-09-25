import MarkdownKit
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// How search images are fetched: the capped, cookie-less downloader, never the paired session.
    @Entry var searchMediaLoader: SearchMediaLoader = .shared
}

/// The media a run's searches found, under its answer as on the desktop: three thumbnails (the last one counting the
/// rest) that open the viewer, then a row of video cards that open in the browser.
struct SearchMediaSection: View {
    let gallery: SearchGallery

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !gallery.images.isEmpty {
                SearchImageGrid(gallery: gallery)
            }
            if !gallery.videos.isEmpty {
                SearchVideoCards(videos: gallery.videos, trustedURLs: gallery.trustedURLs)
            }
        }
    }
}

enum SearchMediaText {
    static func showAll(_ count: Int) -> String {
        String(
            localized: "ios:chat.card.media.showAll", defaultValue: "Show all \(count.formatted()) images",
            comment: "VoiceOver hint of the last search thumbnail under an answer when there are more images. %@ is the total.")
    }

    static func video(_ title: String) -> String {
        String(
            localized: "ios:chat.card.media.video", defaultValue: "Video: \(title)",
            comment: "VoiceOver label of a video card under an answer. %@ is the video's title.")
    }

    static func views(_ count: Int) -> String {
        let compact = count.formatted(.number.notation(.compactName))
        return String(localized: "webSearch:videoCard.views", defaultValue: "\(compact) views", comment: "A video's view count.")
    }

    static func loadHint(_ host: String) -> String {
        String(
            localized: "ios:chat.markdown.loadImageHint", defaultValue: "Downloads this image from \(host).",
            comment: "VoiceOver hint of the Load image button. %@ is the website's host name.")
    }

    static var untitledImage: String {
        String(localized: "ios:chat.markdown.image", defaultValue: "Image", comment: "An image with no description.")
    }
}

struct SearchImageGrid: View {
    static let visible = 3

    let gallery: SearchGallery
    @State private var viewer: ImageViewerPage?
    @Environment(\.searchMediaLoader) private var loader
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 128

    var body: some View {
        let shown = Array(gallery.images.prefix(Self.visible))
        let more = gallery.images.count > Self.visible ? gallery.images.count : nil
        HStack(spacing: 8) {
            ForEach(shown.indices, id: \.self) { index in
                let isLast = index == shown.count - 1
                SearchThumbnail(
                    url: shown[index].preview, trustedURLs: gallery.trustedURLs, title: shown[index].title,
                    moreCount: isLast ? more : nil
                ) {
                    viewer = ImageViewerPage(id: index)
                }
                .frame(maxWidth: .infinity)
                .frame(height: min(tileHeight, 220))
            }
        }
        .fullScreenCover(item: $viewer) { page in
            ImageViewer(pages: pages, start: page.id)
                .environment(\.searchMediaLoader, loader)
        }
    }

    private var pages: [ImageViewerPage.Content] {
        gallery.images.enumerated().map { index, picture in
            ImageViewerPage.Content(
                id: index, source: .search(picture), caption: picture.title.isEmpty ? nil : picture.title,
                link: picture.sourceURL)
        }
    }
}

/// One remote thumbnail: loaded without a tap when the run's own results returned it, behind a tap otherwise, never over
/// plain http. Filled and cropped to its tile (the desktop's object-cover).
struct SearchThumbnail: View {
    let url: URL
    let trustedURLs: Set<URL>
    let title: String
    var moreCount: Int?
    var cornerRadius: CGFloat = 12
    /// False where a tap does something else (a video card opens its page): a thumbnail outside the trusted set then
    /// stays a plain tile, never offering a load it cannot give.
    var offersTapToLoad = true
    let open: () -> Void

    private enum Phase: Equatable {
        case idle, loading, failed
    }

    private struct LoadKey: Equatable {
        let url: URL
        let requested: Bool
    }

    @State private var image: UIImage?
    @State private var phase = Phase.idle
    @State private var requested = false
    @Environment(\.searchMediaLoader) private var loader
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var decision: SearchMediaPolicy.Decision { SearchMediaPolicy.decision(for: url, trustedURLs: trustedURLs) }

    private var shown: UIImage? { image ?? loader.cached(url, maxPixelSize: SearchMediaLoader.thumbnailPixelCap) }

    private var waitsForTap: Bool {
        if offersTapToLoad, case .askToLoad = decision { return !requested && shown == nil }
        return false
    }

    var body: some View {
        Button {
            if waitsForTap { requested = true } else { open() }
        } label: {
            tile
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title.isEmpty ? SearchMediaText.untitledImage : title))
        .accessibilityAddTraits(.isImage)
        .accessibilityHint(hint)
        .task(id: LoadKey(url: url, requested: requested)) { await load() }
    }

    private var tile: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .overlay {
                if let shown {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    placeholder
                }
            }
            .overlay {
                if let moreCount {
                    ZStack {
                        Color.black.opacity(0.5)
                        Label {
                            Text(verbatim: moreCount.formatted())
                        } icon: {
                            Image(systemName: "plus")
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .contentShape(.rect(cornerRadius: cornerRadius))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: shown != nil)
    }

    @ViewBuilder
    private var placeholder: some View {
        switch decision {
        case .refused:
            symbol("photo")
        case .askToLoad(_, let host) where waitsForTap:
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                Text(verbatim: host)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
            .padding(6)
        default:
            if phase == .failed { symbol("photo") } else { EmptyView() }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title3)
            .foregroundStyle(.tertiary)
    }

    private var hint: Text {
        if waitsForTap, case .askToLoad(_, let host) = decision { return Text(verbatim: SearchMediaText.loadHint(host)) }
        if let moreCount { return Text(verbatim: SearchMediaText.showAll(moreCount)) }
        return Text("ios:chat.card.image.openHint")
    }

    private func load() async {
        guard shown == nil else { return }
        switch decision {
        case .load: break
        case .askToLoad where requested: break
        default: return
        }
        phase = .loading
        do {
            image = try await loader.load(url, maxPixelSize: SearchMediaLoader.thumbnailPixelCap)
            phase = .idle
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = Task.isCancelled ? .idle : .failed
        }
    }
}

/// The viewer's page for a search image: the full-size image once it is in, its thumbnail meanwhile (blurred), the
/// thumbnail alone with a note when the full one will not load.
struct SearchViewerImage: View {
    let picture: SearchGallery.Picture

    @State private var full: UIImage?
    @State private var fullFailed = false
    @Environment(\.searchMediaLoader) private var loader

    private var preview: UIImage? { loader.cached(picture.preview, maxPixelSize: SearchMediaLoader.thumbnailPixelCap) }

    var body: some View {
        ZStack {
            if let full {
                ZoomableImage(image: full, label: picture.title.isEmpty ? SearchMediaText.untitledImage : picture.title)
            } else if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .blur(radius: fullFailed ? 0 : 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text(verbatim: picture.title.isEmpty ? SearchMediaText.untitledImage : picture.title))
                if fullFailed {
                    note(Text("webSearch:imageLightbox.previewOnly"))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                } else {
                    ProgressView()
                }
            } else if fullFailed {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                    Text("webSearch:imageLightbox.imageUnavailable")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
    }

    private func note(_ text: Text) -> some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: .capsule)
            .padding(.bottom, 8)
    }

    private func load() async {
        guard full == nil else { return }
        // Opening the image is the tap that asks for it; plain http is never fetched.
        guard let url = picture.url, SearchMediaPolicy.fetchableURL(url.absoluteString) != nil else {
            fullFailed = true
            return
        }
        do {
            full = try await loader.load(url, maxPixelSize: SearchMediaLoader.fullPixelCap)
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { fullFailed = true }
        }
    }
}

/// Video results as cards in a row: thumbnail with a play glyph and the duration, title, channel and views. A tap
/// opens the watch page in the browser; nothing plays in the app.
struct SearchVideoCards: View {
    let videos: [SearchGallery.Video]
    let trustedURLs: Set<URL>
    @ScaledMetric(relativeTo: .subheadline) private var cardWidth: CGFloat = 208
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(videos) { video in
                    card(video)
                        .frame(width: min(cardWidth, 300))
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }

    private func card(_ video: SearchGallery.Video) -> some View {
        Button {
            openURL(video.url)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                thumbnail(video)
                Text(verbatim: video.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let meta = Self.meta(video) {
                    Text(verbatim: meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: SearchMediaText.video(video.title)))
        .accessibilityValue(Text(verbatim: [video.duration, Self.meta(video)].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityHint(Text("ios:chat.message.sources.openHint"))
        .accessibilityAddTraits(.isLink)
    }

    private func thumbnail(_ video: SearchGallery.Video) -> some View {
        Color(.secondarySystemFill)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let thumbnail = video.thumbnail {
                    SearchThumbnail(
                        url: thumbnail, trustedURLs: trustedURLs, title: video.title, cornerRadius: 0, offersTapToLoad: false
                    ) {
                        openURL(video.url)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.6), in: .circle)
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration = video.duration {
                    Text(verbatim: duration)
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7), in: .rect(cornerRadius: 4))
                        .padding(6)
                }
            }
            .clipShape(.rect(cornerRadius: 12))
    }

    /// The desktop's line under a video: its channel (else its site), then its views.
    static func meta(_ video: SearchGallery.Video) -> String? {
        var parts: [String] = []
        if let who = video.creator ?? video.source, !who.isEmpty { parts.append(who) }
        if let views = video.views, views > 0 { parts.append(SearchMediaText.views(views)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
