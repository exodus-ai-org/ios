import Foundation
import Markdown

public struct MarkdownBlockCache: Sendable {
    var source: String = ""
    var starts: [Int] = []

    public init() {}
}

public enum MarkdownPreprocessor {
    public static let citationScheme = "exodus-cite"

    public static func splitBlocks(_ text: String) -> [Substring] {
        var cache = MarkdownBlockCache()
        return splitBlocks(text, cache: &cache)
    }

    public static func splitBlocks(_ text: String, cache: inout MarkdownBlockCache) -> [Substring] {
        guard !text.isEmpty else {
            cache = MarkdownBlockCache()
            return []
        }
        var starts: [Int]
        if hasDefinition(text) {
            starts = [0]
        } else {
            // Resume from the second-to-last block: the last one can still fold into it ("2" becoming "2.").
            let resumable = cache.starts.count >= 2 && text.utf8.starts(with: cache.source.utf8)
            let resumeAt = resumable ? cache.starts[cache.starts.count - 2] : 0
            var tail = blockStarts(text, from: resumeAt)
            if tail.isEmpty { tail = [resumeAt] } else { tail[0] = resumeAt }
            starts = (resumable ? Array(cache.starts.dropLast(2)) : []) + tail
        }
        cache.source = text
        cache.starts = starts

        let merged = mergeOpenMath(text, starts: starts)
        let utf8 = text.utf8
        return merged.indices.map { position in
            let lower = utf8.index(utf8.startIndex, offsetBy: merged[position])
            let upper =
                position + 1 < merged.count ? utf8.index(utf8.startIndex, offsetBy: merged[position + 1]) : text.endIndex
            return text[lower..<upper]
        }
    }

    public static func healTail(_ text: String) -> String {
        MarkdownHealer.heal(text)
    }

    public static func escapeLoneTilde(_ text: String) -> String {
        guard text.contains("~") else { return text }
        return escapeLoneTilde(text, document: parseDocument(text)) ?? text
    }

    public static func rewriteCitations(_ text: String) -> (text: String, citations: [Int]) {
        guard text.contains(MarkdownScan.citationOpen) else { return (text, []) }
        let chars = Array(text)
        let mask = MarkdownScan.codeMask(chars)
        var output = ""
        var citations: [Int] = []
        var index = 0
        while index < chars.count {
            if chars[index] == MarkdownScan.citationOpen, !mask[index], let found = citation(in: chars, at: index) {
                // "!" + "[1](…)" would be image syntax; the desktop keeps the "!" as text.
                if endsWithUnescapedBang(output) {
                    output.removeLast()
                    output += "\\!"
                }
                output += found.numbers.map { "[\($0)](\(citationScheme)://\($0))" }.joined()
                citations += found.numbers
                index = found.end
            } else {
                output.append(chars[index])
                index += 1
            }
        }
        return (output, citations)
    }

    private static func endsWithUnescapedBang(_ text: String) -> Bool {
        guard text.last == "!" else { return false }
        return text.dropLast().reversed().prefix { $0 == "\\" }.count % 2 == 0
    }

    public static func citationNumber(from url: URL) -> Int? {
        guard url.scheme == citationScheme, let host = url.host() else { return nil }
        return Int(host)
    }

    static func parseDocument(_ text: String) -> Document {
        Document(parsing: text, options: [.disableSmartOpts])
    }

    static func escapeLoneTilde(_ text: String, document: Document) -> String? {
        var hasStrike = false
        var codeLines: [ClosedRange<Int>] = []
        var boundaries: Set<Int> = []
        collect(document, strike: &hasStrike, codeLines: &codeLines, boundaries: &boundaries)
        guard hasStrike else { return nil }

        let chars = Array(text)
        var mask = MarkdownScan.codeMask(chars, boundaries: boundaries)
        let lines = MarkdownScan.lineRanges(chars)
        for range in codeLines {
            for number in range where number - 1 < lines.count && number >= 1 {
                for masked in lines[number - 1] { mask[masked] = true }
            }
        }
        maskAutolinksAndMath(chars, into: &mask)

        var output = ""
        var escaped = false
        for (index, character) in chars.enumerated() {
            if character == "~", !mask[index], !escaped,
                index == 0 || chars[index - 1] != "~", index + 1 == chars.count || chars[index + 1] != "~"
            {
                output.append("\\")
            }
            escaped = character == "\\" && !escaped
            output.append(character)
        }
        return output
    }

