import MarkdownKit
import SwiftUI
import UIKit

/// A source's site icon, for its citation chip and its row in the Sources sheet, as the desktop's `SourceFavicon`
/// has it: the one the search returned with the result, else Google's icon for the site — and Google's too when
/// the search's own does not load. Fetched like every search image: https only, through the capped, cookie-less
/// downloader and never the paired session, raster formats only. What neither gives draws the default glyph.
enum SourceIcon {
    /// Icons are drawn at 12 to 20 points; this covers 3x.
    static let pixelSize = 96

    static func url(for source: CitationSource) -> URL? {
        own(source) ?? google(for: source)
    }

    /// What is tried when `url(for:)` does not load: Google's icon, when the first was the search's own.
    static func fallback(for source: CitationSource) -> URL? {
        own(source) == nil ? nil : google(for: source)
    }

    /// Google's icon for a site (the desktop's `faviconUrl`).
    static func google(host: String) -> URL? {
        guard !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/s2/favicons"
        components.queryItems = [URLQueryItem(name: "domain", value: host), URLQueryItem(name: "sz", value: "64")]
        return components.url
    }

    private static func own(_ source: CitationSource) -> URL? {
        source.favicon.flatMap(SearchMediaPolicy.fetchableURL)
    }

    private static func google(for source: CitationSource) -> URL? {
        ExternalLinkPolicy.openableURL(source.link)?.host().flatMap(google(host:))
    }
}

extension MarkdownCitationIcons {
    /// Citation chips draw their icons through the chat's search-image loader, and share its cache.
    static func searchMedia(_ loader: SearchMediaLoader) -> MarkdownCitationIcons {
        MarkdownCitationIcons(
            cached: { loader.cached($0, maxPixelSize: SourceIcon.pixelSize) },
            load: { try? await loader.load($0, maxPixelSize: SourceIcon.pixelSize) })
    }
}

/// A source's icon in a list: the site's own when it can be had, a globe until then and when it cannot.
struct SourceIconView: View {
    let url: URL?
    /// Tried when `url` does not load.
    var fallback: URL?
    @State private var loaded: UIImage?
    @Environment(\.searchMediaLoader) private var loader
    @ScaledMetric private var side: CGFloat

    /// `side` is the icon's size at the default text size; it grows with the text.
    init(url: URL?, fallback: URL? = nil, side: CGFloat = 20) {
        self.url = url
        self.fallback = fallback
        _side = ScaledMetric(wrappedValue: side, relativeTo: .subheadline)
    }

    private var image: UIImage? {
        loaded ?? [url, fallback].lazy.compactMap { $0 }
            .compactMap { loader.cached($0, maxPixelSize: SourceIcon.pixelSize) }.first
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .padding(side * 0.18)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .background(.background, in: Circle())
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url, image == nil else { return }
            loaded = await MarkdownCitationIcons.searchMedia(loader).image(url: url, fallback: fallback)
        }
    }
}
