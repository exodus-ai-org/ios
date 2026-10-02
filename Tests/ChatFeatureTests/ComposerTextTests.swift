import Foundation
import Models
import Testing

@testable import ChatFeature

/// The English the catalog's keys fall back to (the test bundle carries no catalog).
@Suite("The composer's strings")
struct ComposerTextTests {
    @Test("the levels read as on the desktop")
    func levels() {
        #expect(ReasoningEffort.allCases.map(ComposerText.level) == ["Off", "Low", "Medium", "High", "Extra high", "Max"])
    }

    @Test("the reasoning pill names the level")
    func pill() {
        #expect(ComposerText.reasoningPill(.high) == "Reasoning: High")
        #expect(ComposerText.reasoningPill(.xhigh) == "Reasoning: Extra high")
    }

    @Test("a picture's ✕ says which picture it removes")
    func removePicture() {
        #expect(ComposerText.removePicture(2, of: 3) == "Remove picture 2 of 3")
    }

    @Test("one unreadable picture, and several")
    func unreadable() {
        #expect(ComposerText.unreadable(1) == "A picture couldn’t be read and was left out.")
        #expect(ComposerText.unreadable(3) == "3 pictures couldn’t be read and were left out.")
    }

    @Test("a tool without a description says so")
    func noDescription() {
        #expect(ComposerText.noDescription("get_me") == "No description for get_me.")
    }
}
