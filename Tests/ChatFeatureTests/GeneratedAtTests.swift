import Foundation
import Models
import Testing

@testable import ChatFeature

@Suite("The action bar's time")
struct GeneratedAtTests {
    private func bar(_ timestamp: String) -> TurnActionBar? {
        let json = #"""
            [{"id":"u1","runId":"u1","role":"user","content":"hi"},
             {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"Hello"}]\#(timestamp)}]
            """#
        let messages = try! JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
        var cache = RunGrouper.Cache()
        guard case .assistantTurn(let turn)? = RunGrouper.group(messages, cache: &cache).last else { return nil }
        return TurnActions.bar(for: turn, isStreaming: false, canRegenerate: false)
    }

    @Test("the bar carries when the answer was written, and nothing for a row without a time")
    func carriesTheTime() {
        #expect(bar(#","timestamp":1700000000000"#)?.generatedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(bar("")?.generatedAt == nil)
        #expect(bar(#","timestamp":0"#)?.generatedAt == nil)
    }

    @Test("short and relative, as the desktop's: now, then the largest whole unit; never in the future")
    func shortText() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let en = Locale(identifier: "en_US")
        #expect(GeneratedAtText.short(now.addingTimeInterval(-20), now: now, locale: en) == "now")
        #expect(GeneratedAtText.short(now.addingTimeInterval(-5 * 60), now: now, locale: en) == "5m ago")
        #expect(GeneratedAtText.short(now.addingTimeInterval(-3 * 3600), now: now, locale: en) == "3h ago")
        // A phone clock behind the computer's: still "now", not "in 1m".
        #expect(GeneratedAtText.short(now.addingTimeInterval(90), now: now, locale: en) == "now")
    }
}
