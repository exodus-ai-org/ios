# exodus-ios Chat + Settings MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a native iPhone app (Tuist-generated, multi-module) that lists/sends/streams chats and configures one AI provider, talking directly to a running `universal-client` dev server's REST/SSE API — no local persistence, no auth.

**Architecture:** Six Tuist targets — `Models` (Codable wire types, opaque JSON passthrough for round-trip fidelity), `NetworkingKit` (hand-rolled `URLSession` REST client + SSE parser + a `ChatStreamManager` actor that survives view navigation), `ChatFeature`, `SettingsFeature`, `PhilharmonicFeature` (placeholder stub — real feature deferred), and `App` (composition root: DI, the Chat/Philharmonic workspace switcher). Feature modules never depend on each other, only on `NetworkingKit`/`Models`.

**Tech Stack:** Swift 6, SwiftUI, Swift Concurrency (`async`/`await`, actors, `AsyncStream`), Swift Testing (`import Testing`, `@Test`, `#expect`) — not XCTest. Zero third-party dependencies. Tuist 4.208.0 (already installed via `brew install --cask tuist` on this machine — verify with `tuist version`).

**Spec:** `docs/superpowers/specs/2026-09-18-chat-settings-mvp-design.md`

## Global Constraints

- iOS deployment target: **27.0** for every target (matches this machine's Xcode 27 / the SDK actually installed — resolved from the spec's open "iOS 17+" assumption; this is a personal-use app with no App Store back-compat need, so targeting current-only avoids `@available` hedging everywhere).
- Destinations: `.iOS` for every target (App included — no reason to block iPad, nothing here is iPhone-specific layout).
- Swift language mode: **6.0** for every target, set once at the project level in `Project.swift` (`settings: .settings(base: ["SWIFT_VERSION": "6.0"])`) by Task 2 Step 1. Task 1's scaffold ships Tuist's default `SWIFT_VERSION = 5`, so until Task 2 flips it the build does not enforce the strict-concurrency rules this plan's `actor` / `Sendable` / `nonisolated(unsafe)` design is written against — this makes the build enforce them instead of relying on the plan's pre-flight `-strict-concurrency=complete` check alone.
- Bundle id root: `app.yancey.exodus.exodus-ios` (carried over from the existing project). Each module target's bundle id is `app.yancey.exodus.exodus-ios.<TargetName>`.
- `DEVELOPMENT_TEAM = YLF27G9ZMT` on the App target (carried over from the existing project, needed for on-device signing later; irrelevant for Simulator runs).
- Running unit tests: Tuist 4.208.0 does **not** generate a scheme for a `.unitTests` target — there is no `-scheme ModelsTests` (`xcodebuild -list` shows only `App`, `Models`, `NetworkingKit`, `ChatFeature`, `SettingsFeature`, `PhilharmonicFeature`, `ExodusIos-Workspace`). A unit-test target is a testable of the scheme of the module it tests, so run `xcodebuild test -workspace ExodusIos.xcworkspace -scheme <Module> -destination "platform=iOS Simulator,name=iPhone 17"` (`<Module>` = `Models`, `NetworkingKit`, `ChatFeature`, or `SettingsFeature`), and scope to one suite with `-only-testing:<Module>Tests/<Suite>`. If a module's scheme turns out not to include its test target, fall back to `-scheme ExodusIos-Workspace -only-testing:<Module>Tests`. Every `xcodebuild test` command in this plan is written this way.
- Testing framework is **Swift Testing**, not XCTest: `import Testing`, `@Test func …() async throws`, `#expect(...)`, `#require(...)`. Every unit test target hosts it the same way an XCTest target would (`product: .unitTests`).
- No third-party dependencies anywhere — no `Tuist/Package.swift`, no `tuist install` needed. `tuist generate --no-open` is the only generation command required.
- JSON field names are camelCase and match `universal-client`'s TypeScript types **exactly** (`providerConfig`, `modelSnapshot`, `openaiApiKey`, `toolCallId`, …) — Swift property names mirror them 1:1 so default `Codable` synthesis needs no `CodingKeys` remapping anywhere in this plan.
- Server default: `http://localhost:60223`, stored client-side in `UserDefaults` (key `exodus.serverURL`), never hardcoded into a request builder.
- `ChatMessage` (Models) decodes into an **opaque `[String: JSONValue]` passthrough**, not a narrow struct — required so previously-unmodeled fields (`details`, `toolCallId`, `usage`, `cost`, …) round-trip unmodified when a prior turn's messages are echoed back inside the next `POST /api/chat` body (see the spec §3 and `schemas/chat.ts`'s `messageSchema` comment on the desktop side — this is not a Swift-side invention, it mirrors a documented server requirement).
- Every task's Swift code in this plan has been verified to compile with the actual toolchain on this machine (`xcrun swift -strict-concurrency=complete <file>.swift`) before being written down — the core Models/NetworkingKit design (JSONValue, ChatMessage, ChatSseEvent, the `.lines` AsyncSequence-based SSE line splitting, the `ChatStreamManager` actor pattern with `AsyncStream.makeStream()`) is proven, not speculative.

---

## Task 1: Tuist scaffold — replace the plain Xcode project, boot an empty app

**Files:**
- Delete: `exodus-ios.xcodeproj/`, `exodus-ios/` (the old template's `ContentView.swift`, `exodus_iosApp.swift`, `Item.swift` — keep `Assets.xcassets`, moved), `exodus-iosTests/`, `exodus-iosUITests/`
- Create: `Tuist.swift`
- Create: `Project.swift`
- Create: `Sources/App/ExodusApp.swift`
- Create: `Sources/App/RootView.swift` (placeholder body for this task — replaced for real in Task 10)
- Create: `Sources/Models/.gitkeep` equivalent — actually a real placeholder: `Sources/Models/Placeholder.swift`
- Create: `Sources/NetworkingKit/Placeholder.swift`
- Create: `Sources/ChatFeature/Placeholder.swift`
- Create: `Sources/SettingsFeature/Placeholder.swift`
- Create: `Sources/PhilharmonicFeature/PhilharmonicPlaceholderView.swift` (this one is real, reused as-is through Task 10)
- Move: `exodus-ios/Assets.xcassets` → `Resources/App/Assets.xcassets`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a buildable, runnable `ExodusIos.xcworkspace` with 6 empty-but-linked targets (`App`, `Models`, `NetworkingKit`, `ChatFeature`, `SettingsFeature`, `PhilharmonicFeature`). Every later task adds real content to these same targets/folders — none of the paths above change shape again.

- [ ] **Step 1: Confirm Tuist is installed**

Run: `tuist version`
Expected: prints a version (e.g. `4.208.0`). If missing, install with `brew install --cask tuist`.

- [ ] **Step 2: Capture the old project's signing identity, then remove it**

The existing template already has real values worth keeping (bundle id `app.yancey.exodus.exodus-ios`, team `YLF27G9ZMT`) — already captured above as Global Constraints, so nothing to extract at runtime. Remove the old Xcode-managed project:

```bash
git rm -r exodus-ios.xcodeproj exodus-iosTests exodus-iosUITests
mkdir -p /tmp/exodus-ios-assets-migration
cp -R exodus-ios/Assets.xcassets /tmp/exodus-ios-assets-migration/
git rm -r exodus-ios
mkdir -p Resources/App
cp -R /tmp/exodus-ios-assets-migration/Assets.xcassets Resources/App/Assets.xcassets
rm -rf /tmp/exodus-ios-assets-migration
```

- [ ] **Step 3: Create `Tuist.swift`**

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist()
)
```

- [ ] **Step 4: Create placeholder source files for every module**

`Sources/Models/Placeholder.swift`:

```swift
// Replaced with real Codable types in Task 2/3.
enum ModelsPlaceholder {}
```

`Sources/NetworkingKit/Placeholder.swift`:

```swift
// Replaced with APIClient/SSEClient/ChatStreamManager in Task 4/5/6.
enum NetworkingKitPlaceholder {}
```

`Sources/ChatFeature/Placeholder.swift`:

```swift
// Replaced with ChatListView/ChatDetailView in Task 8/9.
enum ChatFeaturePlaceholder {}
```

`Sources/SettingsFeature/Placeholder.swift`:

```swift
// Replaced with SettingsView in Task 7.
enum SettingsFeaturePlaceholder {}
```

`Sources/PhilharmonicFeature/PhilharmonicPlaceholderView.swift` (this is the real, final content for this module in this phase — see spec §7):

```swift
import SwiftUI

public struct PhilharmonicPlaceholderView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("即将支持")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Philharmonic 多智能体工作区还没有移植到 iOS。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Create `Sources/App/ExodusApp.swift` and `Sources/App/RootView.swift`**

`Sources/App/RootView.swift` (throwaway body — Task 10 replaces this with the real workspace switcher):

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("Exodus")
    }
}

#Preview {
    RootView()
}
```

`Sources/App/ExodusApp.swift`:

```swift
import SwiftUI

@main
struct ExodusApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

- [ ] **Step 6: Write `Project.swift`**

```swift
import ProjectDescription

private let bundleIdRoot = "app.yancey.exodus.exodus-ios"
private let developmentTeam = "YLF27G9ZMT"
private let deploymentTargets = DeploymentTargets.iOS("27.0")

private func moduleTarget(
    name: String,
    dependencies: [TargetDependency] = []
) -> Target {
    .target(
        name: name,
        destinations: .iOS,
        product: .staticFramework,
        bundleId: "\(bundleIdRoot).\(name)",
        deploymentTargets: deploymentTargets,
        buildableFolders: ["Sources/\(name)"],
        dependencies: dependencies
    )
}

let project = Project(
    name: "ExodusIos",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            productName: "Exodus",
            bundleId: bundleIdRoot,
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [:],
                    "NSAppTransportSecurity": [
                        "NSAllowsLocalNetworking": true
                    ],
                    "NSLocalNetworkUsageDescription":
                        "Exodus 需要访问本地网络以连接到你电脑上运行的 Exodus 服务。"
                ]
            ),
            buildableFolders: ["Sources/App", "Resources/App"],
            dependencies: [
                .target(name: "ChatFeature"),
                .target(name: "SettingsFeature"),
                .target(name: "PhilharmonicFeature"),
                .target(name: "NetworkingKit")
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": .string(developmentTeam),
                    "CODE_SIGN_STYLE": "Automatic"
                ]
            )
        ),
        moduleTarget(name: "Models"),
        moduleTarget(name: "NetworkingKit", dependencies: [.target(name: "Models")]),
        moduleTarget(
            name: "ChatFeature",
            dependencies: [.target(name: "NetworkingKit"), .target(name: "Models")]
        ),
        moduleTarget(
            name: "SettingsFeature",
            dependencies: [.target(name: "NetworkingKit"), .target(name: "Models")]
        ),
        moduleTarget(name: "PhilharmonicFeature", dependencies: [.target(name: "Models")])
    ]
)
```

- [ ] **Step 7: Generate and build**

```bash
tuist generate --no-open
xcodebuild build \
  -workspace ExodusIos.xcworkspace \
  -scheme App \
  -destination "generic/platform=iOS Simulator"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Boot the Simulator and confirm the app launches**

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcodebuild build \
  -workspace ExodusIos.xcworkspace \
  -scheme App \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath /tmp/exodus-ios-dd
xcrun simctl install booted /tmp/exodus-ios-dd/Build/Products/Debug-iphonesimulator/Exodus.app
xcrun simctl launch booted app.yancey.exodus.exodus-ios
```

Expected: the Simulator shows the app running with the text "Exodus" on screen (no crash).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Scaffold Tuist project with the Chat/Settings/Philharmonic module graph

Replaces the default Xcode/SwiftData template with a Tuist-generated
multi-target project: App composition root plus Models, NetworkingKit,
ChatFeature, SettingsFeature, and a PhilharmonicFeature placeholder,
matching the architecture in docs/superpowers/specs/2026-09-18-chat-settings-mvp-design.md.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Models — JSONValue, ChatMessage, ChatSseEvent

**Files:**
- Create: `Sources/Models/JSONValue.swift`
- Create: `Sources/Models/ChatMessage.swift`
- Create: `Sources/Models/ChatSseEvent.swift`
- Create: `Tests/ModelsTests/ChatMessageTests.swift`
- Create: `Tests/ModelsTests/ChatSseEventTests.swift`
- Delete: `Sources/Models/Placeholder.swift`
- Modify: `Project.swift` — set project-level Swift 6 language mode, and add `ModelsTests` target

**Interfaces:**
- Consumes: nothing new.
- Produces (used by NetworkingKit/ChatFeature in later tasks):
  - `enum JSONValue: Codable, Equatable, Sendable` with cases `.string(String) .number(Double) .bool(Bool) .object([String: JSONValue]) .array([JSONValue]) .null`, plus `var stringValue: String?`, `var boolValue: Bool?`, `var numberValue: Double?`, `func extractPlainText() -> String`.
  - `struct ChatMessage: Codable, Equatable, Sendable, Identifiable` with `var id: String`, `var role: String`, `var raw: [String: JSONValue]`, `init(id:role:raw:)`, computed `var content: JSONValue`, `var displayText: String`, `var isError: Bool`, `var toolName: String?`, and `static func userMessage(id: String, text: String, timestampMs: Double) -> ChatMessage`.
  - `enum ChatSseEvent: Decodable, Sendable` with cases `.messageUpdate(ChatMessage) .toolCallStart(toolCallId: String, toolName: String) .toolCallEnd(toolCallId: String, toolName: String, isError: Bool) .done(messages: [ChatMessage]) .title(String) .error(String) .notice(level: String, message: String) .unknown(type: String)`.

- [ ] **Step 1: Opt the project into Swift 6 language mode, and add the `ModelsTests` target to `Project.swift`**

First, the Swift 6 setting (see Global Constraints). Add one line to the `Project(...)` initializer, between `name: "ExodusIos",` and `targets: [`:

```swift
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
```

It is project-level, so every target — including every test target later tasks append — inherits it; no later task touches it again. (Checked against Tuist 4.208.0: after `tuist generate --no-open`, `xcodebuild -showBuildSettings -project ExodusIos.xcodeproj -target Models` resolves `SWIFT_VERSION = 6.0`, and the Task 1 scaffold still builds clean under it. If any of this task's own code raises a Swift 6 diagnostic the plan's snippet missed, fix the code — do not lower the setting.)

Then add this element to the `targets:` array, right after the `moduleTarget(name: "Models")` line:

```swift
        .target(
            name: "ModelsTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).ModelsTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/ModelsTests"],
            dependencies: [.target(name: "Models")]
        ),
```

