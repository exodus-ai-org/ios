import AVFoundation
import Foundation
import MarkdownKit
import Models
import NetworkingKit
import Observation
import SwiftUI

/// What read-aloud says: the answer as prose. Markdown is taken off (`MarkdownPlainText`), and the citation markers
/// (`【1-source】`, `【1,2-source】`) with the space before them, so nothing is left hanging before a full stop.
enum SpeechText {
    nonisolated(unsafe) private static let marker = #/\s*\u{3010}[0-9,\s]+-source\u{3011}/#

    static func prose(_ markdown: String) -> String {
        MarkdownPlainText.strip(withoutCitations(markdown))
    }

    /// The text without its `【N-source】` markers, and without the space before each.
    static func withoutCitations(_ markdown: String) -> String {
        markdown.replacing(marker, with: "")
    }
}

/// What plays the audio the computer sent. The model is told when the audio ran to its end — not when it was stopped.
@MainActor
protocol SpeechPlayer: AnyObject {
    func play(_ audio: Data, finished: @escaping @MainActor () -> Void) throws
    func stop()
}

enum ReadAloudText {
    static var cannotPlay: String {
        String(
            localized: "ios:chat.readAloud.cannotPlay",
            defaultValue: "This phone cannot play the audio the computer sent. Choose MP3, AAC, WAV or FLAC in the computer\u{2019}s Settings \u{2192} Voice.",
            comment: "Alert text when the speech audio is in a format the phone cannot play (Opus, raw PCM).")
    }
}

/// Read aloud, for the answers of one chat: one answer at a time is asked for, then played. The computer makes the
/// audio (`POST /api/v1/audio/speech`), as it does for the desktop; what it sent for an answer is kept while the chat
/// is open, so playing it again asks nothing.
@MainActor
@Observable
final class ReadAloudModel {
    enum Phase: Equatable {
        case idle, loading, playing
    }

    /// The answer being asked for or played, and where it stands.
    private(set) var active: (id: String, phase: Phase)?
    /// Told the computer's own words when it refuses, or that the audio cannot be played.
    @ObservationIgnored var onFailure: (String) -> Void = { _ in }

    @ObservationIgnored private let fetch: @Sendable (String) async throws -> Data
    @ObservationIgnored private let player: any SpeechPlayer
    /// Newest last; the oldest goes when there are more than `keptLimit`.
    @ObservationIgnored private var kept: [(key: String, audio: Data)] = []
    /// Counts every start and stop: what comes back for an older count is not played.
    @ObservationIgnored private var generation = 0

    static let keptLimit = 6

    init(fetch: @escaping @Sendable (String) async throws -> Data, player: any SpeechPlayer) {
        self.fetch = fetch
        self.player = player
    }

    func phase(for id: String) -> Phase {
        guard let active, active.id == id else { return .idle }
        return active.phase
    }

    /// The button's tap: starts this answer (stopping any other), or stops it when it is the one going.
    func toggle(id: String, text: String) async {
        if phase(for: id) != .idle {
            stop()
            return
        }
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        generation += 1
        let mine = generation
        let key = "\(id)\u{0}\(text)"
        if let audio = kept.first(where: { $0.key == key })?.audio {
            play(audio, id: id, key: key, generation: mine)
            return
        }
        active = (id, .loading)
        do {
            let audio = try await fetch(text)
            guard mine == generation else { return }
            keep(audio, for: key)
            play(audio, id: id, key: key, generation: mine)
        } catch {
            guard mine == generation else { return }
            active = nil
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            onFailure(error.localizedDescription)
        }
    }

    /// Ends whatever is going on: a tap on the playing answer, another answer starting, the chat or the app leaving.
    func stop() {
        generation += 1
        guard active != nil else { return }
        active = nil
        player.stop()
    }

    private func play(_ audio: Data, id: String, key: String, generation mine: Int) {
        do {
            try player.play(audio) { [weak self] in
                guard let self, mine == self.generation else { return }
                self.active = nil
            }
            active = (id, .playing)
        } catch {
            // What cannot be played is not worth keeping: the format may be changed on the computer meanwhile.
            kept.removeAll { $0.key == key }
            active = nil
            onFailure(ReadAloudText.cannotPlay)
        }
    }

    private func keep(_ audio: Data, for key: String) {
        kept.removeAll { $0.key == key }
        kept.append((key, audio))
        if kept.count > Self.keptLimit { kept.removeFirst(kept.count - Self.keptLimit) }
    }
}

extension ReadAloudModel {
    private struct SpeechBody: Encodable {
        let text: String
    }

    /// Read aloud through the paired computer, heard on this phone.
    convenience init(apiClient: APIClient) {
        self.init(
            fetch: { text in
                // Speech for a long answer takes a while to make; the default timeout is for small requests.
                try await apiClient.post("/api/v1/audio/speech", body: SpeechBody(text: text), timeout: 120)
            }, player: AudioSpeechPlayer())
    }
}

/// `AVAudioPlayer`, as speech: heard with the ringer switch off, and other audio is asked to make room.
@MainActor
final class AudioSpeechPlayer: NSObject, SpeechPlayer, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var finished: (@MainActor () -> Void)?

    func play(_ audio: Data, finished: @escaping @MainActor () -> Void) throws {
        stop()
        let player = try AVAudioPlayer(data: audio)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        player.delegate = self
        guard player.prepareToPlay(), player.play() else { throw CocoaError(.fileReadCorruptFile) }
        self.player = player
        self.finished = finished
    }

    func stop() {
        finished = nil
        guard let player else { return }
        player.delegate = nil
        player.stop()
        self.player = nil
        release()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.ended() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in self.ended() }
    }

    private func ended() {
        let done = finished
        finished = nil
        player = nil
        release()
        done?()
    }

    /// Lets what was playing before (music, a podcast) come back.
    private func release() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension EnvironmentValues {
    /// Read aloud for the chat on screen; nil where there is no computer to ask (a read-only sheet).
    @Entry var readAloud: ReadAloudModel?
}
