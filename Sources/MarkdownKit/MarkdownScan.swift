import Foundation

enum MarkdownScan {
    struct Fence: Equatable {
        let marker: Character
        let count: Int
        let prefix: String
    }

    static let citationOpen: Character = "\u{3010}"
    static let citationClose: Character = "\u{3011}"

    static func isNewline(_ character: Character) -> Bool {
        character == "\n" || character == "\r\n" || character == "\r"
    }

    static func isSpace(_ character: Character?) -> Bool {
        guard let character else { return true }
        return character.isWhitespace
    }

    static func isPunctuation(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isPunctuation || character.isSymbol
    }

    static func lineRanges(_ chars: [Character]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        for index in chars.indices where isNewline(chars[index]) {
            ranges.append(start..<index)
            start = index + 1
        }
        ranges.append(start..<chars.count)
        return ranges
    }

    static func isBlank(_ chars: [Character], _ range: Range<Int>) -> Bool {
        chars[range].allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func run(of marker: Character, in chars: [Character], at index: Int) -> Int {
        var end = index
        while end < chars.count, chars[end] == marker { end += 1 }
        return end - index
    }

    static func quotePrefixEnd(_ chars: [Character], _ range: Range<Int>) -> Int {
        var index = range.lowerBound
        while index < range.upperBound, chars[index] == " " || chars[index] == "\t" || chars[index] == ">" {
            index += 1
        }
        return index
    }

    static func listMarkerEnd(_ chars: [Character], _ start: Int, _ end: Int) -> Int? {
        guard start < end else { return nil }
        var index = start
        if "-*+".contains(chars[index]) {
            index += 1
        } else {
            while index < end, index - start < 9, chars[index].isASCII, chars[index].isNumber { index += 1 }
            guard index > start, index < end, chars[index] == "." || chars[index] == ")" else { return nil }
            index += 1
        }
        guard index == end || chars[index] == " " || chars[index] == "\t" else { return nil }
        return index
    }

    static func headingEnd(_ chars: [Character], _ start: Int, _ end: Int) -> Int? {
        guard start < end else { return nil }
        let count = run(of: "#", in: chars, at: start)
        guard (1...6).contains(count), start + count >= end || chars[start + count] == " " else { return nil }
        return min(start + count, end)
    }

    static func isHeading(_ chars: [Character], _ line: Range<Int>) -> Bool {
        headingEnd(chars, quotePrefixEnd(chars, line), line.upperBound) != nil
    }

    // A fence opened on a list-marker line ("- ```py") continues at the item's content column.
    static func fenceOpening(_ chars: [Character], _ range: Range<Int>) -> Fence? {
        var start = range.lowerBound
        var prefix = ""
        while true {
            let quoted = quotePrefixEnd(chars, start..<range.upperBound)
            prefix += String(chars[start..<quoted])
            start = quoted
            guard let marker = listMarkerEnd(chars, start, range.upperBound), marker < range.upperBound else { break }
            prefix += String(repeating: " ", count: marker - start)
            start = marker
        }
        guard start < range.upperBound, chars[start] == "`" || chars[start] == "~" else { return nil }
        let marker = chars[start]
        let count = min(run(of: marker, in: chars, at: start), range.upperBound - start)
        guard count >= 3 else { return nil }
        if marker == "`", chars[(start + count)..<range.upperBound].contains("`") { return nil }
        return Fence(marker: marker, count: count, prefix: prefix)
    }

    static func closes(_ fence: Fence, _ chars: [Character], _ range: Range<Int>) -> Bool {
        let start = quotePrefixEnd(chars, range)
        guard start < range.upperBound, chars[start] == fence.marker else { return false }
        let count = min(run(of: fence.marker, in: chars, at: start), range.upperBound - start)
        return count >= fence.count && isBlank(chars, (start + count)..<range.upperBound)
    }

    static func closingBacktickRun(_ chars: [Character], length: Int, from: Int, to end: Int) -> Int? {
        var index = from
        while index < end {
            guard chars[index] == "`" else {
                index += 1
                continue
            }
            let length2 = min(run(of: "`", in: chars, at: index), end - index)
            if length2 == length { return index }
            index += length2
        }
        return nil
    }

    // Fenced code and closed inline code spans; indented code needs the parser's block ranges.
    // A code span never crosses a block, so pairing restarts at every block start (and at `boundaries`, 0-based lines).
    static func codeMask(_ chars: [Character], boundaries: Set<Int> = []) -> [Bool] {
        var mask = [Bool](repeating: false, count: chars.count)
        var fence: Fence?
        var paragraphStart: Int?

        func markInline(_ range: Range<Int>) {
            var index = range.lowerBound
            while index < range.upperBound {
                if chars[index] == "\\" {
                    index += 2
                    continue
                }
                guard chars[index] == "`" else {
                    index += 1
                    continue
                }
                let length = min(run(of: "`", in: chars, at: index), range.upperBound - index)
                if let close = closingBacktickRun(chars, length: length, from: index + length, to: range.upperBound) {
                    for masked in index..<(close + length) { mask[masked] = true }
                    index = close + length
                } else {
                    index += length
                }
            }
        }

        func flush(until end: Int) {
            if let start = paragraphStart { markInline(start..<end) }
            paragraphStart = nil
        }

        for (number, line) in lineRanges(chars).enumerated() {
            let lineEnd = min(line.upperBound + 1, chars.count)
            if fence == nil, boundaries.contains(number) || startsLeafBlock(chars, line) { flush(until: line.lowerBound) }
            if let open = fence {
                for masked in line.lowerBound..<lineEnd { mask[masked] = true }
                if closes(open, chars, line) { fence = nil }
                continue
            }
            if let opened = fenceOpening(chars, line) {
                flush(until: line.lowerBound)
                fence = opened
                for masked in line.lowerBound..<lineEnd { mask[masked] = true }
                continue
            }
            if isBlank(chars, line) {
                flush(until: line.lowerBound)
            } else if paragraphStart == nil {
                paragraphStart = line.lowerBound
            }
            if isHeading(chars, line) { flush(until: lineEnd) }
        }
        flush(until: chars.count)
        return mask
    }

    /// An inline link, `[text](destination)`, by where its text opens and closes and where the link ends.
    struct InlineLink: Equatable {
        let open: Int
        let close: Int
        let end: Int
    }

    static func isEscaped(_ chars: [Character], _ index: Int) -> Bool {
        var slashes = 0
        var before = index - 1
        while before >= 0, chars[before] == "\\" {
            slashes += 1
            before -= 1
        }
        return slashes % 2 == 1
    }

    /// Whether the line break at `index` has a blank line on the given side of it: where a paragraph ends.
    private static func endsParagraph(_ chars: [Character], at index: Int, forward: Bool) -> Bool {
        var next = forward ? index + 1 : index - 1
        while chars.indices.contains(next), chars[next] == " " || chars[next] == "\t" { next += forward ? 1 : -1 }
        return !chars.indices.contains(next) || isNewline(chars[next])
    }

    /// The inline link whose text `range` stands in, if it stands in one. An image's description is not a link's
    /// text, and neither is a bracket that no `](…)` closes.
    static func enclosingLink(of range: Range<Int>, in chars: [Character], mask: [Bool]) -> InlineLink? {
        var depth = 0
        var open: Int?
        var index = range.lowerBound - 1
        while index >= 0 {
            let character = chars[index]
            if isNewline(character), endsParagraph(chars, at: index, forward: false) { return nil }
            if !mask[index], !isEscaped(chars, index) {
                if character == "]" {
                    depth += 1
                } else if character == "[" {
                    if depth == 0 {
                        open = index
                        break
                    }
                    depth -= 1
                }
            }
            index -= 1
        }
        guard let open else { return nil }
        if open > 0, chars[open - 1] == "!", !isEscaped(chars, open - 1) { return nil }

        depth = 0
        var close: Int?
        index = range.upperBound
        while index < chars.count {
            let character = chars[index]
            if isNewline(character), endsParagraph(chars, at: index, forward: true) { return nil }
            if !mask[index], !isEscaped(chars, index) {
                if character == "[" {
                    depth += 1
                } else if character == "]" {
                    if depth == 0 {
                        close = index
                        break
                    }
                    depth -= 1
                }
            }
            index += 1
        }
        guard let close, close + 1 < chars.count, chars[close + 1] == "(",
            let end = linkEnd(chars, from: close + 2)
        else { return nil }
        return InlineLink(open: open, close: close, end: end)
    }

    /// Where a link ends, from just inside the parenthesis that opens its destination: past the destination, a
    /// title if it has one, and the parenthesis that closes it.
    static func linkEnd(_ chars: [Character], from start: Int) -> Int? {
        var index = start
        func skipSpace() {
            while index < chars.count, chars[index].isWhitespace { index += 1 }
        }
        skipSpace()
        guard index < chars.count else { return nil }
        if chars[index] == "<" {
            index += 1
            while index < chars.count, chars[index] != ">" {
                if isNewline(chars[index]) || chars[index] == "<" { return nil }
                index += chars[index] == "\\" ? 2 : 1
            }
            guard index < chars.count else { return nil }
            index += 1
        } else {
            var depth = 0
            while index < chars.count {
                let character = chars[index]
                if character == "\\" {
                    index += 2
                    continue
                }
                if character.isWhitespace { break }
                if character == "(" { depth += 1 }
                if character == ")" {
                    if depth == 0 { break }
                    depth -= 1
                }
                index += 1
            }
        }
        skipSpace()
        guard index < chars.count else { return nil }
        let closers: [Character: Character] = ["\"": "\"", "'": "'", "(": ")"]
        if let closer = closers[chars[index]] {
            index += 1
            while index < chars.count, chars[index] != closer {
                index += chars[index] == "\\" ? 2 : 1
            }
            guard index < chars.count else { return nil }
            index += 1
            skipSpace()
        }
        guard index < chars.count, chars[index] == ")" else { return nil }
        return index + 1
    }

    static func startsLeafBlock(_ chars: [Character], _ line: Range<Int>) -> Bool {
        let start = quotePrefixEnd(chars, line)
        return listMarkerEnd(chars, start, line.upperBound) != nil || headingEnd(chars, start, line.upperBound) != nil
    }
}
