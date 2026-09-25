# exodus-ios: message rendering (markdown first) — design

Status: written autonomously on 2026-09-24 while the repo owner slept ("模仿 exodus 的 Message 弄 ios 端的,
核心是 markdown … 具体还是靠你"). Every decision below is a ruling the owner can overturn; nothing is committed, and the
renderer sits behind one small interface so the engine can be swapped (§4).

Inputs: the desktop's own implementation (`src/renderer/components/messages.tsx`, `lib/markdown-blocks.ts`,
`markdown-plugins.ts`, `markdown-citations.tsx`, the "chat render path" section of its CLAUDE.md), a read-only survey of
both apps (`scratchpad/ios-parity-survey.md`) and a library study (`scratchpad/ios-markdown-research.md`, 2026-09-24).

## 1. Goal and scope

Make a chat reply on iOS look and behave like the desktop's: **one assistant message per run** (a run = one user message
through the final answer, with every model step and tool result between), whose body is rendered markdown, streamed
smoothly, with a collapsed thinking timeline, compact tool cards, citation chips and an action bar.

In scope (phase A, this spec): typed message model + `runId`, run grouping, a markdown renderer (GFM blocks, inline
formatting, tables, code blocks, links, images, task lists, block-wise streaming with tail healing), thinking timeline,
tool cards v1 (generic / error / terminal), copy + regenerate, citation chips + Sources sheet, run-error line.

