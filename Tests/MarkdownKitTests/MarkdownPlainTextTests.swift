import Testing

@testable import MarkdownKit

/// A search result's snippet is whatever the page or the search engine wrote — markdown, HTML, both — and is shown
/// as a line of plain words: the desktop's `remove-markdown`.
@Suite("MarkdownPlainText")
struct MarkdownPlainTextTests {
    @Test(
        "markup is taken off, the words stay",
        arguments: [
            ("**Bold** and *italic* and ~~gone~~", "Bold and italic and gone"),
            ("Read [the guide](https://example.com/guide) first", "Read the guide first"),
            ("Run `swift build` then test", "Run swift build then test"),
            ("# Heading\n\nA paragraph.", "Heading A paragraph."),
            ("- first\n- second\n  - nested", "first second nested"),
            ("1. one\n2. two", "one two"),
            ("> quoted words", "quoted words"),
            ("![a chart](https://example.com/c.png) follows", "a chart follows"),
            ("| a | b |\n|---|---|\n| 1 | 2 |", "a b 1 2"),
            ("line one\nline two", "line one line two"),
        ])
    func strips(source: String, expected: String) {
        #expect(MarkdownPlainText.strip(source) == expected)
    }

    @Test("HTML tags go, what they wrap stays, and entities are read")
    func html() {
        #expect(MarkdownPlainText.strip("Swift <strong>6.2</strong> is out") == "Swift 6.2 is out")
        #expect(MarkdownPlainText.strip("Tom &amp; Jerry&#x27;s") == "Tom & Jerry's")
        #expect(MarkdownPlainText.strip("<p>A paragraph</p>") == "A paragraph")
    }

    @Test("a code block gives its code")
    func codeBlock() {
        #expect(MarkdownPlainText.strip("Try:\n\n```swift\nlet a = 1\n```") == "Try: let a = 1")
    }

    @Test("plain text comes back as it is, its white space collapsed")
    func plain() {
        #expect(MarkdownPlainText.strip("Costs $200 - $300,  snake_case_name") == "Costs $200 - $300, snake_case_name")
        #expect(MarkdownPlainText.strip("  \n ") == "")
        #expect(MarkdownPlainText.strip("19~32°C and 2 * 3 = 6") == "19~32°C and 2 * 3 = 6")
    }
}
