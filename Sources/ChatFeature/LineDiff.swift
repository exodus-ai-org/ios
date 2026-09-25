import Foundation

/// A line diff of two texts for a card: longest common subsequence over lines, unchanged runs folded down to a few
/// lines of context, and a refusal (`tooLarge`) when the two sides are too big to compare on the phone.
enum LineDiff {
    struct Row: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case context, removed, added }

        let kind: Kind
        /// The line as shown: cut at `maxLineLength` characters.
        let text: String
    }

    enum Item: Equatable, Sendable {
        case row(Row)
        /// Unchanged lines left out between two changes (or before the first, after the last).
        case gap(Int)
    }

    enum Result: Equatable, Sendable {
        case lines(items: [Item], added: Int, removed: Int)
        case tooLarge(oldLines: Int, newLines: Int)

        var added: Int {
            switch self {
            case .lines(_, let added, _): added
            case .tooLarge(_, let newLines): newLines
            }
        }

        var removed: Int {
            switch self {
            case .lines(_, _, let removed): removed
            case .tooLarge(let oldLines, _): oldLines
            }
        }
    }

    static let defaultContext = 3
    /// The LCS table is (old × new) after the common head and tail are trimmed; past this many cells it is refused.
    static let maxCells = 250_000
    static let maxLineLength = 400

    static func diff(
        old: String, new: String, context: Int = defaultContext, maxCells: Int = maxCells,
        maxLineLength: Int = maxLineLength
    ) -> Result {
        let a = lines(of: old)
        let b = lines(of: new)
        var head = 0
        while head < a.count, head < b.count, a[head] == b[head] { head += 1 }
        var tail = 0
        while tail < a.count - head, tail < b.count - head, a[a.count - 1 - tail] == b[b.count - 1 - tail] { tail += 1 }
        let middleA = a[head..<(a.count - tail)]
        let middleB = b[head..<(b.count - tail)]
        guard middleA.count * middleB.count <= maxCells else { return .tooLarge(oldLines: a.count, newLines: b.count) }

        var kinds: [(Row.Kind, Substring)] = a[..<head].map { (.context, $0) }
        kinds += lcs(Array(middleA), Array(middleB))
        kinds += a[(a.count - tail)...].map { (.context, $0) }

        let added = kinds.count { $0.0 == .added }
        let removed = kinds.count { $0.0 == .removed }
        let rows = kinds.map { Row(kind: $0.0, text: clip($0.1, to: maxLineLength)) }
        return .lines(items: fold(rows, context: context), added: added, removed: removed)
    }

    /// Lines split on any newline, CRLF included, so a CRLF file compares equal to its LF edit. A trailing newline
    /// ends the last line rather than starting an empty one, and an empty text has no lines.
    static func lines(of text: String) -> [Substring] {
        guard !text.isEmpty else { return [] }
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    private static func lcs(_ a: [Substring], _ b: [Substring]) -> [(Row.Kind, Substring)] {
        guard !a.isEmpty, !b.isEmpty else { return a.map { (.removed, $0) } + b.map { (.added, $0) } }
        let width = b.count + 1
        var table = [Int32](repeating: 0, count: (a.count + 1) * width)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i * width + j] =
                    a[i] == b[j] ? table[(i + 1) * width + j + 1] + 1 : max(table[(i + 1) * width + j], table[i * width + j + 1])
            }
        }
        var result: [(Row.Kind, Substring)] = []
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                result.append((.context, a[i]))
                i += 1
                j += 1
            } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                result.append((.removed, a[i]))
                i += 1
            } else {
                result.append((.added, b[j]))
                j += 1
            }
        }
        result += a[i...].map { (.removed, $0) }
        result += b[j...].map { (.added, $0) }
        return result
    }

    /// Keeps `context` unchanged lines on each side of a change; a longer unchanged run becomes a gap. A gap of one
    /// line would take the same room as the line, so it is shown instead.
    private static func fold(_ rows: [Row], context: Int) -> [Item] {
        guard rows.contains(where: { $0.kind != .context }) else { return rows.map(Item.row) }
        var items: [Item] = []
        var index = 0
        while index < rows.count {
            guard rows[index].kind == .context else {
                items.append(.row(rows[index]))
                index += 1
                continue
            }
            var end = index
            while end < rows.count, rows[end].kind == .context { end += 1 }
            let keepBefore = index == 0 ? 0 : context
            let keepAfter = end == rows.count ? 0 : context
            let hidden = (end - index) - keepBefore - keepAfter
            if hidden > 1 {
                items += rows[index..<(index + keepBefore)].map(Item.row)
                items.append(.gap(hidden))
                items += rows[(end - keepAfter)..<end].map(Item.row)
            } else {
                items += rows[index..<end].map(Item.row)
            }
            index = end
        }
        return items
    }

    static func clip(_ line: Substring, to length: Int) -> String {
        guard line.count > length else { return String(line) }
        return String(line.prefix(length)) + "…"
    }
}
