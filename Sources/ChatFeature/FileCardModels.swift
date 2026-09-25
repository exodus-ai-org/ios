import Foundation
import Models

/// A file's text made ready to draw: its first `cap` lines, each cut to a length a phone can wrap, and how many lines
/// it has in all. Built once with the card, never while it draws.
struct FilePreview: Equatable, Sendable {
    let lines: [String]
    let totalLines: Int
    /// The whole text, for Copy / Share and the full-file sheet.
    let text: String

    static let cap = 200

    init(_ text: String, cap: Int = cap, maxLineLength: Int = LineDiff.maxLineLength) {
        let all = LineDiff.lines(of: text)
        lines = all.prefix(cap).map { LineDiff.clip($0, to: maxLineLength) }
        totalLines = all.count
        self.text = text
    }

    var isEmpty: Bool { totalLines == 0 }
    /// Lines past the inline cap: the rest is read in the sheet.
    var linesPastCap: Int { totalLines - lines.count }
}

/// A file tool that failed: the path it was given (when its call is in the run) and the tool's own error text.
struct FailedFileCall: Equatable, Sendable {
    let path: String
    /// Nil when the tool gave no text; the card says the tool failed.
    let message: String?
}

struct ReadFileCardModel: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case read(FilePreview, size: Int?)
        /// Asked for as base64: the text is not the file's, so it is not shown.
        case binary(size: Int?)
        case failed(String?)
    }

    let path: String
    let state: State

    init(_ call: DecodedCall<ReadFileArguments, ReadFileResult>) {
        path = call.result.path.isEmpty ? (call.arguments?.path ?? "") : call.result.path
        state =
            call.arguments?.encoding == "base64"
            ? .binary(size: call.result.size) : .read(FilePreview(call.result.content), size: call.result.size)
    }

    init(_ failure: FailedFileCall) {
        path = failure.path
        state = .failed(failure.message)
    }
}

struct WriteFileCardModel: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case written(bytes: Int?, appended: Bool)
        case failed(String?)
    }

    let path: String
    let state: State
    /// What was written, from the call's arguments; nil when the call is not in the run.
    let preview: FilePreview?

    init(_ call: DecodedCall<WriteFileArguments, WriteFileResult>) {
        path = call.result.path
        let bytes = call.result.bytes ?? call.arguments.map { $0.content.utf8.count }
        state = .written(bytes: bytes, appended: call.result.appended)
        preview = call.arguments.map { FilePreview($0.content) }
    }

    init(_ failure: FailedFileCall) {
        path = failure.path
        state = .failed(failure.message)
        preview = nil
    }
}

struct EditFileCardModel: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case edited(replacements: Int?, linesBefore: Int?, linesAfter: Int?, replaceAll: Bool)
        case failed(String?)
    }

    let path: String
    let state: State
    /// Built from the call's `old_string` / `new_string`; nil when the call is not in the run.
    let diff: LineDiff.Result?

    init(_ call: DecodedCall<EditFileArguments, EditFileResult>) {
        path = call.result.path
        state = .edited(
            replacements: call.result.replacements, linesBefore: call.result.linesBefore,
            linesAfter: call.result.linesAfter, replaceAll: call.arguments?.replaceAll ?? false)
        diff = call.arguments.map { LineDiff.diff(old: $0.oldString, new: $0.newString) }
    }

    init(_ failure: FailedFileCall, arguments: EditFileArguments?) {
        path = failure.path
        state = .failed(failure.message)
        diff = arguments.map { LineDiff.diff(old: $0.oldString, new: $0.newString) }
    }

    var isFailed: Bool { if case .failed = state { true } else { false } }

    /// "Replaced N occurrences · a → b lines" is worth a line only when more than one place changed.
    var replacementSummary: (count: Int, before: Int?, after: Int?)? {
        guard case .edited(let count?, let before, let after, let replaceAll) = state, count > 1 || replaceAll else {
            return nil
        }
        return (count, before, after)
    }
}

/// When an edit card starts open: one or two edits in a run are read one by one; from three on, the run is a
/// refactor and its cards start as +/− counts.
enum FileCardRules {
    static let collapseEditsFrom = 3

    static func editsStartOpen(editCount: Int) -> Bool { editCount < collapseEditsFrom }

    static func editCount(in turn: AssistantTurn) -> Int { turn.toolCards.count { $0.toolName == "edit_file" } }

    /// The file's name, and the folder it sits in, as a card's title and subtitle.
    static func fileName(_ path: String) -> String { (path as NSString).lastPathComponent }

    static func directory(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
}
