import Foundation

/// A source a `【N-source】` marker can resolve to: the run's Nth web-search result, as the desktop's
/// `buildCitationSources` numbers them. A marker whose number has no citation is stripped.
public struct MarkdownCitation: Equatable, Sendable {
    public let number: Int
    public let title: String?
    /// The site as the chip names it: its name where the search gave one, else its host.
    public let host: String?
    /// The site's icon, already judged fetchable by whoever made the citation; drawn when
    /// `markdownCitationIcons` can load it.
    public let iconURL: URL?
    /// Another address for the site's icon, tried when `iconURL` does not load.
    public let iconFallbackURL: URL?

    public init(
        number: Int, title: String? = nil, host: String? = nil, iconURL: URL? = nil, iconFallbackURL: URL? = nil
    ) {
        self.number = number
        self.title = title
        self.host = host
        self.iconURL = iconURL
        self.iconFallbackURL = iconFallbackURL
    }

    static let maximumLabelLength = 24

    /// What the chip shows: the site, else the title, else the number (the desktop's `siteName || hostname || title`).
    var chipLabel: String {
        let candidates = [host.map(Self.displayHost), title]
        let label = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? String(number)
        guard label.count > Self.maximumLabelLength else { return label }
        return String(label.prefix(Self.maximumLabelLength - 1)) + "\u{2026}"
    }

    private static func displayHost(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func citeURL(_ number: Int) -> URL {
        URL(string: "\(MarkdownPreprocessor.citationScheme)://\(number)")!
    }
}
