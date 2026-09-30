import Foundation
import Models
import Testing

@testable import ChatFeature

@Suite("TurnFoot: what stands under an answer, in order")
struct TurnFootTests {
    private let bar = TurnActionBar(copyText: "Answer", showsRegenerate: false, sourceCount: 0)

    private func turn(memoryUpdates: [MemoryUpdate] = [], attempt: TurnAttempt? = nil) -> AssistantTurn {
        var turn = AssistantTurn(runId: "r1", body: "Answer", foot: RunFoot(memoryUpdates: memoryUpdates))
        turn.attempt = attempt
        return turn
    }

    @Test("the action row closes a turn: what the run asked for, read and changed stands over it")
    func order() {
        let changed = MemoryUpdate(id: "m1", status: .pending)
        let rows = TurnFoot.rows(
            for: turn(memoryUpdates: [changed], attempt: .chosen(otherVersions: ["r0"], canSwap: true)), bar: bar,
            showsOtherVersions: true)
        #expect(rows == [.approvals, .usedMemories, .memoryChanges, .actionBar, .otherVersions])
    }

    @Test("the other-version link is hidden for now; the choice behind it is not")
    func otherVersionsHidden() {
        let chosen = turn(attempt: .chosen(otherVersions: ["r0"], canSwap: true))
        #expect(!TurnFoot.rows(for: chosen, bar: bar).contains(.otherVersions))
        #expect(chosen.attempt == .chosen(otherVersions: ["r0"], canSwap: true))
    }

    @Test("an ordinary answer: the memories it read, then its actions")
    func ordinary() {
        #expect(TurnFoot.rows(for: turn(), bar: bar) == [.approvals, .usedMemories, .actionBar])
    }

    @Test("a turn with nothing to act on has no action row; what it read is still said")
    func noBar() {
        #expect(TurnFoot.rows(for: turn(), bar: nil) == [.approvals, .usedMemories])
    }

    @Test("an answer being compared, or chosen with nothing folded behind it, has no other-version link")
    func noOtherVersions() {
        #expect(!TurnFoot.rows(for: turn(attempt: .comparing(position: 1)), bar: bar).contains(.otherVersions))
        #expect(
            !TurnFoot.rows(for: turn(attempt: .chosen(otherVersions: [], canSwap: false)), bar: bar)
                .contains(.otherVersions))
    }
}
