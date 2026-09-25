# iOS Message Rendering (phase A: markdown core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** an assistant reply on iOS renders like the desktop's: one message per run, markdown body streamed block by
block with tail healing, collapsed thinking timeline, compact tool cards, citation chips, action bar.

**Spec:** `docs/superpowers/specs/2026-09-24-ios-message-rendering-design.md` (engine decision and hedge in §4).
**Read first, per task:** the desktop sources named in each task (repo `~/Code/exodus/exodus`, read-only) and their
tests — they are the parity fixtures.

## Global Constraints

- **No `git commit` / `add` / `stash` / `checkout` / `restore` / `reset`** — the repo owner's standing rule; work directly
  on `main` in the working tree. The controller snapshots the tree before each task and reviews the diff between
  snapshots. Read-only git is fine. Never revert the owner's uncommitted edits (LAN port 60224 → 63129 in
  `PairingLink.swift`, several `Tests/**`, one README line) or the locale migration already in the tree.
- **Every user-visible string is a catalog key** per the shared-locales design (`docs/superpowers/specs/2026-09-23-shared-desktop-locales-design.md`
  and the README "Localization" section): `ios:chat.message.<element>` for iOS-only strings, a desktop key
  (`chat:…`, `common:…`) only when the meaning is identical; views use the literal key, non-view code
  `String(localized:defaultValue:comment:)` (hostless test targets have no catalog); all 10 languages authored in the same
  change via `python3 scripts/l10n.py add … --en-value …` + `fill`; **`python3 scripts/l10n.py audit` must exit 0** at the
  end of every task.
- **Build gate:** `xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination 'generic/platform=iOS Simulator'
  -derivedDataPath <scratchpad>/DerivedData CODE_SIGNING_ALLOWED=NO` must succeed; tests: `xcodebuild test` for the
  touched test schemes on an iOS 27.0 simulator (`xcrun simctl list devices available`; boot one, shut it down after) —
  if the simulator cannot run for an environment reason, say so and fall back to `swiftc -parse` + the build.
- **Swift 6 language mode, strict concurrency**, iOS 27 target. Swift Testing (`import Testing`, `@Suite`, `@Test`) like
  the existing suites. Types that cross isolation are `Sendable`; `@MainActor` only on UI-facing models.
- No third-party dependency except `apple/swift-markdown` (task A0). No comments beyond one short WHY line.
- Match the desktop's behaviour, not its code: parity rules in the spec §3.2 are requirements.

---

### Task A0: `MarkdownKit` module + swift-markdown dependency (spike that unblocks everything)

**Files:** `Project.swift`, new `Tuist/Package.swift`, `Tuist.swift` if needed, `Sources/MarkdownKit/` (a placeholder
type is enough), `Tests/MarkdownKitTests/` (one smoke test), `.gitignore` if Tuist writes local artefacts.

- [ ] Add `apple/swift-markdown` **exact 0.9.0** as an external Tuist package (`Tuist/Package.swift` with
  `PackageSettings`, product `Markdown`), new static-framework target `MarkdownKit` via the existing `moduleTarget`
  helper depending on `.external(name: "Markdown")`, a `MarkdownKitTests` target following the pattern of the other test
  targets, and `ChatFeature` depending on `MarkdownKit`. Run `tuist install` then `tuist generate --no-open` (Tuist 4.208
  is at `/opt/homebrew/bin/tuist`). Prove: `import Markdown` compiles in `MarkdownKit`, a smoke test parses
  `"# Hi\n\ntext"` and finds one heading and one paragraph via `Document.children`, the App scheme builds, the workspace
  still contains all previous targets.
- [ ] Record in the report exactly which files Tuist generated or modified (`Derived/`, `Tuist/.build`, the xcworkspace…)
  and which of them are tracked in git today, so the owner knows what to commit later.
- Done when: build gate green; `MarkdownKitTests` passes; nothing else changed.

### Task A1: typed message model

Read: desktop `packages/shared/src/types/chat.ts`; `Sources/Models/ChatMessage.swift`, `ChatSseEvent.swift`,
`Sources/ChatFeature/ChatHistoryRows.swift`, `ChatMessage+AnswerText.swift`; existing `Tests/ModelsTests/ChatMessageTests.swift`.

