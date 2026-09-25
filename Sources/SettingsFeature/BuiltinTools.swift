import Foundation
import Models

/// The desktop's built-in tools as the phone knows them. There is no endpoint that lists them, so this mirrors
/// `TOOL_NAMES` (`packages/shared/src/constants/tool-names.ts`) and the switchable subset in `TOOL_REGISTRY`
/// (`constants/tools.ts`); `BuiltinToolsTableTests` pins both against a checked-in copy of the desktop's lists.
enum BuiltinTools {
    enum Group: String, CaseIterable, Identifiable {
        case web = "Web"
        case fileSystem = "File System"
        case aiData = "AI & Data"
        case maps = "Maps"

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .web: LocalizedStringResource("settings:tools.groups.web")
            case .fileSystem: LocalizedStringResource("settings:tools.groups.fileSystem")
            case .aiData: LocalizedStringResource("settings:tools.groups.aiData")
            case .maps: LocalizedStringResource("settings:tools.groups.maps")
            }
        }
    }

    /// A tool the desktop's Built-in Tools page has a switch for.
    struct Tool: Identifiable, Equatable {
        /// The wire name, as stored in `settings.tools.disabledTools`.
        let name: String
        let group: Group
        let title: LocalizedStringResource
        let summary: LocalizedStringResource
        /// Its settings panel holds a key or options the phone does not edit.
        var configuredOnComputer = false

        var id: String { name }

        static func == (lhs: Tool, rhs: Tool) -> Bool { lhs.name == rhs.name }
    }

    /// `TOOL_REGISTRY`, in its order.
    static let switchable: [Tool] = [
        Tool(
            name: "weather", group: .web,
            title: LocalizedStringResource("settings:tools.registry.weather.label"),
            summary: LocalizedStringResource("settings:tools.registry.weather.description")),
        Tool(
            name: "web_search", group: .web,
            title: LocalizedStringResource("settings:tools.registry.webSearch.label"),
            summary: LocalizedStringResource("settings:tools.registry.webSearch.description"), configuredOnComputer: true),
        Tool(
            name: "web_fetch", group: .web,
            title: LocalizedStringResource("settings:tools.registry.webFetch.label"),
            summary: LocalizedStringResource("settings:tools.registry.webFetch.description")),
        Tool(
            name: "terminal", group: .fileSystem,
            title: LocalizedStringResource("settings:tools.registry.terminal.label"),
            summary: LocalizedStringResource("settings:tools.registry.terminal.description")),
        Tool(
            name: "read_file", group: .fileSystem,
            title: LocalizedStringResource("settings:tools.registry.readFile.label"),
            summary: LocalizedStringResource("settings:tools.registry.readFile.description")),
        Tool(
            name: "write_file", group: .fileSystem,
            title: LocalizedStringResource("settings:tools.registry.writeFile.label"),
            summary: LocalizedStringResource("settings:tools.registry.writeFile.description")),
        Tool(
            name: "edit_file", group: .fileSystem,
            title: LocalizedStringResource("settings:tools.registry.editFile.label"),
            summary: LocalizedStringResource("settings:tools.registry.editFile.description")),
        Tool(
            name: "list_directory", group: .fileSystem,
            title: LocalizedStringResource("settings:tools.registry.listDirectory.label"),
            summary: LocalizedStringResource("settings:tools.registry.listDirectory.description")),
        Tool(
            name: "find_files", group: .fileSystem,
            title: LocalizedStringResource("settings:tools.registry.findFiles.label"),
            summary: LocalizedStringResource("settings:tools.registry.findFiles.description")),
        Tool(
            name: "grep", group: .fileSystem,
            title: LocalizedStringResource("settings:tools.registry.grep.label"),
            summary: LocalizedStringResource("settings:tools.registry.grep.description")),
        Tool(
            name: "image_generation", group: .aiData,
            title: LocalizedStringResource("settings:tools.registry.imageGeneration.label"),
            summary: LocalizedStringResource("settings:tools.registry.imageGeneration.description"), configuredOnComputer: true),
        Tool(
            name: "search_knowledge_base", group: .aiData,
            title: LocalizedStringResource("settings:tools.registry.searchKnowledgeBase.label"),
            summary: LocalizedStringResource("settings:tools.registry.searchKnowledgeBase.description")),
        Tool(
            name: "update_memory", group: .aiData,
            title: LocalizedStringResource("settings:tools.registry.updateMemory.label"),
            summary: LocalizedStringResource("settings:tools.registry.updateMemory.description")),
        Tool(
            name: "map_itinerary", group: .maps,
            title: LocalizedStringResource("settings:tools.registry.mapItinerary.label"),
            summary: LocalizedStringResource("settings:tools.registry.mapItinerary.description"), configuredOnComputer: true),
    ]

    /// Every value of `TOOL_NAMES`: the switchable tools plus the ones the desktop binds on its own terms.
    static var allNames: Set<String> { Set(ToolNames.builtIn) }

    /// `LEGACY_TOOL_NAMES`: the camelCase names stored before the desktop's migration 0007. The desktop still reads
    /// them as the snake_case tool.
    static let legacyNames: [String: String] = [
        "computerUse": "computer_use", "deepResearch": "deep_research", "createArtifact": "create_artifact",
        "imageGeneration": "image_generation", "findFiles": "find_files", "editFile": "edit_file",
        "lcmGrep": "lcm_grep", "grep": "grep", "lcmDescribe": "lcm_describe",
        "searchKnowledgeBase": "search_knowledge_base", "mapItinerary": "map_itinerary", "webSearch": "web_search",
        "lcmExpand": "lcm_expand", "weather": "weather", "listDirectory": "list_directory", "terminal": "terminal",
        "readFile": "read_file", "webFetch": "web_fetch", "writeFile": "write_file",
    ]

    /// `toToolName()`: a legacy name becomes its wire name; anything else is unchanged.
    static func wireName(_ stored: String) -> String { legacyNames[stored] ?? stored }

    /// Names in `disabledTools` this app does not know: a tool the desktop added after this table was written.
    static func unknownNames(in disabled: [String]) -> [String] {
        var seen = Set<String>()
        return disabled.filter { !allNames.contains(wireName($0)) && seen.insert($0).inserted }
    }
}
