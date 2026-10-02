import Foundation

enum MarkdownHealer {
    private struct Opener {
        let marker: Character
        var count: Int
        let position: Int
    }

    private struct Scan {
        var mask: [Bool]
        var openers: [Opener] = []
        var openCode: (position: Int, length: Int)?
        var inMath = false
        var mathOpener: Int?
    }

    private static let delimiters: Set<Character> = ["*", "_", "~"]
    private static let inertCharacters: Set<Character> = ["*", "_", "~", "`"]

    static func heal(_ text: String) -> String {
        var chars = Array(text)
        let lines = MarkdownScan.lineRanges(chars)
        var fence: MarkdownScan.Fence?
        var fenceLine = -1
        var floor = 0
        for (number, line) in lines.enumerated() {
            if let open = fence {
                if MarkdownScan.closes(open, chars, line) {
                    fence = nil
                    floor = min(line.upperBound + 1, chars.count)
                }
            } else if let opened = MarkdownScan.fenceOpening(chars, line) {
                fence = opened
                fenceLine = number
            }
        }
        if let fence { return closeFence(chars, lines: lines, fence: fence, fenceLine: fenceLine) }

        chars = dropPartialCitation(chars, floor: floor)
        if chars.count >= 1, chars.last == " ", chars.count < 2 || chars[chars.count - 2] != " " {
            chars.removeLast()
        }
        chars = dropPartialSetextLine(chars, floor: floor)
        chars = dropPartialDelimiterRow(chars, floor: floor)
        return healInline(chars, floor: floor)
    }

    private static func closeFence(
        _ chars: [Character], lines: [Range<Int>], fence: MarkdownScan.Fence, fenceLine: Int
    ) -> String {
        var output = chars
        if let last = lines.last, lines.count - 1 > fenceLine {
            let start = MarkdownScan.quotePrefixEnd(chars, last)
            let rest = chars[start..<last.upperBound]
            if !rest.isEmpty, rest.count < fence.count, rest.allSatisfy({ $0 == fence.marker }) {
                output.removeSubrange(last)
            }
        }
        var healed = String(output)
        if let last = output.last, !MarkdownScan.isNewline(last) { healed += "\n" }
        return healed + fence.prefix + String(repeating: fence.marker, count: fence.count)
    }

    private static func dropPartialCitation(_ chars: [Character], floor: Int) -> [Character] {
        guard let open = chars.lastIndex(of: MarkdownScan.citationOpen), open >= floor else { return chars }
        let rest = chars[(open + 1)...]
        if rest.contains(MarkdownScan.citationClose) || rest.contains(where: MarkdownScan.isNewline) { return chars }
        return Array(chars[..<open])
    }

    private static func dropPartialSetextLine(_ chars: [Character], floor: Int) -> [Character] {
        let lines = MarkdownScan.lineRanges(chars)
        guard lines.count >= 2 else { return chars }
        let last = lines[lines.count - 1]
        let previous = lines[lines.count - 2]
        guard previous.lowerBound >= floor, !MarkdownScan.isBlank(chars, previous) else { return chars }
        var start = last.lowerBound
        while start < last.upperBound, chars[start] == " " { start += 1 }
        let underline = chars[start..<last.upperBound]
        guard (1...2).contains(underline.count), let marker = underline.first, marker == "-" || marker == "=",
            underline.allSatisfy({ $0 == marker })
        else { return chars }
        return Array(chars[..<previous.upperBound])
    }

    // Until a table's delimiter row is whole, cmark reads header + half row as a paragraph ending in a stray "| --".
    private static func dropPartialDelimiterRow(_ chars: [Character], floor: Int) -> [Character] {
        let lines = MarkdownScan.lineRanges(chars)
        guard lines.count >= 2 else { return chars }
        let last = lines[lines.count - 1]
        let previous = lines[lines.count - 2]
        let row = chars[last]
        guard previous.lowerBound >= floor, chars[previous].contains("|"),
            row.contains(where: { !$0.isWhitespace }), row.allSatisfy({ " \t:|-".contains($0) }),
            !isCompleteDelimiterRow(String(row), header: String(chars[previous]))
        else { return chars }
        return Array(chars[..<previous.upperBound])
    }

