# exodus-ios: Chat + Settings MVP Design

Status: approved for implementation
Date: 2026-09-18

## 1. Context

`universal-client` (sibling repo, `../universal-client`) is Exodus: an Electron desktop app whose
entire business logic runs behind a Hono HTTP server on `localhost:60223`, inside the same
process as the Electron main process. The renderer (React) talks to that server exclusively over
HTTP/SSE — never Electron IPC for app data. Because the backend is a normal HTTP server, it is
trivially reachable from any other client, including a phone on the same network.

`exodus-ios` is a pure frontend for that same backend. It ships no server, no database, no auth —
it is a Swift/SwiftUI client that calls the same REST/SSE contract the React renderer already
uses. Authentication is explicitly out of scope (the desktop app has none either — trust is
currently "same machine" / "same network").

Goal of this spec: get the smallest useful slice — **Chat** (list, send, stream, delete) and
**Settings** (pick an AI provider + model, enter its API key) — running natively on iPhone, built
on an architecture that doesn't need to be re-thought when the next surface (Philharmonic, then
phone→desktop remote control) gets added.

Test target for this phase: iOS Simulator + a running `universal-client` dev instance on
`localhost:60223` (simulator shares the Mac's network stack, so literal `localhost` works there).

## 2. Non-goals (this phase)

Explicitly deferred, not because they're unimportant, but to keep this slice shippable:

- Philharmonic (multi-agent Groups) — real screens. A navigation *hook* for it is in scope (§5).
- Auth / pairing / any non-local trust model.
- Chat: rename, cross-chat search, Projects, image/file attachments, rich per-tool-type result
  cards, thinking/multi-step timeline grouping, Deep Research, LCM status.
- Settings: everything except AI Providers (no Personality, Memory, Knowledge Base, MCP, S3,
  Elasticsearch, Voice, Discover, Computer Use, Logger, Keyboard Shortcuts, i18n locale switch).
- Local persistence of chat history (SwiftData, caching) — the Mac's PGlite DB is the only source
  of truth; the app always fetches live.
- Phone → desktop remote control (Computer Use trigger from iOS). Addressed only as forward-looking
  design in §6 — not built.

## 3. Backend contract (as consumed by this app)

All requests go to a configurable base URL (§4.4), mirroring `BASE_URL` in
`src/shared/constants/systems.ts` on desktop (`http://localhost:60223` by default).

**Chat**
- `GET /api/history` → chat list (id, title, updatedAt, …)
- `POST /api/chat` → SSE stream. Body: `{ id: uuid, messages: ChatMessage[], advancedTools: [], reasoningEffort?, projectId? }`.
  `messages` is the **full** running transcript (not just the new message) — the server reads
  `messages.at(-1)` as the new turn. `advancedTools` is a required array; send `[]` (Deep Research
  is out of scope). Omit `reasoningEffort` and `projectId`.
  Events: `message_update | tool_call_start | tool_call_end | done | title | error | notice`,
  each a `data: <json>\n\n` SSE frame (see `src/shared/types/chat.ts` → `ChatSseEvent`).
- `GET /api/chat/:id` → full message history for one chat.
- `DELETE /api/chat/:id` → delete.
- **Not called this phase:** `PUT /api/chat` (rename), `GET /api/chat/search`.
- The server resolves model + API key from **saved Settings** — the chat request body carries
  neither. Settings must be configured before Chat can produce a response.

**Settings**
- `GET /api/settings` → the full settings row (single global row, id `"global"`, no user scoping).
- `POST /api/settings` → **key-level patch, not a full replace.** `updateSettings()`
  (`src/main/lib/db/queries.ts`) spreads the payload's top-level keys straight into Drizzle's
  `.set()`; a key absent from the payload is never touched. Confirmed by reading that function —
  this app can safely `POST` `{ id: "global", providerConfig, providers }` without clobbering
  Personality/Memory/KB/etc. configured from the desktop app.
- `POST /api/settings/models` → `{ provider, apiKey, baseUrl?, apiVersion? }` → live model catalog
  for that provider (`{ models: CachedModelEntry[] }`, each `{ id, displayName, snapshot }`). Used
  to populate the model picker instead of a free-text field.

**Error shape** (`src/shared/utils/http.ts`): non-2xx JSON responses are
`{ type: "error", error: { code, message, params?, hasCustomMessage? } }`. Success responses are
the raw payload, no envelope. All JSON keys are camelCase — no key-decoding-strategy juggling
needed on the Swift side.

## 4. Architecture

### 4.1 Tuist module graph

```
App  ──depends on──▶  ChatFeature
  │                    SettingsFeature
  │                    PhilharmonicFeature  (stub)
  │                    NetworkingKit
  ▼
(composition root: scene wiring, the workspace switcher, DI)

ChatFeature         ──▶ NetworkingKit, Models
SettingsFeature      ──▶ NetworkingKit, Models
PhilharmonicFeature  ──▶ Models                (no NetworkingKit dependency yet — stub has nothing to fetch)
NetworkingKit        ──▶ Models
Models                (no dependencies — pure Codable types / enums)
```

Feature modules never depend on each other — `ChatFeature` has no idea `PhilharmonicFeature`
exists, and vice versa. Only `App` composes them together. This is what makes the workspace
switcher (§5) additive later instead of a refactor.

- **Models** — Swift mirror of `src/shared/types/chat.ts` + the MVP slice of
  `src/shared/schemas/settings-schema.ts`: `ChatMessage` (enum over user/assistant/toolResult),
  `ChatSseEvent`, `AiProviders`, `ProviderConfig`, `ProvidersConfig`, `CachedModelEntry`.
- **NetworkingKit** — `APIClient` (REST), `SSEClient` (streaming), `ChatStreamManager` (§4.2).
- **ChatFeature** — chat list, chat detail, composer. Owns its own `@Observable` view models.
- **SettingsFeature** — AI Providers form + the local Server URL field.
- **PhilharmonicFeature** — one placeholder view ("即将支持"). Exists now purely so the module
  boundary and the `App`-level dependency edge are already correct.
- **App** — `@main` entry, root navigation shell, the workspace switcher, and whatever minimal DI
  (constructing one shared `APIClient`/`ChatStreamManager` instance and handing it to feature
  modules) is needed to wire features together.

Target platform: iOS only for this phase (no iPad/Mac Catalyst consideration yet — nothing here
blocks adding it later). Deployment target: iOS 17+, to use the `@Observable` macro and modern
structured-concurrency APIs throughout instead of Combine/`ObservableObject`.

### 4.2 Networking / streaming layer

Hand-rolled `URLSession`-based client — no third-party dependency. Considered and rejected:
Combine (Apple's own direction has moved to async/await + Observation; adds ceremony with no
benefit here), and pulling in an SSE/HTTP library (the protocol is bespoke — `ChatSseEvent`'s
event names and payload shapes are Exodus-specific, so a generic library still needs a hand-written
parser on top; not worth the dependency).

- **`APIClient`**: `func send<T: Decodable>(_ endpoint: Endpoint) async throws -> T`. Builds the
  request against the configured base URL (§4.4), decodes success bodies directly, decodes
  `{ type: "error", error: {...} }` into a Swift `HTTPError` (mirroring `HttpError` in
  `src/shared/utils/http.ts`) on non-2xx.
- **`SSEClient`**: wraps `URLSession.bytes(for:)`. Buffers the byte stream into lines, extracts
  `data: ` frames, JSON-decodes each into `ChatSseEvent`, and yields them as an
  `AsyncThrowingStream<ChatSseEvent, Error>`. This is a direct port of the line-buffering loop in
  `consumeStream()` (`src/renderer/lib/stream-manager.ts`).
- **`ChatStreamManager`** (actor singleton): owns in-flight streams keyed by chat id, mirroring
  `stream-manager.ts`'s `streams: Map<string, ActiveStream>`. Starting a send kicks off a task that
  survives the view disappearing; a view reappearing for that chat id re-subscribes to current
  state instead of losing progress or double-sending. This preserves the desktop app's "leave the
  chat, come back, the response finished streaming in the background" behavior.

### 4.3 Data flow

Each screen owns an `@Observable` view model that talks to `NetworkingKit` directly via
`async`/`await` (plus subscribing to `ChatStreamManager` for the active chat). No local persistence
layer, no SwiftData, no caching beyond what's held in memory for the current view model's lifetime
— every screen re-fetches from the server as the source of truth, consistent with "no local-first
duplication of state the Mac already owns."

### 4.4 Server address

Client-local preference, **not** part of the backend Settings schema (the backend has no concept
of "where am I" — it doesn't need one, everything talks to it, not the reverse). Stored in
`UserDefaults` on-device. Default: `http://localhost:60223`. Surfaced as a "连接" section at the
top of the Settings screen, above the AI Providers section, so pointing the app at a different
address is possible without a rebuild.

This is the field that turns into a real host/IP once testing moves off the Simulator onto a
physical device (`localhost` on a physical iPhone resolves to the phone itself, not the Mac) — see
§6.

## 5. Chat feature

**Screens**
- **Chat list** (`GET /api/history`): rows = title + relative-updated-time. Swipe-to-delete
  (`DELETE /api/chat/:id`). "+" toolbar button starts a new chat — client generates a v4 UUID
  locally; no server-side chat record exists until the first message is actually sent (matches
  `chat.post('/')`'s `if (!existingChat) saveChat(...)` on desktop).
- **Chat detail** (`GET /api/chat/:id` on open, then live via `ChatStreamManager`): messages
  rendered top-to-bottom in arrival order — one bubble per `ChatMessage`. User/assistant bubbles
  render Markdown via `AttributedString(markdown:)` (bold/italic/inline code/lists — no syntax
  highlighting, no Mermaid, no math; desktop's Monaco/Three.js-backed rendering is out of scope).
  A `toolResult` message renders as one generic collapsed row ("Used web_search" with a
  success/error glyph) rather than per-tool-type rich cards — tool calls can still occur even
  though `advancedTools: []` is sent, because built-in tool binding on the server is driven by
  Settings, not by this flag; the UI must not choke on them, it just doesn't need to render them
  beautifully yet.
- **Composer**: plain text field + send button. No attachments this phase.

**Message/turn identifiers**: client generates `UUID().uuidString.lowercased()` for both the chat
id and each new user message id — matches `uuidV4()` usage in `use-chat.ts` / `postRequestBodySchema`'s
`z.uuid('v4')`.

## 6. Settings feature

One screen, two sections:

1. **连接** (client-local, UserDefaults): Server URL text field, defaulting to
   `http://localhost:60223`.
2. **AI Providers** (backend-synced): provider picker (the 6 `AiProviders` enum cases — OpenAI
   GPT, Azure OpenAI, Anthropic Claude, Google Gemini, xAI Grok, Ollama), an API key field for
   whichever provider is selected, and a model picker populated by calling
   `POST /api/settings/models` once a key is entered (falls back to manual entry if that call
   fails — e.g. bad key). Saves via `POST /api/settings` with only `{ id: "global", providerConfig,
   providers }` in the body (§3 — confirmed safe as a partial patch).

Everything else in the 19-tab desktop Settings surface (Personality, Memory, Knowledge Base, MCP,
S3, Elasticsearch, Voice, Discover, Computer Use, Logger, Keyboard Shortcuts, About) is out of
scope for this phase and simply isn't read or written by this app.

## 7. Workspace switcher hook (Chat ⇄ Philharmonic)

Desktop's sidebar has a "ChatGPT-style" workspace picker (`workspace-switcher.tsx`) — a dropdown
reading "Chat ▾" that switches between the `/` (Chat) and `/philharmonic` top-level routes.
Philharmonic is explicitly called out by the user as the actual high-value surface long-term, so
the navigation shell should already assume a second workspace exists, even though this phase only
implements Chat.

iOS equivalent: the root navigation bar's title is a native `Menu` (the same pattern iOS apps like
Mail/Files use for a tappable-title dropdown) listing "Chat" and "Philharmonic". Philharmonic is
present but disabled/"即将支持" — selecting it is inert this phase, not missing. This is driven by
an `AppWorkspace` enum (`.chat`, `.philharmonic`) that lives in `App` (the composition root), not
in `Models` — it's a navigation concept, not a wire type.

The real payoff is structural, not visual: because `PhilharmonicFeature` already exists as its own
Tuist target (§4.1) with the dependency edge from `App` already wired, turning the placeholder into
a real feature later is additive work inside that target plus flipping the menu item from disabled
to enabled — it does not touch `ChatFeature`, `NetworkingKit`, or the app's composition root beyond
that one flag.

## 8. Forward-looking: phone → desktop control (Phase 2, not built now)

Recorded so the current design doesn't foreclose it, not because any of this is being built in
this phase.

- Desktop already has a Computer Use V0 substrate (`src/main/lib/computer/`): an `exodus-input`
  Swift helper for screenshots/CGEvent input, a perceive→act loop, and a `/api/computer-use` route
  already bound as a calling-tool. A phone-triggered "make the Mac do X" flow has a real backend to
  target later — it doesn't need to be invented from scratch.
- Connectivity, in order of how far the phone is from the Mac:
  - Same LAN: the configurable Server URL (§4.4) already covers this.
  - Same LAN, no manual IP entry: Bonjour/mDNS service discovery — the Mac's Hono process could
    advertise itself and the app could list nearby Macs instead of asking for an address.
  - Off-LAN (phone on cellular, Mac at home/office): **Tailscale** (or another WireGuard-based
    mesh) is the standard, low-maintenance answer for "reach my own machine from anywhere" —
    avoids hand-rolling NAT traversal or standing up a relay server. Recommended over building
    custom tunneling.
- Auth: skipped entirely in this phase because the trust model is "same machine / same LAN." That
  assumption breaks the moment traffic can arrive over Tailscale/the internet — at minimum a
  generated token (Settings on desktop issues one, the phone sends it as a header) would be needed
  before any off-LAN exposure ships. Not built now; the Server URL field being already
  user-editable makes adding a token field alongside it a small follow-up, not a redesign.

## 9. Open assumptions

- iOS 17 as the deployment floor is a default, not a requirement stated by the user — revisit if
  device coverage needs turn out to matter.
- Tool-call handling in Chat (§5) assumes the user's already-configured desktop Settings may still
  trigger built-in tools despite `advancedTools: []`; the generic "Used: toolName" row is a
  deliberate placeholder, not a claim that tool calls won't happen in this phase.