Run: `tuist generate --no-open`
Expected: generation succeeds (the `Tests/ModelsTests` folder doesn't exist yet — create an empty `Tests/ModelsTests/.gitkeep` first if `tuist generate` complains about a missing buildable folder; otherwise proceed straight to Step 2, which populates it).

- [ ] **Step 2: Write the failing tests**

`Tests/ModelsTests/ChatMessageTests.swift`:

```swift
import Foundation
import Testing

@testable import Models

@Suite("ChatMessage")
struct ChatMessageTests {
    @Test("decodes a plain string user message")
    func decodesUserMessage() throws {
        let json = """
            {"id":"11111111-1111-4111-8111-111111111111","role":"user","content":"hi there","timestamp":1700000000000}
            """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(message.id == "11111111-1111-4111-8111-111111111111")
        #expect(message.role == "user")
        #expect(message.displayText == "hi there")
        #expect(message.timestampMs == 1_700_000_000_000)
    }

    @Test("extracts text from an assistant content block array, ignoring unknown block types")
    func decodesAssistantMessage() throws {
        let json = """
            {"id":"a","role":"assistant","content":[{"type":"text","text":"hello"},{"type":"toolCall","id":"t1","name":"web_search"}],"usage":{"input":1},"stopReason":"stop"}
            """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(message.displayText == "hello")
    }

    @Test("round-trips fields this struct never modeled, unmodified")
    func roundTripsUnknownFields() throws {
        let json = """
            {"id":"a","role":"assistant","content":"x","usage":{"input":1},"stopReason":"stop"}
            """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        let reEncoded = try JSONEncoder().encode(message)
        let reDecoded = try JSONDecoder().decode(ChatMessage.self, from: reEncoded)
        #expect(reDecoded.raw["usage"] != nil)
        #expect(reDecoded.raw["stopReason"]?.stringValue == "stop")
    }

    @Test("toolResult message exposes isError and toolName")
    func decodesToolResultMessage() throws {
        let json = """
            {"id":"tr1","role":"toolResult","toolCallId":"tc1","toolName":"web_search","content":[{"type":"text","text":"3 results"}],"details":{"count":3},"isError":false,"timestamp":1700000000000}
            """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(message.role == "toolResult")
        #expect(message.toolName == "web_search")
        #expect(message.isError == false)
    }

    @Test("userMessage(id:text:timestampMs:) builds a message the server will accept")
    func buildsOutgoingUserMessage() throws {
        let message = ChatMessage.userMessage(id: "u1", text: "hello", timestampMs: 1_700_000_000_000)
        #expect(message.role == "user")
        #expect(message.displayText == "hello")
        let data = try JSONEncoder().encode(message)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["id"] as? String == "u1")
        #expect(obj?["content"] as? String == "hello")
    }
}
```

`Tests/ModelsTests/ChatSseEventTests.swift`:

```swift
import Foundation
import Testing

@testable import Models

@Suite("ChatSseEvent")
struct ChatSseEventTests {
    @Test("decodes tool_call_start")
    func decodesToolCallStart() throws {
        let json = """
            {"type":"tool_call_start","toolCallId":"tc1","toolName":"web_search"}
            """.data(using: .utf8)!
        let event = try JSONDecoder().decode(ChatSseEvent.self, from: json)
        guard case .toolCallStart(let toolCallId, let toolName) = event else {
            Issue.record("expected .toolCallStart, got \(event)")
            return
        }
        #expect(toolCallId == "tc1")
        #expect(toolName == "web_search")
    }

    @Test("decodes done with a message array")
    func decodesDone() throws {
        let json = """
            {"type":"done","messages":[{"id":"a","role":"assistant","content":"hi"}]}
            """.data(using: .utf8)!
        let event = try JSONDecoder().decode(ChatSseEvent.self, from: json)
        guard case .done(let messages) = event else {
            Issue.record("expected .done, got \(event)")
            return
        }
        #expect(messages.count == 1)
        #expect(messages[0].displayText == "hi")
    }

    @Test("an unrecognized type decodes to .unknown instead of throwing")
    func unrecognizedTypeIsUnknown() throws {
        let json = """
            {"type":"some_future_event","foo":"bar"}
            """.data(using: .utf8)!
        let event = try JSONDecoder().decode(ChatSseEvent.self, from: json)
        guard case .unknown(let type) = event else {
            Issue.record("expected .unknown, got \(event)")
            return
        }
        #expect(type == "some_future_event")
    }
}
```

- [ ] **Step 3: Run the tests and confirm they fail (types don't exist yet)**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: build failure — `Cannot find type 'ChatMessage' in scope` (and similar for `ChatSseEvent`).

- [ ] **Step 4: Implement `JSONValue.swift`**

```swift
import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .number(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    /// Best-effort plain-text extraction from a pi-ai message `content` value:
    /// a bare string, or an array of blocks where `{type:"text"|"thinking", text|thinking}`
    /// blocks contribute text and every other block type (image, toolCall, …) is skipped.
    public func extractPlainText() -> String {
        switch self {
        case .string(let s):
            return s
        case .array(let items):
            return
                items
                .compactMap { item -> String? in
                    guard case .object(let obj) = item,
                        case .string(let type)? = obj["type"]
                    else { return nil }
                    if type == "text", case .string(let t)? = obj["text"] { return t }
                    if type == "thinking", case .string(let t)? = obj["thinking"] { return t }
                    return nil
                }
                .joined(separator: "\n")
        default:
            return ""
        }
    }
}
```

- [ ] **Step 5: Implement `ChatMessage.swift`**

```swift
import Foundation

/// A chat message as sent by the server. Decodes into a raw `[String: JSONValue]`
/// dictionary rather than a narrow struct — the server's own schema comment
/// (`messageSchema` in `schemas/chat.ts`) explains why: prior turns carry
/// provider-specific fields (`details`, `toolCallId`, `toolName`, `isError`, `usage`,
/// `cost`, …) that must round-trip unmodified when this message is echoed back
/// inside the next `POST /api/chat` request body, or the server loses tool-call
/// pairing information it needs to talk to the LLM provider.
public struct ChatMessage: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var role: String
    public var raw: [String: JSONValue]

    public init(id: String, role: String, raw: [String: JSONValue]) {
        self.id = id
        self.role = role
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: JSONValue].self)
        guard case .string(let id)? = object["id"] else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "ChatMessage missing string 'id'")
        }
        guard case .string(let role)? = object["role"] else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "ChatMessage missing string 'role'")
        }
        self.id = id
        self.role = role
        self.raw = object
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public var content: JSONValue { raw["content"] ?? .null }
    public var displayText: String { content.extractPlainText() }
    public var isError: Bool { raw["isError"]?.boolValue ?? false }
    public var toolName: String? { raw["toolName"]?.stringValue }
    public var timestampMs: Double? { raw["timestamp"]?.numberValue }

    /// Builds a freshly-composed outgoing user message — the shape the composer
    /// hands to `ChatStreamManager.send`. Every other `ChatMessage` in a
    /// conversation was decoded from the server and must never be constructed
    /// this way (it would drop fields the server needs on round-trip).
    public static func userMessage(id: String, text: String, timestampMs: Double) -> ChatMessage {
        ChatMessage(
            id: id,
            role: "user",
            raw: [
                "id": .string(id),
                "role": .string("user"),
                "content": .string(text),
                "timestamp": .number(timestampMs)
            ]
        )
    }
}
```

- [ ] **Step 6: Implement `ChatSseEvent.swift`**

```swift
import Foundation

public enum ChatSseEvent: Sendable {
    case messageUpdate(ChatMessage)
    case toolCallStart(toolCallId: String, toolName: String)
    case toolCallEnd(toolCallId: String, toolName: String, isError: Bool)
    case done(messages: [ChatMessage])
    case title(String)
    case error(String)
    case notice(level: String, message: String)
    /// Forward-compat: an SSE frame whose `type` this client doesn't recognize
    /// yet. Consumers ignore it instead of the whole stream failing.
    case unknown(type: String)
}

extension ChatSseEvent: Decodable {
    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type = try typeContainer.decode(String.self, forKey: .type)

        struct MessagePayload: Decodable { let message: ChatMessage }
        struct ToolCallStartPayload: Decodable { let toolCallId: String; let toolName: String }
        struct ToolCallEndPayload: Decodable {
            let toolCallId: String
            let toolName: String
            let isError: Bool
        }
        struct DonePayload: Decodable { let messages: [ChatMessage] }
        struct TitlePayload: Decodable { let title: String }
        struct ErrorPayload: Decodable { let error: String }
        struct NoticePayload: Decodable { let level: String; let message: String }

        let single = try decoder.singleValueContainer()
        switch type {
        case "message_update":
            self = .messageUpdate(try single.decode(MessagePayload.self).message)
        case "tool_call_start":
            let p = try single.decode(ToolCallStartPayload.self)
            self = .toolCallStart(toolCallId: p.toolCallId, toolName: p.toolName)
        case "tool_call_end":
            let p = try single.decode(ToolCallEndPayload.self)
            self = .toolCallEnd(toolCallId: p.toolCallId, toolName: p.toolName, isError: p.isError)
        case "done":
            self = .done(messages: try single.decode(DonePayload.self).messages)
        case "title":
            self = .title(try single.decode(TitlePayload.self).title)
        case "error":
            self = .error(try single.decode(ErrorPayload.self).error)
        case "notice":
            let p = try single.decode(NoticePayload.self)
            self = .notice(level: p.level, message: p.message)
        default:
            self = .unknown(type: type)
        }
    }
}
```

- [ ] **Step 7: Delete the Models placeholder, run the tests, confirm they pass**

```bash
rm Sources/Models/Placeholder.swift
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "platform=iOS Simulator,name=iPhone 17"
```

Expected: `** TEST SUCCEEDED **`, all 8 tests pass.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Add ChatMessage/ChatSseEvent Models with opaque JSON round-trip

ChatMessage decodes into a raw [String: JSONValue] dictionary instead
of a narrow struct so fields this client doesn't model (details,
toolCallId, usage, cost, ...) survive being echoed back in the next
chat turn, matching the server's own looseObject contract.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Models — Settings/error/history wire types

**Files:**
- Create: `Sources/Models/AiProviders.swift`
- Create: `Sources/Models/Settings.swift`
- Create: `Sources/Models/HTTPError.swift`
- Create: `Sources/Models/ChatSummary.swift`
- Create: `Tests/ModelsTests/SettingsTests.swift`
- Create: `Tests/ModelsTests/HTTPErrorTests.swift`
- Create: `Tests/ModelsTests/ChatSummaryTests.swift`

**Interfaces:**
- Consumes: `JSONValue` (Task 2).
- Produces (used by NetworkingKit/SettingsFeature/ChatFeature):
  - `enum AiProviders: String, Codable, CaseIterable, Sendable, Identifiable` (`id` = `rawValue`, so `ForEach(AiProviders.allCases)` needs no explicit `id:`) — cases `openAiGpt = "OpenAI GPT"`, `azureOpenAi = "Azure OpenAI"`, `anthropicClaude = "Anthropic Claude"`, `googleGemini = "Google Gemini"`, `xaiGrok = "xAI Grok"`, `ollama = "Ollama"`.
  - `struct ModelCost: Codable, Equatable, Sendable { var input: Double; var output: Double }`
  - `struct ModelSnapshot: Codable, Equatable, Sendable { var contextWindow: Double?; var maxOutputTokens: Double?; var reasoningLevels: [String]; var cost: ModelCost? }`
  - `struct ProviderConfig: Codable, Equatable, Sendable { var provider: String?; var model: String?; var modelSnapshot: ModelSnapshot? }`
  - `struct ProvidersConfig: Codable, Equatable, Sendable` with the 12 optional `String?` fields matching `ProvidersSchema` exactly (`openaiApiKey`, `openaiBaseUrl`, `azureOpenaiApiKey`, `azureOpenAiEndpoint`, `azureOpenAiApiVersion`, `anthropicApiKey`, `anthropicBaseUrl`, `googleGeminiApiKey`, `googleGeminiBaseUrl`, `xAiApiKey`, `xAiBaseUrl`, `ollamaBaseUrl`), plus `func apiKey(for provider: AiProviders) -> String?` and `func settingApiKey(_ key: String?, for provider: AiProviders) -> ProvidersConfig`.
  - `struct CachedModelEntry: Codable, Equatable, Sendable, Identifiable { var id: String; var displayName: String; var snapshot: ModelSnapshot }`
  - `struct SettingsSnapshot: Decodable, Sendable { var id: String; var providerConfig: ProviderConfig?; var providers: ProvidersConfig?; var lastBackupAt: String? }` — decodes `GET /api/settings`, ignoring every other field. (`lastBackupAt` is carried only so it can be echoed back — see `SettingsPatch`.)
  - `struct SettingsPatch: Encodable, Sendable { var id: String; var providerConfig: ProviderConfig?; var providers: ProvidersConfig?; var lastBackupAt: String? }` — the outgoing `POST /api/settings` body. `lastBackupAt` must be echoed back from the loaded `SettingsSnapshot`: the server's `updateSettings()` (`src/main/lib/db/queries.ts`) writes `lastBackupAt` unconditionally (`lastBackupAt ? new Date(lastBackupAt) : null`), so a body without it would null the desktop's "last backup" timestamp on every save. Every other top-level key absent from the body is untouched.
  - `struct ListModelsRequest: Encodable, Sendable { var provider: String; var apiKey: String?; var baseUrl: String?; var apiVersion: String? }`
  - `struct ListModelsResponse: Decodable, Sendable { var models: [CachedModelEntry] }`
  - `struct HTTPError: Error, Equatable, Sendable, LocalizedError { var statusCode: Int; var code: String; var message: String }` with `var errorDescription: String? { message }`.
  - `struct ServerErrorEnvelope: Decodable, Sendable` matching `{ type, error: { code, message } }`.
  - `struct ChatSummary: Codable, Equatable, Sendable, Identifiable { var id: String; var title: String; var createdAt: String; var favorite: Bool?; var projectId: String? }` — matches the `chat` Drizzle table (`src/main/lib/db/schema.ts`), **not** `updatedAt` (that column doesn't exist; the server sorts by `createdAt` DESC).

- [ ] **Step 1: Write the failing tests**

`Tests/ModelsTests/SettingsTests.swift`:

```swift
import Foundation
import Testing

@testable import Models

@Suite("Settings wire types")
struct SettingsTests {
    @Test("AiProviders raw values match the server's enum strings exactly")
    func providerRawValues() {
        #expect(AiProviders.openAiGpt.rawValue == "OpenAI GPT")
        #expect(AiProviders.azureOpenAi.rawValue == "Azure OpenAI")
        #expect(AiProviders.anthropicClaude.rawValue == "Anthropic Claude")
        #expect(AiProviders.googleGemini.rawValue == "Google Gemini")
        #expect(AiProviders.xaiGrok.rawValue == "xAI Grok")
        #expect(AiProviders.ollama.rawValue == "Ollama")
    }

    @Test("decodes GET /api/settings, ignoring fields this client doesn't model")
    func decodesSettingsSnapshot() throws {
        let json = """
            {
              "id": "global",
              "providerConfig": {"provider": "Anthropic Claude", "model": "claude-sonnet-5"},
              "providers": {"anthropicApiKey": "sk-ant-xyz"},
              "lastBackupAt": "2026-09-18T12:00:00.000Z",
              "personality": {"baseStyle": "default"},
              "memory": {"autoCapture": true}
            }
            """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: json)
        #expect(snapshot.id == "global")
        #expect(snapshot.providerConfig?.provider == "Anthropic Claude")
        #expect(snapshot.providers?.anthropicApiKey == "sk-ant-xyz")
        #expect(snapshot.lastBackupAt == "2026-09-18T12:00:00.000Z")
    }

    @Test("a null lastBackupAt (never backed up) decodes to nil")
    func decodesNullLastBackupAt() throws {
        let json = #"{"id":"global","lastBackupAt":null}"#.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: json)
        #expect(snapshot.lastBackupAt == nil)
    }

    @Test("SettingsPatch encodes id/providerConfig/providers, and lastBackupAt only when set")
    func encodesSettingsPatch() throws {
        let patch = SettingsPatch(
            id: "global",
            providerConfig: ProviderConfig(provider: "Anthropic Claude", model: "claude-sonnet-5", modelSnapshot: nil),
            providers: ProvidersConfig().settingApiKey("sk-ant-xyz", for: .anthropicClaude)
        )
        let data = try JSONEncoder().encode(patch)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["id"] as? String == "global")
        let providerConfig = obj?["providerConfig"] as? [String: Any]
        #expect(providerConfig?["provider"] as? String == "Anthropic Claude")
        let providers = obj?["providers"] as? [String: Any]
        #expect(providers?["anthropicApiKey"] as? String == "sk-ant-xyz")
        #expect(obj?.keys.contains("lastBackupAt") == false)
    }

    @Test("SettingsPatch echoes lastBackupAt so the server's unconditional write doesn't null it")
    func settingsPatchEchoesLastBackupAt() throws {
        let patch = SettingsPatch(
            id: "global", providerConfig: nil, providers: nil, lastBackupAt: "2026-09-18T12:00:00.000Z")
        let data = try JSONEncoder().encode(patch)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["lastBackupAt"] as? String == "2026-09-18T12:00:00.000Z")
    }

    @Test("ProvidersConfig.apiKey(for:) and settingApiKey(_:for:) round-trip every provider")
    func providersConfigAccessors() {
        // Every provider except Ollama has a settable API key field (Ollama has
        // no `ollamaApiKey` in ProvidersSchema — it runs unauthenticated
        // locally, only `ollamaBaseUrl` exists).
        for provider in AiProviders.allCases where provider != .ollama {
            let updated = ProvidersConfig().settingApiKey("k-\(provider.rawValue)", for: provider)
            #expect(updated.apiKey(for: provider) == "k-\(provider.rawValue)")
        }
    }

    @Test("Ollama has no API key field by design — set/get are both no-ops")
    func ollamaHasNoApiKey() {
        let updated = ProvidersConfig().settingApiKey("k-Ollama", for: .ollama)
        #expect(updated.apiKey(for: .ollama) == nil)
        #expect(updated == ProvidersConfig())
    }

    @Test("decodes a live model catalog response")
    func decodesListModelsResponse() throws {
        let json = """
            {"models":[{"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"contextWindow":200000,"maxOutputTokens":8192,"reasoningLevels":["off","low"],"cost":{"input":3,"output":15}}}]}
            """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ListModelsResponse.self, from: json)
        #expect(response.models.count == 1)
        #expect(response.models[0].id == "claude-sonnet-5")
        #expect(response.models[0].snapshot.reasoningLevels == ["off", "low"])
    }
}
```

`Tests/ModelsTests/HTTPErrorTests.swift`:

```swift
import Foundation
import Testing

@testable import Models

@Suite("HTTPError")
struct HTTPErrorTests {
    @Test("decodes the Anthropic-style error envelope")
    func decodesErrorEnvelope() throws {
        let json = """
            {"type":"error","error":{"code":"VALIDATION_FAILED","message":"API key is required"}}
            """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(ServerErrorEnvelope.self, from: json)
        #expect(envelope.error.code == "VALIDATION_FAILED")
        #expect(envelope.error.message == "API key is required")
    }

    @Test("errorDescription surfaces the message for SwiftUI error alerts")
    func errorDescription() {
        let error = HTTPError(statusCode: 400, code: "VALIDATION_FAILED", message: "API key is required")
        #expect(error.errorDescription == "API key is required")
    }
}
```

`Tests/ModelsTests/ChatSummaryTests.swift`:

```swift
import Foundation
import Testing

@testable import Models

@Suite("ChatSummary")
struct ChatSummaryTests {
    @Test("decodes a chat row from GET /api/history")
    func decodesChatSummary() throws {
        let json = """
            {"id":"c1","createdAt":"2026-09-18T12:34:56.789Z","title":"Trip planning","favorite":false,"projectId":null,"useProjectInstructions":true}
            """.data(using: .utf8)!
        let chat = try JSONDecoder().decode(ChatSummary.self, from: json)
        #expect(chat.id == "c1")
        #expect(chat.title == "Trip planning")
        #expect(chat.createdAt == "2026-09-18T12:34:56.789Z")
        #expect(chat.favorite == false)
        #expect(chat.projectId == nil)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "platform=iOS Simulator,name=iPhone 17" -only-testing ModelsTests/SettingsTests -only-testing ModelsTests/HTTPErrorTests -only-testing ModelsTests/ChatSummaryTests`
Expected: build failure — the new types don't exist yet.

- [ ] **Step 3: Implement `AiProviders.swift`**

```swift
public enum AiProviders: String, Codable, CaseIterable, Sendable, Identifiable {
    case openAiGpt = "OpenAI GPT"
    case azureOpenAi = "Azure OpenAI"
    case anthropicClaude = "Anthropic Claude"
    case googleGemini = "Google Gemini"
    case xaiGrok = "xAI Grok"
    case ollama = "Ollama"

    public var id: String { rawValue }
}
```

- [ ] **Step 4: Implement `Settings.swift`**

```swift
import Foundation

public struct ModelCost: Codable, Equatable, Sendable {
    public var input: Double
    public var output: Double

    public init(input: Double, output: Double) {
        self.input = input
        self.output = output
    }
}

public struct ModelSnapshot: Codable, Equatable, Sendable {
    public var contextWindow: Double?
    public var maxOutputTokens: Double?
    public var reasoningLevels: [String]
    public var cost: ModelCost?

    public init(
        contextWindow: Double? = nil,
        maxOutputTokens: Double? = nil,
        reasoningLevels: [String] = [],
        cost: ModelCost? = nil
    ) {
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.reasoningLevels = reasoningLevels
        self.cost = cost
    }
}

public struct ProviderConfig: Codable, Equatable, Sendable {
    public var provider: String?
    public var model: String?
    public var modelSnapshot: ModelSnapshot?

    public init(provider: String? = nil, model: String? = nil, modelSnapshot: ModelSnapshot? = nil) {
        self.provider = provider
        self.model = model
        self.modelSnapshot = modelSnapshot
    }
}

public struct ProvidersConfig: Codable, Equatable, Sendable {
    public var openaiApiKey: String?
    public var openaiBaseUrl: String?
    public var azureOpenaiApiKey: String?
    public var azureOpenAiEndpoint: String?
    public var azureOpenAiApiVersion: String?
    public var anthropicApiKey: String?
    public var anthropicBaseUrl: String?
    public var googleGeminiApiKey: String?
    public var googleGeminiBaseUrl: String?
    public var xAiApiKey: String?
    public var xAiBaseUrl: String?
    public var ollamaBaseUrl: String?

    public init(
        openaiApiKey: String? = nil,
        openaiBaseUrl: String? = nil,
        azureOpenaiApiKey: String? = nil,
        azureOpenAiEndpoint: String? = nil,
        azureOpenAiApiVersion: String? = nil,
        anthropicApiKey: String? = nil,
        anthropicBaseUrl: String? = nil,
        googleGeminiApiKey: String? = nil,
        googleGeminiBaseUrl: String? = nil,
        xAiApiKey: String? = nil,
        xAiBaseUrl: String? = nil,
        ollamaBaseUrl: String? = nil
    ) {
        self.openaiApiKey = openaiApiKey
        self.openaiBaseUrl = openaiBaseUrl
        self.azureOpenaiApiKey = azureOpenaiApiKey
        self.azureOpenAiEndpoint = azureOpenAiEndpoint
        self.azureOpenAiApiVersion = azureOpenAiApiVersion
        self.anthropicApiKey = anthropicApiKey
        self.anthropicBaseUrl = anthropicBaseUrl
        self.googleGeminiApiKey = googleGeminiApiKey
        self.googleGeminiBaseUrl = googleGeminiBaseUrl
        self.xAiApiKey = xAiApiKey
        self.xAiBaseUrl = xAiBaseUrl
        self.ollamaBaseUrl = ollamaBaseUrl
    }

    public func apiKey(for provider: AiProviders) -> String? {
        switch provider {
        case .openAiGpt: return openaiApiKey
        case .azureOpenAi: return azureOpenaiApiKey
        case .anthropicClaude: return anthropicApiKey
        case .googleGemini: return googleGeminiApiKey
        case .xaiGrok: return xAiApiKey
        case .ollama: return nil
        }
    }

    public func settingApiKey(_ key: String?, for provider: AiProviders) -> ProvidersConfig {
        var copy = self
        switch provider {
        case .openAiGpt: copy.openaiApiKey = key
        case .azureOpenAi: copy.azureOpenaiApiKey = key
        case .anthropicClaude: copy.anthropicApiKey = key
        case .googleGemini: copy.googleGeminiApiKey = key
        case .xaiGrok: copy.xAiApiKey = key
        case .ollama: break
        }
        return copy
    }
}

public struct CachedModelEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var snapshot: ModelSnapshot

    public init(id: String, displayName: String, snapshot: ModelSnapshot) {
        self.id = id
        self.displayName = displayName
        self.snapshot = snapshot
    }
}

public struct SettingsSnapshot: Decodable, Sendable {
    public var id: String
    public var providerConfig: ProviderConfig?
    public var providers: ProvidersConfig?
    /// ISO-8601 string (or nil = never backed up). Carried only so `SettingsPatch` can echo it.
    public var lastBackupAt: String?
}

public struct SettingsPatch: Encodable, Sendable {
    public var id: String
    public var providerConfig: ProviderConfig?
    public var providers: ProvidersConfig?
    /// The server writes `lastBackupAt` unconditionally on every `POST /api/settings`
    /// (`lastBackupAt ? new Date(lastBackupAt) : null`), so the value read from the
    /// `SettingsSnapshot` must be sent back or the desktop's "last backup" is nulled.
    public var lastBackupAt: String?

    public init(id: String, providerConfig: ProviderConfig?, providers: ProvidersConfig?, lastBackupAt: String? = nil) {
        self.id = id
        self.providerConfig = providerConfig
        self.providers = providers
        self.lastBackupAt = lastBackupAt
    }
}

public struct ListModelsRequest: Encodable, Sendable {
    public var provider: String
    public var apiKey: String?
    public var baseUrl: String?
    public var apiVersion: String?

    public init(provider: String, apiKey: String?, baseUrl: String?, apiVersion: String?) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.apiVersion = apiVersion
    }
}

public struct ListModelsResponse: Decodable, Sendable {
    public var models: [CachedModelEntry]
}
```

- [ ] **Step 5: Implement `HTTPError.swift`**

```swift
import Foundation

public struct HTTPError: Error, Equatable, Sendable, LocalizedError {
    public var statusCode: Int
    public var code: String
    public var message: String

    public init(statusCode: Int, code: String, message: String) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct ServerErrorEnvelope: Decodable, Sendable {
    public struct ErrorBody: Decodable, Sendable {
        public var code: String
        public var message: String
    }

    public var type: String
    public var error: ErrorBody
}
```

- [ ] **Step 6: Implement `ChatSummary.swift`**

```swift
public struct ChatSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var createdAt: String
    public var favorite: Bool?
    public var projectId: String?

    public init(id: String, title: String, createdAt: String, favorite: Bool? = nil, projectId: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.favorite = favorite
        self.projectId = projectId
    }
}
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: `** TEST SUCCEEDED **`, all tests pass (Task 2's tests plus this task's).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Add Settings/error/history wire types to Models

AiProviders, ProviderConfig, ProvidersConfig, CachedModelEntry, the
GET /api/settings and POST /api/settings/models shapes, the
Anthropic-style error envelope, and ChatSummary for GET /api/history.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: NetworkingKit — ServerConfigStore + APIClient (REST)

**Files:**
- Create: `Sources/NetworkingKit/ServerConfigStore.swift`
- Create: `Sources/NetworkingKit/APIClient.swift`
- Create: `Tests/NetworkingKitTests/MockURLProtocol.swift`
- Create: `Tests/NetworkingKitTests/APIClientTests.swift`
- Delete: `Sources/NetworkingKit/Placeholder.swift`
- Modify: `Project.swift` — add `NetworkingKitTests` target

**Interfaces:**
- Consumes: `Models` (`HTTPError`, `ServerErrorEnvelope`, and every request/response type used in tests).
- Produces:
  - `final class ServerConfigStore: @unchecked Sendable` with `init(userDefaults: UserDefaults = .standard)`, `var baseURLString: String { get set }` (default `"http://localhost:60223"`, persisted at key `"exodus.serverURL"`). `@unchecked` because `UserDefaults` itself is thread-safe but not `Sendable`-annotated by Foundation, and this type has no other mutable state.
  - `struct APIClient: Sendable` with `init(session: URLSession = .shared, serverConfig: ServerConfigStore)`, `func get<T: Decodable>(_ path: String) async throws -> T`, `func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T`, `func post<Body: Encodable>(_ path: String, body: Body) async throws`, `func delete(_ path: String) async throws`.

- [ ] **Step 1: Add the `NetworkingKitTests` target to `Project.swift`**

Add this element to the `targets:` array, right after `moduleTarget(name: "NetworkingKit", ...)`:

```swift
        .target(
            name: "NetworkingKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).NetworkingKitTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/NetworkingKitTests"],
            dependencies: [.target(name: "NetworkingKit"), .target(name: "Models")]
        ),
```

Run: `tuist generate --no-open`

- [ ] **Step 2: Write `MockURLProtocol.swift` (test infrastructure, not itself under test)**

```swift
import Foundation

/// Intercepts every request on sessions configured with it and returns a
/// canned response via `handler`. `handler` is process-global static state,
/// so tests using it must run serially — see `@Suite(.serialized)` on
/// `APIClientTests`.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
```

- [ ] **Step 3: Write the failing tests**

`Tests/NetworkingKitTests/APIClientTests.swift`:

```swift
import Foundation
import Models
import Testing

@testable import NetworkingKit

@Suite("APIClient", .serialized)
struct APIClientTests {
    private func makeClient() -> APIClient {
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        return APIClient(session: MockURLProtocol.makeSession(), serverConfig: config)
    }

    @Test("GET decodes a successful JSON response")
    func getDecodesSuccess() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/history")
            #expect(request.httpMethod == "GET")
            let json = """
                [{"id":"c1","title":"Trip","createdAt":"2026-09-18T00:00:00.000Z"}]
                """.data(using: .utf8)!
            return (200, json)
        }
        let chats: [ChatSummary] = try await makeClient().get("/api/history")
        #expect(chats.count == 1)
        #expect(chats[0].id == "c1")
    }

    @Test("POST encodes the body and decodes the response")
    func postDecodesSuccess() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            let body = try JSONSerialization.jsonObject(with: request.httpBodyStreamData()) as? [String: Any]
            #expect(body?["provider"] as? String == "Anthropic Claude")
            let json = """
                {"models":[]}
                """.data(using: .utf8)!
            return (200, json)
        }
        let request = ListModelsRequest(provider: "Anthropic Claude", apiKey: "k", baseUrl: nil, apiVersion: nil)
        let response: ListModelsResponse = try await makeClient().post("/api/settings/models", body: request)
        #expect(response.models.isEmpty)
    }

    @Test("POST with no expected response body just checks status")
    func postWithoutDecoding() async throws {
        MockURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        let patch = SettingsPatch(id: "global", providerConfig: nil, providers: nil)
        try await makeClient().post("/api/settings", body: patch)
    }

    @Test("DELETE succeeds on 2xx")
    func deleteSucceeds() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/chat/c1")
            return (200, Data("{\"success\":true}".utf8))
        }
        try await makeClient().delete("/api/chat/c1")
    }

    @Test("a non-2xx Anthropic-style error body throws HTTPError with the server's message")
    func throwsHTTPErrorOnFailure() async throws {
        MockURLProtocol.handler = { _ in
            let json = """
                {"type":"error","error":{"code":"VALIDATION_FAILED","message":"API key is required"}}
                """.data(using: .utf8)!
            return (400, json)
        }
        do {
            let _: ListModelsResponse = try await makeClient().post(
                "/api/settings/models", body: ListModelsRequest(provider: "Ollama", apiKey: nil, baseUrl: nil, apiVersion: nil))
            Issue.record("expected HTTPError to be thrown")
        } catch let error as HTTPError {
            #expect(error.statusCode == 400)
            #expect(error.code == "VALIDATION_FAILED")
            #expect(error.message == "API key is required")
        }
    }
}

