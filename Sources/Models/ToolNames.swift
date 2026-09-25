/// The one list of built-in tool names: the desktop's `TOOL_NAMES` (packages/shared/src/constants/tool-names.ts,
/// pinned by the SettingsFeature fixture test) plus `rag`, a retired tool whose rows old chats still hold (the
/// desktop's `BUILTIN_TOOL_NAMES` keeps it too).
public enum ToolNames {
    public static let builtIn: [String] = [
        "computer_use", "deep_research", "create_artifact", "image_generation", "find_files", "edit_file", "lcm_grep",
        "grep", "lcm_describe", "search_knowledge_base", "map_itinerary", "web_search", "lcm_expand", "weather",
        "list_directory", "terminal", "read_file", "web_fetch", "write_file", "update_memory", "list_mcp_tools",
        "call_mcp_tool",
    ]
    public static let retired: [String] = ["rag"]
    /// What a message row may name without being an unknown tool.
    public static let known: Set<String> = Set(builtIn + retired)
}
