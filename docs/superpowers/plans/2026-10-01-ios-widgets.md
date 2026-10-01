# iPhone Widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home Screen (small, medium), Lock Screen (circular, rectangular) widgets and a Control Center / Action button control that open a conversation with Exodus, with a light touch of today's health, drawn in the Health hero's night sky.

**Architecture:** The app writes a small `WidgetSnapshot` JSON (3 recent chat titles, today's health glance) into an App Group container and asks WidgetKit to reload; the extension only reads and renders it — no network, no credentials. Taps open `exodus://` deep links that `AppShell` routes. Pure logic (snapshot, store, links, presentation rules) lives in `WidgetKitShared`; the SwiftUI widget views live in `WidgetUI`, so the app's DEBUG gallery can draw them too.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, AppIntents (`ControlWidgetButton`, `OpenURLIntent`), Tuist 4 (buildable folders), Swift Testing, iOS 27.

**Spec:** `docs/superpowers/specs/2026-10-01-ios-widgets-design.md` (amended in Task 1: the health suggestion opens Health's ask box, `exodus://health?ask=…`).

## Global Constraints

- Deployment target iOS 27.0; Swift 6 language mode; no third-party dependencies.
- App Group: `group.app.yancey.exodus`. URL scheme: `exodus`. Extension bundle id: `app.yancey.exodus.exodus-ios.widgets`.
- The extension links only `WidgetKitShared`, `WidgetUI`, `OdyKit` — never `NetworkingKit`, never the keychain.
- Snapshot file `widget.json`, written atomically with `.completeFileProtectionUntilFirstUserAuthentication`; titles and summary numbers only, never message content; at most 3 recent chats.
- A pre-filled question is never sent automatically.
- Prompt in a link: at most 500 characters; anything longer, or an unknown link, is ignored.
- Health numbers are shown only when the glance's `day` is the entry's own day.
- Chat titles and health numbers are `.privacySensitive()`.
- Strings: keys `ios:widget.*` in `Resources/App/Localizable.xcstrings` (one catalog, shared with the extension), all 10 languages via `scripts/l10n.py add` / `fill`; `python3 scripts/l10n.py audit` must report 0 errors. Non-view code passes `defaultValue:` (README: hostless tests).
- Commits only via `.superpowers/sdd/commit-mine.sh` (the tree holds the user's uncommitted edits — check `git diff <file>` before editing; files with foreign hunks go in as `--patch`). Never push.
- Simulator for builds/tests: `D8A2BE45-88F3-46AE-8693-B147F2815724` (iPhone 17e, iOS 27), `-derivedDataPath /tmp/md-dd`. After changing `Project.swift`, run `tuist generate --no-open` before building.

## Review Focus

1. **Snapshot from a newer app version or half-written file** — the widget shows the empty state, never crashes (Task 1 test: `version: 99` and truncated JSON decode to empty).
2. **Health glance from yesterday after midnight** — at 00:30 the widget hides the health line instead of showing last night's numbers as today's (Task 3 test: entry on the next day hides health).
3. **A link arriving while the unlock / pairing gate is up** — it is kept and applied once `AppShell` appears, not dropped (Task 5: `ExodusApp` holds `pendingLink` and passes it in; test on `PendingLink.take()`).
4. **Prompt with spaces, `&`, `#`, CJK or emoji** — round-trips through the link intact (Task 2 test).
5. **Unpairing** — recent chat titles from the old computer disappear from the Home Screen (Task 4 test: `cleared()` empties recents and health; wiring through `onComputerChange`).

---

## File Structure

| Path | Responsibility |
|---|---|
| `Sources/WidgetKitShared/WidgetSnapshot.swift` | `WidgetSnapshot`, `RecentChat`, `HealthGlance`, `WidgetMood`; tolerant decoding; `updating(recents:)` / `updating(health:)` / `cleared()` |
| `Sources/WidgetKitShared/SnapshotStore.swift` | Read/write `widget.json` in a directory (App Group container in production) |
| `Sources/WidgetKitShared/DeepLink.swift` | `DeepLink` enum, `url`, `init?(url:)` |
| `Sources/WidgetKitShared/WidgetPresentation.swift` | Greeting period, ink (light/dark text on the sky), visible health for a date, hourly entry dates |
| `Sources/WidgetKitShared/AskExodusIntent.swift` | `AppIntent` that opens `exodus://chat/new` (used by the control; linked by app and extension) |
| `Tests/WidgetKitSharedTests/*.swift` | Unit tests for the above |
| `Sources/WidgetUI/*.swift` | `WidgetSky`, `AskSmallView`, `AskMediumView`, `AskCircularView`, `TodayRectangularView` |
| `Widgets/Sources/*.swift` | Extension: `ExodusWidgetBundle`, `SnapshotProvider`, `AskWidget`, `TodayAccessoryWidget`, `AskControl` |
| `Widgets/Info.plist` | `NSExtension` → `com.apple.widgetkit-extension` |
| `Sources/App/WidgetSnapshotWriter.swift` | App side: applies changes to the store, reloads timelines when the snapshot changed |
| `Sources/App/WidgetGallery.swift` | DEBUG `-WidgetGallery` page drawing every family on fixtures |
| `Project.swift` | New targets, App Group entitlements, URL scheme |
| `Sources/App/ExodusApp.swift`, `Sources/App/AppShell.swift` | `.onOpenURL`, pending link, routing |
| `Sources/ChatFeature/ChatSidebarView.swift`, `ChatDetailView.swift`, `ChatDetailViewModel.swift` | Recents callback; `initialDraft` pre-fill |
| `Sources/HealthFeature/UI/HealthRootView.swift`, `HealthHomeView.swift`, `AskComposer.swift`, `Report/HealthHomeModel.swift` | `widgetGlance`, glance callback, `initialAsk` pre-fill |

---

### Task 1: `WidgetKitShared` — snapshot and store

**Files:**
- Modify: `Project.swift` (add `WidgetKitShared` module + `WidgetKitSharedTests`)
- Modify: `docs/superpowers/specs/2026-10-01-ios-widgets-design.md` (§2.4 / §3.2 amendment)
- Create: `Sources/WidgetKitShared/WidgetSnapshot.swift`, `Sources/WidgetKitShared/SnapshotStore.swift`
- Test: `Tests/WidgetKitSharedTests/WidgetSnapshotTests.swift`

**Interfaces:**
- Produces:
  - `public struct WidgetSnapshot: Codable, Equatable, Sendable { public static let currentVersion = 1; public var version: Int; public var updatedAt: Date; public var recentChats: [RecentChat]; public var health: HealthGlance?; public static let empty: WidgetSnapshot; public func updating(recents: [RecentChat], at: Date) -> WidgetSnapshot; public func updating(health: HealthGlance?, at: Date) -> WidgetSnapshot; public func cleared(at: Date) -> WidgetSnapshot }`
  - `public struct RecentChat: Codable, Equatable, Sendable, Identifiable { public var id: String; public var title: String; public var updatedAt: Date }`
  - `public struct HealthGlance: Codable, Equatable, Sendable { public var day: String; public var sleepMinutes: Int?; public var steps: Int?; public var stepGoal: Int?; public var headline: String?; public var suggestion: String?; public var mood: WidgetMood }`
  - `public enum WidgetMood: String, Codable, Sendable { case sleepy, happy, neutral }`
  - `public struct SnapshotStore: Sendable { public init(directory: URL); public static func appGroup() -> SnapshotStore?; public var fileURL: URL; public func load() -> WidgetSnapshot; public func save(_: WidgetSnapshot) throws }`
  - `public enum WidgetGroup { public static let identifier = "group.app.yancey.exodus" }`

- [ ] **Step 1: Amend the spec**

In `docs/superpowers/specs/2026-10-01-ios-widgets-design.md`, §2.4 table: replace the `exodus://chat/new?prompt=<text>` row's text with "Same, composer pre-filled; never sent automatically." and add a row `exodus://health?ask=<text>` → "Health workspace, its ask box pre-filled; today's data attached as Health's ask attaches it (per consent); never sent automatically." In §3.2 replace `(→ chat/new?prompt=…&health=1)` with `(→ health?ask=…)`. Add under the header: `Amended 2026-10-01 (plan): the health suggestion opens Health's ask box, which already attaches the day and never auto-sends.`

- [ ] **Step 2: Add targets to `Project.swift`**

After `moduleTarget(name: "OdyKit"),` add:

```swift
        moduleTarget(name: "WidgetKitShared"),
        .target(
            name: "WidgetKitSharedTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).WidgetKitSharedTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/WidgetKitSharedTests"],
            dependencies: [.target(name: "WidgetKitShared")]
        ),
```

Add `.target(name: "WidgetKitShared")` to the App target's dependencies. Run `tuist generate --no-open`.

- [ ] **Step 3: Write the failing tests**

`Tests/WidgetKitSharedTests/WidgetSnapshotTests.swift`:

```swift
import Foundation
import Testing

@testable import WidgetKitShared

@Suite("WidgetSnapshot and its store")
struct WidgetSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func store() throws -> SnapshotStore {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SnapshotStore(directory: dir)
    }

    private let glance = HealthGlance(
        day: "2026-10-01", sleepMinutes: 352, steps: 1251, stepGoal: 8000, headline: "Take it easy",
        suggestion: "Why do I feel tired today?", mood: .sleepy)

    @Test("a snapshot written is the snapshot read")
    func roundTrip() throws {
        let store = try store()
        let snapshot = WidgetSnapshot.empty
            .updating(recents: [RecentChat(id: "a", title: "Swift 6", updatedAt: now)], at: now)
            .updating(health: glance, at: now)
        try store.save(snapshot)
        #expect(store.load() == snapshot)
    }

    @Test("no file, a half-written file or a newer version reads as empty")
    func tolerant() throws {
        let store = try store()
        #expect(store.load() == .empty)
        try Data("{\"version\":1,\"updatedAt\":".utf8).write(to: store.fileURL)
        #expect(store.load() == .empty)
        try Data("{\"version\":99,\"updatedAt\":0,\"recentChats\":[]}".utf8).write(to: store.fileURL)
        #expect(store.load() == .empty)
    }

    @Test("recents keep the newest three; health can be set and taken away; clearing forgets both")
    func updates() {
        let chats = (0..<5).map { RecentChat(id: "\($0)", title: "t\($0)", updatedAt: now.addingTimeInterval(Double($0))) }
        let snapshot = WidgetSnapshot.empty.updating(recents: chats, at: now).updating(health: glance, at: now)
        #expect(snapshot.recentChats.map(\.id) == ["4", "3", "2"])
        #expect(snapshot.updating(health: nil, at: now).health == nil)
        let cleared = snapshot.cleared(at: now)
        #expect(cleared.recentChats.isEmpty && cleared.health == nil)
    }

    @Test("a title is trimmed and an empty one is skipped")
    func titles() {
        let chats = [
            RecentChat(id: "a", title: "  Plan  ", updatedAt: now), RecentChat(id: "b", title: " ", updatedAt: now),
        ]
        #expect(WidgetSnapshot.empty.updating(recents: chats, at: now).recentChats.map(\.title) == ["Plan"])
    }
}
```

- [ ] **Step 4: Run to verify it fails**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme WidgetKitShared -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/md-dd 2>&1 | grep -E "error:|Test run with"`
Expected: build error, `cannot find 'WidgetSnapshot' in scope`. (If the scheme has no test action, use `-scheme WidgetKitSharedTests`.)

- [ ] **Step 5: Implement**

`Sources/WidgetKitShared/WidgetSnapshot.swift`:

```swift
import Foundation

/// The App Group the app and its widgets share.
public enum WidgetGroup {
    public static let identifier = "group.app.yancey.exodus"
}

/// Ody's face on a widget, decided by the app from the day.
public enum WidgetMood: String, Codable, Sendable {
    case sleepy, happy, neutral
}

public struct RecentChat: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var updatedAt: Date

    public init(id: String, title: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}

/// Today's health in a few numbers: what a widget may show of the day, never more.
public struct HealthGlance: Codable, Equatable, Sendable {
    /// The report's day, `yyyy-MM-dd`: a glance is shown only on that day.
    public var day: String
    public var sleepMinutes: Int?
    public var steps: Int?
    public var stepGoal: Int?
    public var headline: String?
    /// One question about the day, for the medium widget's chip.
    public var suggestion: String?
    public var mood: WidgetMood

    public init(
        day: String, sleepMinutes: Int?, steps: Int?, stepGoal: Int?, headline: String?, suggestion: String?,
        mood: WidgetMood
    ) {
        self.day = day
        self.sleepMinutes = sleepMinutes
        self.steps = steps
        self.stepGoal = stepGoal
        self.headline = headline
        self.suggestion = suggestion
        self.mood = mood
    }
}

/// What the widgets draw: written by the app, read by the extension. Titles and a few numbers, never a message.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    static let maxRecents = 3

    public var version: Int
    public var updatedAt: Date
    public var recentChats: [RecentChat]
    public var health: HealthGlance?

    public init(version: Int = currentVersion, updatedAt: Date, recentChats: [RecentChat], health: HealthGlance?) {
        self.version = version
        self.updatedAt = updatedAt
        self.recentChats = recentChats
        self.health = health
    }

    public static let empty = WidgetSnapshot(updatedAt: Date(timeIntervalSince1970: 0), recentChats: [], health: nil)

    public func updating(recents: [RecentChat], at date: Date) -> WidgetSnapshot {
        var copy = self
        copy.recentChats = Array(
            recents
                .map { RecentChat(id: $0.id, title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines), updatedAt: $0.updatedAt) }
                .filter { !$0.title.isEmpty }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(Self.maxRecents))
        copy.updatedAt = date
        return copy
    }

    public func updating(health: HealthGlance?, at date: Date) -> WidgetSnapshot {
        var copy = self
        copy.health = health
        copy.updatedAt = date
        return copy
    }

    /// Unpaired: nothing of the old computer stays on the Home Screen.
    public func cleared(at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(updatedAt: date, recentChats: [], health: nil)
    }
}
```

`Sources/WidgetKitShared/SnapshotStore.swift`:

```swift
import Foundation

/// `widget.json` in a directory: the App Group container in the app and the extension, a scratch one in tests.
public struct SnapshotStore: Sendable {
    let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// The shared container; nil when the App Group entitlement is missing (a misconfigured build).
    public static func appGroup() -> SnapshotStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetGroup.identifier)
            .map(SnapshotStore.init(directory:))
    }

    public var fileURL: URL { directory.appending(path: "widget.json") }

    /// Missing, unreadable, half-written or from a newer app: the empty snapshot.
    public func load() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
            let snapshot = try? Self.decoder.decode(WidgetSnapshot.self, from: data),
            snapshot.version <= WidgetSnapshot.currentVersion
        else { return .empty }
        return snapshot
    }

    /// Readable once the phone has been unlocked after a restart: the Lock Screen draws it too.
    public func save(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(snapshot)
            .write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
```

- [ ] **Step 6: Run tests to verify they pass**

Same command as Step 4. Expected: `Test run with 4 tests in 1 suite passed`.

- [ ] **Step 7: Commit**

```bash
.superpowers/sdd/commit-mine.sh "feat(widgets): the snapshot the app writes for its widgets, and where it is kept" \
  --patch /tmp/project-task1.patch \
  docs/superpowers/specs/2026-10-01-ios-widgets-design.md Sources/WidgetKitShared Tests/WidgetKitSharedTests
```
(`Project.swift` has no foreign edits at plan time — check `git diff Project.swift`; if it is all yours, pass it as a path instead of `--patch`.)

---

### Task 2: `DeepLink`

**Files:**
- Create: `Sources/WidgetKitShared/DeepLink.swift`
- Test: `Tests/WidgetKitSharedTests/DeepLinkTests.swift`

**Interfaces:**
- Produces: `public enum DeepLink: Equatable, Sendable { case newChat(prompt: String?); case chat(id: String); case health(ask: String?); public static let scheme = "exodus"; public static let maxPrompt = 500; public var url: URL; public init?(url: URL) }`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import WidgetKitShared

@Suite("DeepLink: the widgets' exodus:// links")
struct DeepLinkTests {
    @Test("every link reads back as itself", arguments: [
        DeepLink.newChat(prompt: nil), .newChat(prompt: "Plan my day"), .chat(id: "3f2a-9c"), .health(ask: nil),
        .health(ask: "Why do I feel tired today?"),
        .newChat(prompt: "a & b #c ?d = e / 100% 今天睡得怎么样？ 😴 \n second line"),
    ])
    func roundTrip(link: DeepLink) throws {
        #expect(DeepLink(url: link.url) == link)
    }

    @Test("the links are the documented ones")
    func shapes() {
        #expect(DeepLink.newChat(prompt: nil).url.absoluteString == "exodus://chat/new")
        #expect(DeepLink.chat(id: "abc").url.absoluteString == "exodus://chat/abc")
        #expect(DeepLink.health(ask: nil).url.absoluteString == "exodus://health")
    }

    @Test("anything else is not a link", arguments: [
        "https://chat/new", "exodus://", "exodus://chat", "exodus://chat/", "exodus://settings",
        "exodus://chat/a/b", "exodus://health/x",
    ])
    func rejects(string: String) throws {
        #expect(DeepLink(url: try #require(URL(string: string))) == nil)
    }

    @Test("an empty prompt is no prompt; one over 500 characters is not a link")
    func prompts() throws {
        #expect(DeepLink(url: try #require(URL(string: "exodus://chat/new?prompt="))) == .newChat(prompt: nil))
        let long = DeepLink.newChat(prompt: String(repeating: "a", count: 501)).url
        #expect(DeepLink(url: long) == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — same command as Task 1 Step 4; expected `cannot find 'DeepLink'`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The links a widget opens the app with. Anything else — another scheme, an unknown path, a prompt too long — is not
/// a link, and the app ignores it.
public enum DeepLink: Equatable, Sendable {
    /// A fresh chat, its composer pre-filled when there is a prompt. Never sent by itself.
    case newChat(prompt: String?)
    case chat(id: String)
    /// Health, its ask box pre-filled when there is a question.
    case health(ask: String?)

    public static let scheme = "exodus"
    public static let maxPrompt = 500

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .newChat(let prompt):
            parts.host = "chat"
            parts.path = "/new"
            parts.queryItems = prompt.map { [URLQueryItem(name: "prompt", value: $0)] }
        case .chat(let id):
            parts.host = "chat"
            parts.path = "/" + id
        case .health(let ask):
            parts.host = "health"
            parts.queryItems = ask.map { [URLQueryItem(name: "ask", value: $0)] }
        }
        // `URLQueryItem` leaves `&`, `=`, `+` and `?` alone inside a value; they are escaped here so the value
        // reads back whole.
        parts.percentEncodedQuery = parts.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        func query(_ name: String) -> String?? {
            let value = parts.queryItems?.first { $0.name == name }?.value
            guard let value, !value.isEmpty else { return .some(nil) }
            return value.count > Self.maxPrompt ? nil : .some(value)
        }
        switch (parts.host, path) {
        case ("chat", ["new"]):
            guard let prompt = query("prompt") else { return nil }
            self = .newChat(prompt: prompt)
        case ("chat", let path) where path.count == 1:
            self = .chat(id: path[0])
        case ("health", []):
            guard let ask = query("ask") else { return nil }
            self = .health(ask: ask)
        default:
            return nil
        }
    }
}
```

Note for the implementer: `URLComponents.queryItems` percent-encodes `&` and `=` inside values but not `+`; the replacement above covers `+`. If the round-trip test still fails on a character, encode the value with `addingPercentEncoding(withAllowedCharacters: .alphanumerics)` and set `percentEncodedQueryItems` instead — the test is the contract.

- [ ] **Step 4: Run tests** — expected all `DeepLinkTests` pass.

- [ ] **Step 5: Commit**

```bash
.superpowers/sdd/commit-mine.sh "feat(widgets): exodus:// links — a new chat, a chat, Health — and nothing else" \
  Sources/WidgetKitShared/DeepLink.swift Tests/WidgetKitSharedTests/DeepLinkTests.swift
```

---

### Task 3: Presentation rules and the timeline's dates

**Files:**
- Create: `Sources/WidgetKitShared/WidgetPresentation.swift`
- Test: `Tests/WidgetKitSharedTests/WidgetPresentationTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot`, `HealthGlance` (Task 1).
- Produces: `public enum WidgetPresentation { public enum Period: Sendable { case morning, afternoon, evening }; public static func period(at: Date, calendar: Calendar) -> Period; public static func clockHour(at: Date, calendar: Calendar) -> Double; public static func health(of: WidgetSnapshot, at: Date, calendar: Calendar) -> HealthGlance?; public static func entryDates(from: Date, calendar: Calendar) -> [Date]; public static func dayString(_ date: Date, calendar: Calendar) -> String }`. Ink is decided in `WidgetUI` from `DaySky.night(atClockHour:)` (OdyKit), not here, so this module stays Foundation-only.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import WidgetKitShared

@Suite("WidgetPresentation: what an entry shows at its hour")
struct WidgetPresentationTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test("morning from 5, afternoon from 12, evening from 18 until 5", arguments: [
        (4, WidgetPresentation.Period.evening), (5, .morning), (11, .morning), (12, .afternoon), (17, .afternoon),
        (18, .evening), (23, .evening),
    ])
    func periods(hour: Int, period: WidgetPresentation.Period) {
        #expect(WidgetPresentation.period(at: date(1, hour), calendar: calendar) == period)
    }

    @Test("today's glance shows today, and after midnight it is gone")
    func staleHealth() {
        let glance = HealthGlance(
            day: "2026-10-01", sleepMinutes: 352, steps: 10, stepGoal: 8000, headline: nil, suggestion: nil,
            mood: .neutral)
        let snapshot = WidgetSnapshot.empty.updating(health: glance, at: date(1, 8))
        #expect(WidgetPresentation.health(of: snapshot, at: date(1, 23, 59), calendar: calendar) == glance)
        #expect(WidgetPresentation.health(of: snapshot, at: date(2, 0, 30), calendar: calendar) == nil)
    }

    @Test("twelve hourly entries, the first now, the rest on the hour")
    func entries() {
        let dates = WidgetPresentation.entryDates(from: date(1, 9, 41), calendar: calendar)
        #expect(dates.count == 12)
        #expect(dates.first == date(1, 9, 41))
        #expect(dates[1] == date(1, 10))
        #expect(dates.last == date(1, 20))
    }

    @Test("the clock hour carries the minutes, for the sky")
    func clockHour() {
        #expect(WidgetPresentation.clockHour(at: date(1, 18, 30), calendar: calendar) == 18.5)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — expected `cannot find 'WidgetPresentation'`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The rules a widget entry is drawn by, apart from drawing: the greeting's period, which health may be shown, and
/// when entries fall.
public enum WidgetPresentation {
    public enum Period: Sendable { case morning, afternoon, evening }

    public static func period(at date: Date, calendar: Calendar) -> Period {
        switch calendar.component(.hour, from: date) {
        case 5..<12: .morning
        case 12..<18: .afternoon
        default: .evening
        }
    }

    public static func clockHour(at date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    public static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The glance, on its own day only: never yesterday's numbers as today's.
    public static func health(of snapshot: WidgetSnapshot, at date: Date, calendar: Calendar) -> HealthGlance? {
        guard let health = snapshot.health, health.day == dayString(date, calendar: calendar) else { return nil }
        return health
    }

    /// Now, then each of the next eleven hours on the hour: the sky moves with the clock.
    public static func entryDates(from now: Date, calendar: Calendar) -> [Date] {
        guard let hour = calendar.dateInterval(of: .hour, for: now)?.start else { return [now] }
        return [now] + (1..<12).compactMap { calendar.date(byAdding: .hour, value: $0, to: hour) }
    }
}
```

- [ ] **Step 4: Run tests** — all pass.

- [ ] **Step 5: Commit**

```bash
.superpowers/sdd/commit-mine.sh "feat(widgets): an entry's greeting, its hour's sky, and only today's health" \
  Sources/WidgetKitShared/WidgetPresentation.swift Tests/WidgetKitSharedTests/WidgetPresentationTests.swift
```

---

### Task 4: The app writes the snapshot

**Files:**
- Modify: `Project.swift` (App entitlements: App Group; Info.plist `CFBundleURLTypes`)
- Create: `Sources/App/WidgetSnapshotWriter.swift`
- Modify: `Sources/ChatFeature/ChatSidebarView.swift` (recents callback), `Sources/App/AppShell.swift`, `Sources/App/ExodusApp.swift`
- Modify: `Sources/HealthFeature/Report/HealthHomeModel.swift` (+ `widgetGlance`), `Sources/HealthFeature/UI/HealthRootView.swift` (glance callback), `Project.swift` (HealthFeature depends on WidgetKitShared)
- Test: `Tests/WidgetKitSharedTests/WidgetSnapshotWriterRulesTests.swift`, `Tests/HealthFeatureTests/WidgetGlanceTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot`, `SnapshotStore`, `RecentChat`, `HealthGlance`, `WidgetMood` (Task 1).
- Produces:
  - `@MainActor final class WidgetSnapshotWriter { init(store: SnapshotStore?, reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }, now: @escaping () -> Date = Date.init); func recentsChanged(_ chats: [ChatSummary]); func healthChanged(_ glance: HealthGlance?); func computerChanged() }`
  - `public extension HealthHomeModel { var widgetGlance: HealthGlance? }`
  - `ChatSidebarView` gains `onRecentsChange: ([ChatSummary]) -> Void = { _ in }`.
  - `HealthRootView` gains `onGlanceChange: (HealthGlance?) -> Void = { _ in }`.
  - `public enum WidgetSnapshotRules { public static func recents(from: [(id: String, title: String, createdAt: String)]) -> [RecentChat] }` in `WidgetKitShared` (ISO-8601 parse, unparsable dates sort last).

- [ ] **Step 1: Write the failing tests**

`Tests/WidgetKitSharedTests/WidgetSnapshotWriterRulesTests.swift`:

```swift
import Foundation
import Testing

@testable import WidgetKitShared

@Suite("WidgetSnapshotRules: the chat list as recents")
struct WidgetSnapshotWriterRulesTests {
    @Test("dates are read as the server writes them; one it cannot read sorts last")
    func recents() {
        let recents = WidgetSnapshotRules.recents(from: [
            ("a", "Old", "2026-09-01T10:00:00.000Z"), ("b", "New", "2026-10-01T10:00:00Z"), ("c", "Odd", "yesterday"),
        ])
        let snapshot = WidgetSnapshot.empty.updating(recents: recents, at: Date())
        #expect(snapshot.recentChats.map(\.id) == ["b", "a", "c"])
    }
}
```

`Tests/HealthFeatureTests/WidgetGlanceTests.swift` — build a `HealthHomeModel` the way the existing `HealthHomeModelTests` do (read that file and reuse its fixture helpers / fake `HealthDataSource`), reach `.ready` with a snapshot whose `odyState` is `.tired`, sleep 352 min, steps 1251 / 8000, headline "Take it easy", then:

```swift
@Test("a ready report is a glance: the day, sleep, steps, headline, a question and a sleepy Ody")
func glance() async throws {
    let model = try await readyModel(odyState: .tired)   // helper built from HealthHomeModelTests' fixtures
    let glance = try #require(model.widgetGlance)
    #expect(glance.day == model.day?.snapshot.date)
    #expect(glance.sleepMinutes == 352 && glance.steps == 1251 && glance.stepGoal == 8000)
    #expect(glance.headline == "Take it easy")
    #expect(glance.suggestion == "Why do I feel tired today?")
    #expect(glance.mood == .sleepy)
}

@Test("consent taken back: no glance")
func revoked() async throws {
    let model = try await readyModel(odyState: .happy)
    #expect(model.widgetGlance?.mood == .happy)
    model.revokeConsent()
    #expect(model.widgetGlance == nil)
}
```

- [ ] **Step 2: Run to verify they fail** (WidgetKitShared and HealthFeature schemes).

- [ ] **Step 3: Implement the shared rule**

Append to `Sources/WidgetKitShared/WidgetSnapshot.swift`:

```swift
/// How the app's own types become a snapshot's, without the module knowing them.
public enum WidgetSnapshotRules {
    public static func recents(from chats: [(id: String, title: String, createdAt: String)]) -> [RecentChat] {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return chats.map { chat in
            let date = fractional.date(from: chat.createdAt) ?? plain.date(from: chat.createdAt) ?? .distantPast
            return RecentChat(id: chat.id, title: chat.title, updatedAt: date)
        }
    }
}
```

- [ ] **Step 4: Implement `widgetGlance`**

Add `.target(name: "WidgetKitShared")` to HealthFeature's dependencies in `Project.swift`, `tuist generate --no-open`. In `Sources/HealthFeature/Report/HealthHomeModel.swift` (check `git diff` first; add as its own extension at the end of the file):

```swift
import WidgetKitShared

extension HealthHomeModel {
    /// What the widgets may show of today: only with a ready report (so only with consent).
    public var widgetGlance: HealthGlance? {
        guard case .ready(let summary) = report, let snapshot = day?.snapshot else { return nil }
        let mood: WidgetMood =
            switch snapshot.odyState {
            case .tired, .recovering: .sleepy
            case .happy, .active, .rested: .happy
            default: .neutral
            }
        let suggestion =
            mood == .sleepy
            ? String(localized: "ios:health.ask.suggestion.energy", defaultValue: "Why do I feel tired today?")
            : String(localized: "ios:health.ask.suggestion.sleep", defaultValue: "How did I sleep last night?")
        return HealthGlance(
            day: snapshot.date, sleepMinutes: snapshot.sleep?.asleepMin, steps: snapshot.activity?.steps,
            stepGoal: snapshot.activity?.stepGoal, headline: summary.headline, suggestion: suggestion, mood: mood)
    }
}
```

(Check the English `defaultValue`s against those keys' English text in `Localizable.xcstrings` and use them verbatim.)

In `HealthRootView` add the parameter `onGlanceChange: @escaping (HealthGlance?) -> Void = { _ in }` (store it) and on its body: `.onChange(of: model.widgetGlance, initial: true) { onGlanceChange(model.widgetGlance) }`. `HealthGlance` is `Equatable`, so this fires only on change.

- [ ] **Step 5: Implement the writer**

`Sources/App/WidgetSnapshotWriter.swift`:

```swift
import Models
import WidgetKit
import WidgetKitShared

/// Keeps the widgets' snapshot in step with the app: recents from the chat list, today's glance from Health, nothing
/// once the computer goes. Reloads the widgets only when what they draw changed.
@MainActor
final class WidgetSnapshotWriter {
    private let store: SnapshotStore?
    private let reload: () -> Void
    private let now: () -> Date
    private var current: WidgetSnapshot

    init(
        store: SnapshotStore? = .appGroup(), reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.reload = reload
        self.now = now
        self.current = store?.load() ?? .empty
    }

    func recentsChanged(_ chats: [ChatSummary]) {
        let recents = WidgetSnapshotRules.recents(from: chats.map { ($0.id, $0.title, $0.createdAt) })
        write(current.updating(recents: recents, at: now()))
    }

    func healthChanged(_ glance: HealthGlance?) { write(current.updating(health: glance, at: now())) }

    func computerChanged() { write(current.cleared(at: now())) }

    private func write(_ next: WidgetSnapshot) {
        // `updatedAt` always moves; what the widgets draw is the rest.
        guard next.recentChats != current.recentChats || next.health != current.health else { return }
        current = next
        do {
            try store?.save(next)
        } catch {
            // The widgets keep the last good snapshot.
            return
        }
        reload()
    }
}
```

Add a test for the writer in `Tests/AppTests/WidgetSnapshotWriterTests.swift` (the `AppTests` target depends on `App`; use `@testable import Exodus` — check the module name the existing AppTests import):

```swift
@MainActor
@Test("the widgets reload only when what they draw changed, and unpairing empties them")
func writer() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    var reloads = 0
    let writer = WidgetSnapshotWriter(store: SnapshotStore(directory: dir), reload: { reloads += 1 })
    let chats = [ChatSummary(id: "a", title: "Plan", createdAt: "2026-10-01T10:00:00Z")]
    writer.recentsChanged(chats)
    writer.recentsChanged(chats)
    #expect(reloads == 1)
    writer.computerChanged()
    #expect(reloads == 2)
    #expect(SnapshotStore(directory: dir).load().recentChats.isEmpty)
}
```

- [ ] **Step 6: Wire it**

1. `Project.swift`, App target: add to `entitlements` `"com.apple.security.application-groups": .array([.string("group.app.yancey.exodus")])`; add to `infoPlist` `"CFBundleURLTypes": [["CFBundleURLName": "app.yancey.exodus.link", "CFBundleURLSchemes": ["exodus"]]]`. `tuist generate --no-open`.
2. `ChatSidebarView`: add `onRecentsChange: @escaping ([ChatSummary]) -> Void = { _ in }` to its init (store it), and on its body `.onChange(of: list.chats, initial: true) { onRecentsChange(list.chats) }` (`list` is its `ChatListViewModel`; `chats` is `[ChatSummary]`, `Equatable`).
3. `ExodusApp`: create one `@State private var widgetWriter = WidgetSnapshotWriter()` and pass it to `AppShell(…, widgetWriter:)`; where `ServerConnection` is set up, register `connection.onComputerChange { Task { @MainActor in widgetWriter.computerChanged() } }` (capture the writer instance, not `self`).
4. `AppShell`: new `let widgetWriter: WidgetSnapshotWriter`; pass `onRecentsChange: { widgetWriter.recentsChanged($0) }` to `ChatSidebarView` and `onGlanceChange: { widgetWriter.healthChanged($0) }` to `HealthRootView`.

- [ ] **Step 7: Run tests** — WidgetKitShared, HealthFeature, App test schemes; and build the App.

- [ ] **Step 8: Commit** (ChatSidebarView, ExodusApp, AppShell, HealthHomeModel, HealthRootView: check each `git diff`; foreign hunks → `--patch` with only yours)

```bash
.superpowers/sdd/commit-mine.sh "feat(widgets): the app keeps the widgets' snapshot — recents, today's glance, nothing after unpairing" \
  [--patch …] Sources/App/WidgetSnapshotWriter.swift Tests/AppTests/WidgetSnapshotWriterTests.swift \
  Tests/WidgetKitSharedTests/WidgetSnapshotWriterRulesTests.swift Tests/HealthFeatureTests/WidgetGlanceTests.swift \
  Sources/WidgetKitShared/WidgetSnapshot.swift …
```

---

### Task 5: Deep-link routing in the app

**Files:**
- Modify: `Sources/App/ExodusApp.swift`, `Sources/App/AppShell.swift`
- Modify: `Sources/ChatFeature/ChatDetailView.swift`, `Sources/ChatFeature/ChatDetailViewModel.swift` (pre-fill)
- Modify: `Sources/HealthFeature/UI/HealthRootView.swift`, `HealthHomeView.swift`, `AskComposer.swift` (pre-fill)
- Create: `Sources/WidgetKitShared/PendingLink.swift`
- Test: `Tests/WidgetKitSharedTests/PendingLinkTests.swift`, `Tests/ChatFeatureTests/ChatDetailViewModelDraftTests.swift`

**Interfaces:**
- Consumes: `DeepLink` (Task 2).
- Produces:
  - `@MainActor @Observable public final class PendingLink { public init(); public func offer(_ url: URL); public func take() -> DeepLink? }` — keeps the latest valid link until taken.
  - `ChatDetailView(…, initialDraft: String? = nil)`; `ChatDetailViewModel.applyDraft(_ text: String)` (public; once per screen, puts it in the composer, focuses, never sends).
  - `HealthRootView(…, initialAsk: String? = nil, onInitialAskUsed: () -> Void = {})` → `AskComposer(initialText:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/WidgetKitSharedTests/PendingLinkTests.swift`:

```swift
import Foundation
import Testing

@testable import WidgetKitShared

@MainActor
@Suite("PendingLink: a link waits behind the gates")
struct PendingLinkTests {
    @Test("the latest valid link is kept until taken, once; an invalid one changes nothing")
    func waits() throws {
        let pending = PendingLink()
        pending.offer(try #require(URL(string: "exodus://chat/new")))
        pending.offer(try #require(URL(string: "exodus://health")))
        pending.offer(try #require(URL(string: "exodus://nowhere")))
        #expect(pending.take() == .health(ask: nil))
        #expect(pending.take() == nil)
    }
}
```

`Tests/ChatFeatureTests/ChatDetailViewModelDraftTests.swift` — make a view model the way `ChatDetailViewModelTests` does (reuse its fake API client), then:

```swift
@Test("a draft fills the composer once and is not sent")
func draft() async throws {
    let model = makeModel()            // from ChatDetailViewModelTests' helpers
    model.applyDraft("Plan my day")
    model.applyDraft("Something else")
    #expect(model.composerText == "Plan my day")
    #expect(model.messages.isEmpty)
}
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement `PendingLink`**

```swift
import Foundation
import Observation

/// A link that arrived while the app could not show it yet (locked, unpaired): kept, the latest only, until the shell
/// takes it.
@MainActor
@Observable
public final class PendingLink {
    public private(set) var link: DeepLink?

    public init() {}

    public func offer(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        self.link = link
    }

    public func take() -> DeepLink? {
        defer { link = nil }
        return link
    }
}
```

- [ ] **Step 4: Implement the pre-fills**

`ChatDetailViewModel` (check `git diff` — foreign hunks exist; add yours next to `sendInitial`):

```swift
    @ObservationIgnored private var appliedDraft = false

    /// Text handed over from a widget: put in the composer, once per chat screen, never sent by itself.
    public func applyDraft(_ text: String) {
        guard !appliedDraft else { return }
        appliedDraft = true
        prefillComposer(text)
    }
```

`ChatDetailView`: add `initialDraft: String? = nil` to `init` (store `private let initialDraft: String?`), and in the same `.task` that handles `initialMessage`, after it: `if let initialDraft { viewModel.applyDraft(initialDraft) }`.

`AskComposer`: add `initialText: String? = nil` to `init`; `_text = State(initialValue: initialText ?? "")`; when `initialText` is non-nil also set `focused = true` in `.onAppear`. `HealthHomeView` and `HealthRootView` pass `initialAsk` through; `HealthRootView` calls `onInitialAskUsed()` in `.onAppear` when `initialAsk != nil`, so a second visit does not refill it.

- [ ] **Step 5: Route in `AppShell` and `ExodusApp`**

`ExodusApp`: `@State private var pendingLink = PendingLink()`; on the root `WindowGroup` content `.onOpenURL { pendingLink.offer($0) }`; pass `pendingLink` to `AppShell`.

`AppShell`: new `let pendingLink: PendingLink`; new state `@State private var draft: (chatId: String, text: String)?` and `@State private var healthAsk: String?`. Add:

```swift
    .onChange(of: pendingLink.link, initial: true) {
        guard let link = pendingLink.take() else { return }
        open(link)
    }

    private func open(_ link: DeepLink) {
        switch link {
        case .newChat(let prompt):
            startNewChat()
            if let prompt { draft = (activeChat.id, prompt) }
        case .chat(let id):
            // The title comes with the history; an unknown id shows the server's error in the chat, and the drawer
            // still lists the rest.
            select(id: id, title: nil)
        case .health(let ask):
            pendingAsk = nil
            healthAsk = ask
            workspace = .health
            setSidebar(open: false)
        }
    }
```

Pass `initialDraft: draft?.chatId == activeChat.id ? draft?.text : nil` to `ChatDetailView`, and `initialAsk: healthAsk, onInitialAskUsed: { healthAsk = nil }` to `HealthRootView`. `DeepLink` needs `Equatable` for `.onChange` — it has it.

Unknown chat id: verify by hand that `ChatDetailView` with an id the server does not know shows its existing "couldn't load" state; if it shows nothing, instead `startNewChat()` when the history load returns 404 — note it in the commit if so.

- [ ] **Step 6: Run tests and build.** Then on the simulator: `xcrun simctl openurl D8A2BE45-88F3-46AE-8693-B147F2815724 "exodus://chat/new?prompt=Plan%20my%20day"` (composer pre-filled, nothing sent), `exodus://health?ask=Why%20do%20I%20feel%20tired%20today%3F` (Health, ask box filled, attach chip on when consent), `exodus://chat/new` (fresh chat, keyboard up). Screenshot each to `.superpowers/widget-link-*.png` and read them.

- [ ] **Step 7: Commit** (patches for files with foreign hunks: ChatDetailView, ChatDetailViewModel, ExodusApp)

```bash
.superpowers/sdd/commit-mine.sh "feat(widgets): exodus:// links open a new chat (pre-filled, never sent), a chat, or Health's ask box" …
```

---

### Task 6: Widget views (`WidgetUI`)

**Files:**
- Modify: `Project.swift` (`moduleTarget(name: "WidgetUI", dependencies: [.target(name: "WidgetKitShared"), .target(name: "OdyKit")])`; App depends on it)
- Create: `Sources/WidgetUI/WidgetSky.swift`, `AskSmallView.swift`, `AskMediumView.swift`, `AccessoryViews.swift`, `WidgetStrings.swift`
- Modify: `Resources/App/Localizable.xcstrings` (via `scripts/l10n.py`)

**Interfaces:**
- Consumes: `WidgetSnapshot`, `HealthGlance`, `WidgetPresentation`, `DeepLink` (Tasks 1–3); `OdyFigure(expression:)`, `OdyExpression`, `DaySky.gradient(atClockHour:)`, `DaySky.night(atClockHour:)`, `RGB.color`, `OdyPalette.marigold` (OdyKit).
- Produces: `public struct AskSmallView: View { public init(snapshot: WidgetSnapshot, date: Date, calendar: Calendar = .current) }`, `public struct AskMediumView: View` (same init), `public struct AskCircularView: View { public init() }`, `public struct TodayRectangularView: View` (same init as small), `public struct WidgetSky: View { public init(date: Date, calendar: Calendar) }`, `public enum WidgetInk { public static func isLight(at: Date, calendar: Calendar) -> Bool }`.

- [ ] **Step 1: Strings**

Add with `python3 scripts/l10n.py add KEY --en-value "…" --comment "…"` then `fill` all 10 languages (write a JSON of translations; zh-Hant/zh-HK/ja/ko/fr/de/es/pt-BR/it):

| Key | English |
|---|---|
| `ios:widget.greeting.morning` | Good morning |
| `ios:widget.greeting.afternoon` | Good afternoon |
| `ios:widget.greeting.evening` | Good evening |
| `ios:widget.greeting.question` | Want to talk? |
| `ios:widget.ask.placeholder` | Ask Exodus… |
| `ios:widget.ask.title` | Ask Exodus |
| `ios:widget.recent.title` | Recent |
| `ios:widget.recent.empty` | No chats yet |
| `ios:widget.chip.planDay` | Plan my day |
| `ios:widget.health.line` | %1$@ · %2$@ steps (sleep duration, step count) |
| `ios:widget.ask.description` | Start a conversation with Exodus. |
| `ios:widget.today.description` | Today in a line, and a way to ask. |

Run `python3 scripts/l10n.py audit` → 0 errors.

- [ ] **Step 2: Sky and ink**

`Sources/WidgetUI/WidgetSky.swift`:

```swift
import OdyKit
import SwiftUI
import WidgetKitShared

/// Text on the sky: white at night, the dark ink by day, as `DaySky.night` decides.
public enum WidgetInk {
    public static func isLight(at date: Date, calendar: Calendar) -> Bool {
        DaySky.night(atClockHour: WidgetPresentation.clockHour(at: date, calendar: calendar)) >= 0.5
    }

    static func color(at date: Date, calendar: Calendar) -> Color {
        isLight(at: date, calendar: calendar) ? .white : Color(red: 0.11, green: 0.10, blue: 0.09)
    }
}

/// The Health hero's sky at the entry's hour, with a few stars at night.
public struct WidgetSky: View {
    let date: Date
    let calendar: Calendar

    public init(date: Date, calendar: Calendar) {
        self.date = date
        self.calendar = calendar
    }

    public var body: some View {
        let hour = WidgetPresentation.clockHour(at: date, calendar: calendar)
        let sky = DaySky.gradient(atClockHour: hour)
        ZStack {
            LinearGradient(colors: [sky.top.color, sky.bottom.color], startPoint: .top, endPoint: .bottom)
            if DaySky.night(atClockHour: hour) >= 0.5 {
                Canvas { context, size in
                    for (x, y) in [(0.72, 0.12), (0.88, 0.3), (0.58, 0.36), (0.94, 0.08)] {
                        let r = CGRect(x: x * size.width, y: y * size.height, width: 2, height: 2)
                        context.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.8)))
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Small and medium**

`Sources/WidgetUI/AskSmallView.swift`:

```swift
import OdyKit
import SwiftUI
import WidgetKitShared

public struct AskSmallView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let calendar: Calendar

    public init(snapshot: WidgetSnapshot, date: Date, calendar: Calendar = .current) {
        self.snapshot = snapshot
        self.date = date
        self.calendar = calendar
    }

    public var body: some View {
        let health = WidgetPresentation.health(of: snapshot, at: date, calendar: calendar)
        let ink = WidgetInk.color(at: date, calendar: calendar)
        VStack(alignment: .leading, spacing: 6) {
            if let health, let line = WidgetStrings.healthLine(health) {
                Text(verbatim: line).font(.caption2.weight(.semibold)).foregroundStyle(ink.opacity(0.8))
                    .privacySensitive()
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WidgetStrings.greeting(WidgetPresentation.period(at: date, calendar: calendar)))
                    Text("ios:widget.greeting.question", bundle: .main)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ink)
                Spacer(minLength: 0)
                OdyFigure(expression: WidgetStrings.expression(health?.mood))
                    .frame(width: 48, height: 54)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            AskCapsule(ink: ink)
        }
        .widgetURL(DeepLink.newChat(prompt: nil).url)
    }
}