- [ ] `ChatMessage` gains `runId: String?`, `toolCallId: String?`, `toolName` (exists), `details: JSONValue?`,
  `durationMs`, `stopReason`, `errorMessage`, and typed content: `enum ContentBlock { text(String), thinking(String),
  toolCall(id:name:arguments:), image(mimeType:dataURL) , unknown(JSONValue) }` decoded from `raw` (keep `raw`
  round-tripping untouched — unknown fields must survive an encode/decode round trip, as today).
- [ ] `ChatHistoryRows.uiMessages` stops dropping `runId` (the desktop's `convertToUIMessages` keeps it).
- [ ] Outgoing user messages: check the server schema (`src/main/lib/server/schemas/chat.ts` in the desktop repo) and
  stamp `runId` on the user message exactly the way the desktop client does if the server expects the client to.
- [ ] Tests from real-shaped JSON (copy shapes from desktop tests/fixtures): user string content, user array content
  with image, assistant with text + thinking + toolCall, toolResult with `details`, an errored assistant.
- Done when: existing tests still pass unchanged, new ones pass, audit green.

### Task A2: run grouper

Read: desktop `src/renderer/components/messages.tsx` (`groupIntoSegments`, `buildAssistantTurn`,
`buildCitationSources`, the segment cache), `messages-grouping.test.ts`, `messages-rerender.test.ts`.

- [ ] `ChatFeature/RunGrouper.swift`: `enum Segment { user(ChatMessage), assistantTurn(AssistantTurn) }` keyed
  `run:<runId>` (a message without `runId` — old rows — is a run of its own), `struct AssistantTurn: Equatable, Sendable
  { id, steps: [Step], body: String, toolCards: [ToolCard], pending: [PendingToolCall], citations: [CitationSource],
  durationMs: Int?, error: String? }`, `Step { thinking(String) | toolCall(name, argumentSummary, isError, resultCount) }`.
  Pure function `RunGrouper.group(_ messages: [ChatMessage], cache: inout Cache) -> [Segment]` returning the *same*
  values (equal identity by `Equatable` + a stored generation) for runs a frame did not touch.
- [ ] Ported test cases: one run with two assistant steps + tool calls + results → one turn, body = texts joined `\n\n`;
  pending tool call (no result yet); tool error; run without `runId`; two runs → two turns; a streaming frame that only
  changes the last message leaves earlier segments unchanged.
- [ ] Wire: `ChatDetailViewModel` exposes `segments` (grouped from `messages`); leave the view on `messages` until A5.

### Task A3: markdown core (`MarkdownKit`, pure logic)

Read: desktop `src/renderer/lib/markdown-blocks.ts`, `markdown-plugins.ts`, `markdown-citations.tsx`, `markdown.tsx`
(the "prose is not markup" settings), tests `tests/unit/renderer/lib/markdown-blocks.test.ts` and the remend cases in
`use-chat`/markdown tests; the study `~/…/scratchpad/ios-markdown-research.md` §Recommendation for verified behaviours.

- [ ] `MarkdownPreprocessor`: `splitBlocks(_ text: String) -> [Substring]` (swift-markdown top-level block ranges, plus the
  link-reference-definition check), `healTail(_ text: String) -> String` (close `**`, `*`, `_`, `~~`, inline `` ` ``,
  fenced code, `$$`; neutralise a half-typed `[text](url` link or `![`; drop a trailing incomplete `【…` marker; never
  alter text inside a closed fence), `escapeLoneTilde(_:)` (`19~32°C to 5~10°C` unchanged visually, `~~x~~` still strikes),
  `rewriteCitations(_:) -> (String, [Int])`.
- [ ] `MarkdownBlock` (Equatable, Sendable) + `MarkdownParser.parse(_:) -> [MarkdownBlock]`: paragraph, heading(level),
  list(ordered/unordered, start, items with optional task checkbox and nested blocks), blockquote, codeBlock(language?,
  text), table(alignments, header, rows), thematicBreak, image, htmlBlock as plain text. Inline content as
  `AttributedString` (strong/emphasis/strikethrough/inline code/link runs; soft break → space, hard break → newline;
  citation links carry `exodus-cite://N`). No math or highlighting yet.
- [ ] `MarkdownStreamModel` (`@MainActor @Observable`): `update(text:)` — reuse settled blocks whose source text is
  unchanged, re-parse only the tail; `isStreaming` heals the last block; a finished/history document is parsed whole once.
- [ ] Tests (Swift Testing, many, table-driven where sensible): every preprocessor rule incl. the desktop's own cases,
  parser output for each block kind, GFM table alignment, nested lists, task list, `$200 - $300` stays text, `~~` vs `~`,
  unclosed fence while streaming, half link, half `【`, stream model reuse (count of re-parsed blocks per update), a 5 000-
  character document with 60 incremental updates re-parses O(tail) (assert via an injected parse counter).
- Done when: all pass; module has no SwiftUI import (pure).

### Task A4: `MarkdownView` + DEBUG gallery

- [ ] `MarkdownView(text: String, citations: [CitationSource], isStreaming: Bool)` in MarkdownKit (SwiftUI): one
  memoised `Equatable` subview per block; paragraph/heading via `Text(AttributedString)`; lists with nested indent and
  task checkboxes (SF Symbols); blockquote with a leading bar; code block in a rounded mono surface with language label
  and a copy button (`UIPasteboard`), horizontal scroll for long lines; table as `Grid` inside a horizontal `ScrollView`
  with alignment and a header row; thematic break; image via `AsyncImage` capped to the content width; links open with
  `openURL`, `exodus-cite://N` renders as a small chip (tappable → callback); Dynamic Type; light/dark via semantic
  colours; `.textSelection(.enabled)` per block.
- [ ] DEBUG-only gallery: in the App target, `#if DEBUG` launch argument `-MarkdownGallery` shows a scrolling screen of
  fixture documents (headings/lists/quote/code/table/task list/links/images/strike vs `19~32°C`/`$200 - $300`/citation
  chips/an unclosed fence being "streamed" by a timer). Nothing of it ships in Release.
- [ ] Verify visually: build, boot an iOS 27.0 simulator, install and launch with `-MarkdownGallery`, `xcrun simctl io
  booted screenshot` light + dark + XXL Dynamic Type (`simctl ui booted content_size`), and READ the PNGs; fix what looks
  wrong; put the final screenshots in the scratchpad and describe each in the report. Shut the simulator down afterwards.

### Task A5: `AssistantTurnView`, thinking timeline, tool cards v1, user bubble

Read: desktop `messages.tsx` (`AssistantTurnSegment`), `thinking-timeline.tsx`, `messages-calling-tools.tsx` (which
built-ins are silent; error box; terminal card; generic MCP card).

- [ ] `ChatDetailView` renders `segments`: `.user` → plain-text bubble (not markdown; keeps existing look), `.assistantTurn`
  → `AssistantTurnView` (timeline collapsed by default + `MarkdownView(body)` + tool cards + 3-dot spinner while the
  run is in flight and nothing has streamed yet). Auto-scroll keeps working (it keyed on `messages.last?.answerText`).
- [ ] `ThinkingTimeline`: header "Thought for N s" / the latest step while streaming; expandable; steps as in the spec;
  pending tool calls show a `ProgressView`.
- [ ] Tool cards v1: error box, terminal (command + output, mono), generic collapsible JSON (pretty-printed `details`/
  content), silent built-ins hidden (`TOOL_NAMES` list from the desktop's `messages-calling-tools.tsx`).
- [ ] Remove the now-dead `MessageRow` paths and `answerText` usage only if nothing else uses them.
- [ ] View-model tests for what is logic (visibility rules, timeline labels); gallery entry with a fake run.

### Task A6: actions, sources, run errors

- [ ] Action bar: copy answer (markdown source), regenerate (re-send the run's user message — check how the desktop's
  `regenerate` is wired through `useChat`/the request body and mirror it in `ChatDetailViewModel`), Sources button when the
  turn has citations, relative time (existing `RecentTimestamp`).
- [ ] `【N-source】` chips open a Sources sheet listing the run's web-search results (title, host, link).
- [ ] Run-error line at the foot of the run it ended; `notice` SSE events (currently dropped in `ChatStreamManager.apply`)
  surface as a transient banner.
- [ ] Tests + catalog keys + audit green.

---

## Later (not in this plan)

Syntax highlighting (Highlightr) and LaTeX `$$` blocks (iosMath) behind the same `MarkdownView`; rich cards (weather,
deep research, artifact in a network-less `WKWebView`, computer-use status, map itinerary via MapKit); attachments
(PhotosPicker, data-URL size limits); LCM compaction strip (generalise `SSEClient` beyond `ChatSseEvent`); read-aloud.
The alternative renderer (SwiftStreamingMarkdown behind the same interface) if this one disappoints.
