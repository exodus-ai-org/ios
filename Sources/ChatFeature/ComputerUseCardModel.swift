import Foundation
import Models

/// A `computer_use` call as its card draws it, read once when the card is built: the running frame while the session
/// streams, the outcome (with the result's last screenshot) when it ends, or why it could not run.
struct ComputerUseCardModel: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// The call is made; no frame has come yet.
        case starting
        case running(ComputerUseFrame)
        case finished(ComputerUseOutcome)
        /// The tool answered `{error}`: `disabled`, `not-allowed`, `self` or a message.
        case refused(String)
        /// The call itself failed; the tool's own message when it gave one.
        case failed(String?)
    }

    /// The call's id: the key its frames are kept under on the phone while the session streams.
    let callId: String?
    let task: String
    let target: String
    let phase: Phase
    /// The result's last screenshot as a data URL; a saved row keeps no other frame.
    let finalScreenshot: String?

    init(callId: String?, arguments: ComputerUseArguments?, phase: Phase, finalScreenshot: String? = nil) {
        self.callId = callId
        task = arguments?.task ?? ""
        target = arguments?.target ?? ""
        self.phase = phase
        self.finalScreenshot = finalScreenshot
    }

    init(_ call: DecodedCall<ComputerUseArguments, ComputerUseDetails>, callId: String?, finalScreenshot: String?) {
        let phase: Phase =
            switch call.result {
            case .frame(let frame): .running(frame)
            case .finished(let outcome): .finished(outcome)
            case .failed(let error): .refused(error)
            }
        self.init(
            callId: callId, arguments: call.arguments, phase: phase,
            finalScreenshot: Self.isRasterDataURL(finalScreenshot) ? finalScreenshot : nil)
    }

    var sessionId: String? {
        switch phase {
        case .running(let frame): frame.sessionId
        case .finished(let outcome): outcome.sessionId
        default: nil
        }
    }

    var summary: String? {
        guard case .finished(let outcome) = phase, !outcome.summary.isEmpty else { return nil }
        return outcome.summary
    }

    /// The first image block of a tool result, as a data URL.
    static func resultImage(_ blocks: [ContentBlock]) -> String? {
        blocks.lazy.compactMap { block -> String? in
            if case .image(_, let dataURL) = block, isRasterDataURL(dataURL) { dataURL } else { nil }
        }.first
    }

    private static func isRasterDataURL(_ value: String?) -> Bool {
        guard let value else { return false }
        let head = value.prefix(24).lowercased()
        return ["data:image/png", "data:image/jpeg", "data:image/jpg", "data:image/webp"].contains { head.hasPrefix($0) }
    }
}

/// What the card shows, decided from the model and whether its turn still streams.
enum ComputerUseRules {
    enum Status: Equatable {
        case starting
        case step(Int)
        case needsYou
        case outcome(String)
        /// The run was stopped while the session had not ended.
        case stopped
        case error
    }

    enum Shots: Equatable {
        case none
        /// The latest frame, large, while the session runs.
        case live
        /// Every frame kept on the phone during the stream, oldest first, and the final screenshot.
        case filmstrip
        /// A run reopened from history: the result's final screenshot only.
        case single
    }

    static func status(_ model: ComputerUseCardModel, isLive: Bool) -> Status {
        switch model.phase {
        case .starting: isLive ? .starting : .stopped
        case .running(let frame):
            !isLive ? .stopped : frame.awaitingHumanQuestion != nil ? .needsYou : .step(frame.step)
        case .finished(let outcome): .outcome(outcome.outcome)
        case .refused, .failed: .error
        }
    }

    static func isRunning(_ model: ComputerUseCardModel, isLive: Bool) -> Bool {
        guard isLive else { return false }
        switch model.phase {
        case .starting, .running: return true
        default: return false
        }
    }

    /// The session's question to the user, while it waits for an answer.
    static func question(_ model: ComputerUseCardModel, isLive: Bool) -> String? {
        guard isLive, case .running(let frame) = model.phase, let question = frame.awaitingHumanQuestion else { return nil }
        return question
    }

    static func shots(_ model: ComputerUseCardModel, isLive: Bool, recorded: Int, hasFinal: Bool) -> Shots {
        if isRunning(model, isLive: isLive) { return recorded > 0 ? .live : .none }
        if recorded > 0 { return .filmstrip }
        if case .finished = model.phase, hasFinal { return .single }
        return .none
    }

    static func errorText(_ code: String, target: String) -> String {
        switch code {
        case "disabled":
            String(
                localized: "ios:chat.card.computer.error.disabled",
                defaultValue: "Computer Use is turned off in Settings on the computer.",
                comment: "Computer Use card: the tool is switched off on the desktop.")
        case "not-allowed":
            String(
                localized: "ios:chat.card.computer.error.notAllowed",
                defaultValue: "“\(target)” isn’t on the Computer Use allowlist. Add it in Settings on the computer.",
                comment: "Computer Use card: the app to control is not allowed. %@ is the app's name.")
        case "self":
            String(
                localized: "ios:chat.card.computer.error.self",
                defaultValue: "Exodus can’t operate its own windows.",
                comment: "Computer Use card: the model asked to control Exodus itself, which is refused.")
        default: code
        }
    }

