import Foundation
import Models
import Synchronization
import os

/// Sends this app's own warnings and errors to the computer's Logger (`POST /api/v1/logs`, logged there as
/// `ios/<scope>`), since the desktop is the only place logs can be read. Everything is redacted before it is queued
/// (`LogRedaction`), held in memory only, and capped; while the app is locked or the computer cannot be reached,
/// reports simply wait. The reporter never reports its own failures: those go to `os.Logger` alone.
public actor LogReporter {
    public enum Level: String, Sendable, Encodable {
        case warn, error
    }

    /// An attribute value: text or a number, never a structure that could carry a body.
    public enum Value: Sendable, Equatable, Encodable {
        case string(String)
        case number(Double)

        public static func int(_ value: Int) -> Value { .number(Double(value)) }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let text):
                try container.encode(text)
            case .number(let number):
                if let whole = Int(exactly: number) { try container.encode(whole) } else { try container.encode(number) }
            }
        }
    }

    public struct Entry: Sendable, Equatable {
        public let level: Level
        public let scope: String
        public let message: String
        public var attributes: [String: Value]
    }

    public struct Configuration: Sendable {
        public var capacity = 200
        public var batchSize = 50
        public var debounce: Duration = .seconds(2)
        public var initialBackoff: Duration = .seconds(5)
        public var maxBackoff: Duration = .seconds(300)
        /// The same report (level, scope, message) is sent at most once per window; repeats are counted instead.
        public var repeatWindow: Duration = .seconds(60)
        public var requestTimeout: TimeInterval = 15

        public init() {}
    }

    private enum Outcome {
        case delivered, rejected(Int), retry(String)
    }

    private enum FlushState {
        case idle
        case scheduled(id: UUID, task: Task<Void, Never>)
        case flushing
    }

    static let path = "/api/v1/logs"

    private let session: URLSession
    private let serverConfig: ServerConfigStore
    private let isReady: @Sendable () -> Bool
    private let sleep: @Sendable (Duration) async throws -> Void
    private let configuration: Configuration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let wallClock: @Sendable () -> Date

    private var buffer: [Entry] = []
    private var dropped = 0
    private var state = FlushState.idle
    private var backoff: Duration?
    private var recent: [String: (at: ContinuousClock.Instant, suppressed: Int)] = [:]
    /// Set when a flush could not happen (locked, unreachable): the next sign of life flushes at once.
    private let waitingForServer = Mutex(false)

    private static let selfLog = Logger(subsystem: "app.yancey.exodus.exodus-ios", category: "log-reporter")

    public init(
        session: URLSession,
        serverConfig: ServerConfigStore,
        configuration: Configuration = Configuration(),
        isReady: @escaping @Sendable () -> Bool = { true },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.serverConfig = serverConfig
        self.configuration = configuration
        self.isReady = isReady
        self.sleep = sleep
        self.now = now
        self.wallClock = wallClock
    }

    // MARK: Reporting

    /// Fire and forget, from any context: logs locally at once, queues the redacted report, never throws or waits.
    public nonisolated func report(
        _ level: Level, scope: String, message: String, attributes: [String: Value] = [:]
    ) {
        let entry = stamped(LogRedaction.entry(level: level, scope: scope, message: message, attributes: attributes))
        Self.logLocally(entry)
        Task { await self.enqueue(entry) }
    }

    /// `report`, awaited: the entry is queued when this returns.
    public func record(_ level: Level, scope: String, message: String, attributes: [String: Value] = [:]) {
        let entry = stamped(LogRedaction.entry(level: level, scope: scope, message: message, attributes: attributes))
        Self.logLocally(entry)
        enqueue(entry)
    }

    /// The desktop stamps a report when it arrives, so a buffered one would look late: say when it happened.
    private nonisolated func stamped(_ entry: Entry) -> Entry {
        var entry = entry
        entry.attributes["occurredAt"] = .string(Self.timestamp(wallClock()))
        return entry
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt))
    }

    /// The app came to the foreground or the computer answered again: flush now, whatever the backoff.
    public nonisolated func flushSoon() {
        Task { await self.restartFlush() }
    }

    /// Called on every successful request to the computer; cheap unless reports are waiting for it.
    public nonisolated func noteReachable() {
        if waitingForServer.withLock({ waiting in defer { waiting = false }; return waiting }) {
            flushSoon()
        }
    }

    var pending: [Entry] { buffer }
    var droppedCount: Int { dropped }
    var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    private func enqueue(_ entry: Entry) {
        var entry = entry
        let key = "\(entry.level.rawValue)|\(entry.scope)|\(entry.message)"
        let at = now()
        if let seen = recent[key], seen.at.duration(to: at) < configuration.repeatWindow {
            recent[key]?.suppressed += 1
            return
        }
        if let suppressed = recent[key]?.suppressed, suppressed > 0 {
            entry.attributes["repeatsSuppressed"] = .int(suppressed)
        }
        if recent.count > 500 { recent.removeAll() }
        recent[key] = (at, 0)

        buffer.append(entry)
        trimToCapacity()
        if case .idle = state { schedule(after: backoff ?? configuration.debounce) }
    }

    private func trimToCapacity() {
        let overflow = buffer.count - configuration.capacity
        guard overflow > 0 else { return }
        buffer.removeFirst(overflow)
        dropped += overflow
    }

    // MARK: Flushing

    private func restartFlush() {
        backoff = nil
        switch state {
        case .flushing:
            return
        case .scheduled(_, let task):
            task.cancel()
            state = .idle
        case .idle:
            break
        }
        if !buffer.isEmpty { schedule(after: .zero) }
    }

    private func schedule(after delay: Duration) {
        let id = UUID()
        let task = Task { [weak self, sleep] in
            do { try await sleep(delay) } catch { return }
            await self?.runScheduled(id: id)
        }
        state = .scheduled(id: id, task: task)
    }

    private func runScheduled(id: UUID) async {
        guard case .scheduled(let current, _) = state, current == id, !Task.isCancelled else { return }
        state = .flushing
        await flushLoop()
    }

    /// Flushes now (tests; the scheduled path goes through the same loop).
    func flush() async {
        switch state {
        case .flushing: return
        case .scheduled(_, let task): task.cancel()
        case .idle: break
        }
        state = .flushing
        await flushLoop()
    }

    private func flushLoop() async {
        while !buffer.isEmpty {
            guard isReady() else {
                waitingForServer.withLock { $0 = true }
                state = .idle
                return
            }
            // Out of the buffer while in flight: reports queued meanwhile can overflow the buffer without touching it.
            let batch = Array(buffer.prefix(configuration.batchSize))
            buffer.removeFirst(batch.count)
            let droppedBefore = dropped
            dropped = 0

            switch await send(batch, droppedBefore: droppedBefore) {
            case .delivered:
                backoff = nil
            case .rejected(let status):
                Self.selfLog.error("Dropped \(batch.count) reports the computer refused (HTTP \(status))")
                dropped += droppedBefore + batch.count
            case .retry(let reason):
                Self.selfLog.notice("Log flush failed, will retry: \(reason, privacy: .public)")
                buffer.insert(contentsOf: batch, at: 0)
                dropped += droppedBefore
                trimToCapacity()
                let next = backoff.map { min($0 * 2, configuration.maxBackoff) } ?? configuration.initialBackoff
                backoff = next
                waitingForServer.withLock { $0 = true }
                schedule(after: next)
                return
            }
        }
        state = .idle
    }

    private struct Payload: Encodable {
        struct Report: Encodable {
            let level: Level
            let scope: String
            let message: String
            let attributes: [String: Value]?
            let source = "ios"
        }

        let reports: [Report]
        let source = "ios"
    }

    private func send(_ batch: [Entry], droppedBefore: Int) async -> Outcome {
        guard let base = URL(string: serverConfig.baseURLString) else { return .retry("no server address") }
        var reports = batch.map { entry in
            Payload.Report(
                level: entry.level, scope: entry.scope, message: entry.message,
                attributes: entry.attributes.isEmpty ? nil : entry.attributes)
        }
        if droppedBefore > 0, let first = batch.first {
            var attributes = first.attributes
            attributes["droppedBefore"] = .int(droppedBefore)
            reports[0] = Payload.Report(
                level: first.level, scope: first.scope, message: first.message, attributes: attributes)
        }
        var request = URLRequest(url: base.appendingPathComponent(Self.path))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization = serverConfig.authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        do {
            request.httpBody = try JSONEncoder().encode(Payload(reports: reports))
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .retry("no HTTP response") }
            return Self.outcome(status: http.statusCode)
        } catch {
            return .retry(String(describing: type(of: error)))
        }
    }

    /// Unauthorised, locked, rate-limited or a server fault may pass; any other 4xx never will, so it is dropped.
    private static func outcome(status: Int) -> Outcome {
        switch status {
        case 200..<300: .delivered
        case 401, 408, 423, 429: .retry("HTTP \(status)")
        case 400..<500: .rejected(status)
        default: .retry("HTTP \(status)")
        }
    }

    static func logLocally(_ entry: Entry) {
        let logger = Logger(subsystem: "app.yancey.exodus.exodus-ios", category: entry.scope)
        let attributes = entry.attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.text)" }
            .joined(separator: " ")
        switch entry.level {
        case .warn: logger.warning("\(entry.message, privacy: .public) \(attributes, privacy: .public)")
        case .error: logger.error("\(entry.message, privacy: .public) \(attributes, privacy: .public)")
        }
    }
}