Out of scope for now (later phases, listed in the plan's "Later"): syntax highlighting (mono + copy first), LaTeX
(`$$` only, raw TeX block first), rich tool cards (weather, deep research, artifact, computer use, map), attachments,
read-aloud, LCM compaction strip. The Settings pages that make sense on a phone are a separate spec.

## 2. What iOS does today (facts from the survey)

- `Models/ChatMessage.swift` keeps the raw JSON but exposes only content/isError/toolName/timestamp; no `runId`,
  `toolCallId`, `details`, `durationMs`, typed content blocks.
- `ChatHistoryRows` drops `runId` from `GET /chat/:id` rows.
- `ChatDetailView` renders one row per raw message; each model step is its own bubble; `MessageRow` shows inline-only
  `AttributedString(markdown:)` re-parsed on every body evaluation; a tool result is a bare "Used: name" row; the user
  bubble is parsed as markdown (the desktop shows plain text).
- `ChatStreamManager` replaces messages by id per `message_update` (correct: the wire sends the whole message so far).

## 3. Architecture

New module **`MarkdownKit`** (static framework, like the others; depends only on `apple/swift-markdown`): pure, testable
logic plus the SwiftUI view. `ChatFeature` depends on it.

```
Models      typed content blocks, runId, toolCallId, details, durationMs        (extend ChatMessage)
ChatFeature RunGrouper  (messages -> [Segment], memoised)  ── AssistantTurn { steps, body, toolCards, pending, duration }
            AssistantTurnView / ThinkingTimeline / ToolCardView / ActionBar / SourcesSheet
MarkdownKit MarkdownPreprocessor  split blocks · heal the tail · lone-~ escape · 【N-source】 rewrite
            MarkdownParser        text -> [MarkdownBlock]   (swift-markdown Document -> our small Equatable AST)
            MarkdownStreamModel   @Observable @MainActor: snapshot in, settled blocks reused, tail re-parsed
            MarkdownView          SwiftUI: memoised per-block views
```

### 3.1 Run grouping (port of `groupIntoSegments` / `buildAssistantTurn`)

Pure functions in ChatFeature, exercised on fixtures shaped like real server JSON. A segment is `.user(message)` or
`.assistantTurn(AssistantTurn)`, keyed `run:<runId>`. `AssistantTurn.body` = every assistant text block of the run joined
with `\n\n`; steps = thinking blocks and tool calls in order; a `toolCall` with no matching `toolResult.toolCallId` yet is
*pending*; the last assistant message's `durationMs` and any `errorMessage`/`stopReason` are carried. The grouper keeps
identity for segments a frame did not touch (the desktop's cache) so SwiftUI diffing stays cheap.

### 3.2 Markdown pipeline (why a preprocessor exists whatever the renderer is)

The desktop's rules are string-level and no Swift library implements them, so they live in `MarkdownPreprocessor`:

1. **Block splitting** by top-level block ranges from swift-markdown (`Markup.range`), with the `[id]:` link-definition
   check. Only the last one or two blocks can change between two streaming snapshots.
2. **Tail healing** (`remend` equivalent): close an open `**`, `*`, `~~`, `` ` `` / ``` fence and `$$`; neutralise a
   half-typed link/image; drop a half-streamed `【N-source】` marker.
3. **`~~` only strikes through.** cmark-gfm and Foundation strike single-`~` pairs (`19~32°C to 5~10°C` strikes "32°C
   to 5"); the preprocessor escapes a lone `~`.
4. **Money is not math:** no single-dollar math ever; `$$…$$` handled in a later phase (raw TeX block first).
5. **Citations:** `【N-source】` becomes a styled run linking `exodus-cite://N` (resolved to the Nth web-search result of
   the run so far, exactly like `buildCitationSources`), or is stripped when unresolved.

`MarkdownParser` maps swift-markdown's typed AST to a small `MarkdownBlock` enum (paragraph, heading, list with task
items, blockquote, code block with language, table with alignment, thematic break, image, html-as-text) whose inline
content is an `AttributedString` (bold/italic/strike/code/link runs). Everything is `Equatable & Sendable`.

`MarkdownStreamModel` receives the full message text on each `message_update`, splits it, keeps the settled prefix blocks
untouched (text equality) and re-parses only the changing tail: the same "re-parse the last block or two per frame"
budget as the desktop (swift-markdown parses ~1.9 ms per 9 KB on an M1 Max; an iPhone is slower, still far under a
frame). `MarkdownView` renders `ForEach` over blocks with each block view `Equatable`-memoised; text that never changes
(history) is parsed once.

### 3.3 Chrome

- User bubble: plain text (`pre-wrap`), not markdown.
- Thinking timeline: collapsed header ("Thought for 12 s", or the latest step while streaming); steps are thinking
  (markdown, first `**bold**` = title) and tool calls (with a monospace argument line); pending calls show a spinner.
- Tool cards v1: an error box (destructive tint) for `isError`, a terminal card (command + output, mono), and a generic
  collapsible JSON row for anything else; built-ins the desktop keeps silent stay hidden.
- Action bar under the answer: copy, regenerate, sources (when citations exist), relative time.
- A provider error is pinned to the run it ended, at the message foot; `notice` events become a banner/toast.
- Every string is a catalog key (`ios:chat.message.*`) — see the shared-locales design; audit must stay green.

## 4. Engine decision and its hedge

The study's primary recommendation was **Microsoft's `SwiftStreamingMarkdown`** (real: MIT, v0.7.0 2026-08-02, 366
stars, tables/math/code/citations/streaming built in) vendored as a local package with the preprocessor in front. This
design instead builds **the renderer on `apple/swift-markdown` 0.9.0** (the study's own "fallback") and keeps SSM as the
documented alternative. Reasons, in order of weight:

1. **Verifiability without a device.** The renderer's logic (splitting, healing, AST mapping, grouping) is pure and unit
   tested; the SwiftUI layer can be checked by launching a DEBUG-only gallery in the iOS 27 simulator and reading a
   `simctl` screenshot. A vendored third-party view can only be judged by looking.
2. **Dependency risk for a solo maintainer.** SSM is four months old, ~80 % one author, Swift 5 mode (#124 open), pins
   forks of iosMath/HighlightSwift by revision (a tagged SwiftPM version does not resolve — vendoring is the only way),
   and needs the `Equatable` macro (swift-syntax, macro-trust prompts, `-skipMacroValidation` in CI). swift-markdown is
   Apple-owned, tools 6.2, one dependency (swift-cmark).
3. **Parity by construction.** The desktop's rules (`~~` only, `$$` only, citation chips, tail healing) are ours either
   way; owning the renderer means they are first-class instead of pre-processing tricks (`$$x$$` → `\(x\)`).

Costs accepted: more code (tables, code blocks, images, selection) and no per-paragraph `UITextView` selection at first
(SwiftUI `Text` selects within one block; the action bar copies the whole answer). **Hedge:** `MarkdownView(text:
citations:isStreaming:)` is the only surface ChatFeature sees; if the custom renderer disappoints, an SSM-backed
implementation of the same view (plus the same preprocessor) drops in behind it. Textual (same author as
swift-markdown-ui; 0.x, no streaming, cannot restrict math to `$$`) is on the watch list; swift-markdown-ui (maintenance
mode) and Down (last push 2023) are rejected.

## 5. Testing and verification

- Pure logic (preprocessor, parser, stream model, grouper, model decoding): Swift Testing suites in
  `Tests/MarkdownKitTests` and `Tests/ChatFeatureTests`, fixtures copied from real server JSON and ported from the
  desktop's own `markdown-blocks.test.ts` / `messages-*.test.ts` cases (including `19~32°C`, `$200 - $300`, an unclosed
  fence, a half-typed link, a half `【` marker).
- View layer: a DEBUG-only gallery screen (launch argument) rendering the fixtures; screenshots via `xcrun simctl io
  booted screenshot` on the iOS 27 simulator, reviewed by reading the PNGs; Dynamic Type at default and XXL, light and
  dark.
- Gate for every task (no commits — see plan): `xcodebuild build` for the App scheme (Simulator, no signing),
  `xcodebuild test` for the touched test targets when the simulator is available, `python3 scripts/l10n.py audit`.

## 6. Risks

- Tuist + an external SwiftPM package is new for this repo (no `Tuist/Package.swift` today): Task A0 proves it first.
- Streaming layout jank cannot be measured off-device; the design bounds per-frame work (tail-only parse, memoised
  blocks) and the gallery includes a synthetic stream to eyeball it.
- Very long code lines and wide tables need horizontal scroll containers; images need size caps.