/// "Ask Exodus…" with the marigold send glyph.
struct AskCapsule: View {
    let ink: Color

    var body: some View {
        HStack {
            Text("ios:widget.ask.placeholder", bundle: .main).font(.footnote).foregroundStyle(ink.opacity(0.75))
            Spacer(minLength: 4)
            Image(systemName: "arrow.up").font(.caption.weight(.bold)).foregroundStyle(.black.opacity(0.8))
                .frame(width: 22, height: 22).background(OdyPalette.marigold, in: .circle)
        }
        .padding(.leading, 10).padding(.trailing, 4).frame(height: 30)
        .background(ink.opacity(0.16), in: .capsule)
    }
}
```

`Sources/WidgetUI/WidgetStrings.swift`:

```swift
import Foundation
import OdyKit
import WidgetKitShared

enum WidgetStrings {
    static func greeting(_ period: WidgetPresentation.Period) -> LocalizedStringResource {
        switch period {
        case .morning: LocalizedStringResource("ios:widget.greeting.morning", bundle: .main)
        case .afternoon: LocalizedStringResource("ios:widget.greeting.afternoon", bundle: .main)
        case .evening: LocalizedStringResource("ios:widget.greeting.evening", bundle: .main)
        }
    }

    /// "☾ 5:52 · 1,251 steps"; nil when there is neither number.
    static func healthLine(_ health: HealthGlance) -> String? {
        let sleep = health.sleepMinutes.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }
        let steps = health.steps.map { $0.formatted(.number) }
        switch (sleep, steps) {
        case let (sleep?, steps?):
            return "☾ " + String(
                localized: "ios:widget.health.line", defaultValue: "\(sleep) · \(steps) steps",
                bundle: .main, comment: "Widget health line: sleep duration (h:mm), then today's step count.")
        case let (sleep?, nil): return "☾ " + sleep
        case let (nil, steps?): return steps
        default: return nil
        }
    }

    static func expression(_ mood: WidgetMood?) -> OdyExpression {
        switch mood {
        case .sleepy: .sleepy
        case .happy: .happy
        default: .content
        }
    }
}
```

(`%1$@ · %2$@ steps` is the English value added in Step 1; with only one of the two numbers the line shows that number alone.)

`Sources/WidgetUI/AskMediumView.swift`: an `HStack(spacing: 14)` of two columns.
- Left (`VStack(alignment: .leading, spacing: 6)`): the health line (as in the small view); if `health?.suggestion` → `Link(destination: DeepLink.health(ask: suggestion).url)` with a chip (`Text(verbatim: suggestion)`, `.font(.caption)`, `.lineLimit(1)`, padding 6/10, background `OdyPalette.marigold.opacity(0.22)` in `.rect(cornerRadius: 12)`); a `Link` to `DeepLink.newChat(prompt: String(localized: "ios:widget.chip.planDay", defaultValue: "Plan my day", bundle: .main)).url` with the same chip in `ink.opacity(0.12)`; `Spacer`; `Link(destination: DeepLink.newChat(prompt: nil).url) { AskCapsule(ink: ink) }`.
- Right (`VStack(alignment: .leading, spacing: 0)`, width ≈ 44%): `Text("ios:widget.recent.title")` caption2 semibold, ink 0.6; then `ForEach(snapshot.recentChats)` → `Link(destination: DeepLink.chat(id: chat.id).url)` with `HStack { Text(verbatim: chat.title).lineLimit(1); Spacer(); Text(chat.updatedAt, style: .relative)... }` — use `Text(chat.updatedAt, format: .relative(presentation: .named))` caption2 ink 0.55, `.privacySensitive()` on the title; `Divider().overlay(ink.opacity(0.12))` between rows; empty → `Text("ios:widget.recent.empty")` caption ink 0.6.
- `.widgetURL(DeepLink.newChat(prompt: nil).url)` on the whole.

`Sources/WidgetUI/AccessoryViews.swift`:

```swift
import OdyKit
import SwiftUI
import WidgetKit
import WidgetKitShared

