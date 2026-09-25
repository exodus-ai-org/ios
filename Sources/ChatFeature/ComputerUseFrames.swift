import Foundation
import MarkdownKit
import Models
import NetworkingKit
import Observation
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Where a computer_use card finds the frames kept for its session; the chat screen gives its view model's.
    @Entry var computerUseFrames: ComputerUseFrameStore?
    /// Answers and stops a running session on the computer; nil where there is no paired session (the gallery).
    @Entry var computerUseRemote: ComputerUseRemote?
}

/// One kept screenshot of a session: the step it was taken at and the action that followed it.
struct ComputerUseShot: Identifiable, Equatable {
    let step: Int
    let action: String?
    let image: UIImage

    var id: Int { step }
}

/// The frames of one session, kept in memory while it streams: a saved row keeps only the final screenshot, so this is
/// what the finished card's filmstrip shows. Bounded to the last `capacity` frames, each downsampled.
@MainActor
@Observable
final class ComputerUseFilmstrip {
    private(set) var shots: [ComputerUseShot] = []
    @ObservationIgnored private var requested: Set<Int> = []
    @ObservationIgnored private let capacity: Int
    @ObservationIgnored private let decode: @Sendable (String) async -> UIImage?

    init(capacity: Int, decode: @escaping @Sendable (String) async -> UIImage?) {
        self.capacity = capacity
        self.decode = decode
    }

    var latest: ComputerUseShot? { shots.last }

    /// Keeps a frame's screenshot, once per step, in step order; the oldest goes when the strip is full.
    func record(_ frame: ComputerUseFrame) async {
        guard claim(frame) else { return }
        await keep(frame)
    }

    /// Whether this frame is new and worth decoding; claimed at once, so a frame repeated by later updates is not.
    func claim(_ frame: ComputerUseFrame) -> Bool {
        guard frame.thumbnail != nil, !requested.contains(frame.step) else { return false }
        if shots.count >= capacity, let oldest = shots.first, frame.step < oldest.step { return false }
        requested.insert(frame.step)
        return true
    }

    func keep(_ frame: ComputerUseFrame) async {
        guard let thumbnail = frame.thumbnail, let image = await decode(thumbnail) else { return }
        let shot = ComputerUseShot(step: frame.step, action: frame.action, image: image)
        shots.insert(shot, at: shots.firstIndex { $0.step > frame.step } ?? shots.endIndex)
        if shots.count > capacity { shots.removeFirst(shots.count - capacity) }
    }
}

/// Every computer_use session this app watched stream, by call id: the few most recent are kept, the rest dropped.
/// Frames are fed in by the chat's view model as updates arrive, so a card scrolled out of view misses none.
@MainActor
final class ComputerUseFrameStore {
    static let shared = ComputerUseFrameStore()

    private var strips: [String: ComputerUseFilmstrip] = [:]
    private var recent: [String] = []
    private var queue: Task<Void, Never>?
    private let finals = NSCache<NSString, UIImage>()
    private let sessionCapacity: Int
    private let frameCapacity: Int
    private let decode: @Sendable (String) async -> UIImage?

    init(
        sessionCapacity: Int = 3, frameCapacity: Int = 10, maxPixelWidth: Int = 800,
        decode: (@Sendable (String) async -> UIImage?)? = nil
    ) {
        self.sessionCapacity = sessionCapacity
        self.frameCapacity = frameCapacity
        self.decode = decode ?? { await Self.decodeScreenshot($0, maxPixelWidth: maxPixelWidth) }
        finals.countLimit = 8
    }

    func filmstrip(for callId: String?) -> ComputerUseFilmstrip? { callId.flatMap { strips[$0] } }

    var keptSessions: [String] { recent }

    /// Records the frames of the computer_use cards in the last run of `segments` (the one that streams).
    func ingest(_ segments: [Segment]) {
        for segment in segments.reversed() {
            guard case .assistantTurn(let turn) = segment else { return }
            for card in turn.toolCards {
                guard case .computerUse(let model) = card.content, let callId = model.callId,
                    case .running(let frame) = model.phase
                else { continue }
                record(callId: callId, frame: frame)
            }
        }
    }

    func record(callId: String, frame: ComputerUseFrame) {
        guard frame.thumbnail != nil else { return }
        let strip = strips[callId] ?? admit(callId)
        guard strip.claim(frame) else { return }
        let previous = queue
        // One frame at a time, in arrival order: frames come seconds apart and each decode is a large PNG.
        queue = Task {
            await previous?.value
            await strip.keep(frame)
        }
    }

    /// Waits for the frames recorded so far to be decoded and kept.
    func settle() async { await queue?.value }

    /// Forgets every screenshot: the computer they came from is no longer paired.
    func removeAll() {
        queue?.cancel()
        queue = nil
        strips = [:]
        recent = []
        finals.removeAllObjects()
    }

    func cachedFinal(for callId: String?) -> UIImage? { callId.flatMap { finals.object(forKey: $0 as NSString) } }

    /// A run's final screenshot, decoded off the main actor and kept in memory.
    func finalScreenshot(for callId: String?, dataURL: String) async -> UIImage? {
        if let cached = cachedFinal(for: callId) { return cached }
        guard let image = await decode(dataURL) else { return nil }
        if let callId { finals.setObject(image, forKey: callId as NSString) }
        return image
    }

    private func admit(_ callId: String) -> ComputerUseFilmstrip {
        let strip = ComputerUseFilmstrip(capacity: frameCapacity, decode: decode)
        strips[callId] = strip
        recent.append(callId)
        while recent.count > sessionCapacity { strips[recent.removeFirst()] = nil }
        return strip
    }

    /// A screenshot sent as base64 (or a data URL) decoded to at most `maxPixelWidth` wide.
    @concurrent
    nonisolated static func decodeScreenshot(_ encoded: String, maxPixelWidth: Int) async -> UIImage? {
        guard encoded.utf8.count <= maxEncodedBytes else { return nil }
        let payload = encoded.hasPrefix("data:") ? encoded.split(separator: ",", maxSplits: 1).last.map(String.init) ?? "" : encoded
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
            let decoded = try? MarkdownImageLoader.downsample(data, maxPixelWidth: maxPixelWidth)
        else { return nil }
        return UIImage(cgImage: decoded.cgImage)
    }

    nonisolated static let maxEncodedBytes = 16 * 1024 * 1024
}

/// The two things the phone can do to a running session, as the desktop's card does: answer its question, or stop it.
struct ComputerUseRemote: Sendable {
    let answer: @Sendable (_ sessionId: String, _ text: String) async throws -> Void
    let stop: @Sendable () async throws -> Void
}

extension ComputerUseRemote {
    /// Through the paired session: `POST /api/v1/computer-use/answer` and `/abort` (which stops every live session, like
    /// the desktop's Stop and its ⌥⇧⎋).
    init(apiClient: APIClient) {
        self.init(
            answer: { sessionId, text in
                try await apiClient.post("/api/v1/computer-use/answer", body: AnswerBody(sessionId: sessionId, answer: text))
            },
            stop: { try await apiClient.post("/api/v1/computer-use/abort", body: EmptyBody()) })
    }

    private struct AnswerBody: Encodable {
        let sessionId: String
        let answer: String
    }

    private struct EmptyBody: Encodable {}
}
