#if DEBUG
import Foundation
import Models
import NetworkingKit
import SwiftUI

/// DEBUG-only: `-SettingsGallery` shows Settings against a canned settings row, unpaired; `-SettingsGalleryPage
/// connection|providers|tools|personality|memory` opens that page; `-SettingsGalleryProvider "Azure OpenAI"` (any
/// `AiProviders` value) makes that the saved provider; `-SettingsGalleryMemory context|list|edit|add|delete|empty|error`
/// scrolls the Memory page to its limits or its entries, opens its edit sheet, add sheet or delete confirmation, or serves an empty or
/// failing memory list; `-SettingsGalleryState empty|error` serves an empty or failing usage, skills, MCP and backup;
/// `-SettingsGalleryCatalog none|stale` changes the stored model list; `-ColorTone <tone>` is the stored tone;
/// `-SettingsGalleryAction backup|tools` starts Back Up Now or opens every MCP server's tools; on Providers,
/// `moveAddress` edits the base URL, `clear` clears the saved key and `keyReentry` makes the model list refuse the mask;
/// `-SettingsGallerySecrets reentry|old` shapes the secrets notice.
public enum SettingsGalleryLaunch {
    public static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-SettingsGallery") }

    static var page: SettingsPage? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-SettingsGalleryPage"), index + 1 < arguments.count else {
            return nil
        }
        return SettingsPage(rawValue: arguments[index + 1])
    }

    static var provider: String { value(after: "-SettingsGalleryProvider") ?? "Anthropic Claude" }

    static var memoryScene: String? { value(after: "-SettingsGalleryMemory") }

    static var state: String? { value(after: "-SettingsGalleryState") }

    static var action: String? { value(after: "-SettingsGalleryAction") }

    static var catalog: String? { value(after: "-SettingsGalleryCatalog") }

    /// `-SettingsGallerySecrets reentry|old`: the notice with keys to enter again and no keychain, or a computer too old
    /// to answer secrets-status.
    static var secrets: String? { value(after: "-SettingsGallerySecrets") }

    static var tone: String { value(after: "-ColorTone") ?? "neutral" }

    static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}

public struct SettingsGalleryView: View {
    private let apiClient: APIClient
    private let serverConfig: ServerConfigStore

    public init() {
        let defaults = UserDefaults(suiteName: "SettingsGallery")!
        defaults.removePersistentDomain(forName: "SettingsGallery")
        let config = ServerConfigStore(userDefaults: defaults)
        config.connection = ServerConnection(store: GalleryCredentialStore())
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [GalleryURLProtocol.self]
        serverConfig = config
        apiClient = APIClient(session: URLSession(configuration: sessionConfiguration), serverConfig: config)
    }

    public var body: some View {
        SettingsView(
            apiClient: apiClient, serverConfig: serverConfig, path: SettingsGalleryLaunch.page.map { [$0] } ?? [])
    }
}

private struct GalleryCredentialStore: CredentialStoring {
    func load(reason: String) async throws -> PairedServer? { nil }
    func save(_ server: PairedServer) throws {}
    func clear() throws {}
    var exists: Bool { false }
}