/// Lock Screen, circular: Ody's outline; a tap starts a chat.
public struct AskCircularView: View {
    public init() {}

    public var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            OdyBodyShape().stroke(lineWidth: 2.5).frame(width: 24, height: 27).widgetAccentable()
        }
        .widgetURL(DeepLink.newChat(prompt: nil).url)
        .accessibilityLabel(Text("ios:widget.ask.title", bundle: .main))
    }
}

/// Lock Screen, rectangular: the note's headline and today's numbers → Health; without today's note, "Ask Exodus".
public struct TodayRectangularView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let calendar: Calendar

    public init(snapshot: WidgetSnapshot, date: Date, calendar: Calendar = .current) {
        self.snapshot = snapshot
        self.date = date
        self.calendar = calendar
    }

    public var body: some View {
        if let health = WidgetPresentation.health(of: snapshot, at: date, calendar: calendar),
            let headline = health.headline
        {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: headline).font(.headline).lineLimit(1).widgetAccentable()
                if let line = WidgetStrings.healthLine(health) {
                    Text(verbatim: line).font(.caption).lineLimit(2).privacySensitive()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.health(ask: nil).url)
        } else {
            Label { Text("ios:widget.ask.title", bundle: .main) } icon: {
                OdyBodyShape().stroke(lineWidth: 2).frame(width: 14, height: 16)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.newChat(prompt: nil).url)
        }
    }
}
```

(`OdyBodyShape` is public in OdyKit — `Sources/OdyKit/OdyFigure.swift:18`.)

- [ ] **Step 4: Build** the App scheme (WidgetUI compiles as an App dependency). No unit tests here — the views are verified in Task 8's gallery.

- [ ] **Step 5: Commit**

```bash
.superpowers/sdd/commit-mine.sh "feat(widgets): the widgets' views — the night sky, Ody, Ask, recents and today in a line" \
  --patch /tmp/xcstrings-widgets.patch Sources/WidgetUI …
