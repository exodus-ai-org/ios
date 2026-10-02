import Foundation

/// With extended thinking off and tools on, some models (Claude among them) write their reasoning into the answer
/// as a literal `<thinking>…</thinking>` span; others (DeepSeek, Qwen, …) do the same with `<think>…</think>`. The
/// desktop now splits those spans out as thinking blocks as the reply streams; messages saved before that still hold
/// them as text, so `ChatMessage.contentBlocks` splits them here, and the transcript shows them in the timeline.
///
/// Mirrors the desktop's `packages/shared/src/utils/thinking-tags.ts`, held to the same vectors. What counts as a
/// span, conservatively: only the literal tags `<thinking>` / `<think>` (any case, no attributes), closed by
/// `</thinking>` or `</think>`; an opening tag only at the start of a line (after optional spaces), so a tag named in
/// prose stays text; never inside a fenced code block or an inline code span; an unclosed span runs to the end and is
/// reasoning.
public enum ThinkingTags {
    public enum Kind: Equatable, Sendable { case text, thinking }

    public struct Part: Equatable, Sendable {
        public var kind: Kind
        public var text: String

        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }
    }

    private static let openTags = ["<thinking>", "<think>"].map(Array.init)
    private static let closeTags = ["</thinking>", "</think>"].map(Array.init)

    /// The text as answer text and reasoning, in order. `final: false` is a stream still running: a tag cut at the
    /// end (`<thin`) is held back; `final: true` lets it out as text.
    public static func split(_ string: String, final: Bool = true) -> [Part] {
        let s = Array(string)
        var raw: [Part] = []
        var cur = ""
        var inSpan = false
        var fence: (char: Character, len: Int)?
        var lineStart = true
        var i = 0

        func flush(_ kind: Kind) {
            raw.append(Part(kind, cur))
            cur = ""
        }

        scan: while i < s.count {
            let ch = s[i]
            if inSpan {
                if ch == "<" {
                    if let close = tag(in: s, at: i, among: closeTags) {
                        flush(.thinking)
                        inSpan = false
                        i += close
                        while i < s.count, s[i].isWhitespace { i += 1 }
                        lineStart = true
                        continue
                    }
                    if !final, isPartial(s[i...], of: closeTags) { break scan }
                }
                cur.append(ch)
                i += 1
                continue
            }

            if let open = fence {
                let end = lineEnd(s, from: i)
                let line = s[i..<end]
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                if let marker = fenceMarker(Array(trimmed), at: 0), lineStart, marker.char == open.char,
                    marker.len >= open.len,
                    trimmed.dropFirst(marker.len).allSatisfy(\.isWhitespace)
                {
                    fence = nil
                }
                cur.append(contentsOf: s[i..<min(end + 1, s.count)])
                i = end + 1
                lineStart = true
                continue
            }

            if ch.isNewline {
                cur.append(ch)
                i += 1
                lineStart = true
                continue
            }
            if lineStart, ch == " " || ch == "\t" {
                cur.append(ch)
                i += 1
                continue
            }

            if lineStart {
                if let marker = fenceMarker(s, at: i) {
                    fence = marker
                    let end = lineEnd(s, from: i)
                    cur.append(contentsOf: s[i..<min(end + 1, s.count)])
                    i = end + 1
                    lineStart = true
                    continue
                }
                if ch == "<" {
                    if let open = tag(in: s, at: i, among: openTags) {
                        flush(.text)
                        inSpan = true
                        i += open
                        continue
                    }
                    if !final, isPartial(s[i...], of: openTags) { break scan }
                }
            }

            if ch == "`" {
                // An inline code span: up to a run of as many backticks on this line, or — unclosed — the line's end.
                var len = 0
                while i + len < s.count, s[i + len] == "`" { len += 1 }
                let end = lineEnd(s, from: i)
                var close: Int?
                var j = i + len
                while j < end {
                    guard s[j] == "`" else {
                        j += 1
                        continue
                    }
                    var run = 0
                    while j + run < s.count, s[j + run] == "`" { run += 1 }
                    if run == len {
                        close = j + run
                        break
                    }
                    j += run
                }
                let stop = close ?? end
                cur.append(contentsOf: s[i..<stop])
                i = stop
                lineStart = false
                continue
            }

            cur.append(ch)
            i += 1
            lineStart = false
        }
        flush(inSpan ? .thinking : .text)

        // Tidy: reasoning trimmed, text before a span trimmed at its end, empty parts dropped, neighbours joined.
        var parts: [Part] = []
        for (index, part) in raw.enumerated() {
            var text = part.text
            if part.kind == .thinking {
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if index + 1 < raw.count, raw[index + 1].kind == .thinking {
                while let last = text.last, last.isWhitespace { text.removeLast() }
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if let last = parts.last, last.kind == part.kind {
                parts[parts.count - 1].text += part.kind == .thinking ? "\n\n" + text : text
            } else {
                parts.append(Part(part.kind, text))
            }
        }
        return parts
    }

    /// Content blocks with every text block's spans split out as thinking blocks, in place.
    public static func split(_ blocks: [ContentBlock]) -> [ContentBlock] {
        guard blocks.contains(where: { if case .text(let t) = $0 { t.contains("<") } else { false } }) else {
            return blocks
        }
        return blocks.flatMap { block -> [ContentBlock] in
            guard case .text(let text) = block, text.contains("<") else { return [block] }
            return split(text).map { $0.kind == .thinking ? .thinking($0.text) : .text($0.text) }
        }
    }

    /// The length of the tag of `tags` that `s` has at `i` (any case), or nil.
    private static func tag(in s: [Character], at i: Int, among tags: [[Character]]) -> Int? {
        for tag in tags where i + tag.count <= s.count {
            if zip(s[i..<(i + tag.count)], tag).allSatisfy({ $0.lowercased() == String($1) }) { return tag.count }
        }
        return nil
    }

    /// Whether `rest` (the end of the text) could still grow into one of `tags`.
    private static func isPartial(_ rest: ArraySlice<Character>, of tags: [[Character]]) -> Bool {
        tags.contains { tag in
            tag.count > rest.count && zip(rest, tag).allSatisfy { $0.lowercased() == String($1) }
        }
    }

    /// A fence marker (three or more backticks or tildes) at `i`, or nil.
    private static func fenceMarker(_ s: [Character], at i: Int) -> (char: Character, len: Int)? {
        guard i < s.count, s[i] == "`" || s[i] == "~" else { return nil }
        let char = s[i]
        var len = 0
        while i + len < s.count, s[i + len] == char { len += 1 }
        return len >= 3 ? (char, len) : nil
    }

    /// The index of the next newline at or after `i`, or the end.
    private static func lineEnd(_ s: [Character], from i: Int) -> Int {
        var j = i
        while j < s.count, !s[j].isNewline { j += 1 }
        return j
    }
}
