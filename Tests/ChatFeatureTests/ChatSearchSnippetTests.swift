import Testing

@testable import ChatFeature

@Suite("ChatSearchSnippet")
struct ChatSearchSnippetTests {
    @Test("windows around the first match: 40 characters before, 80 after, ellipses on both cut ends")
    func windowsAroundTheMatch() throws {
        let text = String(repeating: "a", count: 100) + "NEEDLE" + String(repeating: "b", count: 100)
        let snippet = try #require(ChatSearchSnippet.make(from: text, query: "needle"))
        #expect(snippet == "…" + String(repeating: "a", count: 40) + "NEEDLE" + String(repeating: "b", count: 80) + "…")
    }

    @Test("no ellipsis when the window reaches both ends of the text")
    func shortTextIsReturnedWhole() throws {
        #expect(ChatSearchSnippet.make(from: "alpha needle omega", query: "needle") == "alpha needle omega")
    }

    @Test("matching ignores case and diacritics")
    func matchIgnoresCaseAndDiacritics() throws {
        let text = String(repeating: "x", count: 60) + "Café au lait" + String(repeating: "y", count: 10)
        let snippet = try #require(ChatSearchSnippet.make(from: text, query: "CAFE"))
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.contains("Café au lait"))
    }

    @Test("runs of whitespace and newlines collapse to single spaces")
    func whitespaceCollapses() {
        #expect(ChatSearchSnippet.make(from: "one\n\n  two\tthree", query: "two") == "one two three")
    }

    @Test("a text without the query falls back to its first 120 characters")
    func noMatchFallsBackToTheStart() throws {
        let text = String(repeating: "z", count: 300)
        let snippet = try #require(ChatSearchSnippet.make(from: text, query: "missing"))
        #expect(snippet == String(repeating: "z", count: 120) + "…")
    }

    @Test("a nil, empty or blank text has no snippet")
    func emptyTextHasNoSnippet() {
        #expect(ChatSearchSnippet.make(from: nil, query: "a") == nil)
        #expect(ChatSearchSnippet.make(from: "", query: "a") == nil)
        #expect(ChatSearchSnippet.make(from: " \n\t ", query: "a") == nil)
    }

    @Test("CJK text has no spaces to break on and is windowed by characters")
    func cjkIsWindowedByCharacters() throws {
        let text = String(repeating: "前", count: 60) + "台积电" + String(repeating: "后", count: 100)
        let snippet = try #require(ChatSearchSnippet.make(from: text, query: "台积电"))
        #expect(snippet == "…" + String(repeating: "前", count: 40) + "台积电" + String(repeating: "后", count: 80) + "…")
    }

    @Test("collapsedWhitespace joins words with single spaces and trims the ends")
    func collapsedWhitespace() {
        #expect("  a \n\n b\tc  ".collapsedWhitespace == "a b c")
        #expect("".collapsedWhitespace == "")
    }
}
