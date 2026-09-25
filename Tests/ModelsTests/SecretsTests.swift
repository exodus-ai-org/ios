import Foundation
import Testing

@testable import Models

/// Fixtures copied from exodus `tests/unit/main/lib/secrets/mask.test.ts`, `tests/unit/shared/utils/base-url.test.ts`,
/// `tests/unit/renderer/lib/secrets.test.ts` and `tests/unit/main/lib/server/routes/chat-approval.test.ts`.
@Suite("Secrets: the desktop's masks and rules")
struct SecretsTests {
    @Test("mask: the last four of 12 characters or more, bullets for shorter, nil for unset")
    func mask() {
        #expect(SecretMask.mask("sk-abcdefgh1234") == "•••• 1234")
        #expect(SecretMask.mask("123456789012") == "•••• 9012")
        #expect(SecretMask.mask("short") == "••••")
        #expect(SecretMask.mask("12345678901") == "••••")
        #expect(SecretMask.mask(nil) == nil)
        #expect(SecretMask.mask("") == nil)
        // The tail is four code points (what looksLikeMask counts), so a mask made here reads as one there.
        let emoji = SecretMask.mask("sk-12345678👍🏽")
        #expect(emoji == "•••• 78👍🏽")
        #expect(SecretMask.looksLikeMask(emoji))
        #expect(SecretMask.looksLikeMask(SecretMask.mask("sk-1234567890ab\u{0065}\u{0301}")))
        // The length is the desktop's (UTF-16 units): 11 characters of which one is astral is 12 units.
        #expect(SecretMask.mask("abcdefghij😀") == "•••• hij😀")
    }

    @Test("looksLikeMask recognises both mask shapes and nothing else")
    func looksLikeMask() {
        #expect(SecretMask.looksLikeMask("••••"))
        #expect(SecretMask.looksLikeMask("•••• abcd"))
        #expect(!SecretMask.looksLikeMask("sk-live-1234"))
        #expect(!SecretMask.looksLikeMask("•••• abcde"))
        #expect(!SecretMask.looksLikeMask(""))
        #expect(!SecretMask.looksLikeMask(nil))
    }

    @Test("lastFour reads a mask, and judges a plaintext key (an older computer) by the same rule")
    func lastFour() {
        #expect(SecretMask.lastFour(of: "•••• abcd") == "abcd")
        #expect(SecretMask.lastFour(of: "••••") == nil)
        #expect(SecretMask.lastFour(of: "sk-live-1234567890abcd") == "abcd")
        #expect(SecretMask.lastFour(of: "sk-short") == nil)
        #expect(SecretMask.lastFour(of: nil) == nil)
    }

    /// All 19 cases of exodus `tests/unit/shared/utils/base-url.test.ts` at desktop HEAD `8fc87f53`.
    @Test(
        "normalizeBaseURL matches the desktop's normalizeBaseUrl, case for case",
        arguments: [
            ("https://api.openai.com/v1", "https://api.openai.com/v1"),
            ("https://API.OpenAI.com/v1/", "https://api.openai.com/v1"),
            ("  https://api.openai.com/v1  ", "https://api.openai.com/v1"),
            ("HTTPS://api.anthropic.com", "https://api.anthropic.com"),
            ("https://api.anthropic.com/", "https://api.anthropic.com"),
            ("http://localhost:9200//", "http://localhost:9200"),
            ("http://localhost:9200/Path/", "http://localhost:9200/Path"),
            ("https://h.example:443/v1", "https://h.example/v1"),
            ("http://h.example:8080/v1", "http://h.example:8080/v1"),
            ("http://[::1]:9621/", "http://[::1]:9621"),
            ("http://[FE80::1]/x", "http://[fe80::1]/x"),
            ("https://h.example/v1?api-version=1", "https://h.example/v1?api-version=1"),
            ("https://u:p@h.example/v1", "https://h.example/v1"),
            ("not a url/", "not a url"),
            ("", nil),
            ("   ", nil),
            (nil, nil),
            (nil, nil),
            ("https://api.openai.com@evil.example/v1", "https://evil.example/v1"),
        ] as [(String?, String?)])
    func normalize(input: String?, expected: String?) {
        #expect(SecretDestinations.normalizeBaseURL(input) == expected)
    }

