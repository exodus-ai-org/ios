import Foundation
import Models
import NetworkingKit
import Observation
import SwiftUI

extension EnvironmentValues {
    @Entry var runApprovals: RunApprovalStore?
}

/// One tool call paused for the user's answer, as the run's foot shows it (the desktop's `RunApproval`). Live only:
/// it arrives on this client's own stream and is not persisted, so a chat reopened from history shows none.
@MainActor
@Observable
final class ApprovalEntry: Identifiable {
    enum Decision: String, Sendable {
        case allow, deny
    }

    enum State: Equatable {
        case pending
        /// The answer is on its way; nothing more can be sent.
        case sending(Decision)
        /// The computer no longer had the call when the answer arrived (404): someone answered first, or it timed out.
        /// `approval_resolved` says how, when it comes.
        case answeredElsewhere
        case settled(ApprovalOutcome)
    }

    let request: ApprovalRequest
    var state: State = .pending
    /// The last answer could not be sent; the card still waits.
    var sendFailed = false
    /// Allow once works only once the card has been on screen for `RunApprovalStore.allowDelay`.
    var allowArmed = false

    nonisolated var id: String { request.toolCallId }

    init(request: ApprovalRequest) {
        self.request = request
    }
}

/// A run's paused calls, in arrival order. One object per run, so a card redraws only when its own run's list changes.
@MainActor
@Observable
final class RunApprovalList {
    var entries: [ApprovalEntry] = []
}

/// What the foot shows for an entry, once the run's own state is taken into account (`RunApprovals` on the desktop).
enum ApprovalDisplay: Equatable {
    case asking(sending: Bool)
    case settled(ApprovalOutcome)
    /// Nothing waits for an answer any more and the computer has not said how it ended (the desktop's "expired").
    case noLongerWaiting

    /// A call still pending once the run no longer streams was cut off by Stop: the computer declines it.
    static func of(_ state: ApprovalEntry.State, runIsActive: Bool) -> ApprovalDisplay {
        switch state {
        case .settled(let outcome): .settled(outcome)
        case .pending: runIsActive ? .asking(sending: false) : .settled(.stopped)
        case .sending: runIsActive ? .asking(sending: true) : .settled(.stopped)
        case .answeredElsewhere: .noLongerWaiting
        }
    }
}

/// The approvals of one chat screen, fed by its stream and answered through the paired session
/// (`POST /api/v1/chat/approval`; on the LAN the device token is the user's say-so).
@MainActor
@Observable
final class RunApprovalStore {
    typealias Send = @Sendable (_ runId: String, _ toolCallId: String, _ decision: ApprovalEntry.Decision) async throws
        -> ApprovalOutcome

    @ObservationIgnored private var runs: [String: RunApprovalList] = [:]
    @ObservationIgnored private let send: Send
    /// The desktop's `ALLOW_ENABLE_DELAY_MS`: Allow once stays off this long after the card appears.
    @ObservationIgnored let allowDelay: Duration

    init(allowDelay: Duration = approvalAllowDelay, send: @escaping Send) {
        self.allowDelay = allowDelay
        self.send = send
    }

    convenience init(apiClient: APIClient, allowDelay: Duration = approvalAllowDelay) {
        self.init(allowDelay: allowDelay) { runId, toolCallId, decision in
            let answer: ApprovalAnswer = try await apiClient.post(
                "/api/v1/chat/approval", body: ApprovalDecisionBody(runId: runId, toolCallId: toolCallId, decision: decision.rawValue))
            return answer.outcome
        }
    }

    /// The run's list; created empty on first read, so a view can subscribe before anything arrives.
    func list(for runId: String) -> RunApprovalList {
        if let list = runs[runId] { return list }
        let list = RunApprovalList()
        runs[runId] = list
        return list
    }

    func entry(runId: String, toolCallId: String) -> ApprovalEntry? {
        runs[runId]?.entries.first { $0.request.toolCallId == toolCallId }
    }

    func apply(_ event: ApprovalEvent) {
        switch event {
        case .required(let request):
            let list = list(for: request.runId)
            list.entries = list.entries.filter { $0.request.toolCallId != request.toolCallId } + [ApprovalEntry(request: request)]
        case .resolved(let runId, let toolCallId, let outcome):
            guard let entry = entry(runId: runId, toolCallId: toolCallId), entry.state != .settled(outcome) else { return }
            entry.state = .settled(outcome)
            entry.sendFailed = false
        }
    }

    /// Arms Allow once after `allowDelay`, counted from when the card is first on screen (its view's task).
    func arm(_ entry: ApprovalEntry) async {
        guard !entry.allowArmed else { return }
        do {
            try await Task.sleep(for: allowDelay)
        } catch {
            return
        }
        entry.allowArmed = true
    }

