import Foundation

/// The questionnaire and the confirmation a reply can ask with (spec 2026-10-06): a fenced block whose info string
/// names it (`exodus-ask`, `exodus-confirm`) and whose body is one JSON object. One that validates is drawn as a
/// control; anything else stays the code block it is. The desktop has the same rules
/// (`packages/shared/src/types/interactive.ts`), held to the same vectors; lengths are UTF-16 units, as zod counts.
enum InteractiveBlock: Equatable, Sendable {
    case ask(Ask)
    case confirm(Confirm)

    enum Kind: String, Codable, Sendable {
        case ask, confirm

        /// The fence's info string.
        var language: String { "exodus-" + rawValue }

        init?(language: String) {
            guard language.hasPrefix("exodus-") else { return nil }
            self.init(rawValue: String(language.dropFirst("exodus-".count)))
        }
    }

    struct Ask: Decodable, Equatable, Sendable {
        struct Question: Decodable, Equatable, Sendable {
            enum Kind: String, Decodable, Sendable { case single, multi }

            let id: String
            let text: String
            let type: Kind
            let options: [String]
            /// Adds "Other…", a choice the user types into.
            let other: Bool

            private enum CodingKeys: String, CodingKey { case id, text, type, options, other }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                text = try container.decode(String.self, forKey: .text)
                type = try container.decode(Kind.self, forKey: .type)
                options = try container.decode([String].self, forKey: .options)
                other = try container.decodeIfPresent(Bool.self, forKey: .other) ?? false
            }
        }

        let title: String
        let questions: [Question]
        /// The closing field's label; the phone's own when absent or empty.
        let note: String?
        /// The button's label; the phone's own when absent or empty.
        let submit: String?
    }

    struct Confirm: Decodable, Equatable, Sendable {
        let title: String
        /// Markdown.
        let details: String?
        let approve: String?
        let reject: String?
        let note: String?
    }

    var kind: Kind {
        switch self {
        case .ask: .ask
        case .confirm: .confirm
        }
    }

    /// A fence's body as its block, or nil when it is not one JSON object within the limits.
    static func parse(_ kind: Kind, source: String) -> InteractiveBlock? {
        let data = Data(source.utf8)
        let decoder = JSONDecoder()
        let block: InteractiveBlock? =
            switch kind {
            case .ask: (try? decoder.decode(Ask.self, from: data)).map(InteractiveBlock.ask)
            case .confirm: (try? decoder.decode(Confirm.self, from: data)).map(InteractiveBlock.confirm)
            }
        guard let block, block.isValid else { return nil }
        return block
    }

    var isValid: Bool {
        switch self {
        case .ask(let ask):
            Self.required(ask.title, 200) && (1...8).contains(ask.questions.count)
                && JSText.distinct(ask.questions.map(\.id))
                && Self.within(ask.note, 120) && Self.within(ask.submit, 40)
                && ask.questions.allSatisfy { question in
                    Self.isID(question.id) && Self.required(question.text, 200)
                        && (2...8).contains(question.options.count) && JSText.distinct(question.options)
                        && question.options.allSatisfy { Self.required($0, 80) }
                }
        case .confirm(let confirm):
            Self.required(confirm.title, 200) && Self.within(confirm.details, 1000)
                && Self.within(confirm.approve, 40) && Self.within(confirm.reject, 40) && Self.within(confirm.note, 120)
        }
    }

    private static func required(_ text: String, _ max: Int) -> Bool { !text.isEmpty && text.utf16.count <= max }
    private static func within(_ text: String?, _ max: Int) -> Bool { (text?.utf16.count ?? 0) <= max }
    private static let idUnits = Set("abcdefghijklmnopqrstuvwxyz0123456789_-".utf16)
    private static func isID(_ id: String) -> Bool {
        (1...32).contains(id.utf16.count) && id.utf16.allSatisfy(idUnits.contains)
    }
}

/// A reply's block and the text of its fence — how the Markdown's code block is known as it.
struct InteractiveFence: Equatable, Sendable {
    let block: InteractiveBlock
    let source: String
    /// The fence's opening line, counted from 0 in the text it was found in (`\n`-separated).
    var line = 0

    var kind: InteractiveBlock.Kind { block.kind }

    func matches(language: String?, code: String) -> Bool {
        language.flatMap(InteractiveBlock.Kind.init(language:)) == kind && matches(code: code)
    }

    /// A code block's text is the fence's: compared as the desktop compares them — `\r\n` and `\r` read as `\n`,
    /// trailing line ends dropped, then unit for unit in UTF-16 (canonically equivalent text is not the same text).
    func matches(code: String) -> Bool {
        Self.plainCode(code).elementsEqual(Self.plainCode(source))
    }