extension LogReporter.Value {
    var text: String {
        switch self {
        case .string(let text): text
        case .number(let number): Int(exactly: number).map(String.init) ?? String(number)
        }
    }
}

extension Optional where Wrapped == LogReporter {
    /// Reports through the reporter when there is one; `os.Logger` either way.
    public func report(
        _ level: LogReporter.Level, scope: String, message: String, attributes: [String: LogReporter.Value] = [:]
    ) {
        if let reporter = self {
            reporter.report(level, scope: scope, message: message, attributes: attributes)
        } else {
            LogReporter.logLocally(
                LogRedaction.entry(level: level, scope: scope, message: message, attributes: attributes))
        }
    }
}

extension LogReporter {
    /// What an error may say in a report: its kind and codes, never its text (a server message can echo input).
    public static func attributes(for error: Error) -> [String: Value] {
        var result: [String: Value] = ["errorType": .string(String(describing: type(of: error)))]
        switch error {
        case let http as HTTPError:
            result["status"] = .int(http.statusCode)
            result["errorCode"] = .string(http.code)
        case let url as URLError:
            result["urlError"] = .int(url.code.rawValue)
        case let decoding as DecodingError:
            result["decoding"] = .string(LogRedaction.describe(decoding))
        default:
            break
        }
        return result
    }
}
