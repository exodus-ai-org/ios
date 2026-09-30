import Foundation
import Models
import Testing

@testable import ChatFeature

@Suite("Read aloud: what is read")
struct SpeechTextTests {
    @Test("the answer as prose: markdown taken off, citation markers gone, no space left before the full stop")
    func prose() {
        #expect(
            SpeechText.prose("Swift 6.2 is **out** \u{3010}1-source\u{3011} and `fast`\u{3010}1,2-source\u{3011}.")
                == "Swift 6.2 is out and fast.")
        #expect(SpeechText.prose("# Title\n\n- one\n- two \u{3010}3-source\u{3011}") == "Title one two")
        #expect(SpeechText.prose("See [the notes](https://x.example/n).") == "See the notes.")
    }

    @Test("nothing to say is an empty text")
    func empty() {
        #expect(SpeechText.prose(" \n ") == "")
        #expect(SpeechText.prose("\u{3010}1-source\u{3011}") == "")
    }
}

@MainActor
private final class FakePlayer: SpeechPlayer {
    var played: [Data] = []
    var stops = 0
    var failure: Error?
    private var finished: (@MainActor () -> Void)?

    func play(_ audio: Data, finished: @escaping @MainActor () -> Void) throws {
        if let failure { throw failure }
        played.append(audio)
        self.finished = finished
    }

    func stop() {
        stops += 1
        finished = nil
    }

    /// The audio ran to its end.
    func finish() {
        let done = finished
        finished = nil
        done?()
    }
}

/// A computer that answers when the test says so.
private actor FakeSpeech {
    private(set) var asked: [String] = []
    private var waiting: [CheckedContinuation<Data, Error>] = []

    func fetch(_ text: String) async throws -> Data {
        asked.append(text)
        return try await withCheckedThrowingContinuation { waiting.append($0) }
    }

    func answer(_ data: Data) {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume(returning: data)
    }

    func fail(_ error: Error) {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume(throwing: error)
    }

    var isWaiting: Bool { !waiting.isEmpty }
}

@MainActor
@Suite("Read aloud: idle, loading, playing")
struct ReadAloudModelTests {
    private let audio = Data([1, 2, 3])

    private func make() -> (ReadAloudModel, FakeSpeech, FakePlayer) {
        let speech = FakeSpeech()
        let player = FakePlayer()
        return (ReadAloudModel(fetch: { try await speech.fetch($0) }, player: player), speech, player)
    }

    /// Starts a read and waits until the computer has been asked.
    private func start(_ model: ReadAloudModel, _ speech: FakeSpeech, id: String, text: String = "Hello") async -> Task<Void, Never> {
        let task = Task { await model.toggle(id: id, text: text) }
        while await !speech.isWaiting { await Task.yield() }
        return task
    }

    @Test("a tap asks the computer, then plays what it sent; the end of the audio is idle again")
    func playsThrough() async {
        let (model, speech, player) = make()
        #expect(model.phase(for: "a") == .idle)
        let task = await start(model, speech, id: "a")
        #expect(model.phase(for: "a") == .loading)
        #expect(model.phase(for: "b") == .idle)
        await speech.answer(audio)
        await task.value
        #expect(model.phase(for: "a") == .playing)
        #expect(player.played == [audio])
        #expect(await speech.asked == ["Hello"])
        player.finish()
        #expect(model.phase(for: "a") == .idle)
    }

    @Test("a second tap while it plays stops it")
    func tapStops() async {
        let (model, speech, player) = make()
        let task = await start(model, speech, id: "a")
        await speech.answer(audio)
        await task.value
        await model.toggle(id: "a", text: "Hello")
        #expect(model.phase(for: "a") == .idle)
        #expect(player.stops >= 1)
        #expect(player.played.count == 1)
    }

    @Test("a tap while it loads gives up: what comes back later is not played")
    func tapWhileLoading() async {
        let (model, speech, player) = make()
        let task = await start(model, speech, id: "a")
        await model.toggle(id: "a", text: "Hello")
        #expect(model.phase(for: "a") == .idle)
        await speech.answer(audio)
        await task.value
        #expect(model.phase(for: "a") == .idle)
        #expect(player.played.isEmpty)
    }

    @Test("starting one answer stops another")
    func oneAtATime() async {
        let (model, speech, player) = make()
        let first = await start(model, speech, id: "a", text: "One")
        await speech.answer(audio)
        await first.value
        let second = await start(model, speech, id: "b", text: "Two")
        #expect(model.phase(for: "a") == .idle)
        #expect(model.phase(for: "b") == .loading)
        #expect(player.stops >= 1)
        await speech.answer(Data([9]))
        await second.value
        #expect(model.phase(for: "b") == .playing)
        #expect(player.played == [audio, Data([9])])
    }

    @Test("an answer's audio is kept: a second play does not ask the computer again")
    func kept() async {
        let (model, speech, player) = make()
        let task = await start(model, speech, id: "a")
        await speech.answer(audio)
        await task.value
        player.finish()
        await model.toggle(id: "a", text: "Hello")
        #expect(model.phase(for: "a") == .playing)
        #expect(await speech.asked.count == 1)
        #expect(player.played == [audio, audio])
    }

    @Test("stop ends whatever is going on: leaving the chat, the app going to the background")
    func stop() async {
        let (model, speech, player) = make()
        let task = await start(model, speech, id: "a")
        await speech.answer(audio)
        await task.value
        model.stop()
        #expect(model.phase(for: "a") == .idle)
        #expect(player.stops >= 1)
        player.finish()
        #expect(model.phase(for: "a") == .idle)
    }

    @Test("the computer's refusal is reported with its own words, and the button is idle again")
    func refusal() async {
        let (model, speech, player) = make()
        var failures: [String] = []
        model.onFailure = { failures.append($0) }
        let task = await start(model, speech, id: "a")
        await speech.fail(HTTPError(statusCode: 400, code: "VALIDATION_FAILED", message: "OpenAI API key is not configured"))
        await task.value
        #expect(failures == ["OpenAI API key is not configured"])
        #expect(model.phase(for: "a") == .idle)
        #expect(player.played.isEmpty)
    }

    @Test("audio the phone cannot play is reported, not kept, and the button is idle again")
    func unplayable() async {
        let (model, speech, player) = make()
        var failures: [String] = []
        model.onFailure = { failures.append($0) }
        player.failure = CocoaError(.fileReadCorruptFile)
        let task = await start(model, speech, id: "a")
        await speech.answer(audio)
        await task.value
        #expect(failures == [ReadAloudText.cannotPlay])
        #expect(model.phase(for: "a") == .idle)
        player.failure = nil
        let again = await start(model, speech, id: "a")
        await speech.answer(audio)
        await again.value
        #expect(await speech.asked.count == 2)
    }

    @Test("a cancelled request says nothing")
    func cancelled() async {
        let (model, speech, _) = make()
        var failures: [String] = []
        model.onFailure = { failures.append($0) }
        let task = await start(model, speech, id: "a")
        await speech.fail(CancellationError())
        await task.value
        #expect(failures.isEmpty)
        #expect(model.phase(for: "a") == .idle)
    }

    @Test("an empty text is never asked for")
    func nothingToRead() async {
        let (model, speech, _) = make()
        await model.toggle(id: "a", text: "  ")
        #expect(model.phase(for: "a") == .idle)
        #expect(await speech.asked.isEmpty)
    }
}
