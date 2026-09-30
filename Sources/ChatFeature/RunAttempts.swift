import Foundation
import Models

/// Where a turn stands in a regenerate group, as the transcript draws it (spec 2026-09-26-regenerate-compare §1).
public enum TurnAttempt: Equatable, Sendable {
    /// One of the answers being compared: "Answer `position`" with Use this one.
    case comparing(position: Int)
    /// The answer that was picked; `otherVersions` are the folded runs, `canSwap` whether one may still replace it.
    case chosen(otherVersions: [String], canSwap: Bool)
}

/// What regenerate groups do to the transcript: which runs are hidden, which questions are shown once, and each visible
/// run's place in its group. Built from the runs' user messages only, so it is cheap to redo on every frame.
struct AttemptLayout: Equatable {
    /// Runs whose rows are not shown at all (`folded`, `hidden`).
    private(set) var hiddenRuns: Set<String> = []
    /// Runs whose question bubble is left out: the group's question is shown once, above its first answer.
    private(set) var hiddenQuestions: Set<String> = []
    private(set) var attempts: [String: TurnAttempt] = [:]

    static let empty = AttemptLayout()

    init() {}

    init(_ messages: [ChatMessage]) {
        let runs = RunAttempts.runs(in: messages)
        guard runs.contains(where: { $0.attempt != nil }) else { return }
        let lastGroup = runs.last?.group
        for (group, members) in Dictionary(grouping: runs, by: \.group) {
            let ordered = members.sorted { $0.order < $1.order }
            for member in ordered where member.attempt?.isVisible == false { hiddenRuns.insert(member.runId) }
            let shown = ordered.filter { $0.attempt?.isVisible == true }
            for member in shown.dropFirst() { hiddenQuestions.insert(member.runId) }
            let comparing = shown.filter { $0.attempt == .comparing }
            if comparing.count > 1 {
                for (index, member) in comparing.enumerated() { attempts[member.runId] = .comparing(position: index + 1) }
            }
            let folded = ordered.filter { $0.attempt == .folded }.map(\.runId)
            for member in shown where member.attempt == .chosen {
                attempts[member.runId] = .chosen(otherVersions: folded, canSwap: group == lastGroup)
            }
        }
    }
}

/// The desktop's attempt transitions (`src/main/lib/chat/attempts.ts`), applied to the phone's copy of the transcript
/// so it shows what the computer will store without waiting for a reload.
enum RunAttempts {
    struct Run: Equatable {
        let runId: String
        let group: String
        let attempt: RunAttempt?
        let order: Int
        let messageIndex: Int
    }

    /// Every run's user message, in order, with its group: `alternateOf`, else the run itself.
    static func runs(in messages: [ChatMessage]) -> [Run] {
        var runs: [Run] = []
        for (index, message) in messages.enumerated() where message.role == "user" {
            let runId = message.runId ?? message.id
            runs.append(
                Run(
                    runId: runId, group: message.alternateOf ?? runId, attempt: message.attempt, order: runs.count,
                    messageIndex: index))
        }
        return runs
    }

    /// The group Regenerate joins: the last run's `alternateOf`, or its own id when it has none.
    static func regenerateGroup(in messages: [ChatMessage]) -> String? {
        guard let last = messages.last(where: { $0.role == "user" }) else { return nil }
        return last.alternateOf ?? last.runId ?? last.id
    }

    /// A regenerated run joins `group` comparing: of the group's other runs, the newest shown one compares with it and
    /// every other one is hidden.
    static func regenerate(_ messages: [ChatMessage], newRunId: String, group: String) -> [ChatMessage] {
        var messages = messages
        let members = runs(in: messages).filter { $0.group == group && $0.runId != newRunId }
        let partner = members.last { $0.attempt == nil || $0.attempt?.isVisible == true }
        for member in members {
            set(member.runId == partner?.runId ? .comparing : .hidden, at: member.messageIndex, in: &messages)
        }
        if let index = messages.lastIndex(where: { $0.role == "user" && ($0.runId ?? $0.id) == newRunId }) {
            set(.comparing, at: index, in: &messages)
        }
        return messages
    }

    /// Choosing `runId`: it becomes the group's chosen answer and the one it was shown against is folded. Nil when the
    /// run is not in a group, or the lock rule refuses it (a later run exists and it was not already chosen).
    static func choose(_ messages: [ChatMessage], runId: String) -> [ChatMessage]? {
        let all = runs(in: messages)
        guard let target = all.first(where: { $0.runId == runId }), target.attempt != nil else { return nil }
        if target.attempt == .chosen { return messages }
        guard all.last?.group == target.group else { return nil }
        var messages = messages
        for member in all where member.group == target.group {
            if member.runId == runId {
                set(.chosen, at: member.messageIndex, in: &messages)
            } else if member.attempt == .comparing || member.attempt == .chosen {
                set(.folded, at: member.messageIndex, in: &messages)
            }
        }
        return messages
    }

    /// A new ordinary run while the last group still compares two answers: the newer is chosen and the other folded.
    static func autoChoose(_ messages: [ChatMessage]) -> [ChatMessage] {
        let all = runs(in: messages)
        guard let group = all.last?.group else { return messages }
        let comparing = all.filter { $0.group == group && $0.attempt == .comparing }
        guard comparing.count > 1, let newest = comparing.last else { return messages }
        return choose(messages, runId: newest.runId) ?? messages
    }

    private static func set(_ attempt: RunAttempt, at index: Int, in messages: inout [ChatMessage]) {
        messages[index].raw["attempt"] = .string(attempt.rawValue)
    }
}
