import Foundation
import ImageIO
import MarkdownKit
import Models
import UIKit
import UniformTypeIdentifiers

/// The images and videos a run's searches found, as the desktop's `collectGalleryImages` / `collectGalleryVideos`:
/// by kind, de-duplicated by URL, in result order. Built once with the turn.
struct SearchGallery: Equatable, Sendable {
    struct Picture: Equatable, Sendable, Identifiable {
        /// The full-size image, for the viewer; nil when it is not a fetchable https URL.
        let url: URL?
        /// What the grid draws: the search's thumbnail, else the image itself.
        let preview: URL
        let title: String
        let sourceURL: URL?
        let source: String?

        var id: URL { preview }
    }

    struct Video: Equatable, Sendable, Identifiable {
        /// The watch page, opened in the browser.
        let url: URL
        let thumbnail: URL?
        let title: String
        let source: String?
        let duration: String?
        let creator: String?
        let views: Int?

        var id: URL { url }
    }

    static let imageCap = 24
    static let videoCap = 12

    var images: [Picture] = []
    var videos: [Video] = []
    /// The exact image and thumbnail URLs the run's own searches returned: what loads without a tap. URLs, not their
    /// hosts, as the desktop's final review settled (I6); a `web_fetch` page adds nothing.
    var trustedURLs: Set<URL> = []

    var isEmpty: Bool { images.isEmpty && videos.isEmpty }

    init() {}

    init(media: [WebSearchMedia]) {
        // An image's own URL and its thumbnail; a video's thumbnail only (its URL is a page, never an image).
        trustedURLs = Set(
            media.flatMap { item in
                (item.kind == .image ? [item.url, item.thumbnailUrl] : [item.thumbnailUrl])
                    .compactMap { $0.flatMap(SearchMediaPolicy.fetchableURL) }
            })

        var seenImages = Set<String>()
        var seenVideos = Set<String>()
        for item in media {
            switch item.kind {
            case .image:
                guard images.count < Self.imageCap, seenImages.insert(item.url).inserted else { continue }
                let full = SearchMediaPolicy.fetchableURL(item.url)
                guard let preview = item.thumbnailUrl.flatMap(SearchMediaPolicy.fetchableURL) ?? full else { continue }
                images.append(
                    Picture(
                        url: full, preview: preview, title: item.title,
                        sourceURL: ExternalLinkPolicy.openableURL(item.sourceUrl), source: item.source))
            case .video:
                guard videos.count < Self.videoCap, seenVideos.insert(item.url).inserted,
                    let url = ExternalLinkPolicy.openableURL(item.url)
                else { continue }
                videos.append(
                    Video(
                        url: url, thumbnail: item.thumbnailUrl.flatMap(SearchMediaPolicy.fetchableURL), title: item.title,
                        source: item.source, duration: item.duration, creator: item.creator, views: item.views))
            }
        }
    }
}

/// When a search image may be fetched: https only (no plain http, no credentials in the URL), and without a tap only
/// when the run's own results returned that very URL.
enum SearchMediaPolicy {
    enum Decision: Equatable, Sendable {
        case load(URL)
        case askToLoad(URL, host: String)
        case refused
    }

    static func decision(for url: URL, trustedURLs: Set<URL>) -> Decision {
        guard let fetchable = fetchableURL(url.absoluteString), let host = fetchable.host()?.lowercased() else {
            return .refused
        }
        return trustedURLs.contains(fetchable) ? .load(fetchable) : .askToLoad(fetchable, host: host)
    }

    static func fetchableURL(_ link: String) -> URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty, url.user == nil,
            url.password == nil
        else { return nil }
        return url
    }

    /// The web's bitmap formats only: an SVG or PDF is a document, and ImageIO's rarer decoders (TIFF, ICNS, …) are
    /// never handed bytes from the web.
    static let rasterTypes: Set<String> = [
        UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier, UTType.webP.identifier,
        UTType.heic.identifier, UTType.heif.identifier, UTType.bmp.identifier, "public.avif",
    ]

    static func isRaster(_ data: Data) -> Bool {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) > 0,
            let type = CGImageSourceGetType(source) as String?
        else { return false }
        return rasterTypes.contains(type)
    }
}

/// Decoded search images, in memory only, shared by every chat.
final class SearchMediaCache: @unchecked Sendable {
    static let shared = SearchMediaCache()
    private let storage = NSCache<NSString, UIImage>()

    init(totalCostLimit: Int = 48 * 1024 * 1024) {
        storage.totalCostLimit = totalCostLimit
    }

    func removeAll() { storage.removeAllObjects() }

    func image(for url: URL, maxPixelSize: Int) -> UIImage? {
        storage.object(forKey: Self.key(url, maxPixelSize))
    }

    func insert(_ image: UIImage, for url: URL, maxPixelSize: Int) {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        storage.setObject(image, forKey: Self.key(url, maxPixelSize), cost: Int(pixels) * 4)
    }

    private static func key(_ url: URL, _ size: Int) -> NSString { "\(size)|\(url.absoluteString)" as NSString }
}

/// Fetches a search image through the markdown's capped downloader (15 s, 8 MB, `image/*`, a session with no cookies,
/// credentials or cache) and never through the paired session, then decodes it downsampled.
final class SearchMediaLoader: Sendable {
    enum Failure: Error, Equatable, Sendable {
        case refused
        case notRaster
        case failed
    }

    typealias Fetch = @Sendable (URL) async throws -> Data

    static let shared = SearchMediaLoader(fetch: { try await MarkdownImageLoader.shared.download($0) })
    /// The grid never decodes more than this, whatever the tile's size.
    static let thumbnailPixelCap = 720
    static let fullPixelCap = 2048

    private let fetch: Fetch
    let cache: SearchMediaCache

    init(fetch: @escaping Fetch, cache: SearchMediaCache = .shared) {
        self.fetch = fetch
        self.cache = cache
    }

    convenience init(loader: MarkdownImageLoader, cache: SearchMediaCache = SearchMediaCache()) {
        self.init(fetch: { try await loader.download($0) }, cache: cache)
    }

    func cached(_ url: URL, maxPixelSize: Int) -> UIImage? {
        cache.image(for: url, maxPixelSize: Self.clamp(maxPixelSize))
    }

    func load(_ url: URL, maxPixelSize: Int) async throws -> UIImage {
        guard let fetchable = SearchMediaPolicy.fetchableURL(url.absoluteString) else { throw Failure.refused }
        let size = Self.clamp(maxPixelSize)
        if let hit = cache.image(for: fetchable, maxPixelSize: size) { return hit }
        let data: Data
        do {
            data = try await fetch(fetchable)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                throw CancellationError()
            }
            throw Failure.failed
        }
        try Task.checkCancellation()
        let image = try await Self.decode(data, maxPixelSize: size)
        cache.insert(image, for: fetchable, maxPixelSize: size)
        return image
    }

    @concurrent
    nonisolated static func decode(_ data: Data, maxPixelSize: Int) async throws -> UIImage {
        guard SearchMediaPolicy.isRaster(data) else { throw Failure.notRaster }
        guard let loaded = try? MarkdownImageLoader.downsample(data, maxPixelWidth: maxPixelSize) else {
            throw Failure.notRaster
        }
        return UIImage(cgImage: loaded.cgImage)
    }

    /// Sizes are rounded up to a 120 px step, so a tile that grows by a point reuses its image.
    static func clamp(_ size: Int) -> Int {
        let stepped = (max(size, 1) + 119) / 120 * 120
        return min(stepped, fullPixelCap)
    }
}