    private static func isCompleteDelimiterRow(_ row: String, header: String) -> Bool {
        func cells(_ line: String) -> [Substring] {
            var body = Substring(line.trimmingCharacters(in: .whitespaces))
            if body.hasPrefix("|") { body = body.dropFirst() }
            if body.hasSuffix("|") { body = body.dropLast() }
            return body.split(separator: "|", omittingEmptySubsequences: false)
        }
        let rowCells = cells(row)
        let valid = rowCells.allSatisfy { cell in
            var dashes = Substring(cell.trimmingCharacters(in: .whitespaces))
            if dashes.hasPrefix(":") { dashes = dashes.dropFirst() }
            if dashes.hasSuffix(":") { dashes = dashes.dropLast() }
            return !dashes.isEmpty && dashes.allSatisfy { $0 == "-" }
        }
        let closed =
            !header.trimmingCharacters(in: .whitespaces).hasSuffix("|")
            || row.trimmingCharacters(in: .whitespaces).hasSuffix("|")
        return valid && closed && rowCells.count == cells(header).count
    }

    private static func healInline(_ chars: [Character], floor: Int) -> String {
        let lines = MarkdownScan.lineRanges(chars)
        guard var scopeLine = lines.firstIndex(where: { $0.lowerBound >= floor }) else { return String(chars) }
        for number in scopeLine..<(lines.count - 1) where MarkdownScan.isBlank(chars, lines[number]) {
            scopeLine = number + 1
        }
        guard scopeLine < lines.count else { return String(chars) }
        for number in scopeLine..<lines.count where startsBlock(chars, lines[number]) {
            scopeLine = number
        }
        // An ATX heading is one line: text after it is a paragraph of its own.
        if scopeLine < lines.count - 1, MarkdownScan.isHeading(chars, lines[scopeLine]) { scopeLine += 1 }
        let scopeStart = lines[scopeLine].lowerBound
        let contentStart = contentStart(chars, lines[scopeLine])
        let inMath = mathIsOpen(chars, from: floor, to: scopeStart)

        var scope = Array(chars[contentStart...])
        scope = neutraliseLinks(scope, mask: scan(scope, inMath: inMath).mask)
        let result = scan(scope, inMath: inMath)
        let (insertAt, closers) = closers(for: result, in: scope)
        return String(chars[..<contentStart]) + String(scope[..<insertAt]) + closers + String(scope[insertAt...])
    }

    private static func startsBlock(_ chars: [Character], _ line: Range<Int>) -> Bool {
        let start = MarkdownScan.quotePrefixEnd(chars, line)
        guard start < line.upperBound else { return false }
        if chars[start] == "|" || MarkdownScan.listMarkerEnd(chars, start, line.upperBound) != nil { return true }
        return MarkdownScan.headingEnd(chars, start, line.upperBound) != nil
    }

    private static func contentStart(_ chars: [Character], _ line: Range<Int>) -> Int {
        var index = MarkdownScan.quotePrefixEnd(chars, line)
        func skipSpaces() {
            while index < line.upperBound, chars[index] == " " || chars[index] == "\t" { index += 1 }
        }
        if index < line.upperBound, let end = MarkdownScan.listMarkerEnd(chars, index, line.upperBound) {
            index = end
            skipSpaces()
            if index + 3 <= line.upperBound, chars[index] == "[", "xX ".contains(chars[index + 1]),
                chars[index + 2] == "]", index + 3 == line.upperBound || chars[index + 3] == " "
            {
                index += 3
                skipSpaces()
            }
        } else if index < line.upperBound, let end = MarkdownScan.headingEnd(chars, index, line.upperBound) {
            index = end
            skipSpaces()
        }
        return index
    }

    private static func mathIsOpen(_ chars: [Character], from start: Int, to end: Int) -> Bool {
        guard start < end else { return false }
        let region = Array(chars[start..<end])
        let mask = MarkdownScan.codeMask(region)
        var open = false
        var index = 0
        while index < region.count {
            if mask[index] {
                index += 1
            } else if region[index] == "\\" {
                index += 2
            } else if region[index] == "$", index + 1 < region.count, region[index + 1] == "$" {
                open.toggle()
                index += 2
            } else {
                index += 1
            }
        }
        return open
    }

