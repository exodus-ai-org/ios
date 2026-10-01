import Testing

@testable import Models

struct HealthContextTests {
    @Test func composeIsAFencedBlockThenTheQuestion() {
        let text = HealthContext.compose(json: #"{"steps":1}"#, question: "  Why am I tired?\n")
        #expect(text == "```exodus-health\n{\"steps\":1}\n```\n\nWhy am I tired?")
    }

    @Test func splitReturnsTheBlockAndTheQuestion() {
        let parts = HealthContext.split("```exodus-health\n{\"a\":1}\n```\n\nHow did I sleep?")
        #expect(parts.json == #"{"a":1}"#)
        #expect(parts.body == "How did I sleep?")
    }

    @Test func roundTripsMultiLineJSON() {
        let json = "{\n  \"a\" : 1\n}"
        let parts = HealthContext.split(HealthContext.compose(json: json, question: "q"))
        #expect(parts.json == json)
        #expect(parts.body == "q")
    }

    @Test func onlyALeadingBlockCounts() {
        let text = "Look at this:\n```exodus-health\n{}\n```"
        let parts = HealthContext.split(text)
        #expect(parts.json == nil)
        #expect(parts.body == text)
    }

    @Test func anUnclosedBlockIsJustText() {
        let text = "```exodus-health\n{\"a\":1}"
        #expect(HealthContext.split(text).json == nil)
    }

    @Test func aBlockWithNoQuestionHasAnEmptyBody() {
        let parts = HealthContext.split("```exodus-health\n{}\n```")
        #expect(parts.json == "{}")
        #expect(parts.body.isEmpty)
    }

    @Test func encodesAValueWithSortedKeys() throws {
        struct V: Encodable { let b = 2, a = 1 }
        let text = try HealthContext.compose(V(), question: "q")
        #expect(text.hasPrefix("```exodus-health\n{\"a\":1,\"b\":2}\n```"))
    }
}
