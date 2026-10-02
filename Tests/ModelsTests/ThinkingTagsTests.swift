import Foundation
import Testing

@testable import Models

// The desktop's `tests/unit/shared/utils/thinking-tags.test.ts` holds the same vectors.
private func text(_ t: String) -> ThinkingTags.Part { .init(.text, t) }
private func thinking(_ t: String) -> ThinkingTags.Part { .init(.thinking, t) }
private func split(_ s: String, final: Bool = true) -> [ThinkingTags.Part] { ThinkingTags.split(s, final: final) }

@Suite("ThinkingTags")
struct ThinkingTagsTests {
    @Test("text without tags is one text part; empty text is none")
    func plain() {
        #expect(split("hello world") == [text("hello world")])
        #expect(split("") == [])
    }

    @Test("a leading <thinking> span becomes thinking, the rest text")
    func leading() {
        #expect(
            split("<thinking>国庆假期，北京。用 map_itinerary 展示。</thinking>\n\n我来规划。")
                == [thinking("国庆假期，北京。用 map_itinerary 展示。"), text("我来规划。")])
    }

    @Test("<think>, any case, either closing name")
    func variants() {
        #expect(split("<think>\nplan\n</think>\nanswer") == [thinking("plan"), text("answer")])
        #expect(split("<THINKING>a</Thinking> b") == [thinking("a"), text("b")])
        #expect(split("<thinking>a</think>b") == [thinking("a"), text("b")])
    }

    @Test("spans on their own lines mid-text, several, adjacent ones joined")
    func several() {
        #expect(
            split("Intro.\n<think>one</think>\nMiddle.\n  <thinking>two</thinking>\nEnd.")
                == [text("Intro."), thinking("one"), text("Middle."), thinking("two"), text("End.")])
        #expect(split("<think>a</think>\n<think>b</think>\nc") == [thinking("a\n\nb"), text("c")])
    }

    @Test("prose, inline code, fences, other tags and attributes are left alone")
    func leftAlone() {
        for s in [
            "DeepSeek wraps reasoning in a <think> tag before answering.",
            "`<thinking>` is the tag",
            "Example:\n```xml\n<thinking>\nplan\n</thinking>\n```\nDone.",
            "<thinker>x</thinker> <div>y</div> a < b > c\n<thinkingcap>",
            "<think mode=\"x\">a</think>",
        ] {
            #expect(split(s) == [text(s)])
        }
    }

    @Test("a tilde fence closes; a span after it splits; a span may hold fences")
    func fences() {
        #expect(
            split("~~~\n<think>x</think>\n~~~\n<think>real</think>\nok")
                == [text("~~~\n<think>x</think>\n~~~"), thinking("real"), text("ok")])
        #expect(
            split("<thinking>try\n```\ncode\n```\n</thinking>\nanswer")
                == [thinking("try\n```\ncode\n```"), text("answer")])
    }

    @Test("an unclosed span is reasoning; an empty one vanishes")
    func unclosed() {
        #expect(split("<thinking>still going") == [thinking("still going")])
        #expect(split("Answer.\n<think>half") == [text("Answer."), thinking("half")])
        #expect(split("<think></think>\nhi") == [text("hi")])
    }

    @Test("streaming holds back a partial tag, final lets it out")
    func streaming() {
        #expect(split("<thi", final: false) == [])
        #expect(split("a\n<", final: false) == [text("a\n")])
        #expect(split("<THINK", final: false) == [])
        #expect(split("<thi", final: true) == [text("<thi")])
        #expect(split("<thx", final: false) == [text("<thx")])
        #expect(split("a <thi", final: false) == [text("a <thi")])
        #expect(split("<thinking>plan</thin", final: false) == [thinking("plan")])
    }

    @Test("every chunking of the screenshot answer ends the same, and no prefix shows a tag")
    func chunked() {
        let s = "<thinking>国庆假期，北京，避开热门景点。用 map_itinerary 展示。</thinking>\n\n好的，下面是行程。"
        let chars = Array(s)
        for size in 1...7 {
            var last: [ThinkingTags.Part] = []
            for end in stride(from: size, through: chars.count + size - 1, by: size) {
                last = split(String(chars[0..<min(end, chars.count)]), final: false)
                for part in last where part.kind == .text { #expect(!part.text.contains("<")) }
            }
            #expect(last == split(s))
        }
        #expect(split(s) == [thinking("国庆假期，北京，避开热门景点。用 map_itinerary 展示。"), text("好的，下面是行程。")])
    }

    @Test("an assistant message's contentBlocks carry the span as thinking; a user's are untouched")
    func contentBlocks() throws {
        let json = #"{"id":"a","role":"assistant","content":[{"type":"text","text":"<thinking>plan</thinking>\nGo."},{"type":"toolCall","id":"1","name":"map_itinerary","arguments":{}}]}"#
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        #expect(
            message.contentBlocks == [.thinking("plan"), .text("Go."), .toolCall(id: "1", name: "map_itinerary", arguments: [:])])
        let user = try JSONDecoder().decode(
            ChatMessage.self, from: Data(#"{"id":"u","role":"user","content":"<think>x</think>"}"#.utf8))
        #expect(user.contentBlocks == [.text("<think>x</think>")])
    }
}
