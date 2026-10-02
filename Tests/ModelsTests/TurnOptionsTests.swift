import Foundation
import Testing

@testable import Models

/// The composer's choices as the desktop's route reads them (`postRequestBodySchema`).
@Suite("TurnOptions")
struct TurnOptionsTests {
    @Test("no choices ask for no tool and no effort")
    func noChoices() {
        let options = TurnOptions()
        #expect(options.advancedTools == [])
        #expect(options.wireReasoningEffort == nil)
    }

    @Test("Deep Research is named as the desktop's AdvancedTools names it")
    func deepResearch() {
        #expect(TurnOptions(deepResearch: true).advancedTools == ["Deep Research"])
    }

    @Test("a level is sent by its desktop name, and off is left out")
    func levels() {
        #expect(TurnOptions(reasoningEffort: .xhigh).wireReasoningEffort == "xhigh")
        #expect(TurnOptions(reasoningEffort: .max).wireReasoningEffort == "max")
        #expect(TurnOptions(reasoningEffort: .off).wireReasoningEffort == nil)
    }

    @Test("the levels are the desktop's EffortLevel, in its order")
    func order() {
        #expect(ReasoningEffort.allCases.map(\.rawValue) == ["off", "low", "medium", "high", "xhigh", "max"])
    }
}
