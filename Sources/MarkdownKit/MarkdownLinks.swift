import SwiftUI

/// What a tap on a link in model-written text does. Only web and mail links leave the app, like the
/// desktop's `openExternalSafely`: `tel:`, `sms:`, `shortcuts:`, `file:` and other apps' schemes are
/// reachable by injected text, so they are dropped.
enum MarkdownLinkAction: Equatable {
    case citation(Int)
    case open(URL)
    case discard
}

enum MarkdownLinkPolicy {
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    static func action(for url: URL) -> MarkdownLinkAction {
        if let number = MarkdownPreprocessor.citationNumber(from: url) { return .citation(number) }
        guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return .discard }
        return .open(url)
    }
}

/// Owns the one `OpenURLAction` a `MarkdownView` puts in its environment. The action is created once, so
/// its identity never changes while a message streams; the handlers it routes to are refreshed instead.
@MainActor
final class MarkdownLinkRouter {
    var onCitationTap: ((Int) -> Void)?
    var openURL: ((URL) -> Void)?

    private(set) lazy var action = OpenURLAction { [weak self] url in
        MainActor.assumeIsolated { self?.handle(url) ?? .discarded }
    }

    func handle(_ url: URL) -> OpenURLAction.Result {
        switch MarkdownLinkPolicy.action(for: url) {
        case .citation(let number):
            onCitationTap?(number)
            return .handled
        case .open(let url):
            openURL?(url)
            return .handled
        case .discard:
            return .discarded
        }
    }
}