```
(Catalog patch: as in constraints.md — start from `git show HEAD:Resources/App/Localizable.xcstrings`, apply only the `ios:widget.*` additions.)

---

### Task 7: The widget extension and the control

**Files:**
- Modify: `Project.swift` (extension target; App embeds it)
- Create: `Widgets/Info.plist`, `Widgets/Sources/ExodusWidgetBundle.swift`, `Widgets/Sources/SnapshotProvider.swift`, `Widgets/Sources/AskWidget.swift`, `Widgets/Sources/TodayAccessoryWidget.swift`, `Widgets/Sources/AskControl.swift`
- Create: `Sources/WidgetKitShared/AskExodusIntent.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `struct SnapshotEntry: TimelineEntry { let date: Date; let snapshot: WidgetSnapshot }`; `public struct AskExodusIntent: AppIntent` (title "Ask Exodus", `openAppWhenRun = true`, performs `OpenURLIntent(DeepLink.newChat(prompt: nil).url)`).

- [ ] **Step 1: Target**

In `Project.swift` add:

```swift
        .target(
            name: "ExodusWidgets",
            destinations: .iOS,
            product: .appExtension,
            productName: "ExodusWidgets",
            bundleId: "\(bundleIdRoot).widgets",
            deploymentTargets: deploymentTargets,
            infoPlist: .file(path: "Widgets/Info.plist"),
            buildableFolders: ["Widgets/Sources"],
            resources: ["Resources/App/Localizable.xcstrings"],
            entitlements: .dictionary([
                "com.apple.security.application-groups": .array([.string("group.app.yancey.exodus")])
            ]),
            dependencies: [
                .target(name: "WidgetKitShared"), .target(name: "WidgetUI"), .target(name: "OdyKit"),
                .sdk(name: "WidgetKit", type: .framework), .sdk(name: "SwiftUI", type: .framework),
            ],
            settings: .settings(base: ["DEVELOPMENT_TEAM": .string(developmentTeam), "CODE_SIGN_STYLE": "Automatic"])
        ),
```

