# iOS Settings Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** implement on iOS the desktop Settings pages that make sense on a phone (spec §2): provider completion,
Personality, Memory, Built-in Tools switches, Profile/usage, installed Skills, MCP read-only, Back up now.
**Spec:** `docs/superpowers/specs/2026-09-24-ios-settings-parity-design.md`. **Run after** the message-rendering plan's
tasks A0–A6 (or interleave only where files do not overlap: this plan owns `Sources/SettingsFeature`,
`Sources/Models/Settings*.swift`, `Tests/SettingsFeatureTests`, `Tests/ModelsTests/SettingsTests.swift`).

## Global Constraints

Identical to the message-rendering plan's Global Constraints (no commits or state-changing git; catalog keys for every
string with all 10 languages and `python3 scripts/l10n.py audit` exit 0; Swift 6 strict concurrency; `xcodebuild build` +
touched test schemes; Swift Testing; no new dependency; no comments beyond one short WHY line). Plus:

- Desktop is read-only reference (`~/Code/exodus/exodus`): schema `packages/shared/src/schemas/settings-schema.ts`,
  page sources `src/renderer/components/settings/settings-form/*.tsx`, routes `src/main/lib/server/routes/`
  (`settings.ts`, `memory.ts`, `usage.ts`, `skills.ts`, `mcp.ts`, `backup.ts`), tool names
  `packages/shared/src/constants/tool-names.ts`. Never change the desktop.
- **Write path:** `POST /api/v1/settings` sets only the columns present in the body; nested objects are replaced whole;
  `lastBackupAt` is nulled unless echoed — every write goes through the helper of Task B0, never a hand-built body.
- Secrets: `SecureField` only, never logged, never persisted on the phone; no page shows a key it does not need.
- Destructive actions (delete a memory entry) need an explicit confirm.

---

### Task B0: settings store + column-level patch helper

**Files:** `Sources/Models/Settings.swift` (extend), new `Sources/SettingsFeature/SettingsStore.swift`, tests.

- [ ] Tolerant sub-structs decoded from `GET /api/v1/settings`: `personality`, `memory`, `tools` (`disabledTools:
  [String]`), plus the existing providers/providerConfig; each field optional/defaulted so a row missing any key still
  decodes (see the `ModelSnapshot` comment for why). Keep decode of unknown keys harmless.
- [ ] `SettingsStore` (`@Observable @MainActor`, uses the existing `APIClient`): `load()`, and
  `patch(_ column: String, value: some Encodable)` which posts `{ id, lastBackupAt, <column>: value }` — always echoing
  `id` and the freshly read `lastBackupAt` — after re-reading the current column (read-modify-write). Existing provider
  save flow moves onto it without behaviour change.
- [ ] Tests over `URLProtocol` mocks: decode of a fully populated row, of a row missing each optional column, patch body
  contains exactly `{id, lastBackupAt, column}`; a `null` `lastBackupAt` is echoed as null, a value as the same string.
- Done: existing SettingsFeature/Models tests pass unchanged; audit green; build green.

### Task B1: settings hub

- [ ] `SettingsView` becomes a grouped list (Computer · AI · Behaviour · Data) pushing one page per row with the existing
  pairing/connection UI and provider UI moved into their own pages unchanged; rows for pages that are not built yet are
  absent (no "coming soon" clutter). Catalog keys `ios:settings.hub.*`. Navigation keeps working with the sidebar/toolbar.

### Task B2: AI Providers completion

- [ ] Base URLs (OpenAI, Anthropic, Google, xAI), Azure endpoint + api-version, Ollama URL, following the desktop page
  (`providers-tabs.tsx`, `providers/*.tsx`) for which fields exist per provider and their placeholders. Copy states that the
  provider/model choice applies to the desktop's chats too. Keys remain `SecureField`.

### Task B3: Personality

- [ ] Read `PersonalitySchema` and `personality.tsx`; build the same fields (tone/style/custom instructions or whatever the
  schema holds), saved through the store helper with the schema's limits enforced on the phone.

### Task B4: Memory

- [ ] Toggles (`autoCapture`, `useInChat`) and limits (`memory` schema; clamp 50–95 and 2–24 like the desktop) via the
  store; the memory list from `GET /api/v1/memory` (section, key, summary, details), edit an entry (`PATCH`), delete
  (confirm) and add (`POST`) per `routes/memory.ts` and the desktop's `memory.tsx`.

### Task B5: Built-in Tools switches

- [ ] A static table of tool wire names + display titles mirrored from `TOOL_NAMES` and the desktop's `TOOL_REGISTRY`
  (only those the desktop lists as user-switchable), a toggle per tool writing `tools.disabledTools` (keeps unknown
  names already in the array untouched), and a fixture test pinning the table. Tool panels that hold API keys stay
  desktop-only.

### Task B6: Profile / usage

- [ ] Read-only usage and cost dashboard from `GET /api/v1/usage` (see `usage.ts` and `profile.tsx` for the shape and the
  periods), chat count from `/history`, using Swift Charts; empty and error states; no writes.

### Task B7: Skills (installed) and MCP (read-only)

- [ ] Installed skills list + enable/disable via `GET /api/v1/skills/installed` and `PATCH /:slug/toggle`; MCP servers
  list with active state and tool counts from `GET /api/v1/mcp` and `/mcp/tools` (toggle active only if the desktop's
  route supports a plain active flag; otherwise read-only).

### Task B8: Data — back up now

- [ ] `GET /api/v1/backup/status` (last backup time, count) and `POST /api/v1/backup/now`, with progress and result states.
  No export, import or reset.

---

## Later / not here

Voice and Deep Research settings (after read-aloud and the deep-research card exist), Skills browsing/install, MCP
add/edit, knowledge-base document list. Desktop-side hardening to record for the owner: mask secrets in `GET
/api/v1/settings` on the LAN listener (a paired device currently receives every key unmasked).
