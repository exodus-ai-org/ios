import Foundation
import Models
import Testing

@testable import ChatFeature

private func value(_ json: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func rows(_ result: LineDiff.Result) -> [LineDiff.Item] {
    if case .lines(let items, _, _) = result { items } else { [] }
}

private func context(_ text: String) -> LineDiff.Item { .row(.init(kind: .context, text: text)) }
private func added(_ text: String) -> LineDiff.Item { .row(.init(kind: .added, text: text)) }
private func removed(_ text: String) -> LineDiff.Item { .row(.init(kind: .removed, text: text)) }

@Suite("Line diff: edit_file's old_string → new_string")
struct LineDiffTests {
    @Test("two empty strings have no lines and no changes; empty to text adds every line, text to empty removes them")
    func empty() {
        #expect(LineDiff.diff(old: "", new: "") == .lines(items: [], added: 0, removed: 0))
        #expect(LineDiff.diff(old: "", new: "a\nb") == .lines(items: [added("a"), added("b")], added: 2, removed: 0))
        #expect(LineDiff.diff(old: "a\nb\n", new: "") == .lines(items: [removed("a"), removed("b")], added: 0, removed: 2))
    }

    @Test("an unchanged text is all context, with nothing folded away")
    func identical() {
        let text = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let result = LineDiff.diff(old: text, new: text)
        #expect(result.added == 0 && result.removed == 0)
        #expect(rows(result).count == 20)
    }

    @Test("a whole-file replace with no line in common is every old line removed, then every new line added")
    func wholeFileReplace() {
        let result = LineDiff.diff(old: "a\nb\nc", new: "x\ny")
        #expect(rows(result) == [removed("a"), removed("b"), removed("c"), added("x"), added("y")])
        #expect(result.added == 2 && result.removed == 3)
    }

    @Test("a changed line inside kept lines is removed then added, in place")
    func middleChange() {
        let old = "struct RetryPolicy {\n    var maxAttempts = 3\n}"
        let new = "struct RetryPolicy {\n    var maxAttempts = 5\n    var backoff = 2.0\n}"
        #expect(
            rows(LineDiff.diff(old: old, new: new)) == [
                context("struct RetryPolicy {"), removed("    var maxAttempts = 3"), added("    var maxAttempts = 5"),
                added("    var backoff = 2.0"), context("}"),
            ])
    }

    @Test("CRLF and LF line endings compare equal, so only the real change shows")
    func crlf() {
        let result = LineDiff.diff(old: "a\r\nb\r\nc\r\n", new: "a\nB\nc\n")
        #expect(rows(result) == [context("a"), removed("b"), added("B"), context("c")])
        #expect(LineDiff.lines(of: "a\r\nb") == ["a", "b"])
        #expect(LineDiff.lines(of: "a\n") == ["a"])
        #expect(LineDiff.lines(of: "\n") == [""])
    }

    @Test("a very long line is cut for display but compared whole")
    func longLines() throws {
        let long = String(repeating: "x", count: 10_000)
        let result = LineDiff.diff(old: long + "a", new: long + "b")
        #expect(result.added == 1 && result.removed == 1)
        let texts = rows(result).compactMap { if case .row(let row) = $0 { row.text } else { nil } }
        #expect(texts.count == 2)
        #expect(texts.allSatisfy { $0.count == LineDiff.maxLineLength + 1 && $0.hasSuffix("…") })
    }

    @Test("unchanged runs keep three lines of context by a change and fold the rest")
    func contextFolding() {
        let old = (1...20).map { "\($0)" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "\n10\n", with: "\nten\n")
        let items = rows(LineDiff.diff(old: old, new: new))
        #expect(
            items == [
                .gap(6), context("7"), context("8"), context("9"), removed("10"), added("ten"), context("11"),
                context("12"), context("13"), .gap(7),
            ])
    }

    @Test("a fold that would hide a single line shows the line instead")
    func noSingleLineGap() {
        let items = rows(LineDiff.diff(old: "1\n2\n3\n4\nold", new: "1\n2\n3\n4\nnew"))
        #expect(items == [context("1"), context("2"), context("3"), context("4"), removed("old"), added("new")])
        let folded = rows(LineDiff.diff(old: "1\n2\n3\n4\n5\nold", new: "1\n2\n3\n4\n5\nnew"))
        #expect(folded.first == .gap(2))
    }

    @Test("past the cell cap the diff is refused with both line counts; a shared head and tail do not count")
    func tooLarge() {
        let old = (1...600).map { "old \($0)" }.joined(separator: "\n")
        let new = (1...600).map { "new \($0)" }.joined(separator: "\n")
        #expect(LineDiff.diff(old: old, new: new) == .tooLarge(oldLines: 600, newLines: 600))
        #expect(LineDiff.diff(old: old, new: new).added == 600)

        let file = (1...5_000).map { "line \($0)" }
        var edited = file
        edited[2_500] = "changed"
        let big = LineDiff.diff(old: file.joined(separator: "\n"), new: edited.joined(separator: "\n"))
        #expect(big.added == 1 && big.removed == 1)
        #expect(rows(big).count == 10)
        #expect(LineDiff.diff(old: "a\nb", new: "c\nd", maxCells: 3) == .tooLarge(oldLines: 2, newLines: 2))
    }
}

