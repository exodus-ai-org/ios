#if DEBUG
import MarkdownKit
import SwiftUI
import UIKit

/// Site icons for the DEBUG galleries: drawn here, one colour and one letter per host, so a screenshot never waits on
/// the network and never differs between runs. A host containing "noicon" has none, like a site whose icon fails.
public enum GalleryIcons {
    static let loader = SearchMediaLoader(
        fetch: { url in
            let host = hostName(of: url)
            if host.contains("noicon") { throw URLError(.fileDoesNotExist) }
            return tile(for: host)
        }, cache: SearchMediaCache())

    public static let markdown = MarkdownCitationIcons.searchMedia(loader)

    /// A fixture icon URL for a host, in the shape `SourceIcon.google(host:)` builds.
    public static func url(_ host: String) -> URL? {
        URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")  // l10n:ignore: fixture URL
    }

    /// The site an icon is asked for: named in the query of Google's address, else the address's own host.
    private static func hostName(of url: URL) -> String {
        let domain = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "domain" }?.value
        return (domain ?? url.host() ?? "?").replacing("www.", with: "")
    }

    private static let palette: [UIColor] = [
        .systemOrange, .systemBlue, .systemGreen, .systemIndigo, .systemPink, .systemTeal, .systemRed, .systemBrown,
    ]

    private static func tile(for host: String) -> Data {
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let color = palette[host.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }]
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let letter = String(host.first ?? "?").uppercased() as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: UIColor.white,
            ]
            let bounds = letter.size(withAttributes: attributes)
            letter.draw(
                at: CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2),
                withAttributes: attributes)
        }
    }
}
#endif