extension URLRequest {
    /// `httpBody` is nil for requests dispatched through URLProtocol (the body
    /// travels as a stream instead) — read it back from `httpBodyStream` for
    /// assertions in tests.
    fileprivate func httpBodyStreamData() throws -> Data {
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
```

- [ ] **Step 4: Run the tests and confirm they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme NetworkingKit -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: build failure — `ServerConfigStore`/`APIClient` don't exist yet.

- [ ] **Step 5: Implement `ServerConfigStore.swift`**

```swift
import Foundation

/// `UserDefaults` itself is thread-safe but not marked `Sendable` by Foundation;
/// this type has no other mutable state, so `@unchecked` is a deliberate,
/// narrow override, not a blanket escape hatch.
public final class ServerConfigStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private static let key = "exodus.serverURL"
    private static let defaultBaseURL = "http://localhost:60223"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var baseURLString: String {
        get { userDefaults.string(forKey: Self.key) ?? Self.defaultBaseURL }
        set { userDefaults.set(newValue, forKey: Self.key) }
    }
}
```

- [ ] **Step 6: Implement `APIClient.swift`**

```swift
import Foundation
import Models

public struct APIClient: Sendable {
    private let session: URLSession
    private let serverConfig: ServerConfigStore

    public init(session: URLSession = .shared, serverConfig: ServerConfigStore) {
        self.session = session
        self.serverConfig = serverConfig
    }