    /// Allow once / Deny. Sends once: a second tap while the first is on its way, or after it settled, does nothing.
    /// Allow before the card is armed does nothing either.
    func decide(_ entry: ApprovalEntry, _ decision: ApprovalEntry.Decision) async {
        guard entry.state == .pending, decision == .deny || entry.allowArmed else { return }
        entry.state = .sending(decision)
        entry.sendFailed = false
        do {
            let outcome = try await send(entry.request.runId, entry.request.toolCallId, decision)
            if case .sending = entry.state { entry.state = .settled(outcome) }
        } catch let error as HTTPError where error.code == "APPROVAL_NOT_FOUND" {
            if case .sending = entry.state { entry.state = .answeredElsewhere }
        } catch {
            guard case .sending = entry.state else { return }
            entry.state = .pending
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled { entry.sendFailed = true }
        }
    }
}

struct ApprovalDecisionBody: Encodable, Sendable {
    let runId: String
    let toolCallId: String
    let decision: String
}

struct ApprovalAnswer: Decodable, Sendable {
    let outcome: ApprovalOutcome
}

/// The card's words, out of the view so they can be tested.
enum ApprovalText {
    /// The computer's own wait (`APPROVAL_TIMEOUT_MS`): no countdown shows more, whatever the clocks say.
    static let timeout: TimeInterval = 10 * 60

    /// How long until the computer declines the call unanswered, `m:ss`, between 0:00 and 10:00: `expiresAt` is on the
    /// computer's clock, so a phone clock that is off must not show a longer wait or a negative one.
    static func remaining(until expiry: Date, now: Date) -> String {
        let seconds = min(Int(timeout), max(0, Int(expiry.timeIntervalSince(now).rounded(.up))))
        return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    static func countdown(until expiry: Date, now: Date) -> String {
        let time = remaining(until: expiry, now: now)
        return String(
            localized: "ios:chat.approval.expiresIn", defaultValue: "Declined automatically in \(time)",
            comment: "Under a request to read a secret on the computer. %@ is the time left, such as 9:41.")
    }

    static func settledTitle(_ display: ApprovalDisplay) -> String {
        switch display {
        case .settled(.allowed):
            String(localized: "chat:approval.allowed", defaultValue: "Allowed once", comment: "A settled approval.")
        case .settled(.denied), .settled(.other):
            String(localized: "chat:approval.denied", defaultValue: "Denied", comment: "A settled approval.")
        case .settled(.timedOut):
            String(localized: "chat:approval.timedOut", defaultValue: "Timed out", comment: "A settled approval.")
        case .settled(.stopped):
            String(localized: "chat:approval.stopped", defaultValue: "Stopped", comment: "A settled approval.")
        case .noLongerWaiting, .asking:
            String(localized: "chat:approval.expired", defaultValue: "No longer waiting", comment: "A settled approval.")
        }
    }

    static func settledSymbol(_ display: ApprovalDisplay) -> String {
        switch display {
        case .settled(.allowed): "checkmark"
        case .settled(.denied), .settled(.other): "xmark.octagon"
        case .settled(.stopped): "stop"
        case .settled(.timedOut), .noLongerWaiting, .asking: "clock"
        }
    }
}

/// What the card shows of `summary`, the path or command the computer paused on. The whole of it is shown, wrapped:
/// nothing may be hidden or reordered. The desktop's `sanitizeSummary` (`kernel/approval.ts`) already did this at the
/// source; older computers send the summary raw, so the phone applies the same rules again, in the same order.
enum ApprovalSummary {
    static func sanitized(_ summary: String) -> String {
        // 1. Every Cf character: bidi controls and marks, zero-width characters, the BOM and the rest of the category.
        let visible = String(String.UnicodeScalarView(summary.unicodeScalars.filter { $0.properties.generalCategory != .format }))
        var out = String.UnicodeScalarView()
        var scalars = visible.unicodeScalars.makeIterator()
        var pending = scalars.next()
        while let scalar = pending {
            pending = scalars.next()
            switch scalar.value {
            // 2. A line break shows as ⏎ (CRLF as one), a tab as ⇥; SwiftUI breaks lines on U+2028 / U+2029 too.
            case 0x0D:
                out.append("⏎")
                if pending?.value == 0x0A { pending = scalars.next() }
            case 0x0A, 0x2028, 0x2029, 0x85:
                out.append("⏎")
            case 0x09:
                out.append("⇥")
            // 3. Any other C0 / C1 control.
            case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F...0x9F:
                out.append("\u{FFFD}")
            default:
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// The note under a summary the computer cut (`truncated`, `hiddenChars`): the desktop's plural
    /// `chat:approval.truncatedNote`. The catalog picks the form; the branch only gives the hostless
    /// tests (no catalog) the right English.
    static func truncatedNote(hiddenChars: Int) -> String {
        if hiddenChars == 1 {
            return String(
                localized: "chat:approval.truncatedNote", defaultValue: "\(hiddenChars) more character not shown",
                comment: "Under an approval summary the computer cut. The number is how many characters are hidden (plural).")
        }
        return String(
            localized: "chat:approval.truncatedNote", defaultValue: "\(hiddenChars) more characters not shown",
            comment: "Under an approval summary the computer cut. The number is how many characters are hidden (plural).")
    }
}
