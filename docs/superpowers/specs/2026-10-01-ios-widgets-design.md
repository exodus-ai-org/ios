# iPhone widgets — design

Date: 2026-10-01 · Status: approved in brainstorming, awaiting spec review
Amended 2026-10-01 (plan): the health suggestion opens Health's ask box, which already attaches the day and never auto-sends.
Repo: `exodus-ios` only (no desktop change)
Prototypes: `.superpowers/brainstorm/39692-1790855953/content/` (`widget-direction.html`, `lockscreen-control.html`)

## 1. Goal

Widgets whose main job is **getting into a conversation with Exodus** from the Home Screen, Lock Screen, Control Center and the Action button, with a light touch of **today's health** (one line of numbers, Ody's mood, a health-derived suggested question).

### What the user said vs. what we assumed

| Decided by the user | Assumed / recommended and accepted |
|---|---|
| Mainly "Ask Exodus" (B), plus a little of the Health glance (A) | Ody is the face of every widget |
| Home small + medium, Lock Screen, Control Center / Action button control | No large widget (not enough content to fill it) |
| Medium shows the 3 most recent chats (titles on the Home Screen are fine) | Titles are `privacySensitive` (redacted when locked / StandBy) |
| Visual direction **A · Night sky** (the Health hero's sky, Ody standing in it) | Sky follows the clock via `DaySky`; ink flips dark by day |
| Lock Screen: **circular Ask** + **rectangular "today in a line"** only | No steps ring, no inline accessory |
| Data approach ①: the app writes a snapshot, the widget only renders it | HealthKit-in-extension (③) is a possible later addition, not v1 |

### Non-goals (v1)
- No network, keychain or pairing credentials in the extension.
- No interactive input in widgets (iOS has none); every tap opens the app.
- No large widget, no StandBy-specific layout, no Live Activity.
- No auto-send: a pre-filled question is never sent without the user tapping Send.

## 2. Architecture

### 2.1 Targets and modules
- **`WidgetKitShared`** (new framework, pure Swift, depends on nothing but Foundation): `WidgetSnapshot`, `SnapshotStore`, `DeepLink`, and the pure presentation rules (`WidgetPresentation`: greeting period, Ody mood, ink, staleness). Linked by the app and the extension. Tests: `WidgetKitSharedTests`.
- **`ExodusWidgets`** (new app extension, `bundleId: app.yancey.exodus.exodus-ios.widgets`): a `WidgetBundle` with `AskWidget` (`.systemSmall`, `.systemMedium`), `TodayAccessoryWidget` (`.accessoryCircular` → Ask, `.accessoryRectangular` → today), and `AskControl` (`ControlWidgetButton`). Depends on `WidgetKitShared` and `OdyKit` (Ody figure and `DaySky`) only.
- **App Group** `group.app.yancey.exodus` on both the app and the extension (entitlements in `Project.swift`).
- **URL scheme** `exodus` registered in the app's Info.plist.

### 2.2 Snapshot
```swift
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var version = 1
    var updatedAt: Date
    var recentChats: [RecentChat]      // at most 3, newest first
    var health: HealthGlance?          // nil: no consent, no report, or unpaired
}
struct RecentChat: Codable, Equatable, Sendable { var id: String; var title: String; var updatedAt: Date }
struct HealthGlance: Codable, Equatable, Sendable {
    var day: String                    // "yyyy-MM-dd", the report's day
    var sleepMinutes: Int?
    var steps: Int?
    var stepGoal: Int?
    var headline: String?              // the daily note's headline
    var suggestion: String?            // one question derived from today's note
    var mood: OdyMood                  // .sleepy / .happy / .neutral, decided by the app
}
```
- Stored as `widget.json` in the App Group container; written atomically with `.completeFileProtectionUntilFirstUserAuthentication` (the extension must read it while locked).
- Only titles and summary numbers; never message content.
- A missing, unreadable or newer-version file reads as an empty snapshot.

### 2.3 Who writes it (app side)
A small `WidgetSnapshotWriter` in the app target, fed by:
- **Chat list** loaded or changed → `recentChats` (top 3 by `updatedAt`).
- **Health report** generated or read from cache (with consent) → `health`.
- **Consent withdrawn** in Health → `health = nil`.
- **Unpaired** → empty snapshot.

Each write that changes the snapshot calls `WidgetCenter.shared.reloadAllTimelines()`; an unchanged snapshot is not rewritten.

### 2.4 Deep links
| Link | App does |
|---|---|
| `exodus://chat/new` | Chat workspace, fresh empty chat, composer focused |
| `exodus://chat/new?prompt=<text>` | Same, composer pre-filled; never sent automatically. |
| `exodus://health?ask=<text>` | Health workspace, its ask box pre-filled; today's data attached as Health's ask attaches it (per consent); never sent automatically. |
| `exodus://chat/<id>` | Opens that chat; an unknown id opens a chat that shows the server's error, and the drawer still lists the rest |
| `exodus://health` | Health workspace |

`DeepLink` builds and parses these; anything else (unknown host/path, prompt over 500 characters, empty id) parses to `nil` and the app ignores it. Handled by `.onOpenURL` in `AppShell`; links arriving while the unlock or pairing gate is up wait until it is passed.

### 2.5 Timeline
- One entry per hour for the next 12 hours, starting now; policy `.atEnd`. Each entry carries the snapshot and its date.
- The sky is `DaySky.gradient(atClockHour:)` at the entry's hour; ink is white when the sky's top colour has a relative luminance (WCAG: sRGB → linear, 0.2126/0.7152/0.0722) below 0.18, the dark ink otherwise — the sky's own brightness, not `DaySky.night`, which still reads day while the dusk sky is already deep violet.
- `health` is shown only when `health.day` is the entry's day; otherwise the health parts are hidden (never yesterday's numbers as today's).

## 3. Widgets

### 3.1 Home small (`AskWidget`, night sky)
- Top line (when today's health exists): `☾ 5:52 · 1,251 steps`; otherwise the greeting moves up.
- Greeting by period: morning (5–12), afternoon (12–18), evening (18–5) + "Want to talk?".
- Ody on the right, static, expression from `mood`.
- Bottom: "Ask Exodus…" capsule with a marigold send glyph. Whole widget → `chat/new`.

### 3.2 Home medium
- Left column: health line; the health suggestion chip (→ `health?ask=…`); one general chip (→ `chat/new?prompt=…`, a fixed localized "Plan my day"); the Ask capsule (→ `chat/new`).
- Right column: "Recent" and up to 3 chats (title + relative time) each → `chat/<id>`; none: "No chats yet".
- Uses `Link` per element; the widget background → `chat/new`.

### 3.3 Lock Screen
- **Circular**: Ody outline (`widgetAccentable`) → `chat/new`.
- **Rectangular**: line 1 the note's headline, line 2 sleep + steps / goal → `health`. Without today's note: "Ask Exodus" → `chat/new`.

### 3.4 Control
- `AskControl`: `ControlWidgetButton` with an `OpenIntent` that opens `exodus://chat/new`; label "Ask Exodus", Ody outline symbol. Usable in Control Center and on the Action button.

### 3.5 Rendering modes, empty state, privacy
- Full colour: night sky. Accented / clear Home Screen modes: no sky, Ody outline and text only (`widgetRenderingMode`).
- Never paired / never opened: greeting, Ody and the Ask capsule; "No chats yet". No error, no pairing prompt — the app handles that once opened.
- Chat titles and health numbers are `.privacySensitive()`.
- All strings in `Localizable.xcstrings` (extension shares the catalog), 10 languages via `scripts/l10n.py`.

## 4. Error handling
- Snapshot unreadable → empty snapshot (empty state).
- App fails to write → logged, the widget keeps the last good snapshot.
- Bad deep link → ignored. Unknown chat id → that chat opens and shows the server's error; the drawer still lists the rest.

## 5. Testing and verification
- **`WidgetKitSharedTests`**: snapshot round trip and tolerant decode; store write/read, missing and corrupt file; every `DeepLink` round trip and rejections (unknown path, long prompt, empty id); timeline entries per hour, ink flip at dusk and dawn, stale health hidden; mood rules.
- **App tests**: the writer writes/clears on chat list change, report, consent withdrawn, unpair; unchanged snapshot not rewritten; `AppShell` deep-link routing (new, pre-filled not sent, `exodus://health?ask=…` opens Health's ask box pre-filled and never sent, unknown id → the chat shows the server's error, waits behind the gates).
- **Simulator**: a DEBUG `-WidgetGallery` page rendering every family on fixture snapshots at 07:00, 12:00, 18:30, 23:00, the empty state, dark mode and AX5; screenshots to `.superpowers/widget-*.png`. Then the real widgets on the simulator Home Screen, tapping each link.
- **Device (user)**: add to Home and Lock Screen; chat or refresh Health and see the widget update; Control Center and Action button open a new chat.