    @Test(
        "dot segments resolve as WHATWG's URL parser resolves them",
        arguments: [
            ("https://h.example/v1/./", "https://h.example/v1"),
            ("https://h.example/a/../v1", "https://h.example/v1"),
            ("https://h.example/../../v1", "https://h.example/v1"),
            ("https://h.example/v1/%2e%2E/v2", "https://h.example/v2"),
            ("https://h.example/v1/..", "https://h.example"),
            ("https://h.example/v1.2/x..y", "https://h.example/v1.2/x..y"),
        ] as [(String, String)])
    func dotSegments(input: String, expected: String) {
        #expect(SecretDestinations.normalizeBaseURL(input) == expected)
    }

    @Test("an empty address is nil; a move is judged against the provider's default")
    func moves() {
        #expect(SecretDestinations.normalizeBaseURL("") == nil)
        #expect(SecretDestinations.normalizeBaseURL("   ") == nil)
        #expect(SecretDestinations.normalizeBaseURL(nil) == nil)
        #expect(!SecretDestinations.moves(.openAiGpt, from: nil, to: "https://api.openai.com/v1/"))
        #expect(!SecretDestinations.moves(.openAiGpt, from: "https://API.openai.com/v1", to: ""))
        #expect(SecretDestinations.moves(.openAiGpt, from: nil, to: "https://proxy.example.com/v1"))
        #expect(SecretDestinations.moves(.azureOpenAi, from: "https://a.openai.azure.com", to: nil))
        #expect(!SecretDestinations.moves(.azureOpenAi, from: nil, to: " "))
    }

