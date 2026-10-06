import Foundation

/// A questionnaire's or a confirmation's answer, as the user's next message: a leading `exodus-answer` fence naming the
/// block it answers, a blank line, then the answer in plain words — a line a question. Plain text, like `QuotedText`
/// and `HealthContext`, so every provider reads it as what it is; the transcript reads it back with `split` to draw it
/// as a card and to freeze the block it names. Held to the desktop's vectors
/// (`packages/shared/src/utils/interactive-answer.ts`), and read in UTF-16 units as it is there.
enum InteractiveAnswer {
    static let infoString = "exodus-answer"
    /// An unanswered question's line.
    static let blank = "—"
    private static var opening: String { "```" + infoString + "\n" }  // l10n:ignore: markdown syntax
    private static let closing = "\n```"  // l10n:ignore: markdown syntax

    /// The words an answer is written with, in the answering phone's language (`Labels.current`).
    struct Labels: Equatable, Sendable {
        /// Before an "Other…" choice's text: `Other: …`.
        var other: String
        /// The questionnaire's closing line.
        var addition: String
        /// The confirmation's note line.
        var note: String
        var approved: String
        var rejected: String
    }

    /// What the fence says: the block, the run whose reply holds it, its title, a confirmation's decision.
    struct Head: Decodable, Equatable, Sendable {
        enum Decision: String, Codable, Sendable { case approve, reject }

        var block: InteractiveBlock.Kind
        var decision: Decision?
        var ref: String
        var title: String?

        fileprivate enum CodingKeys: String, CodingKey { case block, decision, ref, title }

        /// As the desktop's `JSON.stringify` writes it, byte for byte: the keys in sorted order, `"` `\` and control
        /// characters escaped, `/` and everything else as it is.
        var json: String {
            var fields = [("block", block.rawValue)]
            if let decision { fields.append(("decision", decision.rawValue)) }
            fields.append(("ref", ref))
            if let title { fields.append(("title", title)) }
            return "{" + fields.map { Self.quoted($0) + ":" + Self.quoted($1) }.joined(separator: ",") + "}"
        }

