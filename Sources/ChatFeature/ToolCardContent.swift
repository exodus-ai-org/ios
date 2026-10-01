import Foundation
import Models

/// A tool call's decoded arguments beside its decoded result.
struct DecodedCall<Arguments: Equatable & Sendable, Result: Equatable & Sendable>: Equatable, Sendable {
    let arguments: Arguments?
    let result: Result
}

/// A tool result read into its typed shape once, when its `ToolCard` is built by the grouper, and never while a card
/// is drawn. `untyped` is a tool with no typed shape; `undecodable` one whose shape did not match.
enum ToolCardContent: Equatable, Sendable {
    case untyped
    case undecodable
    case terminal(TerminalResult)
    case readFile(ReadFileCardModel)
    case writeFile(WriteFileCardModel)
    case editFile(EditFileCardModel)
    case computerUse(ComputerUseCardModel)
    case deepResearch(DeepResearchCardModel)
    case weather(WeatherCardState)
    case imageGeneration(ImageGenerationCardModel)
    case mapItinerary(MapItineraryCardState)
    case memoryUpdate(MemoryUpdateResult)
    case artifact(ArtifactResult)

    init(
        toolName: String, arguments: JSONValue?, payload: JSONValue?, isError: Bool = false, errorText: String? = nil,
        isPending: Bool = false, toolCallId: String? = nil, resultImage: String? = nil
    ) {
        if isPending {
            switch toolName {
            case "image_generation": self = .imageGeneration(.running(arguments: arguments))
            case "computer_use":
                self = .computerUse(
                    ComputerUseCardModel(
                        callId: toolCallId, arguments: arguments.flatMap(ComputerUseArguments.init(json:)), phase: .starting))
            default: self = .untyped
            }
            return
        }
        if isError {
            if toolName == "computer_use" {
                self = .computerUse(
                    ComputerUseCardModel(
                        callId: toolCallId, arguments: arguments.flatMap(ComputerUseArguments.init(json:)),
                        phase: .failed(errorText)))
                return
            }
            self = Self.failed(toolName: toolName, arguments: arguments, errorText: errorText)
            return
        }
        func call<A: JSONValueDecodable, R: JSONValueDecodable>(_: A.Type, _: R.Type) -> DecodedCall<A, R>? {
            payload.flatMap(R.init(json:)).map { DecodedCall(arguments: arguments.flatMap(A.init(json:)), result: $0) }
        }
        func result<R: JSONValueDecodable>(_: R.Type) -> R? { payload.flatMap(R.init(json:)) }

        let content: ToolCardContent? =
            switch toolName {
            case "terminal": result(TerminalResult.self).map(Self.terminal)
            case "read_file": call(ReadFileArguments.self, ReadFileResult.self).map { .readFile(ReadFileCardModel($0)) }
            case "write_file": call(WriteFileArguments.self, WriteFileResult.self).map { .writeFile(WriteFileCardModel($0)) }
            case "edit_file": call(EditFileArguments.self, EditFileResult.self).map { .editFile(EditFileCardModel($0)) }
            case "computer_use":
                call(ComputerUseArguments.self, ComputerUseDetails.self).map {
                    .computerUse(ComputerUseCardModel($0, callId: toolCallId, finalScreenshot: resultImage))
                }
            case "deep_research":
                call(DeepResearchArguments.self, DeepResearchResult.self).map { .deepResearch(DeepResearchCardModel($0)) }
            case "weather": result(WeatherResult.self).map { .weather(.forecast(WeatherCardModel($0))) }
            case "image_generation":
                call(ImageGenerationArguments.self, ImageGenerationResult.self).map {
                    .imageGeneration(ImageGenerationCardModel($0))
                }
            case "map_itinerary": result(MapItineraryDetails.self).map { .mapItinerary(.itinerary(MapItineraryCardModel($0))) }
            case "update_memory": result(MemoryUpdateResult.self).map(Self.memoryUpdate)
            case "create_artifact": result(ArtifactResult.self).map(Self.artifact)
            default: ToolCardContent.untyped
            }
        self = content ?? .undecodable
    }

    var terminal: TerminalResult? { if case .terminal(let value) = self { value } else { nil } }
    var readFile: ReadFileCardModel? { if case .readFile(let value) = self { value } else { nil } }
    var writeFile: WriteFileCardModel? { if case .writeFile(let value) = self { value } else { nil } }
    var editFile: EditFileCardModel? { if case .editFile(let value) = self { value } else { nil } }
    var computerUse: ComputerUseCardModel? { if case .computerUse(let value) = self { value } else { nil } }
    var deepResearch: DeepResearchCardModel? { if case .deepResearch(let value) = self { value } else { nil } }
    var weather: WeatherCardState? { if case .weather(let value) = self { value } else { nil } }
    var imageGeneration: ImageGenerationCardModel? { if case .imageGeneration(let value) = self { value } else { nil } }
    var mapItinerary: MapItineraryCardState? { if case .mapItinerary(let value) = self { value } else { nil } }
    var memoryUpdate: MemoryUpdateResult? { if case .memoryUpdate(let value) = self { value } else { nil } }
    var artifact: ArtifactResult? { if case .artifact(let value) = self { value } else { nil } }

    /// A failed call of a tool whose card draws failures: its path (the weather's place) and error text. Any other
    /// tool's failure has no content (it is a failed step in the timeline).
    private static func failed(toolName: String, arguments: JSONValue?, errorText: String?) -> ToolCardContent {
        let path: String =
            if case .object(let object)? = arguments {
                object["path"]?.stringValue ?? object["filePath"]?.stringValue ?? ""
            } else { "" }
        let failure = FailedFileCall(path: path, message: errorText)
        switch toolName {
        case "weather":
            let place: String = if case .object(let object)? = arguments { object["location"]?.stringValue ?? "" } else { "" }
            return .weather(.failed(place: place, message: errorText))
        case "image_generation": return .imageGeneration(.failed(arguments: arguments, message: errorText))
        case "deep_research":
            let subject = arguments.flatMap(DeepResearchArguments.init(json:))?.subject ?? ""
            return .deepResearch(DeepResearchCardModel(subject: subject, phase: .failed(errorText)))
        case "map_itinerary":
            let title: String? = if case .object(let object)? = arguments { object["title"]?.stringValue } else { nil }
            return .mapItinerary(.failed(title: title.flatMap { $0.isEmpty ? nil : $0 }, message: errorText))
        case "read_file": return .readFile(ReadFileCardModel(failure))
        case "write_file": return .writeFile(WriteFileCardModel(failure))
        case "edit_file": return .editFile(EditFileCardModel(failure, arguments: arguments.flatMap(EditFileArguments.init(json:))))
        default: return .untyped
        }
    }
}
