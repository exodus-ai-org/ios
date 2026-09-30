import Testing

@testable import ChatFeature

/// "Ask about this": the desktop's `quoted-text.ts`, held to the same vectors.
@Suite("QuotedText")
struct QuotedTextTests {
    @Test("a selection is written as a markdown quote")
    func block() {
        #expect(QuotedText.block("大金（6367）已经卖出，不再算持仓。") == "> 大金（6367）已经卖出，不再算持仓。")
        #expect(QuotedText.block("  a \n\nb\r\n") == "> a\n>\n> b")
    }

    @Test("a very long selection is cut")
    func cut() {
        let long = String(repeating: "x", count: QuotedText.maxLength + 50)
        #expect(QuotedText.block(long) == "> " + String(repeating: "x", count: QuotedText.maxLength) + "…")
    }

    @Test("what is sent: the quote, a blank line, what was typed")
    func compose() {
        #expect(QuotedText.compose(quote: "q", text: "  why?  ") == "> q\n\nwhy?")
    }

    @Test(
        "a message is read back as its quote and its question",
        arguments: [
            ("> q\n\nwhy?", "q", "why?"),
            ("> a\n> b\n>\n> c\n\nwhy?", "a\nb\n\nc", "why?"),
            (">q\n\nwhy?", "q", "why?"),
            ("> q\nwhy?", "q", "why?"),
            ("> only a quote", "only a quote", ""),
        ])
    func split(text: String, quote: String, body: String) {
        let parts = QuotedText.split(text)
        #expect(parts.quote == quote)
        #expect(parts.body == body)
    }

    @Test("a message that quotes nothing is left as it is")
    func noQuote() {
        #expect(QuotedText.split("why > not").quote == nil)
        #expect(QuotedText.split("why > not").body == "why > not")
        #expect(QuotedText.split("").quote == nil)
    }

    @Test("split gives back what compose was given")
    func roundTrip() {
        let parts = QuotedText.split(QuotedText.compose(quote: "a\n\nb", text: "why?"))
        #expect(parts.quote == "a\n\nb")
        #expect(parts.body == "why?")
    }
}