@Suite("File cards: models built from the desktop's shapes")
struct FileCardModelTests {
    private func card(_ tool: String, _ arguments: String?, _ details: String?, error: String? = nil) -> ToolCardContent {
        ToolCard(
            id: "t", toolName: tool, kind: .generic, payload: details.map(value), arguments: arguments.map(value),
            isError: error != nil, errorText: error
        ).content
    }

    @Test("read_file {path, content, size}: a preview capped at 200 lines, each line cut to a wrappable length")
    func readFile() throws {
        let content = (1...300).map { "line \($0)" }.joined(separator: "\n")
        let escaped = content.replacingOccurrences(of: "\n", with: "\\n")
        let details = #"{"path":"/x/Pipeline.swift","content":"\#(escaped)","size":2400}"#
        let model = try #require(card("read_file", #"{"path":"/x/Pipeline.swift"}"#, details).readFile)
        guard case .read(let preview, let size) = model.state else {
            Issue.record("not read")
            return
        }
        #expect(size == 2400)
        #expect(preview.totalLines == 300)
        #expect(preview.lines.count == FilePreview.cap)
        #expect(preview.linesPastCap == 100)
        #expect(preview.text == content)
        #expect(FilePreview("").isEmpty)
        #expect(FilePreview(String(repeating: "y", count: 5_000)).lines.first?.count == LineDiff.maxLineLength + 1)
    }

    @Test("read_file asked for base64 is not shown as text")
    func readBinary() {
        let model = card("read_file", #"{"path":"/a.png","encoding":"base64"}"#, #"{"path":"/a.png","content":"iVBORw0K","size":8}"#)
            .readFile
        #expect(model?.state == .binary(size: 8))
    }

    @Test("write_file: bytes and appended from the result, the preview from the arguments' content")
    func writeFile() {
        let model = card(
            "write_file", ###"{"path":"/c/CHANGELOG.md","content":"## 1.4.1\n- Retry","append":true}"###,
            #"{"path":"/c/CHANGELOG.md","bytes":96,"appended":true}"#
        ).writeFile
        #expect(model?.state == .written(bytes: 96, appended: true))
        #expect(model?.preview?.lines == ["## 1.4.1", "- Retry"])
        let noBytes = card("write_file", #"{"path":"/a","content":"é"}"#, #"{"path":"/a"}"#).writeFile
        #expect(noBytes?.state == .written(bytes: 2, appended: false))
        #expect(card("write_file", nil, #"{"path":"/a","bytes":3}"#).writeFile?.preview == nil)
    }

    @Test("edit_file: the diff from old_string/new_string; the replacement line only for several replacements")
    func editFile() throws {
        let one = try #require(
            card(
                "edit_file", #"{"path":"/a","old_string":"x = 1","new_string":"x = 2"}"#,
                #"{"path":"/a","replacements":1,"linesBefore":42,"linesAfter":42}"#
            ).editFile)
        #expect(one.diff?.added == 1 && one.diff?.removed == 1)
        #expect(one.replacementSummary == nil)
        let four = try #require(
            card(
                "edit_file", #"{"path":"/t","old_string":"Color.blue","new_string":"Color.accentColor","replace_all":true}"#,
                #"{"path":"/t","replacements":4,"linesBefore":88,"linesAfter":88}"#
            ).editFile)
        #expect(four.replacementSummary?.count == 4)
        #expect(four.replacementSummary?.before == 88)
    }