private final class GalleryURLProtocol: URLProtocol, @unchecked Sendable {
    private static var settingsJSON: String {
        #"""
        {"id":"global","providerConfig":{"provider":"\#(SettingsGalleryLaunch.provider)","model":"claude-sonnet-5"},
         "providers":{"anthropicApiKey":"•••• 7f3a","anthropicBaseUrl":"https://llm-proxy.example.com",
           "azureOpenaiApiKey":"••••","azureOpenAiEndpoint":"https://gallery.openai.azure.com/openai/deployments/gpt",
           "azureOpenAiApiVersion":"2024-12-01-preview"},
         "personality":{"nickname":"Yancey","occupation":"Software engineer","baseStyle":"candid","warm":"more",
           "emoji":"less","customInstructions":"Answer in short paragraphs. Show code before prose."},
         "tools":{"disabledTools":["terminal","webSearch","future_tool"]},
         "memory":{"autoCapture":true,"useInChat":false,"lcmEnabled":true,"contextWindowPercent":80,"freshTailSize":32},
         "modelCatalog":\#(catalogJSON),"colorTone":"\#(SettingsGalleryLaunch.tone)",
         "lastBackupAt":null}
        """#
    }

    private static let modelsJSON = #"""
        [{"id":"claude-opus-5","displayName":"Claude Opus 5","snapshot":{"contextWindow":1000000,"reasoningLevels":["low","high"]}},
         {"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"contextWindow":1000000,"reasoningLevels":["low","high"]}},
         {"id":"claude-haiku-5","displayName":"Claude Haiku 5","snapshot":{"contextWindow":200000,"reasoningLevels":[]}}]
        """#

    /// `-SettingsGalleryCatalog none` stores no list (the page then fetches one), `stale` one without the saved model.
    private static var catalogJSON: String {
        switch SettingsGalleryLaunch.catalog {
        case "none": "null"
        case "stale": #"{"Anthropic Claude":[{"id":"claude-opus-5","displayName":"Claude Opus 5","snapshot":{}}]}"#
        default: #"{"Anthropic Claude":"# + modelsJSON + "}"
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static let memoryJSON = #"""
        [{"id":"m1","section":"profile","key":"Setup","summary":"MacBook Pro, iPhone 17 Pro, works in Swift and TypeScript",
          "details":["Runs Exodus on the Mac","Prefers dark mode"],"isActive":true,"updatedAt":"2026-09-23T10:00:00.000Z"},
         {"id":"m2","section":"topic","key":"Classical Music","summary":"Listens to Bach and Arvo Pärt while working",
          "details":["Owns the Glenn Gould Goldberg recordings"],"isActive":true},
         {"id":"m3","section":"topic","key":"Exodus iOS","summary":"","details":[],"isActive":true},
         {"id":"m4","section":"person","key":"Ada","summary":"Sister; lives in Lisbon","details":[],"isActive":true},
         {"id":"m5","section":"topic","key":"Marathon training","summary":"Paused after a knee injury",
          "details":[],"isActive":false}]
        """#

    private static var usageJSON: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let pattern: [Double] = [
            42_000, 0, 180_000, 96_000, 310_000, 0, 0, 58_000, 240_000, 120_000, 410_000, 0, 88_000, 150_000,
            0, 0, 64_000, 290_000, 175_000, 36_000, 520_000, 0, 0, 110_000, 205_000, 90_000, 330_000, 140_000,
            260_000, 72_000, 188_000, 95_000, 0, 450_000, 210_000,
        ]
        let days = pattern.enumerated().compactMap { offset, tokens -> String? in
            guard tokens > 0,
                let date = calendar.date(byAdding: .day, value: offset - pattern.count + 1, to: today)
            else { return nil }
            let date10 = UsageStats.dayString(date, calendar: calendar)
            return #"{"date":"\#(date10)","cost":\#(tokens / 250_000),"tokens":\#(tokens)}"#
        }
        return #"""
            {"totalCost":58.73,"totalTokens":48250000,"totalRequests":3184,"daily":[\#(days.joined(separator: ","))],
             "models":[
              {"model":"claude-sonnet-5","provider":"anthropic","cost":31.2,"inputTokens":21000000,"outputTokens":3100000,"cacheReadTokens":9000000,"requests":1402},
              {"model":"gpt-5.6","provider":"openai","cost":14.05,"inputTokens":9800000,"outputTokens":1400000,"cacheReadTokens":0,"requests":803},
              {"model":"gemini-3-pro","provider":"google","cost":8.9,"inputTokens":6100000,"outputTokens":900000,"cacheReadTokens":0,"requests":512},
              {"model":"grok-5","provider":"xai","cost":3.1,"inputTokens":2400000,"outputTokens":350000,"cacheReadTokens":0,"requests":270},
              {"model":"qwen3:32b","provider":"ollama","cost":0,"inputTokens":1800000,"outputTokens":400000,"cacheReadTokens":0,"requests":150},
              {"model":"claude-haiku-5","provider":"anthropic","cost":0.0042,"inputTokens":9000,"outputTokens":1000,"cacheReadTokens":0,"requests":47}]}
            """#
    }

    private static let skillsJSON = #"""
        [{"slug":"pdf","displayName":"PDF","version":"1.4.0","isActive":true,"installPath":"/x","installedAt":1756000000000,
          "registryId":"anthropics/skills/pdf","source":"skills.sh"},
         {"slug":"frontend-design","displayName":"Frontend Design","version":"0.9.2","isActive":false,"installPath":"/x",
          "installedAt":1757500000000,"registryId":"anthropics/skills/frontend-design","source":"skills.sh"},
         {"slug":"weekly-report","displayName":"Weekly Report","version":"0.1.0","isActive":true,"installPath":"/x",
          "installedAt":1745000000000}]
        """#

    private static let mcpJSON = #"""
        [{"id":"s1","name":"github","description":"Issues and pull requests","transportType":"stdio","command":"npx",
          "args":["-y","@modelcontextprotocol/server-github"],"env":{"GITHUB_TOKEN":"•••• 9c1d"},"isActive":true},
         {"id":"s2","name":"linear","description":"","transportType":"streamable-http","url":"https://mcp.linear.app/mcp",
          "headers":{"Authorization":"•••• e0b2"},"isActive":true},
         {"id":"s3","name":"filesystem","description":"Local files outside the workspace","transportType":"stdio",
          "command":"fs-server","isActive":null}]
        """#

    private static let mcpToolsJSON = #"""
        {"tools":[{"mcpServerName":"github","tools":[
           {"name":"search_issues","description":"Search issues and pull requests across repositories."},
           {"name":"create_issue","description":"Open a new issue in a repository."},
           {"name":"get_pull_request","description":"Read a pull request with its diff and review comments."}]},
          {"mcpServerName":"linear","tools":[{"name":"list_issues","description":"List issues assigned to you."},
           {"name":"update_issue","description":""}]}]}
        """#

    private static let backupStatusJSON = #"{"autoBackup":true,"lastBackupAt":"2026-09-24T03:00:02.123Z"}"#

    private static let backupListJSON = #"""
        [{"name":"2026-09-24.tar.gz","size":48213004,"createdAt":"2026-09-24T03:00:02.123Z"},
         {"name":"2026-09-23.tar.gz","size":47990112,"createdAt":"2026-09-23T03:00:01.004Z"},
         {"name":"2026-09-22.tar.gz","size":47100023,"createdAt":"2026-09-22T03:00:01.771Z"}]
        """#

    /// The canned answer for the pages of B6–B8, or nil for any other path.
    private static func pageResponse(path: String, method: String) -> (Int, String)? {
        let empty = SettingsGalleryLaunch.state == "empty"
        let failing = SettingsGalleryLaunch.state == "error"
        let failure = #"{"type":"error","error":{"code":"INTERNAL","message":"The computer did not answer."}}"#
        switch (method, path) {
        case ("POST", "/api/v1/settings/models"):
            Thread.sleep(forTimeInterval: 1.5)
            if SettingsGalleryLaunch.action == "keyReentry" {
                return (
                    400,
                    #"{"type":"error","error":{"code":"SECRET_REENTRY_REQUIRED","message":"The base URL differs from the saved one: re-enter the API key to use it with a new base URL","params":{"field":"apiKey"}}}"#
                )
            }
            return (200, #"{"models":"# + modelsJSON + "}")
        case ("GET", "/api/v1/settings/secrets-status"):
            switch SettingsGalleryLaunch.secrets {
            case "reentry":
                return (
                    200,
                    #"{"encryption":"unavailable","needsReentry":["providers.anthropicApiKey","webSearch.braveApiKey","mcp:github:env.GITHUB_TOKEN"]}"#
                )
            case "old": return (404, #"{"type":"error","error":{"code":"NOT_FOUND","message":"Not found"}}"#)
            default: return (200, #"{"encryption":"on","needsReentry":[]}"#)
            }
        case ("GET", "/api/v1/usage"):
            if failing { return (500, failure) }
            return (200, empty ? #"{"totalCost":0,"totalTokens":0,"totalRequests":0,"daily":[],"models":[]}"# : usageJSON)
        case ("GET", "/api/v1/history"):
            return (200, "[" + Array(repeating: #"{"id":"c"}"#, count: empty ? 0 : 42).joined(separator: ",") + "]")
        case ("GET", "/api/v1/skills/installed"):
            if failing { return (500, failure) }
            return (200, empty ? "[]" : skillsJSON)
        case ("GET", "/api/v1/mcp"):
            if failing { return (500, failure) }
            return (200, empty ? "[]" : mcpJSON)
        case ("GET", "/api/v1/mcp/tools"):
            return (200, empty ? #"{"tools":[]}"# : mcpToolsJSON)
        case ("GET", "/api/v1/backup/status"):
            if failing { return (500, failure) }
            return (200, empty ? #"{"autoBackup":false,"lastBackupAt":null}"# : backupStatusJSON)
        case ("GET", "/api/v1/backup/list"):
            return (200, empty ? "[]" : backupListJSON)
        case ("POST", "/api/v1/backup/now"):
            Thread.sleep(forTimeInterval: 3)
            if failing { return (500, failure) }
            return (200, #"{"filePath":"/Users/me/.exodus/backups/2026-09-24.tar.gz"}"#)
        case (_, let other) where other.hasPrefix("/api/v1/skills/") || other.hasPrefix("/api/v1/mcp/"):
            return (200, #"{"success":true}"#)
        default:
            return nil
        }
    }

    override func startLoading() {
        var status = 200
        var body = request.httpMethod == "GET" ? Data(Self.settingsJSON.utf8) : Data("{}".utf8)
        if let (pageStatus, pageBody) = Self.pageResponse(
            path: request.url?.path ?? "", method: request.httpMethod ?? "GET")
        {
            status = pageStatus
            body = Data(pageBody.utf8)
        }
        if request.url?.path == "/api/v1/memory", request.httpMethod == "GET" {
            switch SettingsGalleryLaunch.memoryScene {
            case "empty": body = Data("[]".utf8)
            case "error":
                status = 500
                body = Data(#"{"type":"error","error":{"code":"INTERNAL","message":"Failed to load memories"}}"#.utf8)
            default: body = Data(Self.memoryJSON.utf8)
            }
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