    public func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(path: path, method: "GET", body: Optional<String>.none)
    }

    public func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        try await send(path: path, method: "POST", body: body)
    }

    public func post<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await send(path: path, method: "POST", body: body, decodeResponse: false)
    }

    public func delete(_ path: String) async throws {
        let _: EmptyResponse = try await send(
            path: path, method: "DELETE", body: Optional<String>.none, decodeResponse: false)
    }

    private func send<Body: Encodable, T: Decodable>(
        path: String,
        method: String,
        body: Body?,
        decodeResponse: Bool = true
    ) async throws -> T {
        guard let base = URL(string: serverConfig.baseURLString) else {
            throw HTTPError(statusCode: 0, code: "INVALID_BASE_URL", message: "Invalid server URL: \(serverConfig.baseURLString)")
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        try Self.throwIfError(data: data, response: response)

        if !decodeResponse {
            return EmptyResponse() as! T
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func throwIfError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data) {
            throw HTTPError(statusCode: http.statusCode, code: envelope.error.code, message: envelope.error.message)
        }
        let fallbackMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
        throw HTTPError(statusCode: http.statusCode, code: "UNKNOWN_ERROR", message: fallbackMessage)
    }
}

private struct EmptyResponse: Decodable {}
```

Note: `EmptyResponse() as! T` is safe only because the two call sites that pass `decodeResponse: false` (`post<Body>` with no `T`, and `delete`) always instantiate `send` with `T == EmptyResponse` explicitly — there is no path where a caller requests a different `T` with `decodeResponse: false`.

- [ ] **Step 7: Delete the NetworkingKit placeholder, run the tests, confirm they pass**

```bash
rm Sources/NetworkingKit/Placeholder.swift
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme NetworkingKit -destination "platform=iOS Simulator,name=iPhone 17"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Add ServerConfigStore and a hand-rolled APIClient to NetworkingKit

Configurable server base URL (default http://localhost:60223,
UserDefaults-backed) plus a thin URLSession REST client that decodes
the server's Anthropic-style error envelope into HTTPError.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: NetworkingKit — SSE frame parsing + SSEClient

**Files:**
- Create: `Sources/NetworkingKit/SSEFrameParsing.swift`
- Create: `Sources/NetworkingKit/SSEClient.swift`
- Create: `Tests/NetworkingKitTests/SSEFrameParsingTests.swift`

**Interfaces:**
- Consumes: `ChatSseEvent` (Models), `ServerConfigStore` (Task 4).
- Produces:
  - `enum SSEFrameParsing { static func decodeEvent(fromLine line: String, decoder: JSONDecoder = JSONDecoder()) -> ChatSseEvent? }` — pure, no networking; returns `nil` for non-`data:` lines, blank payloads, or JSON that fails to parse at all (genuinely malformed, as opposed to an unrecognized-but-valid `type`, which decodes to `.unknown` per Task 2).
  - `struct SSEClient: Sendable { init(session: URLSession = .shared); func events(for request: URLRequest) -> AsyncThrowingStream<ChatSseEvent, Error> }`

- [ ] **Step 1: Write the failing test**

`Tests/NetworkingKitTests/SSEFrameParsingTests.swift`:

```swift
import Models
import Testing

@testable import NetworkingKit

@Suite("SSEFrameParsing")
struct SSEFrameParsingTests {
    @Test("decodes a well-formed data line")
    func decodesDataLine() {
        let event = SSEFrameParsing.decodeEvent(
            fromLine: #"data: {"type":"title","title":"héllo 世界"}"#)
        guard case .title(let title) = event else {
            Issue.record("expected .title, got \(String(describing: event))")
            return
        }
        #expect(title == "héllo 世界")
    }

    @Test("ignores lines that aren't a data: frame")
    func ignoresNonDataLines() {
        #expect(SSEFrameParsing.decodeEvent(fromLine: "") == nil)
        #expect(SSEFrameParsing.decodeEvent(fromLine: "event: ping") == nil)
    }

    @Test("ignores a data: line with an empty payload")
    func ignoresEmptyPayload() {
        #expect(SSEFrameParsing.decodeEvent(fromLine: "data: ") == nil)
    }

    @Test("ignores genuinely malformed JSON instead of throwing")
    func ignoresMalformedJSON() {
        #expect(SSEFrameParsing.decodeEvent(fromLine: "data: {not json") == nil)
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme NetworkingKit -destination "platform=iOS Simulator,name=iPhone 17" -only-testing NetworkingKitTests/SSEFrameParsingTests`
Expected: build failure — `SSEFrameParsing` doesn't exist yet.

- [ ] **Step 3: Implement `SSEFrameParsing.swift`**

```swift
import Foundation
import Models

public enum SSEFrameParsing {
    public static func decodeEvent(fromLine line: String, decoder: JSONDecoder = JSONDecoder()) -> ChatSseEvent? {
        guard line.hasPrefix("data: ") else { return nil }
        let jsonPart = line.dropFirst("data: ".count).trimmingCharacters(in: .whitespaces)
        guard !jsonPart.isEmpty, let data = jsonPart.data(using: .utf8) else { return nil }
        return try? decoder.decode(ChatSseEvent.self, from: data)
    }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme NetworkingKit -destination "platform=iOS Simulator,name=iPhone 17" -only-testing NetworkingKitTests/SSEFrameParsingTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Implement `SSEClient.swift`**

This wraps `URLSession.bytes(for:)` and Foundation's built-in `AsyncSequence.lines` (available on any byte stream, including `URLSession.AsyncBytes`) to split the response into lines, then reuses `SSEFrameParsing` per line — exactly mirroring `consumeStream()` in the desktop app's `stream-manager.ts`, minus the manual buffering (`.lines` already handles multi-byte-safe line splitting). This is not unit-tested here — it is a thin adapter with nothing left to test once `SSEFrameParsing` is covered; Task 11's manual end-to-end pass is what exercises it against a real server.

```swift
import Foundation
import Models

