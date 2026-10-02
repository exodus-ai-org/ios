import Foundation

/// A reasoning effort, as the desktop's `EffortLevel` (`settings-schema.ts`), in its order. `off` asks for no
/// reasoning option.
public enum ReasoningEffort: String, CaseIterable, Sendable, Hashable {
    case off, low, medium, high, xhigh, max
}

/// What a send asks of the run besides the question: the composer's `+` choices (the desktop's `advancedToolsAtom` and
/// `reasoningEffortAtom`), read when the turn starts.
public struct TurnOptions: Equatable, Sendable {
    /// The desktop's `AdvancedTools.DeepResearch`, as `advancedTools` carries it.
    public static let deepResearchTool = "Deep Research"

    public var deepResearch: Bool
    public var reasoningEffort: ReasoningEffort

    public init(deepResearch: Bool = false, reasoningEffort: ReasoningEffort = .off) {
        self.deepResearch = deepResearch
        self.reasoningEffort = reasoningEffort
    }

    /// The body's `advancedTools`.
    public var advancedTools: [String] { deepResearch ? [Self.deepResearchTool] : [] }

    /// The body's `reasoningEffort`: nil when off, so the key is left out and the route sets no reasoning option.
    public var wireReasoningEffort: String? { reasoningEffort == .off ? nil : reasoningEffort.rawValue }
}
