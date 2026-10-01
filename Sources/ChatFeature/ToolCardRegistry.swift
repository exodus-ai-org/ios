import Models
import SwiftUI

/// Which card draws a tool's result: one entry per card, naming the decoded content it reads and the view that draws
/// it. A registered built-in gets a card in the transcript; a tool with no entry, or whose details did not decode,
/// is drawn by the generic card.
enum ToolCardRegistry {
    static let cards: [String: ToolCardBuilder] = [
        "terminal": ToolCardBuilder(\.terminal) { TerminalCard(output: $0) },
        "read_file": ToolCardBuilder(\.readFile, drawsFailures: true) { ReadFileCard(model: $0) },
        "write_file": ToolCardBuilder(\.writeFile, drawsFailures: true) { WriteFileCard(model: $0) },
        "edit_file": ToolCardBuilder(\.editFile, drawsFailures: true) { EditFileCard(model: $0) },
        "weather": ToolCardBuilder(\.weather, drawsFailures: true) { WeatherCard(state: $0) },
        "image_generation": ToolCardBuilder(\.imageGeneration, drawsFailures: true, drawsPending: true) {
            ImageGenerationCard(model: $0)
        },
        "map_itinerary": ToolCardBuilder(\.mapItinerary, drawsFailures: true) { MapItineraryCard(state: $0) },
        "computer_use": ToolCardBuilder(\.computerUse, drawsFailures: true, drawsPending: true) {
            ComputerUseCard(model: $0)
        },
        "deep_research": ToolCardBuilder(\.deepResearch, drawsFailures: true) { DeepResearchCard(model: $0) },
        "create_artifact": ToolCardBuilder(\.artifact) { ArtifactCard(artifact: $0) },
        // Drawn at the run's foot (`MemoryChangeStrip`), never in the timeline: the entry exists so an unreadable result
        // falls back to the generic card and is reported.
        "update_memory": ToolCardBuilder(\.memoryUpdate) { _ in EmptyView() },
    ]

    /// What `ToolCardView` draws, and what it reports when it falls back.
    enum Resolution {
        case card(AnyView)
        case generic(issue: ToolPresentation.RenderIssue?)
    }

    @MainActor
    static func resolve(_ card: ToolCard) -> Resolution {
        if let view = cards[card.toolName]?.make(card.content) { return .card(view) }
        return .generic(issue: ToolPresentation.renderIssue(for: card))
    }

    static func hasCard(for toolName: String) -> Bool { cards[toolName] != nil }

    /// A failed call of such a tool is drawn by its card too (with the tool's error), not only as a timeline step.
    static func drawsFailures(for toolName: String) -> Bool { cards[toolName]?.drawsFailures ?? false }

    /// A call of such a tool has its card from the moment it is made (a running state), not only once it returns.
    static func drawsPending(for toolName: String) -> Bool { cards[toolName]?.drawsPending ?? false }

    static func canDraw(_ card: ToolCard) -> Bool { cards[card.toolName]?.canDraw(card.content) ?? false }
}

struct ToolCardBuilder: Sendable {
    let canDraw: @Sendable (ToolCardContent) -> Bool
    let make: @MainActor @Sendable (ToolCardContent) -> AnyView?
    let drawsFailures: Bool
    let drawsPending: Bool

    init<Value, Card: View>(
        _ read: @escaping @Sendable (ToolCardContent) -> Value?,
        drawsFailures: Bool = false,
        drawsPending: Bool = false,
        _ card: @escaping @MainActor @Sendable (Value) -> Card
    ) {
        self.drawsFailures = drawsFailures
        self.drawsPending = drawsPending
        canDraw = { read($0) != nil }
        make = { content in read(content).map { AnyView(card($0)) } }
    }
}
