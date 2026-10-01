import Foundation
import Observation

/// A link that arrived while the app could not show it yet (locked, unpaired): kept, the latest only, until the shell
/// takes it.
@MainActor
@Observable
public final class PendingLink {
    public private(set) var link: DeepLink?

    public init() {}

    public func offer(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        self.link = link
    }

    public func take() -> DeepLink? {
        defer { link = nil }
        return link
    }
}