and `.target(name: "ExodusWidgets")` in the App's dependencies (Tuist embeds an app extension dependency). The catalog is the App's own file, also a member of the extension through `resources:` — one catalog, so the strings cannot drift. If Tuist rejects `resources:` next to `buildableFolders:`, stop and report it to the controller rather than copying the catalog. `tuist generate --no-open`.

`Widgets/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>Exodus</string>
    <key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key><string>$(CURRENT_PROJECT_VERSION)</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
```

(Match the App's `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` — an extension whose version differs from its app fails validation.)

- [ ] **Step 2: The intent**

`Sources/WidgetKitShared/AskExodusIntent.swift`:

```swift
import AppIntents
import Foundation

/// Control Center and the Action button: open the app on a new chat.
public struct AskExodusIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource("ios:widget.ask.title", defaultValue: "Ask Exodus")
    public static let openAppWhenRun = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DeepLink.newChat(prompt: nil).url))
    }
}
```

- [ ] **Step 3: Provider, widgets, control, bundle**

`Widgets/Sources/SnapshotProvider.swift`:

```swift
import WidgetKit
import WidgetKitShared

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .empty) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: SnapshotStore.appGroup()?.load() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = SnapshotStore.appGroup()?.load() ?? .empty
        let entries = WidgetPresentation.entryDates(from: .now, calendar: .current)
            .map { SnapshotEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
```

`Widgets/Sources/AskWidget.swift`:

```swift
import SwiftUI
import WidgetKit
import WidgetUI

struct AskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.yancey.exodus.ask", provider: SnapshotProvider()) { entry in
            AskWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("ios:widget.ask.title"))
        .description(Text("ios:widget.ask.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct AskWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Group {
            switch family {
            case .systemMedium: AskMediumView(snapshot: entry.snapshot, date: entry.date)
            default: AskSmallView(snapshot: entry.snapshot, date: entry.date)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) {
            // Accented and clear Home Screens draw no sky: text and Ody's outline only.
            if mode == .fullColor { WidgetSky(date: entry.date, calendar: .current) }
        }
    }
}
```

`Widgets/Sources/TodayAccessoryWidget.swift`:

```swift
import SwiftUI
import WidgetKit
import WidgetUI

struct TodayAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.yancey.exodus.today", provider: SnapshotProvider()) { entry in
            TodayAccessoryView(entry: entry).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(Text("ios:widget.ask.title"))
        .description(Text("ios:widget.today.description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct TodayAccessoryView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular: TodayRectangularView(snapshot: entry.snapshot, date: entry.date)
        default: AskCircularView()
        }
    }
}
```

`Widgets/Sources/AskControl.swift`:

```swift
import SwiftUI
import WidgetKit
import WidgetKitShared

struct AskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.yancey.exodus.ask-control") {
            ControlWidgetButton(action: AskExodusIntent()) {
                Label("ios:widget.ask.title", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .displayName("ios:widget.ask.title")
    }
}
```

(Ody's outline is not an SF Symbol; a control's icon must be a symbol. Use `bubble.left.and.text.bubble.right`; a custom symbol of Ody is a later polish, not v1.)

`Widgets/Sources/ExodusWidgetBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct ExodusWidgetBundle: WidgetBundle {
    var body: some Widget {
        AskWidget()
        TodayAccessoryWidget()
        AskControl()
    }
}
```

- [ ] **Step 4: Build** the App scheme (it embeds the extension). Fix signing settings if the build asks (same team as the App).

- [ ] **Step 5: Commit**

```bash
.superpowers/sdd/commit-mine.sh "feat(widgets): the widget extension — Ask on the Home Screen, today on the Lock Screen, Ask in Control Center" \
  [--patch project.patch] Widgets Sources/WidgetKitShared/AskExodusIntent.swift
```

---

### Task 8: DEBUG gallery, simulator verification, device checklist

**Files:**
- Create: `Sources/App/WidgetGallery.swift`
- Modify: `Sources/App/ExodusApp.swift` (launch the gallery on `-WidgetGallery`, like `HealthGallery`)
- Create: `docs/widgets-device-checklist.md`

- [ ] **Step 1: Gallery**

`WidgetGallery` (DEBUG only, `#if DEBUG`): a `ScrollView` that, for each of the dates 07:00, 12:00, 18:30, 23:00 (today, `Calendar.current`), draws `AskSmallView` in a 170×170 and `AskMediumView` in a 364×170 rounded-22 frame over `WidgetSky(date:)` with 14pt padding; then `TodayRectangularView` (172×76) and `AskCircularView` (76×76) on a dark Lock-Screen-like background with `.environment(\.widgetRenderingMode, .accented)` not available outside WidgetKit — draw them plainly in white; then the empty state (`WidgetSnapshot.empty`) small + medium. Fixture: 3 recents ("Swift 6 concurrency migration", "Weekend in Hangzhou", "Reading notes"), glance (today's day string, 352 min, 1251 / 8000 steps, headline "Take it easy", suggestion "Why do I feel tired today?", `.sleepy`). Mirror `HealthGallery`'s `isEnabled` / launch-argument style (`Sources/App/HealthGallery.swift`).

- [ ] **Step 2: Screenshots**

Build and install, then for light, dark, and `content_size extra-extra-extra-large`:
`xcrun simctl launch D8A2BE45-88F3-46AE-8693-B147F2815724 app.yancey.exodus.exodus-ios -WidgetGallery`, screenshot to `.superpowers/widget-gallery-{light,dark,ax}.png`. Read each. Check: text readable on every sky (dark ink at noon, white at 23:00), nothing clipped in medium at AX sizes (titles truncate, never overlap), Ody not covering the greeting.

- [ ] **Step 3: Real widgets on the simulator**

With the app installed, add the widgets on the simulator Home Screen (long-press → Edit → Add Widget → Exodus) — if this cannot be automated, say so in the report and rely on the gallery plus `xcrun simctl openurl` checks from Task 5. Confirm the widget appears in the gallery list (the extension is embedded and registered): `xcrun simctl spawn D8A2BE45-88F3-46AE-8693-B147F2815724 log show --last 2m --predicate 'subsystem == "com.apple.chronod"' | grep -i exodus | head`.

- [ ] **Step 4: Device checklist**

`docs/widgets-device-checklist.md`: (1) add small, medium, both Lock Screen widgets and the control; (2) open the app, open the drawer (recents load) → medium shows the three newest; (3) open Health with consent → small shows the health line, Ody's face matches; (4) revoke consent in Health's menu → the health line disappears; (5) tap each element: Ask → new chat with keyboard, chip "Plan my day" → pre-filled not sent, health chip → Health ask box filled with the attach chip, a recent → that chat, rectangular → Health; (6) lock the phone → titles and numbers redacted in StandBy / Lock Screen; (7) Control Center and Action button → new chat; (8) unpair in Settings → recents vanish from the widget; (9) evening → night sky with white text, noon → warm sky with dark text.

- [ ] **Step 5: Full test run** — WidgetKitShared, HealthFeature, ChatFeature, App tests; `python3 scripts/l10n.py audit`.

- [ ] **Step 6: Commit**

```bash
.superpowers/sdd/commit-mine.sh "feat(widgets): a DEBUG gallery of every widget, and the device checklist" \
  [--patch exodusapp.patch] Sources/App/WidgetGallery.swift docs/widgets-device-checklist.md
```