        private static func quoted(_ text: String) -> String {
            var out = "\""
            for scalar in text.unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\u{8}": out += "\\b"
                case "\u{C}": out += "\\f"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case "\u{0}"..."\u{1F}":
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                default: out.unicodeScalars.append(scalar)
                }
            }
            return out + "\""
        }
    }

    /// One question's answer: the options picked, and the "Other…" text (nil: Other not picked).
    struct Response: Equatable, Sendable {
        var options: [String] = []
        var other: String?
    }

    /// One question's picks, as an answer reads back.
    struct Picks: Equatable, Sendable {
        var options: [String]
        var other: Bool
    }

    /// Typed text on one line: a line break is a space. The desktop's `replaceAll(/\s*[\r\n]+\s*/gu, ' ').trim()`:
    /// only `\n` and `\r` break a line, and a run of whitespace holding one becomes one space.
    static func oneLine(_ text: String) -> String {
        var out: [UInt16] = []
        var run: [UInt16] = []
        func flush() {
            out += run.contains(where: { $0 == JSText.lf || $0 == JSText.cr }) ? [UInt16(UInt8(ascii: " "))] : run
            run.removeAll()
        }
        for unit in text.utf16 {
            if JSText.isWhitespace(unit) {
                run.append(unit)
            } else {
                flush()
                out.append(unit)
            }
        }
        flush()
        return JSText.string(JSText.trim(out[...]))
    }

    static func composeAsk(
        _ block: InteractiveBlock.Ask, ref: String, responses: [String: Response], note: String, labels: Labels
    ) -> String {
        var lines = block.questions.map { question -> String in
            let response = responses[question.id]
            var parts = question.options.filter { option in
                response?.options.contains { JSText.equal($0, option) } == true
            }
            if question.other, let other = response?.other {
                let text = oneLine(other)
                parts.append(text.isEmpty ? labels.other : labels.other + ": " + text)
            }
            return "**" + question.text + "** " + (parts.isEmpty ? blank : parts.joined(separator: ", "))
        }
        let extra = oneLine(note)
        if !extra.isEmpty { lines.append("**" + labels.addition + ":** " + extra) }
        return fence(Head(block: .ask, ref: ref, title: block.title)) + "\n\n" + lines.joined(separator: "\n")
    }

    static func composeConfirm(
        _ block: InteractiveBlock.Confirm, ref: String, approved: Bool, note: String, labels: Labels
    ) -> String {
        var lines = ["**" + block.title + "** " + (approved ? labels.approved : labels.rejected)]
        let extra = oneLine(note)
        if !extra.isEmpty { lines.append("**" + labels.note + ":** " + extra) }
        let head = Head(block: .confirm, decision: approved ? .approve : .reject, ref: ref, title: block.title)
        return fence(head) + "\n\n" + lines.joined(separator: "\n")
    }

    private static func fence(_ head: Head) -> String { opening + head.json + closing }

    /// A message's text as its answer fence and the lines after it. Only a fence that opens the message counts; it
    /// ends at the first line that is exactly the closing fence, and its JSON must name a block and a run. Anything
    /// else is an ordinary message, returned whole.
    static func split(_ text: String) -> (head: Head?, body: String) {
        // Checked before the copy, so an ordinary message costs nothing.
        guard text.utf16.starts(with: opening.utf16) else { return (nil, text) }
        let units = Array(text.utf16)
        let open = Array(opening.utf16)
        let rest = units[open.count...]
        let close = Array(closing.utf16)
        let end: Int
        let after: Int
        if let found = firstIndex(of: close + [JSText.lf], in: rest) {
            end = found
            after = found + close.count + 1
        } else if rest.count >= close.count, rest.suffix(close.count).elementsEqual(close) {
            end = rest.endIndex - close.count
            after = rest.endIndex
        } else {
            return (nil, text)
        }
        // The decoder's known gap with JSON.parse: a duplicate key keeps its first value here (the last there), and a
        // lone-surrogate escape is rejected here (accepted there).
        guard let head = try? JSONDecoder().decode(Head.self, from: Data(JSText.string(rest[..<end]).utf8)),
            !head.ref.isEmpty
        else { return (nil, text) }
        return (head, JSText.string(JSText.trim(rest[after...])))
    }

    private static func firstIndex(of needle: [UInt16], in haystack: ArraySlice<UInt16>) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        return (haystack.startIndex...(haystack.endIndex - needle.count)).first { at in
            haystack[at..<(at + needle.count)].elementsEqual(needle)
        }
    }

    /// The picks an answer carried, read back from its lines without its labels — so an answer written in another
    /// language freezes its block all the same. A question's line starts with `**<question>** `; its options are
    /// matched longest first, separated by ", ", and what is left over is an Other answer.
    static func picks(_ block: InteractiveBlock.Ask, body: String) -> [String: Picks] {
        let lines = body.utf16.split(separator: JSText.lf, omittingEmptySubsequences: false).map(Array.init)
        let separator = Array(", ".utf16)
        var out: [String: Picks] = [:]
        for question in block.questions {
            let prefix = Array(("**" + question.text + "** ").utf16)
            var picked: Set<[UInt16]> = []
            var other = false
            if let line = lines.first(where: { $0.starts(with: prefix) }) {
                let rest = line[prefix.count...]
                if !rest.elementsEqual(blank.utf16) {
                    let options = question.options.map { Array($0.utf16) }.sorted { $0.count > $1.count }
                    var at = rest.startIndex
                    while at < rest.endIndex {
                        let tail = rest[at...]
                        guard
                            let option = options.first(where: { option in
                                tail.starts(with: option)
                                    && (tail.count == option.count
                                        || tail.dropFirst(option.count).starts(with: separator))
                            })
                        else {
                            other = question.other
                            break
                        }
                        picked.insert(option)
                        at += option.count + 2
                    }
                }
            }
            let options = question.options.filter { picked.contains(Array($0.utf16)) }
            out[question.id] = Picks(options: options, other: other)
        }
        return out
    }
}

// In an extension, so the memberwise `Head(block:decision:ref:title:)` stays.
extension InteractiveAnswer.Head {
    /// Read leniently, as the desktop does: a title or a decision of another shape is left out, not fatal.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        block = try container.decode(InteractiveBlock.Kind.self, forKey: .block)
        ref = try container.decode(String.self, forKey: .ref)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        decision = (try? container.decodeIfPresent(String.self, forKey: .decision)).flatMap(Decision.init(rawValue:))
    }
}