    private static func scan(_ scope: [Character], inMath: Bool) -> Scan {
        let count = scope.count
        var result = Scan(mask: [Bool](repeating: false, count: count))
        result.inMath = inMath
        var index = 0
        while index < count {
            let character = scope[index]
            if result.inMath {
                result.mask[index] = true
                if character == "\\" {
                    if index + 1 < count { result.mask[index + 1] = true }
                    index += 2
                } else if character == "$", index + 1 < count, scope[index + 1] == "$" {
                    result.mask[index + 1] = true
                    result.inMath = false
                    result.mathOpener = nil
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            switch character {
            case "\\":
                index += 2
            case "`":
                let length = MarkdownScan.run(of: "`", in: scope, at: index)
                if let close = MarkdownScan.closingBacktickRun(scope, length: length, from: index + length, to: count) {
                    for masked in index..<(close + length) { result.mask[masked] = true }
                    index = close + length
                } else {
                    result.openCode = (index, length)
                    for masked in index..<count { result.mask[masked] = true }
                    index = count
                }
            case "$" where index + 1 < count && scope[index + 1] == "$":
                result.inMath = true
                result.mathOpener = index
                result.mask[index] = true
                result.mask[index + 1] = true
                index += 2
            case "*", "_", "~":
                let length = MarkdownScan.run(of: character, in: scope, at: index)
                delimiter(character, length: length, at: index, in: scope, openers: &result.openers)
                index += length
            default:
                index += 1
            }
        }
        return result
    }

    private static func delimiter(
        _ marker: Character, length: Int, at index: Int, in scope: [Character], openers: inout [Opener]
    ) {
        if marker == "~", length != 2 { return }
        let previous: Character? = index > 0 ? scope[index - 1] : nil
        let next: Character? = index + length < scope.count ? scope[index + length] : nil
        // CJK-friendly, as the parser (`MarkdownPreprocessor.cjkEmphasis`): for `*`, a CJK letter beside
        // punctuation is a boundary, as a space is.
        let cjk = marker == "*"
        let leftFlanking =
            !MarkdownScan.isSpace(next)
            && (!MarkdownScan.isPunctuation(next) || MarkdownScan.isSpace(previous) || MarkdownScan.isPunctuation(previous)
                || (cjk && MarkdownScan.isCJKLetter(previous)))
        let rightFlanking =
            !MarkdownScan.isSpace(previous)
            && (!MarkdownScan.isPunctuation(previous) || MarkdownScan.isSpace(next) || MarkdownScan.isPunctuation(next)
                || (cjk && MarkdownScan.isCJKLetter(next)))
        var canOpen = leftFlanking
        var canClose = rightFlanking
        if marker == "_" {
            canOpen = leftFlanking && (!rightFlanking || MarkdownScan.isPunctuation(previous))
            canClose = rightFlanking && (!leftFlanking || MarkdownScan.isPunctuation(next))
        }
        var remaining = length
        if canClose {
            while remaining > 0, let match = openers.lastIndex(where: { $0.marker == marker }) {
                let taken = min(remaining, openers[match].count)
                remaining -= taken
                openers.removeSubrange((match + 1)...)
                if openers[match].count == taken {
                    openers.remove(at: match)
                } else {
                    openers[match].count -= taken
                }
            }
        }
        if remaining > 0, canOpen {
            openers.append(Opener(marker: marker, count: remaining, position: index + length - remaining))
        }
    }

    private static func hasContent(_ scope: [Character], _ range: Range<Int>) -> Bool {
        guard range.lowerBound < range.upperBound else { return false }
        return scope[range].contains { !$0.isWhitespace && !inertCharacters.contains($0) }
    }

    private static func closers(for scan: Scan, in scope: [Character]) -> (Int, String) {
        let count = scope.count
        var prefix = ""
        var limit = count
        if scan.inMath {
            let opener = scan.mathOpener
            limit = opener ?? 0
            let display = opener.map { $0 + 2 < count && MarkdownScan.isNewline(scope[$0 + 2]) } ?? true
            if opener == nil || hasContent(scope, (opener! + 2)..<count) || display {
                let endsWithNewline = scope.last.map(MarkdownScan.isNewline) ?? false
                if display, !endsWithNewline { prefix = "\n" }
                prefix += "$$"
            }
        } else if let code = scan.openCode {
            limit = code.position
            // Three or more backticks are a fence being typed, never an inline span to close (remend's rule too).
            if code.length < 3, scope[(code.position + code.length)...].contains(where: { !$0.isWhitespace && $0 != "`" }) {
                prefix = String(repeating: "`", count: code.length)
            }
        }

        var insertAt = count
        if prefix.isEmpty, scan.openCode == nil, !scan.inMath {
            while insertAt > 0, scope[insertAt - 1].isWhitespace { insertAt -= 1 }
            var runStart = insertAt
            while runStart > 0, delimiters.contains(scope[runStart - 1]) { runStart -= 1 }
            if runStart < insertAt, runStart == 0 || scope[runStart - 1].isWhitespace, !scan.mask[runStart] {
                insertAt = runStart
                while insertAt > 0, scope[insertAt - 1].isWhitespace { insertAt -= 1 }
            }
            limit = insertAt
        }

        var emphasis = ""
        for opener in scan.openers.reversed() where opener.position + opener.count <= limit {
            if hasContent(scope, (opener.position + opener.count)..<limit) {
                emphasis += String(repeating: opener.marker, count: opener.count)
            }
        }
        return (insertAt, prefix + emphasis)
    }

    private static func neutraliseLinks(_ scope: [Character], mask: [Bool]) -> [Character] {
        var scope = scope
        // A trailing "<letter" is dropped as remend does: a half tag or autolink would flash as raw text.
        if let open = scope.indices.last(where: { scope[$0] == "<" && !mask[$0] }), open + 1 < scope.count,
            scope[open + 1].isLetter || scope[open + 1] == "/", !scope[(open + 1)...].contains(">")
        {
            return trimmingTrailingWhitespace(scope[..<open])
        }

        if let bracket = lastUnmaskedDestination(scope, mask: mask) {
            let hasClose = scope[(bracket + 2)...].indices.contains { scope[$0] == ")" && !mask[$0] }
            if !hasClose, let open = matchingOpenBracket(scope, before: bracket, mask: mask) {
                if open > 0, scope[open - 1] == "!" { return trimmingTrailingWhitespace(scope[..<(open - 1)]) }
                return Array(scope[..<open]) + Array(scope[(open + 1)..<bracket])
            }
        }

        for index in scope.indices.reversed() where scope[index] == "[" && !mask[index] {
            guard matchingCloseBracket(scope, after: index, mask: mask) == nil else { continue }
            if index > 0, scope[index - 1] == "!" { return trimmingTrailingWhitespace(scope[..<(index - 1)]) }
            scope.remove(at: index)
            return scope
        }
        return scope
    }

    private static func trimmingTrailingWhitespace(_ chars: ArraySlice<Character>) -> [Character] {
        Array(chars[..<(chars.lastIndex { !$0.isWhitespace }.map { $0 + 1 } ?? chars.startIndex)])
    }

    private static func lastUnmaskedDestination(_ scope: [Character], mask: [Bool]) -> Int? {
        guard scope.count >= 2 else { return nil }
        return stride(from: scope.count - 2, through: 0, by: -1).first {
            scope[$0] == "]" && scope[$0 + 1] == "(" && !mask[$0]
        }
    }

    private static func matchingOpenBracket(_ scope: [Character], before close: Int, mask: [Bool]) -> Int? {
        var depth = 1
        for index in stride(from: close - 1, through: 0, by: -1) where !mask[index] {
            if scope[index] == "]" {
                depth += 1
            } else if scope[index] == "[" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func matchingCloseBracket(_ scope: [Character], after open: Int, mask: [Bool]) -> Int? {
        var depth = 1
        for index in (open + 1)..<scope.count where !mask[index] {
            if scope[index] == "[" {
                depth += 1
            } else if scope[index] == "]" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }
}