    // cmark's own leaf-block lines bound code-span pairing exactly; the string heuristics are a fallback.
    private static func collect(
        _ markup: Markup, strike: inout Bool, codeLines: inout [ClosedRange<Int>], boundaries: inout Set<Int>
    ) {
        if markup is Strikethrough { strike = true }
        if markup is CodeBlock || markup is HTMLBlock, let range = markup.range {
            codeLines.append(range.lowerBound.line...range.upperBound.line)
            return
        }
        if markup is Paragraph || markup is Heading || markup is Table.Head || markup is Table.Row,
            let range = markup.range
        {
            boundaries.insert(range.lowerBound.line - 1)
            boundaries.insert(range.upperBound.line)
        }
        for child in markup.children {
            collect(child, strike: &strike, codeLines: &codeLines, boundaries: &boundaries)
        }
    }

    private static func maskAutolinksAndMath(_ chars: [Character], into mask: inout [Bool]) {
        var index = 0
        var mathStart: Int?
        while index < chars.count {
            if mask[index] {
                index += 1
                continue
            }
            if chars[index] == "$", index + 1 < chars.count, chars[index + 1] == "$" {
                if let start = mathStart {
                    for masked in start...(index + 1) { mask[masked] = true }
                    mathStart = nil
                } else {
                    mathStart = index
                }
                index += 2
                continue
            }
            if chars[index] == "<", let close = chars[index...].firstIndex(of: ">"),
                chars[index..<close].contains(":"), !chars[index..<close].contains(where: \.isWhitespace)
            {
                for masked in index...close { mask[masked] = true }
                index = close + 1
                continue
            }
            index += 1
        }
    }

    private static func citation(in chars: [Character], at start: Int) -> (numbers: [Int], end: Int)? {
        let suffix = Array("-source") + [MarkdownScan.citationClose]
        var index = start + 1
        while index < chars.count, chars[index].isASCII, chars[index].isNumber || chars[index] == "," || chars[index] == " " {
            index += 1
        }
        guard index > start + 1, index + suffix.count <= chars.count,
            Array(chars[index..<(index + suffix.count)]) == suffix
        else { return nil }
        let numbers = String(chars[(start + 1)..<index]).split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        guard !numbers.isEmpty else { return nil }
        return (numbers, index + suffix.count)
    }

    private static func hasDefinition(_ text: String) -> Bool {
        guard text.contains("]:") else { return false }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.drop { $0 == " " }
            guard line.count - trimmed.count <= 3, trimmed.first == "[" else { continue }
            let label = trimmed.dropFirst().prefix { $0 != "]" }
            if !label.isEmpty, trimmed.dropFirst(label.count + 1).hasPrefix("]:") { return true }
        }
        return false
    }

    private static func blockStarts(_ text: String, from offset: Int) -> [Int] {
        let utf8 = text.utf8
        let suffix = String(Substring(utf8[utf8.index(utf8.startIndex, offsetBy: offset)...]))
        var lineStarts = [0]
        for (position, byte) in suffix.utf8.enumerated() where byte == UInt8(ascii: "\n") {
            lineStarts.append(position + 1)
        }
        var starts: [Int] = []
        for child in parseDocument(suffix).children {
            guard let line = child.range?.lowerBound.line, line >= 1, line <= lineStarts.count else { continue }
            let start = lineStarts[line - 1] + offset
            if starts.last != start { starts.append(start) }
        }
        return starts
    }

    private static func mergeOpenMath(_ text: String, starts: [Int]) -> [Int] {
        guard text.contains("$$") else { return starts }
        let utf8 = text.utf8
        var merged: [Int] = []
        var open = false
        for (position, start) in starts.enumerated() {
            if !open { merged.append(start) }
            let lower = utf8.index(utf8.startIndex, offsetBy: start)
            let upper =
                position + 1 < starts.count ? utf8.index(utf8.startIndex, offsetBy: starts[position + 1]) : text.endIndex
            let block = text[lower..<upper]
            guard block.contains("$$") else { continue }
            if displayMathCount(Array(block)) % 2 == 1 { open.toggle() }
        }
        return merged
    }

    private static func displayMathCount(_ chars: [Character]) -> Int {
        let mask = MarkdownScan.codeMask(chars)
        var count = 0
        var index = 0
        while index + 1 < chars.count {
            if !mask[index], chars[index] == "\\" {
                index += 2
            } else if !mask[index], chars[index] == "$", chars[index + 1] == "$" {
                count += 1
                index += 2
            } else {
                index += 1
            }
        }
        return count
    }
}
