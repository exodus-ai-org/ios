import Observation

/// What a block can do as it stands: answered (frozen), drawn but never answered (a compared answer, the other-version
/// sheet), or open — with sending allowed only while no turn is in flight. The rows, the fields and the buttons all
/// read it, so they never disagree.
enum InteractiveMode: Equatable {
    case frozen
    case readOnly
    case open(canSend: Bool)

    init(answered: Bool, isAnswerable: Bool, canAnswer: Bool) {
        if answered {
            self = .frozen
        } else if !isAnswerable {
            self = .readOnly
        } else {
            self = .open(canSend: canAnswer)
        }
    }

    /// Choices toggle and the fields are drawn.
    var isOpen: Bool { if case .open = self { true } else { false } }
    /// Submit / Approve / Reject are drawn (enabled or not).
    var showsActions: Bool { isOpen }
    var canSend: Bool { self == .open(canSend: true) }
}

/// A block's answer while it is being made: the choices picked, by their place in the question (two options that
/// are canonically equal are still two), the "Other…" texts and the note.
struct InteractiveDraft: Equatable {
    /// Per question id, the indexes of its picked options, in pick order.
    var picks: [String: [Int]] = [:]
    /// Per question id, the "Other…" text; absent while Other is not picked.
    var others: [String: String] = [:]
    var note = ""

    func isPicked(_ question: InteractiveBlock.Ask.Question, _ index: Int) -> Bool {
        picks[question.id]?.contains(index) ?? false
    }

    func isOtherPicked(_ question: InteractiveBlock.Ask.Question) -> Bool { others[question.id] != nil }

    mutating func pick(_ question: InteractiveBlock.Ask.Question, _ index: Int) {
        if question.type == .single {
            picks[question.id] = [index]
            others[question.id] = nil
        } else if let at = picks[question.id]?.firstIndex(of: index) {
            picks[question.id]?.remove(at: at)
        } else {
            picks[question.id, default: []].append(index)
        }
    }

    mutating func pickOther(_ question: InteractiveBlock.Ask.Question) {
        if question.type == .single {
            picks[question.id] = []
            others[question.id] = others[question.id] ?? ""
        } else {
            others[question.id] = others[question.id] == nil ? "" : nil
        }
    }

    /// The draft as `InteractiveAnswer.composeAsk` takes it.
    func responses(_ block: InteractiveBlock.Ask) -> [String: InteractiveAnswer.Response] {
        var out: [String: InteractiveAnswer.Response] = [:]
        for question in block.questions {
            let options = (picks[question.id] ?? []).filter(question.options.indices.contains).map { question.options[$0] }
            out[question.id] = .init(options: options, other: others[question.id])
        }
        return out
    }
}

/// The answers being made in a chat's blocks, by the run whose reply holds each block: held by the transcript, not by
/// the block's view, so a pick survives the lazy transcript dropping the view when it scrolls away. Cleared when the
/// block freezes. Not kept past the chat screen.
@MainActor
@Observable
final class InteractiveDrafts {
    private var drafts: [String: InteractiveDraft] = [:]

    subscript(runId: String) -> InteractiveDraft {
        get { drafts[runId] ?? InteractiveDraft() }
        set { drafts[runId] = newValue }
    }

    func clear(_ runId: String) {
        if drafts[runId] != nil { drafts[runId] = nil }
    }
}
