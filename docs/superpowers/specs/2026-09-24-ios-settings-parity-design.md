# exodus-ios: Settings parity — design

Status: written autonomously on 2026-09-24 while the repo owner slept ("Settings 中值得在 ios 上实现的也实现一下").
Every verdict below is a ruling the owner can overturn. Source: a read-only survey of the desktop's 21 Settings pages and
the iOS `SettingsFeature` (`scratchpad/ios-parity-survey.md`, §2), plus the server's settings write path.

## 1. What a phone Settings should be

The phone is a remote for a desktop that owns the data. So the phone gets the settings that (a) change how chats
feel or behave, (b) are pure forms with no external infrastructure, (c) a person plausibly changes from a sofa — and
none of the ones that (d) configure infrastructure or secrets (Elasticsearch, LightRAG, S3), (e) drive the desktop's own
OS (computer use, updater, shortcuts, launch at login, pairing management), (f) are developer tools (logger, SQL
console), or (g) are destructive (import, export, reset). The provider/model choice is global: it changes the desktop's
chats too — the UI says so.

## 2. Verdicts (desktop page → iOS)

| Desktop page | iOS | Notes |
|---|---|---|
| AI Providers | Already, partial → **complete** | add base URLs, Azure endpoint / api-version, Ollama URL; keys stay `SecureField`, never logged or cached beyond the session |
| Personality | **Build** | `settings.personality` pure form, affects every chat |
| Memory | **Build** | `settings.memory` toggles and limits (clamp 50–95 / 2–24) + browse / edit / delete entries via `/api/v1/memory` |
| Built-in Tools | **Build (switches)** | `settings.tools.disabledTools`; tool names are hard-coded in `TOOL_NAMES` (no list endpoint) — a static table mirrored from the desktop, with a test that pins it against a fixture |
| Profile | **Build (read-only)** | usage / cost dashboard from `GET /usage` (+ chat count from `/history`), Swift Charts |
| Skills Market | **Build installed list + toggle** | `/skills/installed`, `PATCH /skills/:slug/toggle`; browsing/installing a skill stays desktop (it installs prompts the agent will run) |
| MCP Servers | **Build read-only + active toggle** | `/mcp` list and `/mcp/tools`; add/edit stays desktop (stdio commands, env/header secrets) |
| Data Controls | **Build "Back up now"** | `/backup/status`, `/backup/now`; export / import / reset are desktop-only |
| Voice, Deep Research | Later | only meaningful with read-aloud / dictation and the deep-research card |
| Discover, General, Keyboard Shortcuts, About, Devices, Full Text Search, Knowledge Base, Computer Use, AWS S3, Logger, Chat Audit | **Desktop-only** | reasons in §1 |

## 3. Architecture

- **Settings I/O.** Today `SettingsSnapshot` decodes 4 keys and `SettingsPatch` encodes 4. Replace with a small settings
  store: one tolerant `GET /api/v1/settings` decode into typed sub-structs (each decodes leniently — a stored row can lack
  any key), and a **column-level patch helper**: `POST /api/v1/settings` runs Drizzle `.set({...rest})` so only the
  columns present in the body change, nested objects are replaced whole (so: read-modify-write of the one column),
  and **`lastBackupAt` is nulled unless echoed** — the helper always echoes `id` and `lastBackupAt`. The server does no
  validation, so the phone enforces ranges (memory sliders) and never sends a partial nested object it did not first read.
- **Concurrency.** The desktop autosaves per column, last write wins. A page re-reads its column on appear and before
  each save; no optimistic merge across pages.
- **Structure.** `SettingsView` becomes a hub (grouped list: Computer, AI, Behaviour, Data), each page a view +
  `@Observable @MainActor` view-model in `SettingsFeature`, tests on the view-models (Swift Testing, `URLProtocol`
  mocks like the existing suites). Strings are `ios:settings.<page>.*` catalog keys; audit stays green.
- **Security posture.** `GET /settings` returns every secret unmasked to a paired device (a desktop-side hardening item
  — masking on the LAN listener — outside this spec; recorded in the plan). The phone never shows a secret it does not
  need, shows keys in `SecureField` only, never logs bodies, never persists settings to disk.

## 4. Testing and verification

View-model tests over mocked HTTP (load, decode leniency, save payload shape incl. the `lastBackupAt` echo, clamping,
error paths); the gallery/screenshot approach of the message-rendering spec for page layout; `xcodebuild build` + tests;
`python3 scripts/l10n.py audit`.

## 5. Risks

- The static tool-name table drifts from the desktop's `TOOL_NAMES`; the fixture test pins today's list and the plan asks
  for a comment-free check that fails loudly when the server reports an unknown name.
- Provider/model/base-URL edits are global and immediate on the desktop; confirmation copy says so.
- Memory editing writes user data; every destructive action is an explicit confirm.