public struct SSEClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func events(for request: URLRequest) -> AsyncThrowingStream<ChatSseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: body) {
                            throw HTTPError(statusCode: http.statusCode, code: envelope.error.code, message: envelope.error.message)
                        }
                        throw HTTPError(statusCode: http.statusCode, code: "UNKNOWN_ERROR", message: "HTTP \(http.statusCode)")
                    }
                    for try await line in bytes.lines {
                        if let event = SSEFrameParsing.decodeEvent(fromLine: line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 6: Build the whole workspace to confirm `SSEClient` compiles (no dedicated test for it — see Step 5's note)**

Run: `xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "generic/platform=iOS Simulator"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Add SSE parsing and SSEClient to NetworkingKit

SSEFrameParsing is a pure, fully-tested data:-line -> ChatSseEvent
decoder; SSEClient adapts it to URLSession.bytes(for:), using
Foundation's AsyncSequence.lines for multibyte-safe line splitting
instead of hand-rolled buffering.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: NetworkingKit — ChatStreamManager

**Files:**
- Create: `Sources/NetworkingKit/ChatStreamManager.swift`
- Create: `Tests/NetworkingKitTests/ChatStreamManagerTests.swift`

**Interfaces:**
- Consumes: `ChatMessage`, `ChatSseEvent` (Models); `SSEClient`, `ServerConfigStore` (this module).
- Produces:
  - `enum ChatStatus: String, Sendable, Equatable { case idle, submitted, streaming, error }`
  - `enum ChatStreamUpdate: Sendable { case messages([ChatMessage]), status(ChatStatus), title(String), finished([ChatMessage]), failed(String) }`
  - `actor ChatStreamManager { init(sseClient: SSEClient = SSEClient()); func isStreaming(_ chatId: String) -> Bool; func attach(_ chatId: String) -> AsyncStream<ChatStreamUpdate>?; func send(chatId: String, messages: [ChatMessage], serverConfig: ServerConfigStore) -> AsyncStream<ChatStreamUpdate> }` — mirrors `stream-manager.ts`'s singleton map, `subscribe`/`unsubscribe`, and `startStream`/`stopStream`, so a `ChatDetailView` that disappears and reappears re-attaches to an in-flight turn instead of losing it or double-sending.

- [ ] **Step 1: Write the failing tests**

`Tests/NetworkingKitTests/ChatStreamManagerTests.swift` uses a fake `SSEClient`-shaped event source by driving `ChatStreamManager` against a `MockURLProtocol`-backed `URLSession` whose response body is a canned SSE stream (reusing the Task 4 infrastructure, this time returning a **stream** body via `URLProtocol`'s incremental `didLoad:` calls rather than one `didLoad:` call, so `SSEClient`'s real `URLSession.bytes(for:)` code path is exercised for real):

```swift
import Foundation
import Models
import Testing

@testable import NetworkingKit

private final class StreamingMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var chunks: [Data] = []
    /// When `false`, delivers `chunks` but never calls `didFinishLoading` —
    /// simulates a still-open SSE connection instead of a completed HTTP
    /// response. `ChatStreamManager.finish(chatId:)` only runs once the
    /// underlying byte stream actually ends, so a mock that finishes
    /// instantly (the default) cannot be used to test "the turn is still
    /// in flight" — it stops being in flight essentially immediately.
    nonisolated(unsafe) static var finishesLoading: Bool = true
    /// HTTP status the mock answers with. Every test that depends on it sets it
    /// explicitly (the suite is `.serialized`, statics are shared).
    nonisolated(unsafe) static var statusCode: Int = 200
    /// The `timeoutInterval` of the last request the mock saw — lets a test pin
    /// the request configuration `ChatStreamManager` builds.
    nonisolated(unsafe) static var lastTimeout: TimeInterval?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastTimeout = request.timeoutInterval
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.statusCode, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in Self.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        if Self.finishesLoading {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreamingMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

@Suite("ChatStreamManager", .serialized)
struct ChatStreamManagerTests {
    @Test("streams message_update frames then finishes on done, collecting the final messages")
    func streamsToCompletion() async throws {
        let sse = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"He"}}\n\n\
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"Hello"}}\n\n\
            data: {"type":"done","messages":[{"id":"u1","role":"user","content":"hi"},{"id":"a1","role":"assistant","content":"Hello"}]}\n\n
            """
        StreamingMockURLProtocol.finishesLoading = true
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.chunks = [Data(sse.utf8)]

        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        var seenStatuses: [ChatStatus] = []
        var finalMessages: [ChatMessage] = []
        for await update in await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig) {
            switch update {
            case .status(let s): seenStatuses.append(s)
            case .finished(let messages): finalMessages = messages
            default: break
            }
        }

        #expect(seenStatuses.first == .submitted)
        #expect(finalMessages.count == 2)
        #expect(finalMessages.last?.displayText == "Hello")
        #expect(await manager.isStreaming("c1") == false)
        // The server sends no keep-alive frames, so the request must tolerate a
        // long silent stretch (see `makeRequest`).
        #expect(StreamingMockURLProtocol.lastTimeout == 3600)
    }

    @Test("a non-2xx response (e.g. no provider configured yet) surfaces the server's message as .failed and ends the stream")
    func httpErrorSurfacesServerMessage() async throws {
        StreamingMockURLProtocol.finishesLoading = true
        StreamingMockURLProtocol.statusCode = 400
        StreamingMockURLProtocol.chunks = [
            Data(#"{"type":"error","error":{"code":"NO_PROVIDER","message":"Please configure a provider in Settings"}}"#.utf8)
        ]
        defer { StreamingMockURLProtocol.statusCode = 200 }

        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        var seenStatuses: [ChatStatus] = []
        var failure: String?
        var sawFinished = false
        for await update in await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig) {
            switch update {
            case .status(let s): seenStatuses.append(s)
            case .failed(let message): failure = message
            case .finished: sawFinished = true
            default: break
            }
        }

        #expect(failure == "Please configure a provider in Settings")
        #expect(seenStatuses.last == .error)
        #expect(!sawFinished)
        #expect(await manager.isStreaming("c1") == false)
    }

    @Test("an in-flight stream can be attached to from a second observer and replays current state")
    func attachReplaysSnapshot() async throws {
        // finishesLoading = false: the mock delivers one chunk and never
        // signals completion, so the underlying byte stream stays open —
        // genuinely "still in flight," not a race against a mock that would
        // otherwise finish (and call ChatStreamManager.finish(chatId:)) in
        // well under a millisecond.
        StreamingMockURLProtocol.finishesLoading = false
        StreamingMockURLProtocol.statusCode = 200
        let sse = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"partial"}}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(sse.utf8)]
        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        let updates = await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig)
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()  // .status(.submitted)
        _ = await iterator.next()  // .messages([...]) once the one chunk is parsed — awaiting
        // this deterministically waits for that point without any sleep.

        let attached = await manager.attach("c1")
        #expect(attached != nil)
        #expect(await manager.isStreaming("c1"))
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme NetworkingKit -destination "platform=iOS Simulator,name=iPhone 17" -only-testing NetworkingKitTests/ChatStreamManagerTests`
Expected: build failure — `ChatStreamManager` doesn't exist yet.

- [ ] **Step 3: Implement `ChatStreamManager.swift`**

```swift
import Foundation
import Models

public enum ChatStatus: String, Sendable, Equatable {
    case idle, submitted, streaming, error
}

public enum ChatStreamUpdate: Sendable {
    case messages([ChatMessage])
    case status(ChatStatus)
    case title(String)
    case finished([ChatMessage])
    case failed(String)
}

public actor ChatStreamManager {
    private struct ActiveStream {
        var task: Task<Void, Never>?
        var messages: [ChatMessage]
        var status: ChatStatus
        var continuation: AsyncStream<ChatStreamUpdate>.Continuation?
    }

    private let sseClient: SSEClient
    private var streams: [String: ActiveStream] = [:]

    public init(sseClient: SSEClient = SSEClient()) {
        self.sseClient = sseClient
    }

    public func isStreaming(_ chatId: String) -> Bool {
        guard let stream = streams[chatId] else { return false }
        return stream.status == .submitted || stream.status == .streaming
    }

    /// Replays the current snapshot (messages + status) then live-updates.
    /// Returns `nil` if nothing is in flight for this chat.
    public func attach(_ chatId: String) -> AsyncStream<ChatStreamUpdate>? {
        guard var stream = streams[chatId] else { return nil }
        let (output, continuation) = AsyncStream<ChatStreamUpdate>.makeStream()
        continuation.yield(.messages(stream.messages))
        continuation.yield(.status(stream.status))
        stream.continuation = continuation
        streams[chatId] = stream
        return output
    }

    public func send(
        chatId: String,
        messages: [ChatMessage],
        serverConfig: ServerConfigStore
    ) -> AsyncStream<ChatStreamUpdate> {
        streams[chatId]?.task?.cancel()

        let (output, continuation) = AsyncStream<ChatStreamUpdate>.makeStream()
        streams[chatId] = ActiveStream(task: nil, messages: messages, status: .submitted, continuation: continuation)
        continuation.yield(.status(.submitted))

        let request = Self.makeRequest(chatId: chatId, messages: messages, serverConfig: serverConfig)
        let sseClient = self.sseClient

        let task = Task { [weak self] in
            guard let request else {
                await self?.fail(chatId: chatId, message: "Invalid server URL")
                return
            }
            do {
                for try await event in sseClient.events(for: request) {
                    await self?.apply(chatId: chatId, event: event)
                }
                await self?.finish(chatId: chatId)
            } catch {
                await self?.fail(chatId: chatId, message: (error as? LocalizedError)?.errorDescription ?? String(describing: error))
            }
        }
        streams[chatId]?.task = task
        return output
    }

    private func apply(chatId: String, event: ChatSseEvent) {
        guard var stream = streams[chatId] else { return }
        switch event {
        case .messageUpdate(let message):
            if let index = stream.messages.firstIndex(where: { $0.id == message.id }) {
                stream.messages[index] = message
            } else {
                stream.messages.append(message)
            }
            stream.status = .streaming
            stream.continuation?.yield(.messages(stream.messages))
        case .done(let messages):
            stream.messages = messages
            stream.continuation?.yield(.messages(stream.messages))
        case .title(let title):
            stream.continuation?.yield(.title(title))
        case .error(let message):
            stream.continuation?.yield(.failed(message))
        case .toolCallStart, .toolCallEnd, .notice, .unknown:
            break
        }
        streams[chatId] = stream
    }

    private func finish(chatId: String) {
        guard let stream = streams[chatId] else { return }
        stream.continuation?.yield(.status(.idle))
        stream.continuation?.yield(.finished(stream.messages))
        stream.continuation?.finish()
        streams[chatId] = nil
    }

    private func fail(chatId: String, message: String) {
        guard let stream = streams[chatId] else { return }
        stream.continuation?.yield(.status(.error))
        stream.continuation?.yield(.failed(message))
        stream.continuation?.finish()
        streams[chatId] = nil
    }

    private static func makeRequest(
        chatId: String,
        messages: [ChatMessage],
        serverConfig: ServerConfigStore
    ) -> URLRequest? {
        guard let base = URL(string: serverConfig.baseURLString) else { return nil }
        var request = URLRequest(url: base.appendingPathComponent("/api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The server sends no keep-alive frames, and URLSession's default 60 s
        // *inactivity* timeout would kill a turn during a long silent stretch (a
        // reasoning model thinking before its first token, a slow tool call) that
        // the desktop's `fetch` simply waits out. Allow up to an hour of silence.
        request.timeoutInterval = 3600
        struct Body: Encodable {
            let id: String
            let messages: [ChatMessage]
            let advancedTools: [String]
        }
        request.httpBody = try? JSONEncoder().encode(Body(id: chatId, messages: messages, advancedTools: []))
        return request
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme NetworkingKit -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: `** TEST SUCCEEDED **`, every NetworkingKit test (Tasks 4-6) passes.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Add ChatStreamManager actor to NetworkingKit

Owns in-flight POST /api/chat streams keyed by chat id, upserting
message_update frames by message id and replaying the current
snapshot to a view that re-attaches mid-stream — mirrors
stream-manager.ts's "leave and come back, the response kept
streaming in the background" behavior.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: SettingsFeature

**Files:**
- Create: `Sources/SettingsFeature/SettingsViewModel.swift`
- Create: `Sources/SettingsFeature/SettingsView.swift`
- Create: `Tests/SettingsFeatureTests/SettingsViewModelTests.swift`
- Delete: `Sources/SettingsFeature/Placeholder.swift`
- Modify: `Project.swift` — add `SettingsFeatureTests` target
- Modify: `Sources/App/RootView.swift` — temporarily present `SettingsView` so it's reachable for manual verification (Task 10 wires the real navigation; this is a throwaway hook removed there)

**Interfaces:**
- Consumes: `APIClient`, `ServerConfigStore` (NetworkingKit); `AiProviders`, `ProviderConfig`, `ProvidersConfig`, `SettingsSnapshot`, `SettingsPatch`, `ListModelsRequest`, `ListModelsResponse`, `CachedModelEntry` (Models).
- Produces: `public struct SettingsView: View { public init(apiClient: APIClient, serverConfig: ServerConfigStore) }` — the type `RootView`/App composition (Task 10) instantiates directly.

**Controller rulings baked into this task** (each found by checking the plan's original view model against the desktop server and a real user flow; every one has a test below):

1. **Switching the provider must swap the API key.** The original view model kept one `apiKeyText` for whichever provider was selected and never refreshed it on a switch, so `save()` wrote the *previous* provider's key into the *new* provider's slot. `select(provider:)` parks the key typed for the provider being left, loads the new provider's key, clears the (per-provider) model catalog and restores the loaded model only if the loaded provider is the one selected again. `selectedProvider` is therefore `private(set)`.
2. **`modelSnapshot` is never blindly `nil`.** `POST /api/settings` replaces `providerConfig` wholesale and the desktop feeds `providerConfig.modelSnapshot` (context window, max output tokens, reasoning levels, cost) to its model resolver (`src/main/lib/ai/providers/index.ts`). Save sends the picked catalog entry's snapshot; else the loaded snapshot if provider *and* model are unchanged; else none (a snapshot for a different model would be wrong data).
3. **`lastBackupAt` is echoed** from the loaded snapshot into the patch (Task 3), because the server writes it unconditionally and would otherwise null the desktop's "last backup" timestamp.
4. **Ollama has no API key** (`ProvidersSchema` only has `ollamaBaseUrl`). The form shows no key field for it and "Refresh model list" is enabled without one; the desktop server queries its own Ollama.
5. **The server address is normalized before it is stored.** The field is meant to take a bare `192.168.1.10:60223` once the app runs on a real device (spec §4.4/§6); `URL(string:)` accepts that as a relative reference and every request then fails with an unhelpful error. `saveServerURL()` trims, defaults a missing scheme to `http://`, drops trailing slashes, and refuses anything that is not an http(s) URL with a host — without touching the stored value.
6. **Errors are shown as `error.localizedDescription`** (for `HTTPError` that is the server's message; for a refused connection it is "Could not connect to the server." instead of a `URLError(_nsError: …)` dump).
7. **Step 8 (manual verification) is not for the implementer** — it needs `pnpm dev` running in `../universal-client` and a real API key. The human/controller covers it in Task 11's end-to-end pass. Skip it and say so in the report.

8. **Never write to a server whose settings haven't been loaded.** `POST /api/settings` replaces `providers` and `providerConfig` wholesale and nulls `lastBackupAt` when it is absent, so saving from a form that never successfully loaded would wipe the desktop's other providers' keys, flip its provider and null its last-backup time. The natural first run on a real device does exactly that: the default `localhost` is unreachable so the initial load fails, the user types the LAN address and a key, taps Save without pressing Return. `hasLoadedSettings` is true only after a successful `loadSettings()` (reset at the start of every load, and whenever `saveServerURL()` changes the stored address); `save()` refuses without it; in the view, Save while not loaded *connects* instead of writing — it persists the address and reloads that server's settings — and the button reads "Connect".
9. **A model-list response is applied only if it is still the current one**: `fetchModels()` compares the provider and key it was requested for with the current ones after the `await`, so a response that arrives after a provider switch cannot attach one provider's catalog to another.

Swift 6 notes for the tests below: the view model is `@MainActor`, so the suite is `@MainActor`; the mock handler runs on a URLProtocol thread, so request bodies are recorded behind a `Mutex` and asserted afterwards, never with a captured `var` and never with `#expect` inside the handler. If you still hit a Swift 6 diagnostic, fix it minimally and record it in the report; never lower `SWIFT_VERSION`.

- [ ] **Step 1: Add the `SettingsFeatureTests` target to `Project.swift`**

Add after `moduleTarget(name: "SettingsFeature", ...)`:

```swift
        .target(
            name: "SettingsFeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).SettingsFeatureTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/SettingsFeatureTests"],
            dependencies: [
                .target(name: "SettingsFeature"), .target(name: "NetworkingKit"), .target(name: "Models")
            ]
        ),
```

Run: `tuist generate --no-open`

- [ ] **Step 2: Write the failing tests**

`Tests/SettingsFeatureTests/SettingsViewModelTests.swift` reuses `MockURLProtocol` from `NetworkingKitTests` — Tuist test targets can't import another test target directly, so this task re-declares a minimal copy scoped to this target (small enough that duplicating it is simpler than extracting a shared test-support module for two call sites):

```swift
import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import SettingsFeature

private final class SettingsMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SettingsMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// The mock handler runs on a URLProtocol thread, so the bodies it sees are recorded
/// behind a lock and asserted from the test afterwards (an `#expect` inside a handler
/// could silently never run).
private final class BodyRecorder: Sendable {
    private let storage = Mutex<[String: [Data]]>([:])

    func record(_ data: Data, for path: String) {
        storage.withLock { $0[path, default: []].append(data) }
    }

    func bodies(for path: String) -> [Data] {
        storage.withLock { $0[path] ?? [] }
    }

    /// The JSON object of the one and only body posted to `path`.
    func onlyJSONBody(for path: String) throws -> [String: Any] {
        let all = bodies(for: path)
        try #require(all.count == 1)
        let object = try JSONSerialization.jsonObject(with: all[0])
        return try #require(object as? [String: Any])
    }
}

/// Installs a handler that answers by method + path and records every POST body.
private func serve(
    settings: String = #"{"id":"global"}"#,
    models: String = #"{"models":[]}"#,
    postSettingsStatus: Int = 200,
    postSettingsBody: String = "{}",
    recorder: BodyRecorder
) {
    SettingsMockURLProtocol.handler = { request in
        let path = request.url?.path ?? ""
        if request.httpMethod == "POST" {
            recorder.record(try request.httpBodyStreamData(), for: path)
        }
        switch (request.httpMethod, path) {
        case ("GET", "/api/settings"):
            return (200, Data(settings.utf8))
        case ("POST", "/api/settings/models"):
            return (200, Data(models.utf8))
        case ("POST", "/api/settings"):
            return (postSettingsStatus, Data(postSettingsBody.utf8))
        default:
            return (404, Data(#"{"type":"error","error":{"code":"NOT_FOUND","message":"no route"}}"#.utf8))
        }
    }
}

@MainActor
@Suite("SettingsViewModel", .serialized)
struct SettingsViewModelTests {
    /// What the desktop has saved: Anthropic selected with a model snapshot, an OpenAI key
    /// for a provider that is not selected, and a last-backup timestamp.
    private static let loadedSettingsJSON = #"""
        {"id":"global",
         "providerConfig":{"provider":"Anthropic Claude","model":"claude-sonnet-5",
           "modelSnapshot":{"contextWindow":200000,"maxOutputTokens":64000,"reasoningLevels":["low","high"],"cost":{"input":3,"output":15}}},
         "providers":{"anthropicApiKey":"sk-ant-1","openaiApiKey":"sk-oai-2"},
         "lastBackupAt":"2026-09-18T12:00:00.000Z"}
        """#

    private func makeViewModel(_ suite: String = #function) -> (SettingsViewModel, ServerConfigStore) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let client = APIClient(session: SettingsMockURLProtocol.makeSession(), serverConfig: config)
        return (SettingsViewModel(apiClient: client, serverConfig: config), config)
    }

    @Test("loadSettings populates the selected provider, model, and API key")
    func loadSettingsPopulatesForm() async throws {
        serve(settings: Self.loadedSettingsJSON, recorder: BodyRecorder())
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        #expect(vm.selectedProvider == .anthropicClaude)
        #expect(vm.modelText == "claude-sonnet-5")
        #expect(vm.apiKeyText == "sk-ant-1")
        #expect(vm.errorMessage == nil)
    }

    @Test("fetchModels posts the provider and key, and populates availableModels from the live catalog")
    func fetchModelsPopulatesCatalog() async throws {
        let recorder = BodyRecorder()
        serve(
            models: #"{"models":[{"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"reasoningLevels":[]}}]}"#,
            recorder: recorder)
        let (vm, _) = makeViewModel()
        vm.apiKeyText = "sk-ant-xyz"
        await vm.fetchModels()
        #expect(vm.availableModels.count == 1)
        #expect(vm.availableModels[0].id == "claude-sonnet-5")
        #expect(vm.errorMessage == nil)
        let body = try recorder.onlyJSONBody(for: "/api/settings/models")
        #expect(body["provider"] as? String == "Anthropic Claude")
        #expect(body["apiKey"] as? String == "sk-ant-xyz")
    }

    @Test("save() posts only id/providerConfig/providers and reports success")
    func saveSendsPartialPatch() async throws {
        let recorder = BodyRecorder()
        serve(recorder: recorder)
        let (vm, _) = makeViewModel()
        vm.apiKeyText = "sk-ant-xyz"
        vm.modelText = "claude-sonnet-5"
        let success = await vm.save()
        #expect(success)
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        #expect(Set(body.keys) == ["id", "providerConfig", "providers"])
        #expect(body["id"] as? String == "global")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        #expect(providerConfig["provider"] as? String == "Anthropic Claude")
        #expect(providerConfig["model"] as? String == "claude-sonnet-5")
        #expect(providerConfig.keys.contains("modelSnapshot") == false)
        let providers = try #require(body["providers"] as? [String: Any])
        #expect(providers["anthropicApiKey"] as? String == "sk-ant-xyz")
    }

    @Test("save() echoes the loaded lastBackupAt so the server does not null the desktop's timestamp")
    func saveEchoesLastBackupAt() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        #expect(body["lastBackupAt"] as? String == "2026-09-18T12:00:00.000Z")
    }

    @Test("save() keeps the model snapshot the desktop saved when provider and model are unchanged")
    func savePreservesLoadedModelSnapshot() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        let snapshot = try #require(providerConfig["modelSnapshot"] as? [String: Any])
        #expect(snapshot["contextWindow"] as? Double == 200_000)
        #expect(snapshot["maxOutputTokens"] as? Double == 64_000)
        #expect(snapshot["reasoningLevels"] as? [String] == ["low", "high"])
        let cost = try #require(snapshot["cost"] as? [String: Any])
        #expect(cost["input"] as? Double == 3)
        #expect(cost["output"] as? Double == 15)
    }

    @Test("save() sends the snapshot of the catalog entry the user picked, not the stale loaded one")
    func savePicksCatalogSnapshotForChosenModel() async throws {
        let recorder = BodyRecorder()
        serve(
            settings: Self.loadedSettingsJSON,
            models: #"{"models":[{"id":"claude-opus-5","displayName":"Claude Opus 5","snapshot":{"contextWindow":1000000,"reasoningLevels":["high"]}}]}"#,
            recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        await vm.fetchModels()
        vm.modelText = "claude-opus-5"
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        #expect(providerConfig["model"] as? String == "claude-opus-5")
        let snapshot = try #require(providerConfig["modelSnapshot"] as? [String: Any])
        #expect(snapshot["contextWindow"] as? Double == 1_000_000)
    }

    @Test("save() attaches no snapshot to a model the desktop has no snapshot for")
    func saveDropsSnapshotForAnUnknownModel() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        vm.modelText = "some-custom-model"
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        #expect(providerConfig["model"] as? String == "some-custom-model")
        #expect(providerConfig.keys.contains("modelSnapshot") == false)
    }

    @Test("switching provider swaps the key and model, clears the catalog, and switching back restores them")
    func switchingProviderSwapsKeyAndResetsModel() async throws {
        serve(
            settings: Self.loadedSettingsJSON,
            models: #"{"models":[{"id":"claude-sonnet-5","displayName":"Claude Sonnet 5","snapshot":{"reasoningLevels":[]}}]}"#,
            recorder: BodyRecorder())
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        await vm.fetchModels()
        #expect(vm.availableModels.count == 1)

        vm.select(provider: .openAiGpt)
        #expect(vm.selectedProvider == .openAiGpt)
        #expect(vm.apiKeyText == "sk-oai-2")
        #expect(vm.modelText == "")
        #expect(vm.availableModels.isEmpty)

        vm.select(provider: .anthropicClaude)
        #expect(vm.apiKeyText == "sk-ant-1")
        #expect(vm.modelText == "claude-sonnet-5")
    }

    @Test("saving after a provider switch never copies the previous provider's key into the new one")
    func savingAfterSwitchNeverCopiesTheOldKey() async throws {
        let recorder = BodyRecorder()
        serve(
            settings: #"{"id":"global","providerConfig":{"provider":"Anthropic Claude","model":"claude-sonnet-5"},"providers":{"anthropicApiKey":"sk-ant-1"}}"#,
            recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        vm.select(provider: .openAiGpt)
        #expect(vm.apiKeyText == "")
        vm.modelText = "gpt-x"
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providerConfig = try #require(body["providerConfig"] as? [String: Any])
        #expect(providerConfig["provider"] as? String == "OpenAI GPT")
        let providers = try #require(body["providers"] as? [String: Any])
        #expect(providers["anthropicApiKey"] as? String == "sk-ant-1")
        #expect(providers.keys.contains("openaiApiKey") == false)
    }

    @Test("clearing the key field removes that provider's key and leaves the other providers' keys alone")
    func clearingAKeyRemovesOnlyThatKey() async throws {
        let recorder = BodyRecorder()
        serve(settings: Self.loadedSettingsJSON, recorder: recorder)
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        vm.apiKeyText = ""
        #expect(await vm.save())
        let body = try recorder.onlyJSONBody(for: "/api/settings")
        let providers = try #require(body["providers"] as? [String: Any])
        #expect(providers.keys.contains("anthropicApiKey") == false)
        #expect(providers["openaiApiKey"] as? String == "sk-oai-2")
    }

    @Test("Ollama needs no API key: no key field, and the model list can be fetched without one")
    func ollamaNeedsNoApiKey() async throws {
        let recorder = BodyRecorder()
        serve(recorder: recorder)
        let (vm, _) = makeViewModel()
        #expect(vm.providerUsesApiKey)
        #expect(vm.canFetchModels == false)  // Anthropic, no key typed yet

        vm.select(provider: .ollama)
        #expect(vm.providerUsesApiKey == false)
        #expect(vm.canFetchModels)
        await vm.fetchModels()
        let body = try recorder.onlyJSONBody(for: "/api/settings/models")
        #expect(body["provider"] as? String == "Ollama")
        #expect(body.keys.contains("apiKey") == false)
    }

    @Test("a bare host:port is normalized to an http:// address, stored, and shown back")
    func saveServerURLNormalizes() async throws {
        let cases: [(input: String, expected: String)] = [
            ("192.168.1.10:60223", "http://192.168.1.10:60223"),
            ("  http://mac.local:60223/  ", "http://mac.local:60223"),
            ("https://exodus.example.com", "https://exodus.example.com"),
        ]
        for (input, expected) in cases {
            let (vm, config) = makeViewModel()
            vm.serverURLText = input
            #expect(vm.saveServerURL(), "\(input) should be accepted")
            #expect(config.baseURLString == expected)
            #expect(vm.serverURLText == expected)
            #expect(vm.errorMessage == nil)
        }
    }

    @Test("an unusable server address is refused with a message and the stored one is left untouched")
    func saveServerURLRejectsGarbage() async throws {
        for input in ["", "   ", "http://", "://", "ftp://host"] {
            let (vm, config) = makeViewModel()
            vm.serverURLText = input
            #expect(vm.saveServerURL() == false, "\(input.debugDescription) should be refused")
            #expect(vm.errorMessage != nil)
            #expect(config.baseURLString == "http://localhost:60223")
        }
    }

    @Test("a transport failure is shown as a human message, not a URLError dump")
    func transportErrorUsesAHumanMessage() async throws {
        SettingsMockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let (vm, _) = makeViewModel()
        await vm.loadSettings()
        let message = try #require(vm.errorMessage)
        #expect(message == URLError(.cannotConnectToHost).localizedDescription)
        #expect(message.contains("URLError") == false)
    }

    @Test("a failed save surfaces the server's error message")
    func saveSurfacesServerError() async throws {
        serve(
            postSettingsStatus: 400,
            postSettingsBody: #"{"type":"error","error":{"code":"VALIDATION_FAILED","message":"Invalid setting configuration"}}"#,
            recorder: BodyRecorder())
        let (vm, _) = makeViewModel()
        let success = await vm.save()
        #expect(success == false)
        #expect(vm.errorMessage == "Invalid setting configuration")
    }
}

extension URLRequest {
    fileprivate func httpBodyStreamData() throws -> Data {
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme SettingsFeature -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: build failure — `SettingsViewModel` doesn't exist yet.

- [ ] **Step 4: Implement `SettingsViewModel.swift`**

```swift
import Foundation
import Models
import NetworkingKit
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var serverURLText: String
    public private(set) var selectedProvider: AiProviders = .anthropicClaude
    public var apiKeyText: String = ""
    public var modelText: String = ""
    public private(set) var availableModels: [CachedModelEntry] = []
    public var isLoading = false
    public var isSaving = false
    public var isLoadingModels = false
    public var errorMessage: String?
    public var didSave = false

    private let apiClient: APIClient
    private let serverConfig: ServerConfigStore

    /// The provider settings as last loaded/saved, plus keys the user typed for providers
    /// they have since switched away from. The selected provider's key lives in
    /// `apiKeyText` until it is parked (on a switch) or saved.
    private var workingProviders = ProvidersConfig()
    private var loadedProviderConfig: ProviderConfig?
    private var loadedLastBackupAt: String?

    public init(apiClient: APIClient, serverConfig: ServerConfigStore) {
        self.apiClient = apiClient
        self.serverConfig = serverConfig
        self.serverURLText = serverConfig.baseURLString
    }

    /// Ollama runs unauthenticated: `ProvidersSchema` has only `ollamaBaseUrl`, no key.
    public var providerUsesApiKey: Bool { selectedProvider != .ollama }
    public var canFetchModels: Bool { !providerUsesApiKey || !apiKeyText.isEmpty }

    /// Normalizes what was typed — trims, defaults a missing scheme to `http://` (the field
    /// takes a bare `192.168.1.10:60223` on a real device), drops trailing slashes — and
    /// stores it only if it is an http(s) URL with a host. Otherwise sets `errorMessage`
    /// and leaves the stored address untouched.
    @discardableResult
    public func saveServerURL() -> Bool {
        var text = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else {
            errorMessage = "Server address must look like http://192.168.1.10:60223"
            return false
        }
        errorMessage = nil
        serverURLText = text
        serverConfig.baseURLString = text
        return true
    }

    /// Switches the selected provider. Parks the key typed for the provider being left, loads
    /// the new provider's key, drops the model catalog (it belongs to one provider) and restores
    /// the loaded model only when the loaded provider is the one being selected again.
    public func select(provider: AiProviders) {
        guard provider != selectedProvider else { return }
        workingProviders = workingProviders.settingApiKey(apiKeyText.isEmpty ? nil : apiKeyText, for: selectedProvider)
        selectedProvider = provider
        apiKeyText = workingProviders.apiKey(for: provider) ?? ""
        availableModels = []
        modelText = provider.rawValue == loadedProviderConfig?.provider ? (loadedProviderConfig?.model ?? "") : ""
    }

    public func loadSettings() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let snapshot: SettingsSnapshot = try await apiClient.get("/api/settings")
            workingProviders = snapshot.providers ?? ProvidersConfig()
            loadedProviderConfig = snapshot.providerConfig
            loadedLastBackupAt = snapshot.lastBackupAt
            availableModels = []
            if let raw = snapshot.providerConfig?.provider, let provider = AiProviders(rawValue: raw) {
                selectedProvider = provider
                modelText = snapshot.providerConfig?.model ?? ""
            } else {
                modelText = ""
            }
            apiKeyText = workingProviders.apiKey(for: selectedProvider) ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func fetchModels() async {
        isLoadingModels = true
        errorMessage = nil
        defer { isLoadingModels = false }
        do {
            let request = ListModelsRequest(
                provider: selectedProvider.rawValue,
                apiKey: apiKeyText.isEmpty ? nil : apiKeyText,
                baseUrl: nil,
                apiVersion: nil
            )
            let response: ListModelsResponse = try await apiClient.post("/api/settings/models", body: request)
            availableModels = response.models
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `POST /api/settings` replaces `providerConfig` wholesale and the desktop feeds
    /// `providerConfig.modelSnapshot` (context window, max output, reasoning levels, cost) to
    /// its model resolver, so never send `nil` for a model the desktop already knows: prefer
    /// the picked catalog entry; else keep the loaded snapshot only if provider AND model are
    /// unchanged (a snapshot for a different model would be wrong data); else none.
    private func resolvedModelSnapshot() -> ModelSnapshot? {
        if let entry = availableModels.first(where: { $0.id == modelText }) { return entry.snapshot }
        guard let loaded = loadedProviderConfig,
              loaded.provider == selectedProvider.rawValue,
              loaded.model == modelText
        else { return nil }
        return loaded.modelSnapshot
    }

    @discardableResult
    public func save() async -> Bool {
        isSaving = true
        errorMessage = nil
        didSave = false
        defer { isSaving = false }
        do {
            let providers = workingProviders.settingApiKey(apiKeyText.isEmpty ? nil : apiKeyText, for: selectedProvider)
            let providerConfig = ProviderConfig(
                provider: selectedProvider.rawValue,
                model: modelText.isEmpty ? nil : modelText,
                modelSnapshot: modelText.isEmpty ? nil : resolvedModelSnapshot()
            )
            // `lastBackupAt` is echoed because the server writes it unconditionally (see SettingsPatch).
            let patch = SettingsPatch(
                id: "global", providerConfig: providerConfig, providers: providers, lastBackupAt: loadedLastBackupAt)
            try await apiClient.post("/api/settings", body: patch)
            workingProviders = providers
            loadedProviderConfig = providerConfig
            didSave = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme SettingsFeature -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Implement `SettingsView.swift`**

```swift
import Models
import NetworkingKit
import SwiftUI

public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(apiClient: APIClient, serverConfig: ServerConfigStore) {
        _viewModel = State(initialValue: SettingsViewModel(apiClient: apiClient, serverConfig: serverConfig))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("连接") {
                    TextField("http://192.168.1.10:60223", text: $viewModel.serverURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit {
                            // A new address means a different server: reload its provider settings.
                            if viewModel.saveServerURL() {
                                Task { await viewModel.loadSettings() }
                            }
                        }
                }

                Section("AI Providers") {
                    Picker(
                        "Provider",
                        selection: Binding(
                            get: { viewModel.selectedProvider },
                            set: { viewModel.select(provider: $0) })
                    ) {
                        ForEach(AiProviders.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }

                    if viewModel.providerUsesApiKey {
                        SecureField("API Key", text: $viewModel.apiKeyText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Text("Ollama runs on your Mac and needs no API key.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.availableModels.isEmpty {
                        TextField("Model", text: $viewModel.modelText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Picker("Model", selection: $viewModel.modelText) {
                            // Keep the current value selectable even when it isn't in the catalog.
                            if viewModel.modelText.isEmpty {
                                Text("Select a model").tag("")
                            } else if !viewModel.availableModels.contains(where: { $0.id == viewModel.modelText }) {
                                Text(viewModel.modelText).tag(viewModel.modelText)
                            }
                            ForEach(viewModel.availableModels) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                    }

                    Button {
                        Task { await viewModel.fetchModels() }
                    } label: {
                        if viewModel.isLoadingModels {
                            ProgressView()
                        } else {
                            Text("Refresh model list")
                        }
                    }
                    .disabled(!viewModel.canFetchModels)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard viewModel.saveServerURL() else { return }
                            if await viewModel.save() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await viewModel.loadSettings() }
        }
    }
}
```

- [ ] **Step 7: Wire a temporary manual-verification hook, delete the placeholder, build**

`Sources/App/RootView.swift` (throwaway — Task 10 replaces this entirely):

```swift
import NetworkingKit
import SettingsFeature
import SwiftUI

struct RootView: View {
    @State private var showSettings = false
    private let apiClient: APIClient
    private let serverConfig: ServerConfigStore

    init() {
        let config = ServerConfigStore()
        serverConfig = config
        apiClient = APIClient(serverConfig: config)
    }

    var body: some View {
        Button("Open Settings") { showSettings = true }
            .sheet(isPresented: $showSettings) {
                SettingsView(apiClient: apiClient, serverConfig: serverConfig)
            }
    }
}

#Preview {
    RootView()
}
```

```bash
rm Sources/SettingsFeature/Placeholder.swift
tuist generate --no-open
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "generic/platform=iOS Simulator"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Manual verification against a live desktop server — NOT for the implementer**

This needs `pnpm dev` running in `../universal-client` and a real API key, so the human/controller does it in Task 11's end-to-end pass: in the Simulator, "Open Settings", pick "Anthropic Claude", paste a real key, "Refresh model list" (a live catalog appears), pick a model, "Save", then confirm the desktop app's own Settings → AI Providers tab shows the same provider/model/key and that its "last backup" and the model's context window / reasoning options are unchanged. The implementer skips this step and says so in the report.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Add SettingsFeature: server URL + AI Providers form

SettingsViewModel loads GET /api/settings into a narrow snapshot,
optionally live-fetches a provider's model catalog via
POST /api/settings/models, and saves via a POST /api/settings body of
id/providerConfig/providers plus the echoed lastBackupAt. Saving keeps
the desktop's modelSnapshot, swaps the API key with the selected
provider, and the server address is normalized before it is stored.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: ChatFeature — chat list

**Files:**
- Create: `Sources/ChatFeature/ChatListViewModel.swift`
- Create: `Sources/ChatFeature/ChatListView.swift`
- Create: `Tests/ChatFeatureTests/ChatListViewModelTests.swift`
- Delete: `Sources/ChatFeature/Placeholder.swift`
- Modify: `Project.swift` — add `ChatFeatureTests` target

**Interfaces:**
- Consumes: `APIClient` (NetworkingKit); `ChatSummary` (Models).
- Produces: `public struct ChatListView: View { public init(apiClient: APIClient, onSelectChat: @escaping (String) -> Void, onNewChat: @escaping (String) -> Void) }` — `onSelectChat`/`onNewChat` hand a chat id up to whatever owns navigation (Task 10's `RootView`), keeping `ChatFeature` itself free of any `PhilharmonicFeature`/`SettingsFeature` knowledge.

**Controller rulings baked into this task** (found by checking the plan's original list against the desktop server and a real user flow; each has a test below):

1. **Cancellation is not an error.** SwiftUI cancels a view's `.task` (and an interrupted `.refreshable`) when the view goes away, and the in-flight `URLSession` call then throws `URLError(.cancelled)` / `CancellationError`. The original `load()` put that in `errorMessage`, so tapping into a chat while the list was still loading showed a "cancelled" alert the next time the user came back. `load()` and `delete(_:)` swallow cancellation silently.
2. **A failed load is not an empty list.** With the server unreachable the original view showed "No chats yet" behind the alert. `loadFailed` distinguishes the two; the view shows a "Can't load chats" state with a Retry button, and a failed *re*load keeps the chats already on screen.
3. **The row shows how long ago the chat was created.** Spec §5 says "relative-updated-time", but `GET /api/history` returns raw `chat` rows (`getAllChats`, `src/main/lib/db/queries.ts:60`) and that table has only `createdAt`, no `updatedAt`, so created-time is all the server can give. Rows keep the server's order (`desc(createdAt)`). The original showed the raw ISO string.
4. **`GET /api/history` with no `projectId` returns ALL chats, project chats included** (`queries.ts:69`). The MVP list shows them as they come.
5. User-facing errors are `error.localizedDescription` (for `HTTPError` that is the server's message), as in Task 7.
6. `chats` is `private(set)`: tests fill the list by loading through the mock, not by assigning to it.

Swift 6 notes for the tests below: the view model is `@MainActor`, so the suite is `@MainActor`; the mock handler runs on a URLProtocol thread, so requests are recorded behind a `Mutex` and asserted afterwards — never with `#expect` inside a handler (it can silently never run) and never with a captured `var`. `-only-testing:` takes the Swift TYPE name (`ChatFeatureTests/ChatListViewModelTests`); a wrong name matches nothing yet reports success with 0 tests, so check that a green run reports N > 0. If you still hit a Swift 6 diagnostic, fix it minimally and record it in the report; never lower `SWIFT_VERSION` and never weaken an assertion.

- [ ] **Step 1: Add the `ChatFeatureTests` target to `Project.swift`**

Add after `moduleTarget(name: "ChatFeature", ...)`:

```swift
        .target(
            name: "ChatFeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).ChatFeatureTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/ChatFeatureTests"],
            dependencies: [
                .target(name: "ChatFeature"), .target(name: "NetworkingKit"), .target(name: "Models")
            ]
        ),
```

Run: `tuist generate --no-open`

- [ ] **Step 2: Write the failing tests**

`Tests/ChatFeatureTests/ChatListViewModelTests.swift` (same small per-target `MockURLProtocol` duplication rationale as Task 7):

```swift
import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

private final class ChatListMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatListMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// The handler runs on a URLProtocol thread, so the requests it sees are recorded behind a
/// lock and asserted from the test afterwards.
private final class RequestRecorder: Sendable {
    private let storage = Mutex<[String]>([])
    func record(_ line: String) { storage.withLock { $0.append(line) } }
    var requests: [String] { storage.withLock { $0 } }
}

private let twoChatsJSON = #"""
    [{"id":"c1","title":"Trip planning","createdAt":"2026-09-18T00:00:00.000Z","favorite":false,"projectId":null},
     {"id":"c2","title":"New chat","createdAt":"2026-09-17T00:00:00.000Z","favorite":null,"projectId":"p1"}]
    """#

private let serverErrorJSON =
    #"{"type":"error","error":{"code":"DB_QUERY_FAILED","message":"Failed to get chat history"}}"#

/// Answers `GET /api/history` and `DELETE /api/chat/<id>`, recording "METHOD path" for every request.
private func serve(
    history: String = "[]",
    historyStatus: Int = 200,
    deleteStatus: Int = 200,
    deleteBody: String = #"{"success":true}"#,
    recorder: RequestRecorder
) {
    ChatListMockURLProtocol.handler = { request in
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        recorder.record("\(method) \(path)")
        if method == "GET", path == "/api/history" {
            return (historyStatus, Data(history.utf8))
        }
        if method == "DELETE", path.hasPrefix("/api/chat/") {
            return (deleteStatus, Data(deleteBody.utf8))
        }
        return (404, Data(#"{"type":"error","error":{"code":"NOT_FOUND","message":"no route"}}"#.utf8))
    }
}

@MainActor
@Suite("ChatListViewModel", .serialized)
struct ChatListViewModelTests {
    private func makeViewModel(_ suite: String = #function) -> ChatListViewModel {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let client = APIClient(session: ChatListMockURLProtocol.makeSession(), serverConfig: config)
        return ChatListViewModel(apiClient: client)
    }

    @Test("load() fills the list from GET /api/history, in the server's order")
    func loadPopulatesChatsInServerOrder() async throws {
        let recorder = RequestRecorder()
        serve(history: twoChatsJSON, recorder: recorder)
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.chats[0].title == "Trip planning")
        #expect(recorder.requests == ["GET /api/history"])
        #expect(vm.errorMessage == nil)
        #expect(vm.loadFailed == false)
    }

    @Test("delete(_:) sends DELETE /api/chat/<id> and removes only that chat after it succeeds")
    func deleteRemovesChatAfterSuccessfulDelete() async throws {
        let recorder = RequestRecorder()
        serve(history: twoChatsJSON, recorder: recorder)
        let vm = makeViewModel()
        await vm.load()
        await vm.delete(vm.chats[0])
        #expect(recorder.requests == ["GET /api/history", "DELETE /api/chat/c1"])
        #expect(vm.chats.map(\.id) == ["c2"])
        #expect(vm.errorMessage == nil)
    }

    @Test("a failed delete keeps the chat in the list and shows the server's message")
    func failedDeleteKeepsTheChat() async throws {
        serve(
            history: twoChatsJSON,
            deleteStatus: 500,
            deleteBody: #"{"type":"error","error":{"code":"DB_QUERY_FAILED","message":"Failed to delete chat"}}"#,
            recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        await vm.delete(vm.chats[0])
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.errorMessage == "Failed to delete chat")
    }

    @Test("a failed load surfaces the server's message and is marked as a failure, not an empty list")
    func loadSurfacesError() async throws {
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.errorMessage == "Failed to get chat history")
        #expect(vm.loadFailed)
        #expect(vm.chats.isEmpty)
    }

    @Test("a failed reload keeps the chats already on screen")
    func failedReloadKeepsExistingChats() async throws {
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        await vm.load()
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.errorMessage == "Failed to get chat history")
        #expect(vm.loadFailed)
    }

    @Test("a successful reload clears the failure state")
    func successfulReloadClearsFailure() async throws {
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.loadFailed)
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        await vm.load()
        #expect(vm.loadFailed == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.chats.count == 2)
    }

    @Test("a cancelled load or delete is not shown as an error")
    func cancellationIsNotAnError() async throws {
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()

        ChatListMockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        await vm.load()
        #expect(vm.errorMessage == nil)
        #expect(vm.loadFailed == false)
        #expect(vm.chats.count == 2)

        await vm.delete(vm.chats[0])
        #expect(vm.errorMessage == nil)
        #expect(vm.chats.count == 2)
    }

    @Test("a transport failure is shown as a human message, not a URLError dump")
    func transportErrorUsesAHumanMessage() async throws {
        ChatListMockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let vm = makeViewModel()
        await vm.load()
        let message = try #require(vm.errorMessage)
        #expect(message == URLError(.cannotConnectToHost).localizedDescription)
        // A bare in-process URLError describes itself as "(NSURLErrorDomain error -1004.)"; the
        // dump form (`String(describing:)`) contains "Domain=" and must not reach the user.
        #expect(message.contains("Domain=") == false)
        #expect(vm.loadFailed)
    }

    @Test("relative time is human-readable, handles fractional and plain ISO strings, and falls back to the raw text")
    func relativeTimeIsHumanReadable() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-20T00:00:00Z"))
        let en = Locale(identifier: "en_US")
        #expect(ChatListViewModel.relativeTime(forCreatedAt: "2026-09-18T00:00:00.000Z", now: now, locale: en) == "2 days ago")
        #expect(ChatListViewModel.relativeTime(forCreatedAt: "2026-09-19T21:00:00Z", now: now, locale: en) == "3 hours ago")
        #expect(ChatListViewModel.relativeTime(forCreatedAt: "not a date", now: now, locale: en) == "not a date")
    }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: build failure — `ChatListViewModel` doesn't exist yet.

- [ ] **Step 4: Implement `ChatListViewModel.swift`**

```swift
import Foundation
import Models
import NetworkingKit
import Observation

@MainActor
@Observable
public final class ChatListViewModel {
    public private(set) var chats: [ChatSummary] = []
    public private(set) var isLoading = false
    /// True when the last load failed — lets the view tell "couldn't load" from "no chats yet".
    public private(set) var loadFailed = false
    public var errorMessage: String?

    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            chats = try await apiClient.get("/api/history")
            loadFailed = false
        } catch {
            // SwiftUI cancels a view's `.task` when the view goes away; that is not a failure.
            guard !Self.isCancellation(error) else { return }
            loadFailed = true
            errorMessage = error.localizedDescription
        }
    }

    public func delete(_ chat: ChatSummary) async {
        do {
            try await apiClient.delete("/api/chat/\(chat.id)")
            chats.removeAll { $0.id == chat.id }
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// The server's chat list carries only `createdAt` (the `chat` table has no `updatedAt`),
    /// so a row shows how long ago the chat was created. Accepts ISO-8601 with or without
    /// fractional seconds; anything else is returned unchanged.
    public nonisolated static func relativeTime(
        forCreatedAt iso: String, now: Date = .now, locale: Locale = .current
    ) -> String {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = withFraction.date(from: iso) ?? plain.date(from: iso) else { return iso }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Implement `ChatListView.swift`**

```swift
import Models
import NetworkingKit
import SwiftUI

public struct ChatListView: View {
    @State private var viewModel: ChatListViewModel
    private let onSelectChat: (String) -> Void
    private let onNewChat: (String) -> Void

    public init(apiClient: APIClient, onSelectChat: @escaping (String) -> Void, onNewChat: @escaping (String) -> Void) {
        _viewModel = State(initialValue: ChatListViewModel(apiClient: apiClient))
        self.onSelectChat = onSelectChat
        self.onNewChat = onNewChat
    }

    public var body: some View {
        List {
            ForEach(viewModel.chats) { chat in
                Button {
                    onSelectChat(chat.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chat.title).font(.body)
                        Text(ChatListViewModel.relativeTime(forCreatedAt: chat.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets {
                    let chat = viewModel.chats[index]
                    Task { await viewModel.delete(chat) }
                }
            }
        }
        .overlay {
            if viewModel.chats.isEmpty {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.loadFailed {
                    ContentUnavailableView {
                        Label("Can't load chats", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Pull down or tap Retry to try again.")
                    } actions: {
                        Button("Retry") { Task { await viewModel.load() } }
                    }
                } else {
                    ContentUnavailableView("No chats yet", systemImage: "message")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNewChat(UUID().uuidString.lowercased())
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
```

- [ ] **Step 7: Delete the placeholder, generate, build**

```bash
rm Sources/ChatFeature/Placeholder.swift
tuist generate --no-open
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "generic/platform=iOS Simulator"
```

Expected: `** BUILD SUCCEEDED **`. `ChatListView` isn't reachable from `RootView` yet — that's Task 10.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Add ChatFeature chat list (GET /api/history, delete, new chat)

ChatListViewModel/ChatListView hand chat-id selection up via
callbacks instead of owning navigation, keeping ChatFeature decoupled
from what RootView does with the id.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: ChatFeature — chat detail, composer, streaming

**Files:**
- Create: `Sources/ChatFeature/ChatDetailViewModel.swift`
- Create: `Sources/ChatFeature/ChatDetailView.swift`
- Create: `Sources/ChatFeature/MessageRow.swift`
- Create: `Tests/ChatFeatureTests/ChatDetailViewModelTests.swift`

**Interfaces:**
- Consumes: `APIClient`, `ChatStreamManager`, `ServerConfigStore`, `ChatStatus`, `ChatStreamUpdate` (NetworkingKit); `ChatMessage` (Models).
- Produces: `public struct ChatDetailView: View { public init(chatId: String, apiClient: APIClient, streamManager: ChatStreamManager, serverConfig: ServerConfigStore) }`.

- [ ] **Step 1: Write the failing tests**

`Tests/ChatFeatureTests/ChatDetailViewModelTests.swift` (same per-target `MockURLProtocol` pattern; also exercises `ChatStreamManager` directly since it's a real, cheap-to-construct actor, not something worth re-mocking):

```swift
import Foundation
import Models
import NetworkingKit
import Testing

@testable import ChatFeature

private final class ChatDetailMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var streamChunks: [Data]?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let chunks = Self.streamChunks {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatDetailMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

@Suite("ChatDetailViewModel", .serialized)
struct ChatDetailViewModelTests {
    private func makeViewModel(chatId: String = "c1") -> ChatDetailViewModel {
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let session = ChatDetailMockURLProtocol.makeSession()
        let apiClient = APIClient(session: session, serverConfig: config)
        let streamManager = ChatStreamManager(sseClient: SSEClient(session: session))
        return ChatDetailViewModel(chatId: chatId, apiClient: apiClient, streamManager: streamManager, serverConfig: config)
    }

    @Test("loadHistory populates messages from GET /api/chat/:id")
    func loadHistoryPopulatesMessages() async throws {
        ChatDetailMockURLProtocol.streamChunks = nil
        ChatDetailMockURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/chat/c1")
            let json = """
                [{"id":"u1","role":"user","content":"hi"},{"id":"a1","role":"assistant","content":"hello"}]
                """.data(using: .utf8)!
            return (200, json)
        }
        let vm = makeViewModel()
        await vm.loadHistory()
        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.displayText == "hello")
    }

    @Test("sendMessage appends the user message immediately, then streams the assistant reply to completion")
    func sendMessageStreamsToCompletion() async throws {
        ChatDetailMockURLProtocol.handler = nil
        let sse = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"Hel"}}\n\n\
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"Hello!"}}\n\n\
            data: {"type":"done","messages":[{"id":"u1","role":"user","content":"hi"},{"id":"a1","role":"assistant","content":"Hello!"}]}\n\n
            """
        ChatDetailMockURLProtocol.streamChunks = [Data(sse.utf8)]

        let vm = makeViewModel()
        vm.composerText = "hi"
        await vm.sendMessage()

        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.displayText == "Hello!")
        #expect(vm.status == .idle)
        #expect(vm.composerText.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "platform=iOS Simulator,name=iPhone 17" -only-testing ChatFeatureTests/ChatDetailViewModelTests`
Expected: build failure — `ChatDetailViewModel` doesn't exist yet.

- [ ] **Step 3: Implement `ChatDetailViewModel.swift`**

```swift
import Foundation
import Models
import NetworkingKit
import Observation

@MainActor
@Observable
public final class ChatDetailViewModel {
    public let chatId: String
    public var messages: [ChatMessage] = []
    public var status: ChatStatus = .idle
    public var composerText: String = ""
    public var chatTitle: String?
    public var errorMessage: String?

    private let apiClient: APIClient
    private let streamManager: ChatStreamManager
    private let serverConfig: ServerConfigStore

    public init(chatId: String, apiClient: APIClient, streamManager: ChatStreamManager, serverConfig: ServerConfigStore) {
        self.chatId = chatId
        self.apiClient = apiClient
        self.streamManager = streamManager
        self.serverConfig = serverConfig
    }

    public func onAppear() async {
        if await streamManager.isStreaming(chatId), let updates = await streamManager.attach(chatId) {
            status = .streaming
            await consume(updates)
        } else {
            await loadHistory()
        }
    }

    public func loadHistory() async {
        do {
            messages = try await apiClient.get("/api/chat/\(chatId)")
        } catch {
            errorMessage = (error as? HTTPError)?.message ?? String(describing: error)
        }
    }

    public func sendMessage() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""

        let userMessage = ChatMessage.userMessage(
            id: UUID().uuidString.lowercased(), text: text, timestampMs: Date().timeIntervalSince1970 * 1000)
        messages.append(userMessage)

        let updates = await streamManager.send(chatId: chatId, messages: messages, serverConfig: serverConfig)
        await consume(updates)
    }

    private func consume(_ updates: AsyncStream<ChatStreamUpdate>) async {
        for await update in updates {
            switch update {
            case .messages(let messages):
                self.messages = messages
            case .status(let status):
                self.status = status
            case .title(let title):
                chatTitle = title
            case .finished(let messages):
                self.messages = messages
                status = .idle
            case .failed(let message):
                errorMessage = message
                status = .error
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: `** TEST SUCCEEDED **`, every ChatFeature test (Task 8 + this task) passes.

- [ ] **Step 5: Implement `MessageRow.swift`**

```swift
import Models
import SwiftUI

struct MessageRow: View {
    let message: ChatMessage

    /// Basic Markdown only (bold/italic/inline code/lists) via Foundation's
    /// built-in parser — no syntax highlighting, no Mermaid, no math, per the
    /// spec's explicit MVP scope. Falls back to the raw string if parsing
    /// fails rather than dropping the message.
    private static func renderedText(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    var body: some View {
        switch message.role {
        case "user":
            HStack {
                Spacer(minLength: 40)
                Text(Self.renderedText(message.displayText))
                    .padding(10)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case "assistant":
            HStack {
                Text(message.displayText.isEmpty ? AttributedString("…") : Self.renderedText(message.displayText))
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 40)
            }
        case "toolResult":
            HStack(spacing: 6) {
                Image(systemName: message.isError ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(message.isError ? .red : .secondary)
                Text("Used: \(message.toolName ?? "tool")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        default:
            EmptyView()
        }
    }
}
```

- [ ] **Step 6: Implement `ChatDetailView.swift`**

```swift
import Models
import NetworkingKit
import SwiftUI

public struct ChatDetailView: View {
    @State private var viewModel: ChatDetailViewModel

    public init(chatId: String, apiClient: APIClient, streamManager: ChatStreamManager, serverConfig: ServerConfigStore) {
        _viewModel = State(
            initialValue: ChatDetailViewModel(
                chatId: chatId, apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig))
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(message: message).id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .onChange(of: viewModel.messages.count) {
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack {
                TextField("Message", text: $viewModel.composerText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(
                    viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.status == .submitted || viewModel.status == .streaming)
            }
            .padding()
        }
        .navigationTitle(viewModel.chatTitle ?? "New Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
```

- [ ] **Step 7: Build the whole workspace**

```bash
tuist generate --no-open
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "generic/platform=iOS Simulator"
```

Expected: `** BUILD SUCCEEDED **`. `ChatDetailView` isn't reachable from `RootView` yet — that's Task 10.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Add ChatFeature chat detail: history load, streaming send, composer

ChatDetailViewModel re-attaches to an in-flight ChatStreamManager
stream on appear instead of always re-fetching, so leaving and
returning to a chat mid-response doesn't lose progress. MessageRow
renders user/assistant bubbles and a generic "Used: toolName" row for
tool results, per the MVP scope (no per-tool rich cards).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: App shell — workspace switcher, real navigation, final Info.plist review

**Files:**
- Modify: `Sources/App/RootView.swift` — replace the Task 7 throwaway body with real navigation
- Create: `Sources/App/AppWorkspace.swift`
- Modify: `Sources/App/ExodusApp.swift` — construct the shared `APIClient`/`ChatStreamManager`/`ServerConfigStore` once

**Interfaces:**
- Consumes: `ChatListView`, `ChatDetailView` (ChatFeature); `SettingsView` (SettingsFeature); `PhilharmonicPlaceholderView` (PhilharmonicFeature); `APIClient`, `ChatStreamManager`, `ServerConfigStore` (NetworkingKit).
- Produces: the final `RootView` — no later task modifies it.

- [ ] **Step 1: Implement `AppWorkspace.swift`**

```swift
enum AppWorkspace: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case philharmonic = "Philharmonic"

    var id: String { rawValue }
    var isAvailable: Bool { self == .chat }
}
```

- [ ] **Step 2: Replace `Sources/App/RootView.swift`**

```swift
import ChatFeature
import NetworkingKit
import PhilharmonicFeature
import SettingsFeature
import SwiftUI

struct RootView: View {
    let apiClient: APIClient
    let streamManager: ChatStreamManager
    let serverConfig: ServerConfigStore

    @State private var workspace: AppWorkspace = .chat
    @State private var path: [String] = []
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch workspace {
                case .chat:
                    ChatListView(
                        apiClient: apiClient,
                        onSelectChat: { chatId in path.append(chatId) },
                        onNewChat: { chatId in path.append(chatId) }
                    )
                case .philharmonic:
                    PhilharmonicPlaceholderView()
                }
            }
            .navigationDestination(for: String.self) { chatId in
                ChatDetailView(
                    chatId: chatId, apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(AppWorkspace.allCases) { option in
                            Button {
                                workspace = option
                            } label: {
                                if option == workspace {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else if option.isAvailable {
                                    Text(option.rawValue)
                                } else {
                                    Text("\(option.rawValue)(即将支持)")
                                }
                            }
                            .disabled(!option.isAvailable && option != workspace)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(workspace.rawValue).font(.headline)
                            Image(systemName: "chevron.down").font(.caption)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(apiClient: apiClient, serverConfig: serverConfig)
        }
    }
}
```

- [ ] **Step 3: Update `Sources/App/ExodusApp.swift`**

```swift
import NetworkingKit
import SwiftUI

@main
struct ExodusApp: App {
    private let serverConfig: ServerConfigStore
    private let apiClient: APIClient
    private let streamManager: ChatStreamManager

    init() {
        let config = ServerConfigStore()
        serverConfig = config
        apiClient = APIClient(serverConfig: config)
        streamManager = ChatStreamManager()
    }

    var body: some Scene {
        WindowGroup {
            RootView(apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig)
        }
    }
}
```

- [ ] **Step 4: Build**

```bash
tuist generate --no-open
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "generic/platform=iOS Simulator"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manually verify the workspace switcher and navigation in the Simulator**

```bash
xcodebuild build \
  -workspace ExodusIos.xcworkspace \
  -scheme App \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath /tmp/exodus-ios-dd
xcrun simctl install booted /tmp/exodus-ios-dd/Build/Products/Debug-iphonesimulator/Exodus.app
xcrun simctl launch booted app.yancey.exodus.exodus-ios
```

In the Simulator: confirm the nav bar title reads "Chat" with a chevron; tapping it shows a menu with "Chat" (checked) and "Philharmonic(即将支持)" (disabled); tapping the gear icon opens Settings as a sheet; tapping "New Chat" pushes into an empty `ChatDetailView`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Wire the App composition root: workspace switcher + real navigation

RootView now owns the single shared APIClient/ChatStreamManager/
ServerConfigStore instances and composes ChatFeature/SettingsFeature/
PhilharmonicFeature — neither feature module knows the others exist.
The nav-bar title is a native Menu switching between Chat and a
disabled Philharmonic placeholder, mirroring desktop's
workspace-switcher.tsx.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: End-to-end manual verification

**Files:** none (verification only).

**Interfaces:** none — this task consumes the finished app as a whole.

- [ ] **Step 1: Start the desktop dev server**

In `../universal-client`: `pnpm dev`. Confirm it logs the Hono server listening on port 60223.

- [ ] **Step 2: Run the full test suite one more time**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "platform=iOS Simulator,name=iPhone 17"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme NetworkingKit -destination "platform=iOS Simulator,name=iPhone 17"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme SettingsFeature -destination "platform=iOS Simulator,name=iPhone 17"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "platform=iOS Simulator,name=iPhone 17"
```

Expected: `** TEST SUCCEEDED **` on all four.

- [ ] **Step 3: Fresh install and manual walkthrough**

```bash
xcrun simctl uninstall booted app.yancey.exodus.exodus-ios || true
xcodebuild build \
  -workspace ExodusIos.xcworkspace \
  -scheme App \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath /tmp/exodus-ios-dd
xcrun simctl install booted /tmp/exodus-ios-dd/Build/Products/Debug-iphonesimulator/Exodus.app
xcrun simctl launch booted app.yancey.exodus.exodus-ios
```

Walk through, on a fresh install (no prior UserDefaults state, so Server URL defaults to `http://localhost:60223`):

1. Tap the gear icon → Settings → confirm the Server URL field already shows `http://localhost:60223`.
2. Pick a provider you have a real API key for, paste the key, tap "Refresh model list", confirm real models appear, pick one, tap Save. Confirm the sheet dismisses with no error.
3. Back on the chat list, tap "New Chat", type a message, send it. Confirm: the user bubble appears immediately; the assistant bubble fills in as it streams (not all at once); the nav title updates from "New Chat" to a real generated title once the turn completes.
4. Navigate back to the chat list (confirm the new chat now appears there with the generated title), then back into the same chat (confirm the full conversation reloads via `GET /api/chat/:id`).
5. Start a second message, and while it's still streaming, navigate back to the chat list and immediately back into the chat — confirm the in-progress response is still there and keeps streaming to completion (this is the `ChatStreamManager.attach` behavior from Task 6/9 — the one behavior that can't be caught by any unit test, since it depends on real SwiftUI view lifecycle timing).
6. Swipe-to-delete that chat from the list. Confirm it disappears and (checking the desktop app or its DB) is actually gone server-side, not just hidden locally.
7. Tap the workspace switcher title, confirm "Philharmonic(即将支持)" is visible but disabled and does nothing when tapped.

- [ ] **Step 4: Note any findings**

If anything in Step 3 doesn't match, that's a real bug to fix before considering this plan done — file it as a follow-up task rather than silently patching around it, since every prior task's automated tests already passed and a manual-only failure here means a gap in what those tests covered.

This task has no commit of its own — it either confirms Tasks 1-10 are done, or surfaces a specific regression to fix (with its own commit) before the plan is complete.
