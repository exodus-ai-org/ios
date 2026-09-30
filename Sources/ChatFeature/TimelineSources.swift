import Foundation

/// The results of a search step as the timeline shows them: a pill per site, not per result. Sixty results are
/// mostly the same dozen sites, and a wall of pills says less than the sites and how much each gave.
struct TimelineSources: Equatable {
    struct Site: Equatable, Identifiable {
        /// What the pill reads, folded: the site's identity.
        let id: String
        let name: String
        /// How many of the step's results are this site's.
        let count: Int
        /// The site's first result: what the pill opens, and where its icon comes from.
        let first: CitationSource

        /// Shown after the name from two results up.
        var countText: String? { count > 1 ? count.formatted() : nil }
    }

    /// The sites shown, in the order first seen.
    let sites: [Site]
    /// How many sites are not shown.
    let more: Int

    static let siteLimit = 8

    static func pills(_ results: [CitationSource], limit: Int = siteLimit) -> TimelineSources {
        var order: [String] = []
        var names: [String: String] = [:]
        var firsts: [String: CitationSource] = [:]
        var counts: [String: Int] = [:]
        for result in results {
            let name = name(of: result)
            let id = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if counts[id] == nil {
                order.append(id)
                names[id] = name
                firsts[id] = result
            }
            counts[id, default: 0] += 1
        }
        let sites = order.prefix(limit).compactMap { id -> Site? in
            guard let name = names[id], let first = firsts[id] else { return nil }
            return Site(id: id, name: name, count: counts[id] ?? 1, first: first)
        }
        return TimelineSources(sites: sites, more: max(0, order.count - limit))
    }

    /// The site's name, else its host; a result with neither goes by its title, else by its link as written.
    static func name(of result: CitationSource) -> String {
        if let host = ToolPresentation.host(of: result) { return host }
        return result.title.isEmpty ? result.link : result.title
    }
}