    /// A reply's block: its first `exodus-ask` / `exodus-confirm` fence that opens a line at the left margin — not
    /// inside another fence, a list or a quote — and is closed. Only that first one counts: when it does not validate
    /// the reply has none, and a second is code either way. A fence still open (a reply being written) is not one yet.
    /// Read in UTF-16 units, as the desktop's `findInteractiveBlock` reads it, so the two agree on every reply.
    static func first(in markdown: String) -> InteractiveFence? {
        let lines = markdown.utf16.split(separator: JSText.lf, omittingEmptySubsequences: false).map(Array.init)
        var open: (unit: UInt16, length: Int)?
        for (index, line) in lines.enumerated() {
            let run = fenceRun(line)
            if let current = open {
                if let run, run.unit == current.unit, run.length >= current.length, JSText.isBlank(run.rest) {
                    open = nil
                }
                continue
            }
            if line.starts(with: ticks),
                let kind = InteractiveBlock.Kind(language: JSText.string(JSText.trimmingEnd(line.dropFirst(3))))
            {
                for end in lines.indices.dropFirst(index + 1) {
                    if let close = fenceRun(lines[end]), close.unit == tick, JSText.isBlank(close.rest) {
                        let source = JSText.string(Array(lines[(index + 1)..<end].joined(separator: [JSText.lf])))
                        return InteractiveBlock.parse(kind, source: source).map {
                            InteractiveFence(block: $0, source: source, line: index)
                        }
                    }
                }
                return nil
            }
            if let run { open = (run.unit, run.length) }
        }
        return nil
    }

    private static let tick = UInt16(UInt8(ascii: "`"))
    private static let tilde = UInt16(UInt8(ascii: "~"))
    private static let ticks: [UInt16] = [tick, tick, tick]

    /// A line that opens or closes a fence: up to three spaces, then three or more backticks or tildes.
    private static func fenceRun(_ line: [UInt16]) -> (unit: UInt16, length: Int, rest: ArraySlice<UInt16>)? {
        var start = 0
        while start < 3, start < line.count, line[start] == UInt16(UInt8(ascii: " ")) { start += 1 }
        guard start < line.count, line[start] == tick || line[start] == tilde else { return nil }
        let unit = line[start]
        var end = start
        while end < line.count, line[end] == unit { end += 1 }
        return end - start >= 3 ? (unit, end - start, line[end...]) : nil
    }

    /// The desktop's `plainCode`: `unixLines(text).replace(/\n+$/u, '')`, in UTF-16 units.
    private static func plainCode(_ text: String) -> ArraySlice<UInt16> {
        var units = JSText.unixLines(text)[...]
        while units.last == JSText.lf { units = units.dropLast() }
        return units
    }
}

/// JavaScript's string rules where the wire depends on them: equality and lengths in UTF-16 code units (Swift's
/// `String ==` treats canonically equivalent text as equal; JS does not), and `\s` / `trim()`'s whitespace.
enum JSText {
    static let lf = UInt16(UInt8(ascii: "\n"))
    static let cr = UInt16(UInt8(ascii: "\r"))

    /// ECMAScript WhiteSpace and LineTerminator — what `\s` matches and `trim()` removes. All in the BMP.
    static func isWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    static func isBlank<C: Collection<UInt16>>(_ units: C) -> Bool { units.allSatisfy(isWhitespace) }

    static func trimmingEnd(_ units: ArraySlice<UInt16>) -> ArraySlice<UInt16> {
        var end = units.endIndex
        while end > units.startIndex, isWhitespace(units[end - 1]) { end -= 1 }
        return units[..<end]
    }

    /// `String.prototype.trim()`.
    static func trim(_ units: ArraySlice<UInt16>) -> ArraySlice<UInt16> {
        var start = units.startIndex
        while start < units.endIndex, isWhitespace(units[start]) { start += 1 }
        return trimmingEnd(units[start...])
    }

    static func string<C: Collection<UInt16>>(_ units: C) -> String { String(decoding: units, as: UTF16.self) }

    /// `new Set(values).size === values.length`.
    static func distinct(_ values: [String]) -> Bool { Set(values.map { Array($0.utf16) }).count == values.count }

    static func equal(_ a: String, _ b: String) -> Bool { a.utf16.elementsEqual(b.utf16) }

    /// `text.replaceAll(/\r\n?/g, '\n')`: every line end a `\n`.
    static func unixLines(_ text: String) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(text.utf16.count)
        var afterCR = false
        for unit in text.utf16 {
            if unit == cr {
                out.append(lf)
                afterCR = true
            } else {
                if !(afterCR && unit == lf) { out.append(unit) }
                afterCR = false
            }
        }
        return out
    }
}