    static func statusText(_ status: Status) -> String {
        switch status {
        case .starting:
            String(localized: "chat:computerUseCard.running", defaultValue: "running…", comment: "Computer Use card status.")
        case .step(let step):
            String(
                localized: "chat:computerUseCard.stepBadge", defaultValue: "step \(String(step))",
                comment: "Computer Use card status. %@ is the step number.")
        case .needsYou:
            String(
                localized: "ios:chat.card.computer.needsYou", defaultValue: "Needs you",
                comment: "Computer Use card status: the session waits for the user's answer.")
        case .outcome(let outcome): outcomeText(outcome)
        case .stopped: outcomeText("aborted")
        case .error:
            String(localized: "chat:computerUseCard.error", defaultValue: "error", comment: "Computer Use card status.")
        }
    }

    static func outcomeText(_ outcome: String) -> String {
        switch outcome {
        case "success":
            String(localized: "chat:computerUseCard.outcome.success", defaultValue: "success", comment: "Computer Use outcome.")
        case "failed":
            String(localized: "chat:computerUseCard.outcome.failed", defaultValue: "failed", comment: "Computer Use outcome.")
        case "aborted":
            String(localized: "chat:computerUseCard.outcome.aborted", defaultValue: "aborted", comment: "Computer Use outcome.")
        case "abandoned":
            String(
                localized: "chat:computerUseCard.outcome.abandoned", defaultValue: "abandoned", comment: "Computer Use outcome.")
        case "stuck":
            String(localized: "chat:computerUseCard.outcome.stuck", defaultValue: "stuck", comment: "Computer Use outcome.")
        default: outcome
        }
    }

    /// An action kind (`click`, `type`, …) as a person says it; a kind this app does not know is shown as it came.
    static func actionName(_ kind: String) -> String {
        switch kind {
        case "click":
            String(localized: "ios:chat.card.computer.action.click", defaultValue: "Click", comment: "Computer Use action.")
        case "type":
            String(localized: "ios:chat.card.computer.action.type", defaultValue: "Type", comment: "Computer Use action: typing text.")
        case "drag":
            String(localized: "ios:chat.card.computer.action.drag", defaultValue: "Drag", comment: "Computer Use action.")
        case "hotkey":
            String(
                localized: "ios:chat.card.computer.action.hotkey", defaultValue: "Keyboard shortcut",
                comment: "Computer Use action: a key combination such as Command-C.")
        case "wait":
            String(localized: "ios:chat.card.computer.action.wait", defaultValue: "Wait", comment: "Computer Use action.")
        case "moveMouse":
            String(
                localized: "ios:chat.card.computer.action.moveMouse", defaultValue: "Move pointer",
                comment: "Computer Use action: moving the mouse pointer.")
        case "wheel":
            String(localized: "ios:chat.card.computer.action.scroll", defaultValue: "Scroll", comment: "Computer Use action.")
        case "mouseDown", "mouseUp":
            String(
                localized: "ios:chat.card.computer.action.mouseButton", defaultValue: "Mouse button",
                comment: "Computer Use action: pressing or releasing a mouse button.")
        case "keyDown", "keyUp":
            String(
                localized: "ios:chat.card.computer.action.key", defaultValue: "Key press",
                comment: "Computer Use action: pressing or releasing one key.")
        default: kind
        }
    }

    /// "Step 3: Click", or "Step 3: …" before the step has acted.
    static func stepLine(_ step: Int, action: String?) -> String {
        if let action {
            let name = actionName(action)
            return String(
                localized: "chat:computerUseCard.stepWithAction", defaultValue: "Step \(String(step)): \(name)",
                comment: "Computer Use card: a step and its action. The first %@ is the step number, the second the action.")
        }
        return String(
            localized: "chat:computerUseCard.stepNoAction", defaultValue: "Step \(String(step)): …",
            comment: "Computer Use card: a step whose action is not known yet. %@ is the step number.")
    }

    /// VoiceOver label of a screenshot: "Target window at step 3".
    static func shotLabel(step: Int) -> String {
        String(
            localized: "chat:computerUseCard.targetWindowAlt", defaultValue: "Target window at step \(String(step))",
            comment: "VoiceOver label of a Computer Use screenshot. %@ is the step number.")
    }

    static var finalShotLabel: String {
        String(
            localized: "ios:chat.card.computer.finalScreen", defaultValue: "Final screen",
            comment: "Caption and VoiceOver label of the last screenshot of a Computer Use session.")
    }

    static func sessionText(_ id: String) -> String {
        String(
            localized: "chat:computerUseCard.session", defaultValue: "session: \(id)",
            comment: "Computer Use card: the session's id. %@ is the id.")
    }
}
