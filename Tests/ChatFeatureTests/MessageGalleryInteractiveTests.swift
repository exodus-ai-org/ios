#if DEBUG
import Testing

@testable import ChatFeature

@Suite("MessageGalleryFixtures: the interactive blocks' runs")
struct MessageGalleryInteractiveTests {
    @Test("ask, confirm and answered name the last three runs; another name is none")
    func namedSections() {
        let count = MessageGalleryFixtures.runs.count
        #expect(MessageGalleryFixtures.namedSection("ask") == count - 3)
        #expect(MessageGalleryFixtures.namedSection("confirm") == count - 2)
        #expect(MessageGalleryFixtures.namedSection("answered") == count - 1)
        #expect(MessageGalleryFixtures.namedSection("questionnaire") == nil)
    }

    @Test("the answered run's answer names the run of its questionnaire, so the block is drawn frozen")
    func answeredFreezes() throws {
        let index = try #require(MessageGalleryFixtures.namedSection("answered"))
        let segments = MessageGalleryFixtures.segments(MessageGalleryFixtures.runs[index].json)
        let asking = try #require(
            segments.compactMap { segment -> AssistantTurn? in
                if case .assistantTurn(let turn) = segment, turn.body.contains("```exodus-ask") { turn } else { nil }
            }.first)
        let answer = try #require(
            segments.compactMap { segment -> InteractiveAnswer.Head? in
                if case .user(let message) = segment { InteractiveAnswer.split(message.answerText).head } else { nil }
            }.first)
        #expect(answer.ref == asking.runId)
        #expect(InteractiveRendering.answers(in: segments)[asking.runId] != nil)
    }
}
#endif
