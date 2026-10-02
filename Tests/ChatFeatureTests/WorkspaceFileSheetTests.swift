import Foundation
import Models
import Testing

@testable import ChatFeature

private struct Unreachable: Error {}

private func loader(_ result: @escaping @Sendable (String) throws -> WorkspaceFile) -> WorkspaceFileLoader {
    WorkspaceFileLoader { path in try result(path) }
}

private let rules = WorkspaceFile(
    path: "/Users/me/.exodus/workspace/c1/investment-rules.md", name: "investment-rules.md", size: 31,
    kind: .markdown, content: "# Rules\n\n- Buy low.\n- Sell high.\n")

@Suite("The file sheet: what the View button shows")
@MainActor
struct WorkspaceFileSheetModelTests {
    @Test("a Markdown file is shown parsed, with its name as the title and its text for Copy")
    func markdown() async {
        let model = WorkspaceFileSheetModel(path: "investment-rules.md", loader: loader { _ in rules })
        #expect(model.state == .loading)
        await model.load()
        #expect(model.state == .loaded(rules))
        #expect(model.markdown?.blocks.isEmpty == false)
        #expect(model.fileName == "investment-rules.md")
        #expect(model.text == rules.content)
    }

    @Test("plain text is not parsed as Markdown")
    func text() async {
        let log = WorkspaceFile(path: "/w/c1/log.txt", name: "log.txt", size: 5, kind: .text, content: "# not a heading")
        let model = WorkspaceFileSheetModel(path: "/w/c1/log.txt", loader: loader { _ in log })
        await model.load()
        #expect(model.state == .loaded(log))
        #expect(model.markdown == nil)
    }

    @Test("the path the card holds is the one asked for")
    func asksForThePath() async {
        let model = WorkspaceFileSheetModel(path: "/w/c1/a.md") {
            #expect($0 == "/w/c1/a.md")
            return rules
        }
        await model.load()
    }

    @Test(
        "each refusal is its own fallback; only an unreachable computer offers to try again",
        arguments: [
            (HTTPError(statusCode: 413, code: "FILE_TOO_LARGE", message: ""), WorkspaceFileSheetModel.Fallback.tooLarge),
            (HTTPError(statusCode: 415, code: "FILE_NOT_TEXT", message: ""), .notText),
            (HTTPError(statusCode: 404, code: "FILE_NOT_FOUND", message: ""), .notFound),
            (HTTPError(statusCode: 403, code: "OUTSIDE_WORKSPACE", message: ""), .outsideWorkspace),
            (HTTPError(statusCode: 400, code: "INVALID_PATH", message: ""), .outsideWorkspace),
            // A computer without the route answers Hono's bare 404.
            (HTTPError(statusCode: 404, code: "UNKNOWN_ERROR", message: "404 Not Found"), .unreachable),
            (HTTPError(statusCode: 423, code: "APP_LOCKED", message: ""), .unreachable),
            (HTTPError(statusCode: 500, code: "FILE_READ_FAILED", message: ""), .unreachable),
        ])
    func fallbacks(error: HTTPError, expected: WorkspaceFileSheetModel.Fallback) async {
        let model = WorkspaceFileSheetModel(path: "a.md", loader: loader { _ in throw error })
        await model.load()
        #expect(model.state == .failed(expected))
        #expect(expected.canRetry == (expected == .unreachable))
        #expect(!expected.message.isEmpty)
        #expect(model.text == nil)
        #expect(model.fileName == "a.md")
    }

    @Test("no answer at all reads as unreachable, and trying again loads the file")
    func retry() async {
        let calls = Counter()
        let model = WorkspaceFileSheetModel(path: "investment-rules.md") { _ in
            if calls.next() == 1 { throw Unreachable() }
            return rules
        }
        await model.load()
        #expect(model.state == .failed(.unreachable))
        await model.load()
        #expect(model.state == .loaded(rules))
    }

    @Test("a screenshot of the sheet is “<file name> · <chat title>”")
    func screenTitle() {
        #expect(
            WorkspaceFileSheetModel.screenTitle(fileName: "investment-rules.md", chatTitle: "Retirement plan")
                == "investment-rules.md · Retirement plan")
        #expect(WorkspaceFileSheetModel.screenTitle(fileName: "a.md", chatTitle: nil) == "a.md")
    }
}

@Suite("WorkspaceFile: the route's answer")
struct WorkspaceFileDecodingTests {
    @Test("decodes the route's JSON; a kind the phone does not know is plain text")
    func decodes() throws {
        let json = """
            {"path":"/w/c1/a.csv","name":"a.csv","size":3,"modifiedAt":1759380000000.5,"kind":"table","content":"a,b"}
            """
        let file = try JSONDecoder().decode(WorkspaceFile.self, from: Data(json.utf8))
        #expect(file.kind == .text)
        #expect(file.size == 3 && file.content == "a,b" && file.modifiedAt == 1_759_380_000_000.5)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}

extension WorkspaceFileSheetModel {
    convenience init(path: String, fetch: @escaping @Sendable (String) async throws -> WorkspaceFile) {
        self.init(path: path, loader: WorkspaceFileLoader(fetch: fetch))
    }
}
