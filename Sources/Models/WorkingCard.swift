import Foundation

/// A kind of card the transcript draws while the model works, which Settings › Working cards can hide. A phone-only
/// preference, kept in UserDefaults: the chat reads it where it lays a turn out, Settings writes it. A hidden card's
/// step still stands in the thinking timeline.
public enum WorkingCard: String, CaseIterable, Sendable {
    case terminal, fileReads, fileEdits

    /// True, or never set, shows the card.
    public var defaultsKey: String { "workingCards.\(rawValue)" }

    public var toolNames: Set<String> {
        switch self {
        case .terminal: ["terminal"]
        case .fileReads: ["read_file"]
        case .fileEdits: ["write_file", "edit_file"]
        }
    }

    /// The tools whose cards are hidden, given which kinds show.
    public static func hiddenTools(showing shows: (WorkingCard) -> Bool) -> Set<String> {
        allCases.reduce(into: []) { tools, card in
            if !shows(card) { tools.formUnion(card.toolNames) }
        }
    }

    public static func hiddenTools(in defaults: UserDefaults) -> Set<String> {
        hiddenTools { defaults.object(forKey: $0.defaultsKey) as? Bool ?? true }
    }
}