    @Test("a failed call keeps the path from its arguments and the tool's own error text")
    func failures() {
        let edit = card(
            "edit_file", #"{"path":"/a.swift","old_string":"a","new_string":"b"}"#, nil, error: "old_string appears 3 times")
            .editFile
        #expect(edit?.isFailed == true)
        #expect(edit?.state == .failed("old_string appears 3 times"))
        #expect(edit?.diff?.added == 1)
        #expect(card("write_file", #"{"filePath":"/etc/hosts"}"#, nil, error: "EACCES").writeFile?.path == "/etc/hosts")
        #expect(card("read_file", nil, nil, error: "").readFile?.state == .failed(""))
        #expect(ToolCard(id: "t", toolName: "read_file", kind: .generic, isError: true).content.readFile?.state == .failed(nil))
    }
}

@Suite("File cards: an edit card starts open for one edit, as counts from three")
struct FileCardCollapseTests {
    private func run(edits: Int) -> AssistantTurn {
        var messages = [decode(#"{"id":"u","runId":"u","role":"user","content":"q","timestamp":1}"#)]
        for index in 0..<edits {
            messages.append(
                decode(
                    #"{"id":"a\#(index)","runId":"u","role":"assistant","content":[{"type":"toolCall","id":"k\#(index)","name":"edit_file","arguments":{"path":"/f\#(index)","old_string":"a","new_string":"b"}}],"stopReason":"toolUse","timestamp":2}"#
                ))
            messages.append(
                decode(
                    #"{"id":"t\#(index)","runId":"u","role":"toolResult","toolCallId":"k\#(index)","toolName":"edit_file","content":[{"type":"text","text":"ok"}],"details":{"path":"/f\#(index)","replacements":1},"isError":false,"timestamp":3}"#
                ))
        }
        var cache = RunGrouper.Cache()
        return RunGrouper.group(messages, cache: &cache).compactMap { if case .assistantTurn(let t) = $0 { t } else { nil } }
            .first!
    }

    @Test("1 or 2 edits in a run start open; 3 or more start collapsed")
    func rule() {
        #expect(FileCardRules.editsStartOpen(editCount: 1))
        #expect(FileCardRules.editsStartOpen(editCount: 2))
        #expect(!FileCardRules.editsStartOpen(editCount: 3))
        #expect(!FileCardRules.editsStartOpen(editCount: 7))
    }

    @Test("the count is the run's edit_file cards")
    func count() {
        #expect(FileCardRules.editCount(in: run(edits: 1)) == 1)
        #expect(FileCardRules.editsStartOpen(editCount: FileCardRules.editCount(in: run(edits: 1))))
        #expect(FileCardRules.editCount(in: run(edits: 3)) == 3)
        #expect(!FileCardRules.editsStartOpen(editCount: FileCardRules.editCount(in: run(edits: 3))))
    }
}

@Suite("File cards: copy")
struct FileCardTextTests {
    @Test("line counts, write summaries and the diff's VoiceOver labels read as sentences")
    func text() {
        #expect(FileCardText.lineCount(1) == "1 line")
        #expect(FileCardText.lineCount(12) == "12 lines")
        #expect(FileCardText.writeSummary(bytes: nil, appended: true) == "Appended")
        #expect(FileCardText.diffStat(added: 4, removed: 3) == "4 lines added, 3 removed")
        #expect(FileCardText.replacements(4, before: 88, after: 88) == "Replaced 4 occurrences · 88 → 88 lines")
        #expect(FileCardText.replacements(4, before: nil, after: 88) == "Replaced 4 occurrences")
        #expect(FileCardText.accessibilityLine(.init(kind: .added, text: "let a = 2")) == "Added: let a = 2")
        #expect(FileCardText.accessibilityLine(.init(kind: .context, text: "}")) == "}")
    }
}
