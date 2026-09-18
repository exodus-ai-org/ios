public enum AiProviders: String, Codable, CaseIterable, Sendable, Identifiable {
    case openAiGpt = "OpenAI GPT"
    case azureOpenAi = "Azure OpenAI"
    case anthropicClaude = "Anthropic Claude"
    case googleGemini = "Google Gemini"
    case xaiGrok = "xAI Grok"
    case ollama = "Ollama"

    public var id: String { rawValue }
}
