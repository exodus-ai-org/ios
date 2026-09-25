import Foundation
import Observation

@MainActor
@Observable
public final class MarkdownStreamModel {
    public private(set) var blocks: [MarkdownBlock] = []
    public private(set) var citations: [Int] = []
    @ObservationIgnored public private(set) var lastUpdateParseCount = 0

    @ObservationIgnored private var text: String?
    @ObservationIgnored private var isStreaming = false
    @ObservationIgnored private var isSplit = false
    @ObservationIgnored private var cache = MarkdownBlockCache()
    @ObservationIgnored private var entries: [(input: String, result: MarkdownParseResult)] = []

    @ObservationIgnored private var memo: (blocks: [MarkdownBlock], citations: [Int]) = ([], [])
    @ObservationIgnored private var observedIsStale = false
    /// Told once per markup kind this model's text fell back to plain text for.
    @ObservationIgnored public var diagnostics: RenderDiagnostics = .none
    @ObservationIgnored private var reportedKinds: Set<String> = []

    public init() {}

    public func update(text: String, isStreaming: Bool) {
        let changed = apply(text: text, isStreaming: isStreaming)
        guard changed || observedIsStale else { return }
        observedIsStale = false
        blocks = memo.blocks
        citations = memo.citations
    }

    /// The blocks for `text`, computed synchronously and without touching observed state, so a view can
    /// call it from `body` and has its blocks on the very first frame (a lazy list measures real height).
    public func blocks(for text: String, isStreaming: Bool) -> [MarkdownBlock] {
        rendered(for: text, isStreaming: isStreaming).blocks
    }

    /// The citation numbers for the same `text`, consistent with `blocks(for:isStreaming:)`.
    public func citations(for text: String, isStreaming: Bool) -> [Int] {
        rendered(for: text, isStreaming: isStreaming).citations
    }

    public func rendered(for text: String, isStreaming: Bool) -> (blocks: [MarkdownBlock], citations: [Int]) {
        if apply(text: text, isStreaming: isStreaming) { observedIsStale = true }
        return memo
    }

    private func apply(text: String, isStreaming: Bool) -> Bool {
        if text == self.text, isStreaming == self.isStreaming {
            lastUpdateParseCount = 0
            return false
        }
        // A reply that ever streamed stays split so its settled blocks survive the final frame.
        if isStreaming || (self.text != nil && isSplit) { isSplit = true }
        self.text = text
        self.isStreaming = isStreaming

        let inputs: [String]
        if isSplit {
            let pieces = MarkdownPreprocessor.splitBlocks(text, cache: &cache)
            inputs = pieces.enumerated().map { index, piece in
                isStreaming && index == pieces.count - 1 ? MarkdownPreprocessor.healTail(String(piece)) : String(piece)
            }
        } else {
            inputs = text.isEmpty ? [] : [text]
        }

        var parses = 0
        var next: [(input: String, result: MarkdownParseResult)] = []
        next.reserveCapacity(inputs.count)
        for (index, input) in inputs.enumerated() {
            if index < entries.count, entries[index].input == input {
                next.append(entries[index])
            } else {
                let result = MarkdownParser.parse(input, source: index)
                noteUnhandled(result.unhandledKinds)
                next.append((input, result))
                parses += 1
            }
        }
        entries = next
        lastUpdateParseCount = parses
        memo = (next.flatMap(\.result.blocks), next.flatMap(\.result.citations))
        return true
    }

    func noteUnhandled(_ kinds: [String]) {
        for kind in kinds where reportedKinds.insert(kind).inserted {
            diagnostics.report("markdown", "Markup rendered as plain text", ["markup": kind])
        }
    }
}
