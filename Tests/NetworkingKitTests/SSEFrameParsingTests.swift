import Models
import Testing

@testable import NetworkingKit

@Suite("SSEFrameParsing")
struct SSEFrameParsingTests {
    @Test("decodes a well-formed data line")
    func decodesDataLine() {
        let event = SSEFrameParsing.decodeEvent(
            fromLine: #"data: {"type":"title","title":"héllo 世界"}"#)
        guard case .title(let title) = event else {
            Issue.record("expected .title, got \(String(describing: event))")
            return
        }
        #expect(title == "héllo 世界")
    }

    @Test("ignores lines that aren't a data: frame")
    func ignoresNonDataLines() {
        #expect(SSEFrameParsing.decodeEvent(fromLine: "") == nil)
        #expect(SSEFrameParsing.decodeEvent(fromLine: "event: ping") == nil)
    }

    @Test("ignores a data: line with an empty payload")
    func ignoresEmptyPayload() {
        #expect(SSEFrameParsing.decodeEvent(fromLine: "data: ") == nil)
    }

    @Test("ignores genuinely malformed JSON instead of throwing")
    func ignoresMalformedJSON() {
        #expect(SSEFrameParsing.decodeEvent(fromLine: "data: {not json") == nil)
    }
}