    @Test("secrets-status decodes both states; names are kept in order, once each")
    func secretsStatus() throws {
        let on = try JSONDecoder().decode(SecretsStatus.self, from: Data(#"{"encryption":"on","needsReentry":[]}"#.utf8))
        #expect(on == SecretsStatus(encryption: .on, needsReentry: []))
        let off = try JSONDecoder().decode(
            SecretsStatus.self,
            from: Data(
                #"{"encryption":"unavailable","needsReentry":["providers.openaiApiKey","mcp:github:env.GITHUB_TOKEN","providers.openaiApiKey",7]}"#
                    .utf8))
        #expect(off.encryption == .unavailable)
        #expect(off.needsReentry == ["providers.openaiApiKey", "mcp:github:env.GITHUB_TOKEN"])
        let future = try JSONDecoder().decode(SecretsStatus.self, from: Data(#"{"encryption":"hsm"}"#.utf8))
        #expect(future.encryption == .other("hsm"))
        #expect(future.needsReentry.isEmpty)
    }

    @Test("a re-entry name reads as the desktop's notice reads it; an MCP server name may hold a colon")
    func reentryNames() {
        #expect(SecretReentryName("providers.xAiApiKey") == .setting(.xAiApiKey))
        #expect(SecretReentryName.SettingSecret.xAiApiKey.provider == .xaiGrok)
        #expect(SecretReentryName.SettingSecret.braveApiKey.provider == nil)
        #expect(SecretReentryName("mcp:github:env.GITHUB_TOKEN") == .mcp(server: "github", field: "env.GITHUB_TOKEN"))
        #expect(SecretReentryName("mcp:a:b:headers.Authorization") == .mcp(server: "a:b", field: "headers.Authorization"))
        #expect(SecretReentryName("mcp:x:url") == .mcp(server: "x", field: "url"))
        #expect(SecretReentryName("mcp:x:command") == .unknown("mcp:x:command"))
        #expect(SecretReentryName("somethingNew") == .unknown("somethingNew"))
        #expect(SecretReentryName.SettingSecret.allCases.count == 12)
    }

    @Test("SECRET_REENTRY_REQUIRED carries params.field; numbers in params read as text")
    func reentryEnvelope() throws {
        let json = #"{"type":"error","error":{"code":"SECRET_REENTRY_REQUIRED","message":"The base URL differs from the saved one: re-enter the API key to use it with a new base URL","params":{"field":"apiKey","n":3},"hasCustomMessage":true}}"#
        let envelope = try JSONDecoder().decode(ServerErrorEnvelope.self, from: Data(json.utf8))
        #expect(envelope.error.params == ["field": "apiKey", "n": "3"])
        let error = HTTPError(
            statusCode: 400, code: envelope.error.code, message: envelope.error.message, params: envelope.error.params)
        #expect(error.reentryField == "apiKey")
        #expect(HTTPError(statusCode: 400, code: "VALIDATION_FAILED", message: "x", params: ["field": "apiKey"]).reentryField == nil)
    }

    @Test("keys typed here are held masked once saved; masks stay as they are")
    func maskingKeys() {
        let config = ProvidersConfig(openaiApiKey: "sk-live-1234567890abcd", anthropicApiKey: "•••• 7f3a", xAiApiKey: "short")
        let masked = config.maskingKeys()
        #expect(masked.openaiApiKey == "•••• abcd")
        #expect(masked.anthropicApiKey == "•••• 7f3a")
        #expect(masked.xAiApiKey == "••••")
        #expect(masked.googleGeminiApiKey == nil)
    }

    @Test("a providers column written with a Clear posts that key as null; other unset keys stay absent")
    func clearingWrite() throws {
        let value = ProvidersConfig(openaiBaseUrl: "https://x.example", anthropicApiKey: "•••• 7f3a")
        let body = SettingsWriteBody(
            id: "global", lastBackupAt: nil,
            columns: [SettingsColumn.providers.assigning(value, clearing: [.openAiGpt, .anthropicClaude])].map {
                ($0.name, $0.value)
            })
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        let providers = try #require(json["providers"] as? [String: Any])
        #expect(providers["openaiApiKey"] is NSNull)
        #expect(providers["anthropicApiKey"] as? String == "•••• 7f3a")
        #expect(providers.keys.contains("xAiApiKey") == false)
        #expect(providers["openaiBaseUrl"] as? String == "https://x.example")
    }
}

@Suite("Approval events")
struct ApprovalEventTests {
    @Test("approval_required and approval_resolved decode as the chat route sends them")
    func decode() throws {
        let required = try JSONDecoder().decode(
            ChatSseEvent.self,
            from: Data(
                #"{"type":"approval_required","runId":"u-1","toolCallId":"call_1","toolName":"read_file","summary":"~/.ssh/id_rsa","expiresAt":1790000000123}"#
                    .utf8))
        guard case .approvalRequired(let request) = required else {
            Issue.record("not an approval request")
            return
        }
        #expect(request.runId == "u-1")
        #expect(request.toolCallId == "call_1")
        #expect(request.toolName == "read_file")
        #expect(request.summary == "~/.ssh/id_rsa")
        #expect(abs(request.expiresAt.timeIntervalSince1970 - 1_790_000_000.123) < 0.0005)

        for (raw, outcome) in [
            ("allowed", ApprovalOutcome.allowed), ("denied", .denied), ("timed_out", .timedOut), ("stopped", .stopped),
            ("revoked", .other("revoked")),
        ] {
            let event = try JSONDecoder().decode(
                ChatSseEvent.self,
                from: Data(#"{"type":"approval_resolved","runId":"u-1","toolCallId":"call_1","outcome":"\#(raw)"}"#.utf8))
            guard case .approvalResolved(let runId, let toolCallId, let decoded) = event else {
                Issue.record("not resolved")
                return
            }
            #expect(runId == "u-1" && toolCallId == "call_1" && decoded == outcome)
        }
    }

    @Test("an approval frame missing a field fails to decode (reported as undecodable), never guessed")
    func malformed() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ChatSseEvent.self, from: Data(#"{"type":"approval_required","runId":"u-1","toolCallId":"c"}"#.utf8))
        }
    }
}
