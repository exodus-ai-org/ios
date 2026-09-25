import Foundation

/// The markdown layer's link allowlist, for a tap outside a `MarkdownView` (the Sources sheet): the same
/// `MarkdownLinkPolicy` decides, so a link in a source's URL leaves the app on exactly the schemes model-written
/// text may use — web and mail — and never through `javascript:`, `tel:`, `shortcuts:`, `file:` or an app's own scheme.
public enum ExternalLinkPolicy {
    /// The URL a tap may open, or nil when the link is not one (not a URL, another scheme, or a citation).
    public static func openableURL(_ link: String) -> URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if case .open(let allowed) = MarkdownLinkPolicy.action(for: url) { return allowed }
        return nil
    }
}
