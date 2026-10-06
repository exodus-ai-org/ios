# Interactive Blocks 1 — Questionnaire and Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the model needs the user's choice or go-ahead it asks with a native control inside its reply — a questionnaire (`exodus-ask`) or a confirmation (`exodus-confirm`), each with room to type — on the desktop and on the phone, and the user's answer goes back as a plain-text message (a leading `exodus-answer` fence, then the answer in words) that both clients draw as a compact card and that freezes the block it answers.

**Architecture:** One mechanism for both blocks: a fenced code block whose info string names it and whose body is one JSON object. Pure, tested rules come first and exist twice, held to the same vectors: the desktop's `packages/shared/src/types/interactive.ts` (zod limits, `findInteractiveBlock`) and `packages/shared/src/utils/interactive-answer.ts` (`composeAskAnswer`, `composeConfirmAnswer`, `splitAnswer`, `readPicks`), and exodus-ios's `InteractiveBlock` / `InteractiveFence` / `InteractiveAnswer` in `Sources/ChatFeature/Interactive/`. The desktop's chat system prompt gains one short section; its renderer draws a turn's block from `<pre>` in `markdown.tsx` through two React contexts (the turn's block, the chat's answers + send), the questionnaire on the user's shadcn `Questionnaire`; the user bubble draws an answer as a card. The phone's MarkdownKit gains a host hook for fenced blocks (`markdownFencedBlocks`), set per turn by `AssistantTurnView`; the block views send through a new `ChatDetailViewModel.sendText(_:)` that bypasses the composer; `UserBubble` draws the answer card. Nothing is stored: a block is frozen when the chat holds a later user message whose answer fence names the block's run.

**Tech Stack:** Desktop: TypeScript, React 19, react-markdown, zod 4, `@shadcn/react` Questionnaire (via the user's `ui/questionnaire.tsx`), i18next, vitest (+ happy-dom), bun. iOS: Swift 6, SwiftUI (iOS 27: `sensoryFeedback`, `AnyLayout`, `AccessibilityNotification`), swift-markdown (via MarkdownKit), Foundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-06-interactive-blocks-design.md` (exodus-ios) — §2 the wire (blocks, answer, frozen state), §3 the prompt, §4 the desktop renderer, §5 the iOS renderer, §6 edge cases, §7 testing. Phase 2 (§8) is out of scope. Style and tooling follow `docs/superpowers/plans/2026-10-02-health-trends-2-period-reports.md`.

## Decisions (spec gaps, resolved here)

1. **`ref` is the run id** of the turn whose reply holds the block (`AssistantTurn.runId` on both clients) — the id of the user message that run answered (`ChatMessage.runId`'s definition: "the id of the run's user message"). A turn's answer is several assistant messages joined, so "the block's message id" has no single value; the run id is the one identity the desktop and the phone share for it.
2. **The answer fence carries `title` (both blocks) and `decision` (`approve`/`reject`, confirmation only)** besides `block` and `ref`. The card needs the block's title (the questionnaire's title is not in its lines, and the block's message may sit on a history page not loaded yet), and a frozen confirmation needs its decision without reading localized words. Keys are written in sorted order — `block`, `decision`, `ref`, `title` — so `JSON.stringify` and Swift's `JSONEncoder(.sortedKeys, .withoutEscapingSlashes)` write the same bytes.
3. **The answer's words** come from `AnswerLabels { other, addition, note, approved, rejected }` in the answering client's language (desktop `chat:interactive.answer.*` + `interactive.approved/rejected`; iOS `ios:chat.block.answer.*` + `approved/rejected`). Questionnaire: `**<question>** <picks>` with picks **in the options' order** (not tap order) joined by `", "`; Other with text → `<other>: <text>`, Other picked with nothing typed → the word alone; nothing picked → `—`; the closing line `**<addition>:** <note>` only when typed. Confirmation: `**<title>** <approved|rejected>`, then `**<note>:** <note>` when typed. Typed text is made one line (`\s*[\r\n]+\s*` → one space, trimmed).
4. **Block limits** (zod and the Swift decoder, the same vectors): the questionnaire's `title` is **required** (1–200; the spec's example always has one); optional labels may be absent, `null` or `""` (treated as absent; `null` counts as absent so the two decoders agree); unknown keys are ignored; option texts must be **distinct** within a question (the Questionnaire primitive keys choices by value); lengths are **UTF-16 units** on both sides (zod counts JavaScript string length).
5. **Which fence is the block:** only the first `exodus-ask` / `exodus-confirm` fence of a **turn** (all its text blocks, joined as `body`) counts, and only when it opens a line at the left margin (` ``` ` + name, trailing spaces allowed), is outside any other fence (backtick or tilde, CommonMark lengths), and is closed by its own line of ` ``` `. If that first fence does not validate, the turn has no block; a second fence is code either way. A fence still open (a reply streaming) is code until it closes.
6. **Frozen picks** are read back from the answer's lines without labels (`readPicks` / `InteractiveAnswer.picks`): for each question, the line that starts with `**<question>** `, then options matched greedily, longest first, separated by `", "`; anything left over is an Other answer. So a block answered on the phone in Japanese freezes correctly on a desktop in English.
7. **Desktop questionnaire = the primitive's stepper:** one question at a time with Previous / Skip / Next and Submit on the last; our own progress line ("Question 1 of 2", `item` controlled — the primitive's `Progress` text is English-only); a blank answer is **Skip** (the primitive's validation rule; spec §6 "submit with blanks" holds through Skip, Skip on the last question submits); the closing note is a textarea shown on the last step, outside the items. A frozen questionnaire is a static summary (the primitive hides disabled items).
8. **A failed send:** both clients add the user's message before the stream answers, so the block freezes on the answer even when the send fails; the retry is the run's error line and Regenerate, which re-sends the last user message (the answer). This replaces spec §6's "the answer stays in the block's fields".
9. **The desktop chat route is unchanged:** the fence reaches the model as the user's text; only the system prompt teaches it. The prompt section lives in a new file (`src/main/lib/ai/interactive-blocks-prompt.ts`) and is inserted into `getSystemPrompt` before `<response_format>`; the confirmation is also how the existing hard stops ask. Deep Research (`deepResearchBootPrompt`), titles and Health have their own prompts and never get it.
10. **iOS MarkdownKit hook:** MarkdownKit cannot depend on ChatFeature, so it gains `MarkdownFencedBlocks` (languages + a `@MainActor @Sendable` draw closure returning `AnyView?`) as an environment value read only by code blocks; `AssistantTurnView` sets it per turn. `AssistantTurnView`'s equality adds `answered` and compares `canAnswer` only when the turn holds an unanswered block (checked when `canAnswer` changes — a turn starting or ending — never per streamed frame). A compared answer's column (`CompareViews`) is given no answer path: its block is drawn but cannot be sent until one answer is kept.
11. **iOS send path:** `ChatDetailViewModel.sendText(_:)` (+ `canAnswer`, the composer's rule without its text) starts a turn with the given text; the composer's text, quote and pictures stay untouched.
12. **Desktop code header:** `markdown.tsx`'s language label regex becomes `/language-([\w-]+)/`, so an `exodus-ask` fence that falls back to code is labelled `exodus-ask`, not `exodus`.
13. **Haptics:** `.selection` on each option tap, `.success` on Submit/Approve/Reject (`.sensoryFeedback`); the chat screen's existing light send tap also plays (it is the send's).
14. **Gallery fixtures are English**; the gallery gains `-MessageGallerySection ask|confirm|answered` (names, so the screenshot script does not depend on how many runs come before).
15. **The user's uncommitted Questionnaire:** `src/renderer/components/ui/questionnaire.tsx` (untracked), `ui/button.tsx` and the `@shadcn/react` / `cn` dependencies in `package.json` / `bun.lock` are the user's work in progress. Task 3 imports `@/components/ui/questionnaire` and never edits, stages or commits those files; the desktop commits therefore build only together with them (the pre-commit typecheck runs on the working tree, where they exist).

## Global Constraints

- Two repos, both on branch `maintenance`, **never push**: iOS `/Users/yanceyleo/Code/exodus/exodus-ios`, desktop `/Users/yanceyleo/Code/exodus/exodus`. Read `exodus-ios/.superpowers/sdd/constraints.md` once; where it differs from this list (simulator, `git add -p`), this list wins.
- **Commits only through each repo's helper**, from that repo's root: `.superpowers/sdd/commit-mine.sh "<subject>" [--patch FILE.patch ...] <paths you own>` (iOS: `/Users/yanceyleo/Code/exodus/exodus-ios/.superpowers/sdd/commit-mine.sh`; desktop: `/Users/yanceyleo/Code/exodus/exodus/.superpowers/sdd/commit-mine.sh`, whose commit runs the desktop's pre-commit hook: `lint-staged` (`oxlint` + `oxfmt` on staged `*.{ts,tsx}`, `oxfmt` on staged `*.json`) → `bun run typecheck` → `bun run i18n:check`). Never run `git add`, `git commit`, `git commit -a`, `git stash`, `git reset`, `git restore`, `git checkout -- <file>`, and never `--no-verify`. After each commit run `git show --stat HEAD` and confirm it lists ONLY your files; if not, or if the hook fails on files that are not yours, STOP and report BLOCKED (do not repair history, do not touch the user's files).
- **The desktop formatter and the user's edits:** `lint-staged` formats the staged (HEAD-side) version of every committed file and then puts the user's unstaged edits back; when it has to change a patched file, the user's dirty file can come back garbled. So **every `--patch` you commit on the desktop must already be formatted**: `/tmp/blocks/dual_edit.py fmt EDITS.py` (and `desktop_strings.py check`) runs `bunx oxfmt` on the HEAD-side result and must print `FORMAT-OK`; if it prints a diff, change the `new` text in `EDITS.py` to the `+` lines it shows and run it again. Files you create or that were clean: `bunx oxlint <files> && bunx oxfmt <files>` before committing, so the hook changes nothing.
- **Both trees hold the user's uncommitted work.** Files this plan edits that were dirty on 2026-10-06 (edit them ONLY through `/tmp/blocks/dual_edit.py`, `/tmp/blocks/desktop_strings.py` or `/tmp/blocks/add_keys.py`, and commit their patch): desktop `src/main/lib/ai/prompts.ts`, `src/renderer/components/chat.tsx`, `packages/shared/src/i18n/locales/{de,en,es,fr,it,ja,ko,pt-BR,zh-Hant-HK,zh-Hant-TW}/chat.json`; iOS `Sources/ChatFeature/ChatDetailViewModel.swift`, `Sources/ChatFeature/ChatDetailView.swift`, `Sources/ChatFeature/MessageGallery.swift`, `Resources/App/Localizable.xcstrings`. Never touched: every other dirty path (desktop ~176, iOS ~77), the user's `src/renderer/components/ui/questionnaire.tsx`, `ui/button.tsx`, `package.json`, `bun.lock` (Decision 15), and iOS `Resources/App/Assets.xcassets/LaunchLogo.imageset/Contents.json`, pre-staged by someone else (must stay staged and out of every commit). Every other file this plan edits was clean on 2026-10-06 (iOS HEAD `70bbf09`, desktop HEAD `e7927e05`). Run `git diff --stat` at the start and end of every task: only the files your task names may change. **Before editing any other file, run `git diff --stat -- <file>`; if it is no longer empty, edit it only through `/tmp/blocks/dual_edit.py` and commit its patch.**
- **Tool approvals are untouched:** no task edits `approval_required`, `decideApproval`, `run-approvals.tsx`, `RunApprovals*.swift` or anything that reads them. A confirmation block is the model asking; a tool approval stays the kernel's gate.
- **The vectors are the contract:** the test vectors in Task 1 and Task 5 are the same text in both repos (copied verbatim). A change to the wire changes both files and both implementations.
- iOS: Swift 6 language mode, iOS 27.0 deployment target, Tuist 4.208 with buildable folders. **After creating any new file under `Sources/` or `Tests/`, run `tuist generate --no-open` before building.**
- iOS builds/tests: simulator `992425B7-F06B-4CE5-9288-95C71C2F1D44`, `-derivedDataPath /tmp/blocks-dd`. Tests: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme <ChatFeature|MarkdownKit> -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd [-only-testing:<ChatFeatureTests|MarkdownKitTests>/<TypeName>] 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"`. A wrong `-only-testing` name still prints SUCCEEDED — confirm a `Test run with N tests` line with N > 0. App build: `xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`.
- Desktop tests: from `/Users/yanceyleo/Code/exodus/exodus`, `bunx vitest run <path>`. Typecheck before a desktop commit: `bun run typecheck:shared`, `bun run typecheck:node`, `bun run typecheck:web` (each that covers your files).
- iOS strings: new keys `ios:chat.block.<element>`, all ten languages (en, zh-Hant, zh-HK, ja, ko, fr, de, es, pt-BR, it), inserted **textually** with `/tmp/blocks/add_keys.py` (Task 6). Never run `scripts/l10n.py add`, `fill` or `save`. `python3 scripts/l10n.py audit 2>&1 | tail -1` prints `0 error(s)` at the end of every iOS task (warnings for keys not referenced yet are fine until Task 8). Views use the key literal (`Text("ios:chat.block.answered")`); code uses `String(localized: "…", defaultValue: "<exact English>", comment: "…")` whose `defaultValue` equals the catalog's English exactly. Never concatenate a sentence; **never pass a ternary of two string literals to a text initializer** (use an `if`/`else` `@ViewBuilder`); user data and model-written text go through `Text(verbatim:)`. No CJK in `Sources/` (the audit rejects it; tests may hold CJK).
- Desktop strings: the `chat` namespace's new `interactive` object, all ten locales (`i18n:check` fails on a missing translation), inserted textually with `/tmp/blocks/desktop_strings.py` (Task 3). Components read them with `useTranslation('chat')`.
- No new packages in either repo (the desktop uses the user's own `@shadcn/react` through `ui/questionnaire.tsx`). iOS: native frameworks only. Haptics only through `.sensoryFeedback`. Dynamic Type: text styles, `AnyLayout` switching at `dynamicTypeSize.isAccessibilitySize`. Reduce Motion: no animation on freezing.
- Match the surrounding code: doc comments short and plain, saying *why*; no comment noise; Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`); vitest `describe`/`it`.
- Do not dispatch subagents from inside a task.

## Review Focus

- A reply that shows a block's JSON as an example — inside an ordinary ` ```json ` fence, a ` ```` ` markdown fence, a tilde fence, or indented under a list item — must stay code, never become a live control. Tests: `interactive.test.ts › findInteractiveBlock › …` cases "inside a longer backtick fence", "inside a tilde fence", "indented under a list item" (Task 1) and `InteractiveFenceTests.find` with the same cases (Task 5).
- Options with emoji or CJK near the limits: the desktop and the phone must agree on what is a block (UTF-16 counting) and write byte-identical answers, or a block valid on one client is code on the other and a frozen block cannot find its picks. Tests: the "40 emoji / 41 emoji" limit vectors and the five answer vectors (Tasks 1 and 5).
- Pressing Submit / Approve while a reply is still streaming, or on the phone before the history has loaded: nothing may be sent. Tests: `interactive-blocks.test.ts › confirmation … nothing while a reply streams` (Task 3) and `ChatDetailViewModelAnswerTests.waitsForHistoryAndForTheTurnInFlight` (Task 6).
- A chat answered on the phone in Japanese and reopened on a desktop in English (or the reverse): the block must still show frozen with the right picks, since the labels differ. Tests: `interactive-answer.test.ts › readPicks › reads the picks back without knowing the language they were written in` (Task 1) and `InteractiveAnswerTests.picksWithoutLabels` (Task 5).
- A user who types or pastes a message that merely starts with ` ```exodus-answer ` but is malformed (bad JSON, unknown block): it must render as an ordinary message, not crash or vanish. Tests: `splitAnswer` vectors "not JSON", "an unknown block" (Tasks 1, 5) and `answer-card.test.ts › a malformed answer fence is an ordinary message` (Task 4).

---

## Shared tooling

### `/tmp/blocks/dual_edit.py` (for the dirty files)

Create it the first time it is needed (`mkdir -p /tmp/blocks`). Every anchor in this plan is written against the committed file; the working file also holds the user's edits, so the commit is HEAD + our edits only.

```python
#!/usr/bin/env python3
"""Edits a file that also holds someone else's uncommitted work, and commits only our part.

    dual_edit.py check EDITS.py          every edit applies to the working file and to HEAD's (nothing written)
    dual_edit.py fmt EDITS.py            desktop: oxfmt leaves HEAD's file with the edits unchanged (nothing written)
    dual_edit.py apply EDITS.py          applies the edits to the working file (an edit already in is skipped)
    dual_edit.py patch EDITS.py OUT      writes OUT: HEAD's file -> HEAD's file with the edits, for commit-mine.sh --patch

EDITS.py defines PATH (repo-relative) and EDITS, a list of (old, new) exact-text pairs applied in order; each `old`
must occur once in the file as committed and once in the working file. Run from the repo root.
"""
import difflib
import os
import runpy
import subprocess
import sys
import tempfile

mode, edits_path = sys.argv[1], sys.argv[2]
spec = runpy.run_path(edits_path)
path, edits = spec["PATH"], spec["EDITS"]
work = open(path, encoding="utf-8").read()
head = subprocess.run(["git", "show", "HEAD:" + path], capture_output=True, text=True, check=True).stdout


def strict(text, label):
    for old, new in edits:
        n = text.count(old)
        if n != 1:
            sys.exit("%s: %s: `old` found %d times (want 1): %r" % (label, path, n, old[:100]))
        text = text.replace(old, new, 1)
    return text


def lenient(text):
    for old, new in edits:
        n = text.count(old)
        if n == 0:
            continue  # already applied
        if n > 1:
            sys.exit("working file: %s: `old` found %d times: %r" % (path, n, old[:100]))
        text = text.replace(old, new, 1)
    return text


def oxfmt(text):
    """The text as the desktop's formatter leaves it, formatted beside the real file (so its config applies)."""
    folder, name = os.path.split(path)
    probe = os.path.join(folder, "__fmt_probe__" + name)
    open(probe, "w", encoding="utf-8").write(text)
    try:
        subprocess.run(["bunx", "oxfmt", probe], check=True, capture_output=True)
        return open(probe, encoding="utf-8").read()
    finally:
        os.remove(probe)


if mode == "check":
    strict(head, "HEAD")
    strict(work, "working file")
    print("OK", path, len(edits), "edit(s) apply to HEAD and to the working file")
elif mode == "fmt":
    mine = strict(head, "HEAD")
    formatted = oxfmt(mine)
    if formatted != mine:
        sys.stdout.writelines(difflib.unified_diff(
            mine.splitlines(keepends=True), formatted.splitlines(keepends=True), "edits", "oxfmt"))
        sys.exit("FORMAT: oxfmt changes the HEAD side; make the `new` texts look like the + lines and run again")
    print("FORMAT-OK", path)
elif mode == "apply":
    new = lenient(work)
    open(path, "w", encoding="utf-8").write(new)
    print("applied" if new != work else "nothing to apply", path)
elif mode == "patch":
    out = sys.argv[3]
    mine = strict(head, "HEAD")
    with open(out, "w", encoding="utf-8") as f:
        f.writelines(difflib.unified_diff(
            head.splitlines(keepends=True), mine.splitlines(keepends=True), "a/" + path, "b/" + path))
    idx = tempfile.mktemp(prefix="dual-idx.")
    env = dict(os.environ, GIT_INDEX_FILE=idx)
    subprocess.run(["git", "read-tree", "HEAD"], env=env, check=True)
    subprocess.run(["git", "apply", "--cached", "--check", out], env=env, check=True)
    os.remove(idx)
    print("PATCH-OK", out)
else:
    sys.exit("mode is check, fmt, apply or patch")
```

Workflow: write `EDITS.py` with the task's (old, new) pairs → `check` (prints `OK`) → desktop only: `fmt` (prints `FORMAT-OK`) → `apply` → build/test → `patch EDITS.py X.patch` (prints `PATCH-OK`) → `commit-mine.sh … --patch X.patch` → `git diff -- <file>` afterwards shows only the user's edits.

### `/tmp/blocks/desktop_strings.py` — written in Task 3. `/tmp/blocks/add_keys.py` — written in Task 6.

---

## File Structure

**Desktop (`/Users/yanceyleo/Code/exodus/exodus`)**
- Create `packages/shared/src/types/interactive.ts` — block schemas (zod), `interactiveKind`, `parseInteractiveBlock`, `findInteractiveBlock`.
- Create `packages/shared/src/utils/interactive-answer.ts` — `composeAskAnswer`, `composeConfirmAnswer`, `splitAnswer`, `readPicks`, `AnswerLabels`.
- Create `tests/unit/shared/types/interactive.test.ts`, `tests/unit/shared/utils/interactive-answer.test.ts` — the vectors.
- Create `src/main/lib/ai/interactive-blocks-prompt.ts` — `INTERACTIVE_BLOCKS_PROMPT`, `ASK_EXAMPLE`, `CONFIRM_EXAMPLE`.
- Modify `src/main/lib/ai/prompts.ts` (dirty; patch) — the section in `getSystemPrompt`.
- Create `tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts`.
- Modify `packages/shared/src/i18n/locales/<10>/chat.json` (dirty; patch) — `interactive.*`.
- Create `src/renderer/components/chat/interactive/interactive-context.tsx` — `InteractiveProvider`, `InteractiveTurnContext`, `useInteractiveTurn`, `useInteractiveChat`, `answersIn`, `Answered`.
- Create `src/renderer/components/chat/interactive/interactive-fence.tsx` — `fenceOf`, `InteractiveFence`.
- Create `src/renderer/components/chat/interactive/questionnaire-block.tsx`, `confirmation-block.tsx`, `answer-labels.ts`, `answer-title.tsx`.
- Modify `src/renderer/components/markdown.tsx` — `pre()` hands an interactive fence to `InteractiveFence`; the label regex.
- Modify `src/renderer/components/chat/assistant-turn-segment.tsx` — the turn's block context.
- Modify `src/renderer/components/chat.tsx` (dirty; patch) — `InteractiveProvider` around the transcript.
- Modify `src/renderer/components/chat/user-bubble.tsx` — the answer card.
- Create `tests/unit/renderer/components/chat/interactive-blocks.test.ts`, `answer-card.test.ts`.

**iOS (`/Users/yanceyleo/Code/exodus/exodus-ios`)**
- Create `Sources/ChatFeature/Interactive/InteractiveBlock.swift` — `InteractiveBlock` (decoder + limits), `InteractiveFence` (`first(in:)`, `matches`).
- Create `Sources/ChatFeature/Interactive/InteractiveAnswer.swift` — `composeAsk`, `composeConfirm`, `split`, `picks`, `Labels`, `Head`.
- Create `Sources/ChatFeature/Interactive/InteractiveText.swift` — the localized words, `Labels.current`.
- Create `Sources/MarkdownKit/MarkdownFencedBlocks.swift`; modify `Sources/MarkdownKit/MarkdownBlockView.swift` (code blocks go through it).
- Modify `Sources/ChatFeature/ChatDetailViewModel.swift` (dirty; patch) — `canAnswer`, `sendText(_:)`.
- Create `Sources/ChatFeature/Interactive/InteractiveBlockView.swift` — `InteractiveAnswered`, `InteractiveRendering`, `InteractiveBlockView`, `InteractiveOptionRow`, `InteractiveNoteField`, `InteractiveAnsweredLine`.
- Create `Sources/ChatFeature/Interactive/QuestionnaireBlockView.swift`, `ConfirmationBlockView.swift`, `InteractiveAnswerCard.swift`.
- Modify `Sources/ChatFeature/AssistantTurnView.swift` — `TranscriptActions`, `TranscriptRows`, `AssistantTurnView`, `UserBubble`.
- Modify `Sources/ChatFeature/ChatDetailView.swift` (dirty; patch) — the actions.
- Create `Sources/ChatFeature/MessageGalleryInteractive.swift`; modify `Sources/ChatFeature/MessageGallery.swift` (dirty; patch).
- Modify `Resources/App/Localizable.xcstrings` (dirty; patch) — 15 keys.
- Tests: `Tests/ChatFeatureTests/InteractiveBlockTests.swift`, `InteractiveAnswerTests.swift`, `InteractiveTextTests.swift`, `ChatDetailViewModelAnswerTests.swift`, `InteractiveRenderingTests.swift`, `InteractiveAnswerCardTests.swift`; `Tests/MarkdownKitTests/MarkdownFencedBlocksTests.swift`.
- Create `docs/chat-interactive-blocks-device-checklist.md`.

---
### Task 1: Desktop — the blocks' schemas, finding a reply's block, and the answer's wire

**Files:**
- Create: `packages/shared/src/types/interactive.ts`
- Create: `packages/shared/src/utils/interactive-answer.ts`
- Test: `tests/unit/shared/types/interactive.test.ts`
- Test: `tests/unit/shared/utils/interactive-answer.test.ts`

**Interfaces:**
- Consumes: `zod` (already a dependency).
- Produces (`@exodus/shared/types/interactive`): `INTERACTIVE_LANGUAGES` (`{ ask: 'exodus-ask', confirm: 'exodus-confirm' }`), `type InteractiveKind = 'ask' | 'confirm'`, `askQuestionSchema`, `askBlockSchema`, `confirmBlockSchema`, types `AskQuestion`, `AskBlock`, `ConfirmBlock`, `InteractiveFence = { kind: 'ask'; block: AskBlock; source: string } | { kind: 'confirm'; block: ConfirmBlock; source: string }`, `interactiveKind(language: string): InteractiveKind | null`, `parseInteractiveBlock(kind: InteractiveKind, source: string): InteractiveFence | null`, `findInteractiveBlock(markdown: string): InteractiveFence | null`.
- Produces (`@exodus/shared/utils/interactive-answer`): `ANSWER_INFO_STRING`, `BLANK_ANSWER` (`'—'`), `interface AnswerLabels { other; addition; note; approved; rejected: string }`, `interface AnswerHead { block: InteractiveKind; ref: string; title?: string; decision?: 'approve' | 'reject' }`, `interface QuestionResponse { options: readonly string[]; other: string | null }`, `composeAskAnswer(block: AskBlock, ref: string, responses: Readonly<Record<string, QuestionResponse | undefined>>, note: string, labels: AnswerLabels): string`, `composeConfirmAnswer(block: ConfirmBlock, ref: string, approved: boolean, note: string, labels: AnswerLabels): string`, `splitAnswer(text: string): { answer: AnswerHead | null; body: string }`, `readPicks(block: AskBlock, body: string): Record<string, { options: string[]; other: boolean }>`.

- [ ] **Step 1: Check the paths are new**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
ls packages/shared/src/types/interactive.ts packages/shared/src/utils/interactive-answer.ts 2>&1 | grep -c "No such file"   # 2
git diff --stat                                                                                                          # note the user's paths; they stay as they are
```

- [ ] **Step 2: Write the failing tests**

Create `tests/unit/shared/types/interactive.test.ts`:

````ts
// The two blocks a reply can ask with, their limits, and which fence of a
// reply is its block. exodus-ios's InteractiveBlockTests holds the same
// vectors — keep them in step.
import {
  findInteractiveBlock,
  parseInteractiveBlock
} from '@exodus/shared/types/interactive'
import { describe, expect, it } from 'vitest'

const ASK_SOURCE =
  '{"title":"我想先确认一下你的具体情况","questions":[{"id":"where","text":"哪里最痒？","type":"single","options":["小腿","手臂","全身到处都痒"],"other":true},{"id":"when","text":"什么时候最痒？","type":"multi","options":["洗澡后","晚上","全天"]}],"note":"还有什么想补充的？","submit":"提交，帮我判断"}'
const CONFIRM_SOURCE =
  '{"title":"要我把这份行程写进日历吗？","details":"10 月 21–25 日，五天，17 个地点；日历「旅行」。","approve":"写进去","reject":"先不要","note":"有要改的地方可以写在这里"}'

const q = (id: string, extra: Record<string, unknown> = {}) => ({
  id,
  text: 'Q',
  type: 'single',
  options: ['x', 'y'],
  ...extra
})
const ask = (extra: Record<string, unknown> = {}) =>
  JSON.stringify({ title: 'T', questions: [q('a')], ...extra })
const confirm = (extra: Record<string, unknown> = {}) =>
  JSON.stringify({ title: 'T', ...extra })
const range = (n: number) => Array.from({ length: n }, (_, i) => i)

const ASK_CASES: Array<[string, string, boolean]> = [
  ["the spec's example", ASK_SOURCE, true],
  ['eight questions', ask({ questions: range(8).map((i) => q(`q${i}`)) }), true],
  ['nine questions', ask({ questions: range(9).map((i) => q(`q${i}`)) }), false],
  ['no questions', ask({ questions: [] }), false],
  ['an 80-character option', ask({ questions: [q('a', { options: ['x'.repeat(80), 'y'] })] }), true],
  ['an 81-character option', ask({ questions: [q('a', { options: ['x'.repeat(81), 'y'] })] }), false],
  ['40 emoji (80 UTF-16 units)', ask({ questions: [q('a', { options: ['😀'.repeat(40), 'y'] })] }), true],
  ['41 emoji (82 UTF-16 units)', ask({ questions: [q('a', { options: ['😀'.repeat(41), 'y'] })] }), false],
  ['one option', ask({ questions: [q('a', { options: ['x'] })] }), false],
  ['nine options', ask({ questions: [q('a', { options: range(9).map(String) })] }), false],
  ['the same option twice', ask({ questions: [q('a', { options: ['x', 'x'] })] }), false],
  ['two questions with one id', ask({ questions: [q('a'), q('a')] }), false],
  ['an id with a capital', ask({ questions: [q('Where')] }), false],
  ['a 33-character id', ask({ questions: [q('a'.repeat(33))] }), false],
  ['a type that is neither single nor multi', ask({ questions: [q('a', { type: 'text' })] }), false],
  ['an empty title', ask({ title: '' }), false],
  ['a 201-character question', ask({ questions: [q('a', { text: 'q'.repeat(201) })] }), false],
  ['a 121-character note', ask({ note: 'n'.repeat(121) }), false],
  ['a 41-character submit', ask({ submit: 's'.repeat(41) }), false],
  ['nulls for what is optional', ask({ note: null, submit: null, questions: [q('a', { other: null })] }), true],
  ['keys it does not know', ask({ colour: 'red' }), true],
  ['not JSON', '{"title":', false],
  ['an array', '[]', false]
]

const CONFIRM_CASES: Array<[string, string, boolean]> = [
  ["the spec's example", CONFIRM_SOURCE, true],
  ['a title alone', confirm(), true],
  ['no title', JSON.stringify({ details: 'd' }), false],
  ['a 201-character title', confirm({ title: 't'.repeat(201) }), false],
  ['1000 characters of details', confirm({ details: 'd'.repeat(1000) }), true],
  ['1001 characters of details', confirm({ details: 'd'.repeat(1001) }), false],
  ['a 41-character approve', confirm({ approve: 'a'.repeat(41) }), false],
  ['a 41-character reject', confirm({ reject: 'r'.repeat(41) }), false],
  ['a 121-character note', confirm({ note: 'n'.repeat(121) }), false]
]

describe('parseInteractiveBlock', () => {
  it.each(ASK_CASES)('exodus-ask: %s → valid: %s', (_name, source, valid) => {
    expect(parseInteractiveBlock('ask', source) !== null).toBe(valid)
  })

  it.each(CONFIRM_CASES)(
    'exodus-confirm: %s → valid: %s',
    (_name, source, valid) => {
      expect(parseInteractiveBlock('confirm', source) !== null).toBe(valid)
    }
  )

  it('keeps what the fence said, and reads a missing "other" as no Other', () => {
    const fence = parseInteractiveBlock('ask', ASK_SOURCE)
    expect(fence?.kind).toBe('ask')
    expect(fence?.source).toBe(ASK_SOURCE)
    if (fence?.kind !== 'ask') throw new Error('expected a questionnaire')
    expect(fence.block.questions.map((x) => x.other ?? false)).toEqual([
      true,
      false
    ])
  })
})

const FIND_CASES: Array<[string, string, 'ask' | 'confirm' | null]> = [
  ['a questionnaire after a paragraph', `Intro\n\n\`\`\`exodus-ask\n${ASK_SOURCE}\n\`\`\`\n\nAfter`, 'ask'],
  ['a fence still open (a reply streaming)', `Intro\n\n\`\`\`exodus-ask\n${ASK_SOURCE}`, null],
  ['two blocks: only the first counts', `\`\`\`exodus-confirm\n${CONFIRM_SOURCE}\n\`\`\`\n\n\`\`\`exodus-ask\n${ASK_SOURCE}\n\`\`\``, 'confirm'],
  ['a first block that does not validate: none', `\`\`\`exodus-ask\n{oops}\n\`\`\`\n\n\`\`\`exodus-confirm\n${CONFIRM_SOURCE}\n\`\`\``, null],
  ['inside a longer backtick fence', `\`\`\`\`md\n\`\`\`exodus-ask\n${ASK_SOURCE}\n\`\`\`\n\`\`\`\``, null],
  ['inside a tilde fence', `~~~\n\`\`\`exodus-ask\n${ASK_SOURCE}\n\`\`\`\n~~~`, null],
  ['indented under a list item', `- item\n\n  \`\`\`exodus-ask\n  ${ASK_SOURCE}\n  \`\`\``, null],
  ['after an ordinary code block', `\`\`\`js\nlet a = 1\n\`\`\`\n\n\`\`\`exodus-confirm\n${CONFIRM_SOURCE}\n\`\`\``, 'confirm'],
  ['trailing spaces after the name', `\`\`\`exodus-confirm  \n${CONFIRM_SOURCE}\n\`\`\``, 'confirm'],
  ['another name', `\`\`\`exodus-answer\n{"block":"ask","ref":"r"}\n\`\`\``, null]
]

describe('findInteractiveBlock', () => {
  it.each(FIND_CASES)('%s → %s', (_name, markdown, kind) => {
    expect(findInteractiveBlock(markdown)?.kind ?? null).toBe(kind)
  })

  it("gives the block's fence text, to know its code block by", () => {
    const markdown = `Intro\n\n\`\`\`exodus-ask\n${ASK_SOURCE}\n\`\`\`\n`
    expect(findInteractiveBlock(markdown)?.source).toBe(ASK_SOURCE)
  })
})
````

Create `tests/unit/shared/utils/interactive-answer.test.ts`:

````ts
// A block's answer as the user's next message, read back as a card and as the
// picks that freeze the block. exodus-ios's InteractiveAnswerTests holds the
// same vectors — keep them in step.
import {
  askBlockSchema,
  confirmBlockSchema
} from '@exodus/shared/types/interactive'
import {
  composeAskAnswer,
  composeConfirmAnswer,
  readPicks,
  splitAnswer,
  type AnswerLabels
} from '@exodus/shared/utils/interactive-answer'
import { describe, expect, it } from 'vitest'

const ASK_SOURCE =
  '{"title":"我想先确认一下你的具体情况","questions":[{"id":"where","text":"哪里最痒？","type":"single","options":["小腿","手臂","全身到处都痒"],"other":true},{"id":"when","text":"什么时候最痒？","type":"multi","options":["洗澡后","晚上","全天"]}],"note":"还有什么想补充的？","submit":"提交，帮我判断"}'
const CONFIRM_SOURCE =
  '{"title":"要我把这份行程写进日历吗？","details":"10 月 21–25 日，五天，17 个地点；日历「旅行」。","approve":"写进去","reject":"先不要","note":"有要改的地方可以写在这里"}'
const SIZES_SOURCE =
  '{"title":"Pick a plan","questions":[{"id":"size","text":"Which sizes?","type":"multi","options":["Small, cheap","Medium","Large, roomy"],"other":true}]}'
const QUOTED_SOURCE = '{"title":"Send \\"Q3/Q4\\" report?"}'

const ZH: AnswerLabels = {
  other: '其他',
  addition: '补充',
  note: '备注',
  approved: '同意',
  rejected: '拒绝'
}
const EN: AnswerLabels = {
  other: 'Other',
  addition: 'Also',
  note: 'Note',
  approved: 'Approved',
  rejected: 'Rejected'
}

const ANSWER_CJK =
  '```exodus-answer\n{"block":"ask","ref":"a9f2","title":"我想先确认一下你的具体情况"}\n```\n\n' +
  '**哪里最痒？** 小腿\n**什么时候最痒？** 洗澡后, 晚上\n**补充:** 用的是丝塔芙润肤乳'
const ANSWER_OTHER =
  '```exodus-answer\n{"block":"ask","ref":"a9f2","title":"我想先确认一下你的具体情况"}\n```\n\n' +
  '**哪里最痒？** 其他: 脚踝 和脚背\n**什么时候最痒？** —'
const ANSWER_COMMAS =
  '```exodus-answer\n{"block":"ask","ref":"r-2","title":"Pick a plan"}\n```\n\n' +
  '**Which sizes?** Small, cheap, Large, roomy, Other'
const ANSWER_APPROVE =
  '```exodus-answer\n{"block":"confirm","decision":"approve","ref":"c1","title":"要我把这份行程写进日历吗？"}\n```\n\n' +
  '**要我把这份行程写进日历吗？** 同意\n**备注:** 第三天换成京都'
const ANSWER_REJECT =
  '```exodus-answer\n{"block":"confirm","decision":"reject","ref":"c2","title":"Send \\"Q3/Q4\\" report?"}\n```\n\n' +
  '**Send "Q3/Q4" report?** Rejected'

const ask = (source: string) => askBlockSchema.parse(JSON.parse(source))
const confirm = (source: string) => confirmBlockSchema.parse(JSON.parse(source))

describe('composeAskAnswer', () => {
  it("writes a line a question, the picks in the options' order, then the closing note", () => {
    const text = composeAskAnswer(
      ask(ASK_SOURCE),
      'a9f2',
      {
        where: { options: ['小腿'], other: null },
        when: { options: ['晚上', '洗澡后'], other: null }
      },
      '用的是丝塔芙润肤乳',
      ZH
    )
    expect(text).toBe(ANSWER_CJK)
  })

  it('writes Other with its text on one line, a blank as —, and no note line when none was typed', () => {
    const text = composeAskAnswer(
      ask(ASK_SOURCE),
      'a9f2',
      { where: { options: [], other: '脚踝\n和脚背' } },
      '  ',
      ZH
    )
    expect(text).toBe(ANSWER_OTHER)
  })

  it("keeps an option's commas, and writes Other picked with nothing typed as the word alone", () => {
    const text = composeAskAnswer(
      ask(SIZES_SOURCE),
      'r-2',
      { size: { options: ['Large, roomy', 'Small, cheap'], other: '' } },
      '',
      EN
    )
    expect(text).toBe(ANSWER_COMMAS)
  })
})

describe('composeConfirmAnswer', () => {
  it('writes the title and the decision, then the note', () => {
    expect(
      composeConfirmAnswer(confirm(CONFIRM_SOURCE), 'c1', true, '第三天换成京都', ZH)
    ).toBe(ANSWER_APPROVE)
  })

  it('escapes the title in the fence as JSON does, slashes left alone, and leaves out an empty note', () => {
    expect(
      composeConfirmAnswer(confirm(QUOTED_SOURCE), 'c2', false, '\n', EN)
    ).toBe(ANSWER_REJECT)
  })
})

describe('splitAnswer', () => {
  it('reads the fence and the lines after it', () => {
    expect(splitAnswer(ANSWER_CJK)).toEqual({
      answer: { block: 'ask', ref: 'a9f2', title: '我想先确认一下你的具体情况' },
      body: '**哪里最痒？** 小腿\n**什么时候最痒？** 洗澡后, 晚上\n**补充:** 用的是丝塔芙润肤乳'
    })
    expect(splitAnswer(ANSWER_REJECT).answer).toEqual({
      block: 'confirm',
      decision: 'reject',
      ref: 'c2',
      title: 'Send "Q3/Q4" report?'
    })
  })

  it('reads a fence with nothing after it', () => {
    expect(
      splitAnswer('```exodus-answer\n{"block":"confirm","ref":"r"}\n```')
    ).toEqual({ answer: { block: 'confirm', ref: 'r' }, body: '' })
  })

  it.each([
    ['an ordinary message', 'hello'],
    ['not JSON', '```exodus-answer\n{oops}\n```\n\nhi'],
    ['an unknown block', '```exodus-answer\n{"block":"poll","ref":"r"}\n```\n\nhi'],
    ['no ref', '```exodus-answer\n{"block":"ask"}\n```\n\nhi'],
    ['a fence never closed', '```exodus-answer\n{"block":"ask","ref":"r"}']
  ])('%s is not an answer', (_name, text) => {
    expect(splitAnswer(text)).toEqual({ answer: null, body: text })
  })
})

describe('readPicks', () => {
  it('reads each question back from its line', () => {
    const block = ask(ASK_SOURCE)
    expect(readPicks(block, splitAnswer(ANSWER_CJK).body)).toEqual({
      where: { options: ['小腿'], other: false },
      when: { options: ['洗澡后', '晚上'], other: false }
    })
    expect(readPicks(block, splitAnswer(ANSWER_OTHER).body)).toEqual({
      where: { options: [], other: true },
      when: { options: [], other: false }
    })
  })

  it("matches options that hold commas, longest first, and what is left over as Other", () => {
    expect(readPicks(ask(SIZES_SOURCE), splitAnswer(ANSWER_COMMAS).body)).toEqual({
      size: { options: ['Small, cheap', 'Large, roomy'], other: true }
    })
  })

  it('reads the picks back without knowing the language they were written in', () => {
    const block = ask(SIZES_SOURCE)
    const japanese = composeAskAnswer(
      block,
      'r',
      { size: { options: ['Medium'], other: '特大' } },
      'メモ',
      { other: 'その他', addition: '補足', note: 'メモ', approved: '承認済み', rejected: '却下済み' }
    )
    expect(readPicks(block, splitAnswer(japanese).body)).toEqual({
      size: { options: ['Medium'], other: true }
    })
  })

  it('a question without its line has no picks', () => {
    expect(readPicks(ask(SIZES_SOURCE), '')).toEqual({
      size: { options: [], other: false }
    })
  })
})
````

- [ ] **Step 3: Run them to see them fail**

Run: `bunx vitest run tests/unit/shared/types/interactive.test.ts tests/unit/shared/utils/interactive-answer.test.ts`
Expected: FAIL — `Failed to resolve import "@exodus/shared/types/interactive"`.

- [ ] **Step 4: Write `packages/shared/src/types/interactive.ts`**

```ts
// The questionnaire and the confirmation a reply can ask with (exodus-ios spec
// 2026-10-06): a fenced block whose info string names it and whose body is one
// JSON object. One that validates is drawn as a control; anything else stays
// the code block it is. exodus-ios has the same rules (`InteractiveBlock`),
// held to the same vectors; lengths are UTF-16 units there too.
import { z } from 'zod'

export const INTERACTIVE_LANGUAGES = {
  ask: 'exodus-ask',
  confirm: 'exodus-confirm'
} as const

export type InteractiveKind = keyof typeof INTERACTIVE_LANGUAGES

/** An optional label: absent, null or a string of at most `max`. */
const label = (max: number) => z.string().max(max).nullish()

const distinct = (values: readonly string[]) =>
  new Set(values).size === values.length

export const askQuestionSchema = z.object({
  id: z.string().regex(/^[a-z0-9_-]{1,32}$/),
  text: z.string().min(1).max(200),
  type: z.enum(['single', 'multi']),
  options: z.array(z.string().min(1).max(80)).min(2).max(8).refine(distinct),
  /** Adds "Other…", a choice the user types into. */
  other: z.boolean().nullish()
})

export const askBlockSchema = z.object({
  title: z.string().min(1).max(200),
  questions: z
    .array(askQuestionSchema)
    .min(1)
    .max(8)
    .refine((questions) => distinct(questions.map((q) => q.id))),
  /** The closing field's label; the client's own when absent. */
  note: label(120),
  /** The button's label; the client's own when absent. */
  submit: label(40)
})

export const confirmBlockSchema = z.object({
  title: z.string().min(1).max(200),
  /** Markdown. */
  details: label(1000),
  approve: label(40),
  reject: label(40),
  note: label(120)
})

export type AskQuestion = z.infer<typeof askQuestionSchema>
export type AskBlock = z.infer<typeof askBlockSchema>
export type ConfirmBlock = z.infer<typeof confirmBlockSchema>

/** A reply's block, and the text of its fence — how its code block is known. */
export type InteractiveFence =
  | { kind: 'ask'; block: AskBlock; source: string }
  | { kind: 'confirm'; block: ConfirmBlock; source: string }

/** The block a fence's info string names, or null. */
export function interactiveKind(language: string): InteractiveKind | null {
  if (language === INTERACTIVE_LANGUAGES.ask) return 'ask'
  if (language === INTERACTIVE_LANGUAGES.confirm) return 'confirm'
  return null
}

/** A fence's body as its block, or null when it is not one JSON object within the limits. */
export function parseInteractiveBlock(
  kind: InteractiveKind,
  source: string
): InteractiveFence | null {
  let value: unknown
  try {
    value = JSON.parse(source)
  } catch {
    return null
  }
  if (kind === 'ask') {
    const parsed = askBlockSchema.safeParse(value)
    return parsed.success ? { kind, block: parsed.data, source } : null
  }
  const parsed = confirmBlockSchema.safeParse(value)
  return parsed.success ? { kind, block: parsed.data, source } : null
}

/** A line that opens or closes a fence: up to three spaces, then three or more backticks or tildes. */
function fenceRun(
  line: string
): { char: string; length: number; rest: string } | null {
  let start = 0
  while (start < 3 && line[start] === ' ') start++
  const char = line[start]
  if (char !== '`' && char !== '~') return null
  let end = start
  while (line[end] === char) end++
  if (end - start < 3) return null
  return { char, length: end - start, rest: line.slice(end) }
}

/**
 * A reply's block: its first `exodus-ask` / `exodus-confirm` fence that opens a
 * line at the left margin — not inside another fence, a list or a quote — and
 * is closed. Only that first one counts: when it does not validate the reply
 * has none, and a second is code either way. A fence still open (a reply
 * being written) is not a block yet.
 */
export function findInteractiveBlock(
  markdown: string
): InteractiveFence | null {
  const lines = markdown.split('\n')
  let open: { char: string; length: number } | null = null
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const run = fenceRun(line)
    if (open) {
      if (
        run &&
        run.char === open.char &&
        run.length >= open.length &&
        run.rest.trim() === ''
      ) {
        open = null
      }
      continue
    }
    const kind = line.startsWith('```')
      ? interactiveKind(line.slice(3).trimEnd())
      : null
    if (kind) {
      for (let j = i + 1; j < lines.length; j++) {
        const close = fenceRun(lines[j])
        if (close && close.char === '`' && close.rest.trim() === '') {
          return parseInteractiveBlock(kind, lines.slice(i + 1, j).join('\n'))
        }
      }
      return null
    }
    if (run) open = { char: run.char, length: run.length }
  }
  return null
}
```

- [ ] **Step 5: Write `packages/shared/src/utils/interactive-answer.ts`**

````ts
// A questionnaire's or a confirmation's answer, as the user's next message: a
// leading ```exodus-answer fence naming the block it answers, a blank line,
// then the answer in plain words — a line a question. Plain text, like a quote
// (`quoted-text.ts`) or a Health question (`health-context.ts`), so every
// provider reads it as what it is; the clients read it back with
// `splitAnswer` to draw it as a card and to freeze the block it names.
// exodus-ios has the same rules (`InteractiveAnswer`), held to the same
// vectors.
import type {
  AskBlock,
  ConfirmBlock,
  InteractiveKind
} from '../types/interactive'

export const ANSWER_INFO_STRING = 'exodus-answer'
/** An unanswered question's line. */
export const BLANK_ANSWER = '—'

const OPENING = `\`\`\`${ANSWER_INFO_STRING}\n`
const CLOSING = '\n```'

/** The words an answer is written with, in the answering client's language. */
export interface AnswerLabels {
  /** Before an "Other…" choice's text: `Other: …`. */
  other: string
  /** The questionnaire's closing line. */
  addition: string
  /** The confirmation's note line. */
  note: string
  approved: string
  rejected: string
}

/** What the fence says: the block, the run whose reply holds it, its title, a confirmation's decision. */
export interface AnswerHead {
  block: InteractiveKind
  ref: string
  title?: string
  decision?: 'approve' | 'reject'
}

/** One question's answer: the options picked, and the "Other…" text (null: Other not picked). */
export interface QuestionResponse {
  options: readonly string[]
  other: string | null
}

/** Typed text on one line: a line break is a space. */
function oneLine(text: string): string {
  return text.replace(/\s*[\r\n]+\s*/g, ' ').trim()
}

function fence(head: AnswerHead): string {
  // The keys in sorted order, as exodus-ios's encoder writes them.
  const json = JSON.stringify({
    block: head.block,
    ...(head.decision ? { decision: head.decision } : {}),
    ref: head.ref,
    ...(head.title !== undefined ? { title: head.title } : {})
  })
  return `${OPENING}${json}${CLOSING}`
}

export function composeAskAnswer(
  block: AskBlock,
  ref: string,
  responses: Readonly<Record<string, QuestionResponse | undefined>>,
  note: string,
  labels: AnswerLabels
): string {
  const lines = block.questions.map((question) => {
    const response = responses[question.id]
    const parts = question.options.filter((option) =>
      response?.options.includes(option)
    )
    if (question.other && response && response.other !== null) {
      const text = oneLine(response.other)
      parts.push(text === '' ? labels.other : `${labels.other}: ${text}`)
    }
    const answer = parts.length > 0 ? parts.join(', ') : BLANK_ANSWER
    return `**${question.text}** ${answer}`
  })
  const extra = oneLine(note)
  if (extra !== '') lines.push(`**${labels.addition}:** ${extra}`)
  const head = fence({ block: 'ask', ref, title: block.title })
  return `${head}\n\n${lines.join('\n')}`
}

export function composeConfirmAnswer(
  block: ConfirmBlock,
  ref: string,
  approved: boolean,
  note: string,
  labels: AnswerLabels
): string {
  const word = approved ? labels.approved : labels.rejected
  const lines = [`**${block.title}** ${word}`]
  const extra = oneLine(note)
  if (extra !== '') lines.push(`**${labels.note}:** ${extra}`)
  const head = fence({
    block: 'confirm',
    ref,
    title: block.title,
    decision: approved ? 'approve' : 'reject'
  })
  return `${head}\n\n${lines.join('\n')}`
}

function answerHead(json: string): AnswerHead | null {
  let value: unknown
  try {
    value = JSON.parse(json)
  } catch {
    return null
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null
  }
  const { block, ref, title, decision } = value as Record<string, unknown>
  if (block !== 'ask' && block !== 'confirm') return null
  if (typeof ref !== 'string' || ref === '') return null
  return {
    block,
    ref,
    ...(typeof title === 'string' ? { title } : {}),
    ...(decision === 'approve' || decision === 'reject' ? { decision } : {})
  }
}

/**
 * A message's text as its answer fence and the lines after it. Only a fence
 * that opens the message counts; it ends at the first line that is exactly the
 * closing fence, and its JSON must name a block and a run. Anything else is an
 * ordinary message, returned whole.
 */
export function splitAnswer(text: string): {
  answer: AnswerHead | null
  body: string
} {
  if (!text.startsWith(OPENING)) return { answer: null, body: text }
  const rest = text.slice(OPENING.length)
  let end = rest.indexOf(`${CLOSING}\n`)
  let after = end + CLOSING.length + 1
  if (end === -1 && rest.endsWith(CLOSING)) {
    end = rest.length - CLOSING.length
    after = rest.length
  }
  if (end === -1) return { answer: null, body: text }
  const answer = answerHead(rest.slice(0, end))
  if (!answer) return { answer: null, body: text }
  return { answer, body: rest.slice(after).trim() }
}

/**
 * The picks an answer carried, read back from its lines without its labels —
 * so an answer written in another language freezes its block all the same.
 * A question's line starts with `**<question>** `; its options are matched
 * longest first, separated by ", ", and what is left over is an Other answer.
 */
export function readPicks(
  block: AskBlock,
  body: string
): Record<string, { options: string[]; other: boolean }> {
  const lines = body.split('\n')
  const out: Record<string, { options: string[]; other: boolean }> = {}
  for (const question of block.questions) {
    const prefix = `**${question.text}** `
    const line = lines.find((l) => l.startsWith(prefix))
    const picked = new Set<string>()
    let other = false
    if (line !== undefined) {
      const rest = line.slice(prefix.length)
      if (rest !== BLANK_ANSWER) {
        const options = [...question.options].sort(
          (a, b) => b.length - a.length
        )
        let at = 0
        while (at < rest.length) {
          const option = options.find(
            (o) =>
              rest.startsWith(o, at) &&
              (at + o.length === rest.length ||
                rest.startsWith(', ', at + o.length))
          )
          if (option === undefined) {
            other = question.other === true
            break
          }
          picked.add(option)
          at += option.length + 2
        }
      }
    }
    out[question.id] = {
      options: question.options.filter((o) => picked.has(o)),
      other
    }
  }
  return out
}
````

- [ ] **Step 6: Run the tests**

Run: `bunx vitest run tests/unit/shared/types/interactive.test.ts tests/unit/shared/utils/interactive-answer.test.ts`
Expected: PASS — every case of both files.

- [ ] **Step 7: Lint, format, typecheck, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
F="packages/shared/src/types/interactive.ts packages/shared/src/utils/interactive-answer.ts tests/unit/shared/types/interactive.test.ts tests/unit/shared/utils/interactive-answer.test.ts"
bunx oxlint $F && bunx oxfmt $F
bunx vitest run tests/unit/shared/types/interactive.test.ts tests/unit/shared/utils/interactive-answer.test.ts
bun run typecheck:shared && bun run typecheck:node
git diff --stat                        # nothing of ours besides these four new files
.superpowers/sdd/commit-mine.sh "feat(chat): the questionnaire and confirmation blocks' wire — limits, which fence of a reply is its block, and the answer as plain text a card and a frozen block read back" $F
git show --stat HEAD                   # exactly the four files
```

---

### Task 2: Desktop — the chat prompt's section on interactive blocks

**Files:**
- Create: `src/main/lib/ai/interactive-blocks-prompt.ts`
- Modify: `src/main/lib/ai/prompts.ts` (dirty — `/tmp/blocks/dual_edit.py`)
- Test: `tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts`

**Interfaces:**
- Consumes: `askBlockSchema`, `confirmBlockSchema` (Task 1) — in the test only.
- Produces: `INTERACTIVE_BLOCKS_PROMPT: string`, `ASK_EXAMPLE`, `CONFIRM_EXAMPLE` (plain objects); `getSystemPrompt()` now contains the section.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts`:

````ts
// The chat's prompt teaches the two blocks and the answer that comes back;
// no other prompt does.
import {
  askBlockSchema,
  confirmBlockSchema
} from '@exodus/shared/types/interactive'
import { describe, expect, it, vi } from 'vitest'

vi.mock('electron', () => ({ app: { getPath: () => '/tmp' } }))
const logger = vi.hoisted(() => ({
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
  debug: vi.fn()
}))
vi.mock('@main/lib/logger', () => ({ logger }))
vi.mock('@main/lib/ai/memory/manager', () => ({
  callLlm: vi.fn(),
  loadRelevantMemories: vi.fn(),
  parseJsonFromResponse: vi.fn()
}))
vi.mock('@main/lib/ai/utils/model-util', () => ({
  getModelFromProvider: vi.fn()
}))
vi.mock('@main/lib/db/memory-queries', () => ({ createMemory: vi.fn() }))

const {
  ASK_EXAMPLE,
  CONFIRM_EXAMPLE,
  INTERACTIVE_BLOCKS_PROMPT
} = await import('@main/lib/ai/interactive-blocks-prompt')
const {
  deepResearchBootPrompt,
  deepResearchSystemPrompt,
  getSystemPrompt,
  titleGenerationPrompt
} = await import('@main/lib/ai/prompts')
const { HEALTH_PERIOD_REPORT_SYSTEM, HEALTH_SUMMARY_SYSTEM } = await import(
  '@main/lib/server/routes/health'
)

describe('the interactive blocks section', () => {
  it('is in the chat prompt, with both blocks and the answer fence', () => {
    const prompt = getSystemPrompt({})
    expect(prompt).toContain(INTERACTIVE_BLOCKS_PROMPT)
    expect(prompt).toContain(
      `\`\`\`exodus-ask\n${JSON.stringify(ASK_EXAMPLE)}\n\`\`\``
    )
    expect(prompt).toContain(
      `\`\`\`exodus-confirm\n${JSON.stringify(CONFIRM_EXAMPLE)}\n\`\`\``
    )
    expect(prompt).toContain('```exodus-answer')
    // Before the response format, after the citations.
    expect(prompt.indexOf('<interactive_blocks>')).toBeGreaterThan(
      prompt.indexOf('</citation_rules>')
    )
    expect(prompt.indexOf('</interactive_blocks>')).toBeLessThan(
      prompt.indexOf('<response_format>')
    )
  })

  it('shows examples the clients draw', () => {
    expect(askBlockSchema.safeParse(ASK_EXAMPLE).success).toBe(true)
    expect(confirmBlockSchema.safeParse(CONFIRM_EXAMPLE).success).toBe(true)
  })

  it('stays short: every chat turn reads it', () => {
    expect(INTERACTIVE_BLOCKS_PROMPT.split('\n').length).toBeLessThanOrEqual(40)
  })

  it('is in no other prompt', () => {
    for (const other of [
      deepResearchBootPrompt,
      deepResearchSystemPrompt,
      titleGenerationPrompt,
      HEALTH_SUMMARY_SYSTEM,
      HEALTH_PERIOD_REPORT_SYSTEM
    ]) {
      expect(other).not.toContain('exodus-ask')
      expect(other).not.toContain('exodus-confirm')
    }
  })
})
````

- [ ] **Step 2: Run it to see it fail**

Run: `bunx vitest run tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts`
Expected: FAIL — `Failed to resolve import "@main/lib/ai/interactive-blocks-prompt"`.

- [ ] **Step 3: Write `src/main/lib/ai/interactive-blocks-prompt.ts`**

```ts
// The chat's section on interactive blocks (exodus-ios spec 2026-10-06 §3):
// the two fenced blocks both apps draw as controls, and the answer that comes
// back. Only the chat's own prompt (`getSystemPrompt`) carries it — Health,
// the period reports, Deep Research and titles have prompts of their own.
// Every chat turn reads it, so it stays short.

/** The questionnaire the section shows; a test holds that it validates. */
export const ASK_EXAMPLE = {
  title: 'A few details first',
  questions: [
    {
      id: 'where',
      text: 'Where does it itch most?',
      type: 'single',
      options: ['Lower legs', 'Arms', 'All over'],
      other: true
    },
    {
      id: 'when',
      text: 'When is it worst?',
      type: 'multi',
      options: ['After a shower', 'At night', 'All day']
    }
  ],
  note: 'Anything else I should know?',
  submit: 'Send'
}

/** The confirmation the section shows; a test holds that it validates. */
export const CONFIRM_EXAMPLE = {
  title: 'Add this trip to your calendar?',
  details: 'Oct 21–25, five days, 17 stops; calendar *Travel*.',
  approve: 'Add it',
  reject: 'Not now',
  note: 'Anything to change?'
}

const FENCE = '```'

export const INTERACTIVE_BLOCKS_PROMPT = `<interactive_blocks>
Both apps draw two fenced blocks as controls inside your reply; the user's answer comes back as a message.

\`exodus-ask\` is a questionnaire. Use it when your answer depends on facts only the user has — their situation, preferences, constraints — and a few short choices get them faster than prose. Ask only what changes your answer; what you can reasonably assume, assume and say so. 1–8 questions, 2–8 short options each; "type" is "single" or "multi"; "other": true adds a choice the user types into.
${FENCE}exodus-ask
${JSON.stringify(ASK_EXAMPLE)}
${FENCE}

\`exodus-confirm\` is a confirmation. Use it before an action that changes something outside this chat — writing or deleting files, sending a message or an email, booking, adding to a calendar, spending money, and every hard stop above — then do nothing until the answer comes. Say what will happen in "details" (Markdown), briefly.
${FENCE}exodus-confirm
${JSON.stringify(CONFIRM_EXAMPLE)}
${FENCE}

Rules
- At most one block per reply, after what you write, on lines of its own; never inside another code block, a list, a quote or a table.
- The JSON is one object with only these keys. Limits: title 200 characters, question 200, option 80, note 120, submit/approve/reject 40, details 1000; question ids are lowercase letters, digits, "_" or "-", each used once.
- Write the block's words in the user's language.
- A user message that opens with ${FENCE}exodus-answer answers the questionnaire or confirmation you asked: act on it, do not ask again. "—" is a question left blank; carry on with what you have. A rejected confirmation means do not do it.
- Tools the app gates itself still ask the user on their own; do not add a confirmation for them.
</interactive_blocks>`
```

- [ ] **Step 4: Insert it into the chat prompt (`src/main/lib/ai/prompts.ts`, dirty)**

`mkdir -p /tmp/blocks`, create `/tmp/blocks/dual_edit.py` (Shared tooling), then `/tmp/blocks/prompts_edits.py`:

```python
PATH = "src/main/lib/ai/prompts.ts"
EDITS = [
    (
        "import type { Settings } from '../db/schema'\n",
        "import type { Settings } from '../db/schema'\nimport { INTERACTIVE_BLOCKS_PROMPT } from './interactive-blocks-prompt'\n",
    ),
    (
        "</citation_rules>\n\n<response_format>",
        "</citation_rules>\n\n${INTERACTIVE_BLOCKS_PROMPT}\n\n<response_format>",
    ),
]
```

```bash
cd /Users/yanceyleo/Code/exodus/exodus
python3 /tmp/blocks/dual_edit.py check /tmp/blocks/prompts_edits.py    # OK … 2 edit(s)
python3 /tmp/blocks/dual_edit.py fmt /tmp/blocks/prompts_edits.py      # FORMAT-OK (else: copy oxfmt's + lines into the `new` texts, re-run)
python3 /tmp/blocks/dual_edit.py apply /tmp/blocks/prompts_edits.py    # applied
```

- [ ] **Step 5: Run the tests**

Run: `bunx vitest run tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts tests/unit/main/lib/ai/prompts.test.ts`
Expected: PASS (the existing prompt tests unchanged).

- [ ] **Step 6: Lint, format, typecheck, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
F="src/main/lib/ai/interactive-blocks-prompt.ts tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts"
bunx oxlint $F src/main/lib/ai/prompts.ts && bunx oxfmt $F
bun run typecheck:node
python3 /tmp/blocks/dual_edit.py patch /tmp/blocks/prompts_edits.py /tmp/blocks/prompts.patch   # PATCH-OK
.superpowers/sdd/commit-mine.sh "feat(chat): the chat's prompt teaches the questionnaire and the confirmation blocks — when to ask with each, their limits, and that an exodus-answer message is the answer" \
  --patch /tmp/blocks/prompts.patch $F
git show --stat HEAD                   # the two new files and prompts.ts
git diff -- src/main/lib/ai/prompts.ts # only the user's own edits remain
```

---
### Task 3: Desktop — the blocks drawn in a reply: strings, the turn's and the chat's context, the questionnaire, the confirmation

**Files:**
- Modify: `packages/shared/src/i18n/locales/{de,en,es,fr,it,ja,ko,pt-BR,zh-Hant-HK,zh-Hant-TW}/chat.json` (dirty — `/tmp/blocks/desktop_strings.py`)
- Create: `src/renderer/components/chat/interactive/interactive-context.tsx`
- Create: `src/renderer/components/chat/interactive/interactive-fence.tsx`
- Create: `src/renderer/components/chat/interactive/questionnaire-block.tsx`
- Create: `src/renderer/components/chat/interactive/confirmation-block.tsx`
- Create: `src/renderer/components/chat/interactive/answer-labels.ts`
- Modify: `src/renderer/components/markdown.tsx` (clean)
- Modify: `src/renderer/components/chat/assistant-turn-segment.tsx` (clean)
- Modify: `src/renderer/components/chat.tsx` (dirty — `/tmp/blocks/dual_edit.py`)
- Test: `tests/unit/renderer/components/chat/interactive-blocks.test.ts`

**Interfaces:**
- Consumes: Task 1's `findInteractiveBlock`, `interactiveKind`, `InteractiveFence`, `InteractiveKind`, `AskBlock`, `AskQuestion`, `ConfirmBlock`, `composeAskAnswer`, `composeConfirmAnswer`, `readPicks`, `splitAnswer`, `AnswerHead`, `AnswerLabels`, `QuestionResponse`; the user's `@/components/ui/questionnaire` (`Questionnaire`, `QuestionnaireItem`, `QuestionnaireTitle`, `QuestionnaireChoices`, `QuestionnaireChoice`, `QuestionnaireInput`, `QuestionnaireError`, `QuestionnaireActions`, `QuestionnairePrevious`, `QuestionnaireSkip`, `QuestionnaireNext`, `QuestionnaireSubmit`); `@/components/ui/button` `Button`, `@/components/ui/textarea` `Textarea`, `ErrorBoundary` (`@/components/card-error-boundary`), `useChat`'s `sendMessage` and `status` (in `chat.tsx`).
- Produces: `interface Answered { head: AnswerHead; body: string }`; `answersIn(messages: readonly ChatMessage[]): Map<string, Answered>`; `InteractiveProvider({ messages, status, send, children? })`; `useInteractiveChat(): InteractiveChat | null` with `InteractiveChat { answers: ReadonlyMap<string, Answered>; canSubmit: boolean; submit(text: string): void }`; `InteractiveTurnContext` (`React.Context<InteractiveTurn | null>`, `InteractiveTurn { runId: string; fence: InteractiveFence | null }`); `useInteractiveTurn(runId: string, body: string): InteractiveTurn`; `fenceOf(node: unknown): { kind: InteractiveKind; source: string } | null`; `InteractiveFence({ kind, source, children })`; `QuestionnaireBlock(props: BlockProps<AskBlock>)`, `ConfirmationBlock(props: BlockProps<ConfirmBlock>)` with `BlockProps<B> { block: B; runId: string; answered: Answered | null; canSubmit: boolean; submit: (text: string) => void }`; `answerLabels(t: TFunction<'chat'>): AnswerLabels`; strings `chat:interactive.*` (Task 4 uses `interactive.answer.title`). DOM contract the tests read: a block's root has `data-interactive="ask"|"confirm"` and `data-state` (`open`, `answered`, `approve`, `reject`); a frozen pick has `data-picked`.

- [ ] **Step 1: Check the clean files are still clean**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
git diff --stat -- src/renderer/components/markdown.tsx src/renderer/components/chat/assistant-turn-segment.tsx   # must print nothing
git status --short src/renderer/components/ui/questionnaire.tsx   # ?? — the user's; import it, never stage it
```

- [ ] **Step 2: Write the failing test**

Create `tests/unit/renderer/components/chat/interactive-blocks.test.ts`:

````ts
// @vitest-environment happy-dom
// A turn's questionnaire or confirmation is drawn as a control and answers
// through the chat's send; once the chat holds the answer the block is frozen.
// Anything else — invalid, a second block, a fence still open, a block
// outside a turn — stays the code block it is.
import type {
  ChatMessage,
  ChatStatus,
  SendMessageOptions
} from '@exodus/shared/types/chat'
import {
  askBlockSchema,
  confirmBlockSchema
} from '@exodus/shared/types/interactive'
import {
  composeAskAnswer,
  composeConfirmAnswer,
  type AnswerLabels
} from '@exodus/shared/utils/interactive-answer'
import { act, createElement } from 'react'
import { createRoot } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

;(
  globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }
).IS_REACT_ACT_ENVIRONMENT = true

const t = (key: string, params?: Record<string, unknown>) =>
  params ? `${key} ${JSON.stringify(params)}` : key
const i18n = { resolvedLanguage: 'en', language: 'en' }
vi.mock('react-i18next', () => ({ useTranslation: () => ({ t, i18n }) }))

const { default: Markdown } = await import('@/components/markdown')
const {
  InteractiveProvider,
  InteractiveTurnContext,
  answersIn,
  useInteractiveTurn
} = await import('@/components/chat/interactive/interactive-context')

// What `answerLabels(t)` gives with `t` returning its key.
const LABELS: AnswerLabels = {
  other: 'interactive.answer.other',
  addition: 'interactive.answer.addition',
  note: 'interactive.answer.note',
  approved: 'interactive.approved',
  rejected: 'interactive.rejected'
}
const ASK = {
  title: 'Where does it itch?',
  questions: [
    {
      id: 'where',
      text: 'Where?',
      type: 'single',
      options: ['Legs', 'Arms'],
      other: true
    }
  ]
}
const CONFIRM = { title: 'Send the report?', details: 'To **Ann**, today.' }
const ASK_BLOCK = askBlockSchema.parse(ASK)
const CONFIRM_BLOCK = confirmBlockSchema.parse(CONFIRM)

const fence = (language: string, value: unknown) =>
  `\`\`\`${language}\n${typeof value === 'string' ? value : JSON.stringify(value)}\n\`\`\``
const userMessage = (id: string, text: string) =>
  ({ id, runId: id, role: 'user', content: text, timestamp: 1 }) as ChatMessage

/** A turn's reply as `AssistantTurnSegment` draws it: its Markdown under the turn's block. */
function Turn({ body }: { body: string }) {
  const turn = useInteractiveTurn('run-1', body)
  return createElement(
    InteractiveTurnContext.Provider,
    { value: turn },
    createElement(Markdown, { src: body })
  )
}

let host: HTMLDivElement
let root: ReturnType<typeof createRoot>
const send = vi.fn(async (_opts: SendMessageOptions) => {})

beforeEach(() => {
  send.mockClear()
  host = document.createElement('div')
  document.body.append(host)
  root = createRoot(host)
})

afterEach(async () => {
  await act(async () => root.unmount())
  host.remove()
})

const show = (
  body: string,
  { messages = [], status = 'idle' }: { messages?: ChatMessage[]; status?: ChatStatus } = {},
  inTurn = true
) =>
  act(async () =>
    root.render(
      createElement(
        InteractiveProvider,
        { messages, status, send },
        inTurn ? createElement(Turn, { body }) : createElement(Markdown, { src: body })
      )
    )
  )

const block = () => host.querySelector('[data-interactive]')
const button = (label: string) =>
  Array.from(host.querySelectorAll('button')).find(
    (b) => b.textContent === label
  )

describe('a questionnaire in a reply', () => {
  it("is drawn in place of its code, and Submit sends the composed answer", async () => {
    await show(`Before I answer:\n\n${fence('exodus-ask', ASK)}`)
    expect(block()?.getAttribute('data-interactive')).toBe('ask')
    expect(block()?.getAttribute('data-state')).toBe('open')
    expect(host.querySelector('pre')).toBeNull()

    const arms = host.querySelector<HTMLInputElement>('input[value="Arms"]')
    await act(async () => arms?.click())
    await act(async () => {
      host
        .querySelector('form')
        ?.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
    })
    expect(send).toHaveBeenCalledWith({
      text: composeAskAnswer(
        ASK_BLOCK,
        'run-1',
        { where: { options: ['Arms'], other: null } },
        '',
        LABELS
      )
    })
  })

  it('is frozen once the chat holds its answer: the picks shown, no Submit', async () => {
    const answer = composeAskAnswer(
      ASK_BLOCK,
      'run-1',
      { where: { options: ['Legs'], other: null } },
      '',
      LABELS
    )
    await show(fence('exodus-ask', ASK), { messages: [userMessage('u2', answer)] })
    expect(block()?.getAttribute('data-state')).toBe('answered')
    expect(host.querySelector('button[type="submit"]')).toBeNull()
    expect(
      Array.from(host.querySelectorAll('[data-picked]')).map((n) => n.textContent)
    ).toEqual(['Legs'])
    expect(host.textContent).toContain('interactive.answered')
  })
})

describe('a confirmation in a reply', () => {
  it('Approve sends the decision and the note', async () => {
    await show(fence('exodus-confirm', CONFIRM))
    expect(block()?.getAttribute('data-state')).toBe('open')
    expect(host.querySelector('strong')?.textContent).toBe('Ann')

    const note = host.querySelector('textarea')
    const setValue = Object.getOwnPropertyDescriptor(
      HTMLTextAreaElement.prototype,
      'value'
    )?.set
    await act(async () => {
      if (!note || !setValue) return
      setValue.call(note, 'cc Bob')
      note.dispatchEvent(new Event('input', { bubbles: true }))
    })
    await act(async () => button('interactive.approve')?.click())
    expect(send).toHaveBeenCalledWith({
      text: composeConfirmAnswer(CONFIRM_BLOCK, 'run-1', true, 'cc Bob', LABELS)
    })
  })

  it('sends nothing while a reply streams', async () => {
    await show(fence('exodus-confirm', CONFIRM), { status: 'streaming' })
    expect(button('interactive.approve')?.disabled).toBe(true)
    expect(button('interactive.reject')?.disabled).toBe(true)
    await act(async () => button('interactive.approve')?.click())
    expect(send).not.toHaveBeenCalled()
  })

  it('shows the decision once answered, without its buttons', async () => {
    const answer = composeConfirmAnswer(CONFIRM_BLOCK, 'run-1', false, '', LABELS)
    await show(fence('exodus-confirm', CONFIRM), {
      messages: [userMessage('u2', answer)]
    })
    expect(block()?.getAttribute('data-state')).toBe('reject')
    expect(host.textContent).toContain('interactive.rejected')
    expect(button('interactive.approve')).toBeUndefined()
  })
})

describe('what stays code', () => {
  it('a block over the limits', async () => {
    await show(fence('exodus-ask', { ...ASK, questions: [] }))
    expect(block()).toBeNull()
    expect(host.querySelector('pre')).not.toBeNull()
  })

  it('a second block in the reply', async () => {
    await show(`${fence('exodus-confirm', CONFIRM)}\n\n${fence('exodus-ask', ASK)}`)
    expect(host.querySelectorAll('[data-interactive]')).toHaveLength(1)
    expect(block()?.getAttribute('data-interactive')).toBe('confirm')
    expect(host.querySelectorAll('pre')).toHaveLength(1)
  })

  it('a fence still being written', async () => {
    await show('```exodus-ask\n{"title":"Where')
    expect(block()).toBeNull()
  })

  it('a block outside a turn (a user message, a tool description)', async () => {
    await show(fence('exodus-ask', ASK), {}, false)
    expect(block()).toBeNull()
    expect(host.querySelector('pre')).not.toBeNull()
  })
})

describe('answersIn', () => {
  it("maps each answer to the run it names; other messages are not answers", () => {
    const answer = composeConfirmAnswer(CONFIRM_BLOCK, 'run-1', true, '', LABELS)
    const answers = answersIn([
      userMessage('u1', 'hello'),
      userMessage('u2', answer),
      {
        id: 'a1',
        runId: 'u1',
        role: 'assistant',
        content: [{ type: 'text', text: answer }],
        timestamp: 1
      } as unknown as ChatMessage
    ])
    expect([...answers.keys()]).toEqual(['run-1'])
    expect(answers.get('run-1')?.head.decision).toBe('approve')
  })
})
````

- [ ] **Step 3: Run it to see it fail**

Run: `bunx vitest run tests/unit/renderer/components/chat/interactive-blocks.test.ts`
Expected: FAIL — `Failed to resolve import "@/components/chat/interactive/interactive-context"`.

- [ ] **Step 4: Write the strings script and add the strings**

Create `/tmp/blocks/desktop_strings.py`:

```python
#!/usr/bin/env python3
"""Adds the chat namespace's `interactive` strings to the ten desktop locales, textually: every chat.json holds the
user's uncommitted edits, so only our object is inserted (before "workspaceFile") and no other line is rewritten.

    desktop_strings.py check         inserts into HEAD's and the working file of every locale; oxfmt leaves HEAD's
                                     file with it unchanged (nothing written)
    desktop_strings.py apply         inserts into the working files (a file that has it already is skipped)
    desktop_strings.py patch OUT     writes OUT: each HEAD file -> HEAD file with the object, for commit-mine.sh --patch
Run from the desktop repo root.
"""
import difflib
import json
import os
import subprocess
import sys
import tempfile

DIR = "packages/shared/src/i18n/locales"
ANCHOR = '\n  "workspaceFile": {\n'
KEYS = ["other", "otherPlaceholder", "noteDefault", "notePlaceholder", "submit", "previous", "next", "skip", "progress",
        "chooseOrSkip", "approve", "reject", "approved", "rejected", "answered"]
ANSWER_KEYS = ["other", "addition", "note", "title"]

# locale: (the 15 top-level strings in KEYS' order, the 4 answer strings in ANSWER_KEYS' order)
STRINGS = {
    "en": (["Other…", "Your answer", "Anything else?", "Optional", "Submit", "Previous", "Next", "Skip",
            "Question {{current}} of {{total}}", "Choose an answer, or skip this question.", "Approve", "Reject",
            "Approved", "Rejected", "Answered"],
           ["Other", "Also", "Note", "Your answer"]),
    "de": (["Andere …", "Deine Antwort", "Noch etwas?", "Optional", "Senden", "Zurück", "Weiter", "Überspringen",
            "Frage {{current}} von {{total}}", "Wähle eine Antwort oder überspringe die Frage.", "Zustimmen",
            "Ablehnen", "Zugestimmt", "Abgelehnt", "Beantwortet"],
           ["Andere", "Außerdem", "Notiz", "Deine Antwort"]),
    "es": (["Otra…", "Tu respuesta", "¿Algo más?", "Opcional", "Enviar", "Anterior", "Siguiente", "Omitir",
            "Pregunta {{current}} de {{total}}", "Elige una respuesta u omite esta pregunta.", "Aprobar", "Rechazar",
            "Aprobado", "Rechazado", "Respondido"],
           ["Otra", "Además", "Nota", "Tu respuesta"]),
    "fr": (["Autre…", "Ta réponse", "Autre chose ?", "Facultatif", "Envoyer", "Précédent", "Suivant", "Passer",
            "Question {{current}} sur {{total}}", "Choisis une réponse ou passe cette question.", "Approuver",
            "Refuser", "Approuvé", "Refusé", "Répondu"],
           ["Autre", "En plus", "Note", "Ta réponse"]),
    "it": (["Altro…", "La tua risposta", "Altro da aggiungere?", "Facoltativo", "Invia", "Indietro", "Avanti", "Salta",
            "Domanda {{current}} di {{total}}", "Scegli una risposta o salta questa domanda.", "Approva", "Rifiuta",
            "Approvato", "Rifiutato", "Risposto"],
           ["Altro", "Inoltre", "Nota", "La tua risposta"]),
    "ja": (["その他…", "回答を入力", "ほかに伝えたいことは？", "任意", "送信", "前へ", "次へ", "スキップ",
            "質問 {{current}}/{{total}}", "回答を選ぶか、この質問をスキップしてください。", "承認", "却下",
            "承認済み", "却下済み", "回答済み"],
           ["その他", "補足", "メモ", "あなたの回答"]),
    "ko": (["기타…", "답변 입력", "더 하고 싶은 말이 있나요?", "선택 사항", "보내기", "이전", "다음", "건너뛰기",
            "질문 {{current}}/{{total}}", "답을 고르거나 이 질문을 건너뛰세요.", "승인", "거절",
            "승인함", "거절함", "답변함"],
           ["기타", "추가", "메모", "내 답변"]),
    "pt-BR": (["Outra…", "Sua resposta", "Mais alguma coisa?", "Opcional", "Enviar", "Anterior", "Próxima", "Pular",
               "Pergunta {{current}} de {{total}}", "Escolha uma resposta ou pule esta pergunta.", "Aprovar",
               "Recusar", "Aprovado", "Recusado", "Respondido"],
              ["Outra", "Além disso", "Observação", "Sua resposta"]),
    "zh-Hant-HK": (["其他…", "你嘅答案", "仲有冇嘢想補充？", "可選填", "提交", "上一題", "下一題", "略過",
                    "第 {{current}} 題，共 {{total}} 題", "揀一個答案，或者略過呢題。", "同意", "拒絕",
                    "已同意", "已拒絕", "已回答"],
                   ["其他", "補充", "備註", "你嘅答案"]),
    "zh-Hant-TW": (["其他…", "你的答案", "還有什麼想補充的嗎？", "選填", "提交", "上一題", "下一題", "略過",
                    "第 {{current}} 題，共 {{total}} 題", "請選一個答案，或略過這一題。", "同意", "拒絕",
                    "已同意", "已拒絕", "已回答"],
                   ["其他", "補充", "備註", "你的回答"]),
}


def values(locale):
    top, answer = STRINGS[locale]
    assert len(top) == len(KEYS) and len(answer) == len(ANSWER_KEYS), locale
    assert "{{current}}" in top[KEYS.index("progress")] and "{{total}}" in top[KEYS.index("progress")], locale
    out = dict(zip(KEYS, top))
    out["answer"] = dict(zip(ANSWER_KEYS, answer))
    return out


def insert(text, locale, label):
    if text.count(ANCHOR) != 1:
        sys.exit("%s: %s: the anchor is not there once" % (label, locale))
    if "interactive" in json.loads(text):
        sys.exit("%s: %s: already has `interactive`" % (label, locale))
    body = json.dumps(values(locale), ensure_ascii=False, indent=2).replace("\n", "\n  ")
    out = text.replace(ANCHOR, '\n  "interactive": ' + body + "," + ANCHOR, 1)
    json.loads(out)
    return out


def path(locale):
    return "%s/%s/chat.json" % (DIR, locale)


def head(p):
    return subprocess.run(["git", "show", "HEAD:" + p], capture_output=True, text=True, check=True).stdout


def oxfmt(p, text):
    folder, name = os.path.split(p)
    probe = os.path.join(folder, "__fmt_probe__" + name)
    open(probe, "w", encoding="utf-8").write(text)
    try:
        subprocess.run(["bunx", "oxfmt", probe], check=True, capture_output=True)
        return open(probe, encoding="utf-8").read()
    finally:
        os.remove(probe)


mode = sys.argv[1]
if mode == "check":
    for locale in STRINGS:
        p = path(locale)
        mine = insert(head(p), locale, "HEAD")
        insert(open(p, encoding="utf-8").read(), locale, "working file")
        if oxfmt(p, mine) != mine:
            sys.exit("FORMAT: oxfmt changes %s's HEAD side" % p)
    print("OK", len(STRINGS), "locales; FORMAT-OK")
elif mode == "apply":
    for locale in STRINGS:
        p = path(locale)
        text = open(p, encoding="utf-8").read()
        if "interactive" in json.loads(text):
            print("already there", p)
            continue
        open(p, "w", encoding="utf-8").write(insert(text, locale, "working file"))
        print("applied", p)
elif mode == "patch":
    out = sys.argv[2]
    with open(out, "w", encoding="utf-8") as f:
        for locale in STRINGS:
            p = path(locale)
            before = head(p)
            f.writelines(difflib.unified_diff(
                before.splitlines(keepends=True), insert(before, locale, "HEAD").splitlines(keepends=True),
                "a/" + p, "b/" + p))
    idx = tempfile.mktemp(prefix="strings-idx.")
    env = dict(os.environ, GIT_INDEX_FILE=idx)
    subprocess.run(["git", "read-tree", "HEAD"], env=env, check=True)
    subprocess.run(["git", "apply", "--cached", "--check", out], env=env, check=True)
    os.remove(idx)
    print("PATCH-OK", out)
else:
    sys.exit("mode is check, apply or patch")
```

```bash
cd /Users/yanceyleo/Code/exodus/exodus
python3 /tmp/blocks/desktop_strings.py check     # OK 10 locales; FORMAT-OK
python3 /tmp/blocks/desktop_strings.py apply     # applied × 10
bun run i18n:check | tail -1                     # i18n:check OK
```

- [ ] **Step 5: Write `src/renderer/components/chat/interactive/answer-labels.ts`**

```ts
import type { AnswerLabels } from '@exodus/shared/utils/interactive-answer'
import type { TFunction } from 'i18next'

/** The words this client writes an answer with, in the user's language. */
export function answerLabels(t: TFunction<'chat'>): AnswerLabels {
  return {
    other: t('interactive.answer.other'),
    addition: t('interactive.answer.addition'),
    note: t('interactive.answer.note'),
    approved: t('interactive.approved'),
    rejected: t('interactive.rejected')
  }
}
```

- [ ] **Step 6: Write `src/renderer/components/chat/interactive/interactive-context.tsx`**

```tsx
// What a reply's blocks read: the turn's own block (found once over its whole
// answer, so a second block in a later paragraph stays code), and the chat's
// answers and send. Nothing is stored: a block is answered when the chat
// holds a user message whose answer fence names its run.
import type {
  ChatMessage,
  ChatStatus,
  SendMessageOptions
} from '@exodus/shared/types/chat'
import {
  findInteractiveBlock,
  type InteractiveFence
} from '@exodus/shared/types/interactive'
import {
  splitAnswer,
  type AnswerHead
} from '@exodus/shared/utils/interactive-answer'
import { createContext, type ReactNode, useContext, useMemo } from 'react'

/** A block's answer as the chat holds it: the fence's head and the lines after it. */
export interface Answered {
  head: AnswerHead
  body: string
}

export interface InteractiveChat {
  /** Each block answered so far, by the run whose reply holds it. */
  answers: ReadonlyMap<string, Answered>
  /** Whether an answer may be sent now: as the composer, not while a reply is on its way. */
  canSubmit: boolean
  submit: (text: string) => void
}

export interface InteractiveTurn {
  runId: string
  fence: InteractiveFence | null
}

const InteractiveChatContext = createContext<InteractiveChat | null>(null)
export const InteractiveTurnContext = createContext<InteractiveTurn | null>(
  null
)

/** A user message's words (its pictures aside). */
function messageText(message: ChatMessage): string {
  if (message.role !== 'user') return ''
  if (typeof message.content === 'string') return message.content
  return message.content
    .flatMap((part) => (part.type === 'text' ? [part.text] : []))
    .join('\n')
}

/** The answers in a chat's messages, by the run each names. */
export function answersIn(messages: readonly ChatMessage[]): Map<string, Answered> {
  const answers = new Map<string, Answered>()
  for (const message of messages) {
    if (message.role !== 'user') continue
    const { answer, body } = splitAnswer(messageText(message))
    if (answer) answers.set(answer.ref, { head: answer, body })
  }
  return answers
}

/** Around a chat's transcript: its answers, and an answer sent as a typed message is (the composer's draft untouched). */
export function InteractiveProvider({
  messages,
  status,
  send,
  children
}: {
  messages: ChatMessage[]
  status: ChatStatus
  send: (opts: SendMessageOptions) => Promise<void>
  children?: ReactNode
}) {
  const answers = useMemo(() => answersIn(messages), [messages])
  const canSubmit = status !== 'submitted' && status !== 'streaming'
  const value = useMemo<InteractiveChat>(
    () => ({
      answers,
      canSubmit,
      submit: (text) => {
        void send({ text })
      }
    }),
    [answers, canSubmit, send]
  )
  return (
    <InteractiveChatContext.Provider value={value}>
      {children}
    </InteractiveChatContext.Provider>
  )
}

export function useInteractiveChat(): InteractiveChat | null {
  return useContext(InteractiveChatContext)
}

/** A turn's block, for the Markdown of its reply. */
export function useInteractiveTurn(runId: string, body: string): InteractiveTurn {
  return useMemo(
    () => ({ runId, fence: findInteractiveBlock(body) }),
    [runId, body]
  )
}
```

- [ ] **Step 7: Write `src/renderer/components/chat/interactive/questionnaire-block.tsx`**

```tsx
// A reply's questionnaire (`exodus-ask`) on the user's shadcn Questionnaire:
// one question at a time with Previous / Skip / Next, Submit on the last with
// the closing note above it. A blank is a Skip. Submit sends the answers as
// the user's next message (`composeAskAnswer`); once the chat holds that
// message the block is frozen, a summary of the picks it carried
// (`readPicks`) — the primitive hides an item it would disable.
import type { AskBlock, AskQuestion } from '@exodus/shared/types/interactive'
import {
  composeAskAnswer,
  readPicks,
  type QuestionResponse
} from '@exodus/shared/utils/interactive-answer'
import { CheckIcon } from 'lucide-react'
import { type FormEvent, type ReactNode, useState } from 'react'
import { useTranslation } from 'react-i18next'

import {
  Questionnaire,
  QuestionnaireActions,
  QuestionnaireChoice,
  QuestionnaireChoices,
  QuestionnaireError,
  QuestionnaireInput,
  QuestionnaireItem,
  QuestionnaireNext,
  QuestionnairePrevious,
  QuestionnaireSkip,
  QuestionnaireSubmit,
  QuestionnaireTitle
} from '@/components/ui/questionnaire'
import { Textarea } from '@/components/ui/textarea'
import { cn } from '@/lib/utils'

import { answerLabels } from './answer-labels'
import type { Answered } from './interactive-context'

export interface BlockProps<B> {
  block: B
  /** The run whose reply holds the block: the answer's `ref`. */
  runId: string
  answered: Answered | null
  canSubmit: boolean
  submit: (text: string) => void
}

/** The value of a question's "Other…" choice. */
const OTHER = '__exodus_other__'

const CARD = 'bg-card text-card-foreground rounded-2xl border p-4'

const picksOther = (response: QuestionResponse | undefined) =>
  response !== undefined && response.other !== null

export function QuestionnaireBlock(props: BlockProps<AskBlock>) {
  return props.answered ? (
    <AnsweredQuestionnaire block={props.block} body={props.answered.body} />
  ) : (
    <OpenQuestionnaire {...props} />
  )
}

function OpenQuestionnaire({
  block,
  runId,
  canSubmit,
  submit
}: BlockProps<AskBlock>) {
  const { t } = useTranslation('chat')
  const [current, setCurrent] = useState(block.questions[0].id)
  const [responses, setResponses] = useState<Record<string, QuestionResponse>>(
    {}
  )
  const [note, setNote] = useState('')
  const index = Math.max(
    0,
    block.questions.findIndex((q) => q.id === current)
  )
  const onLast = index === block.questions.length - 1

  const respond = (
    question: AskQuestion,
    change: (response: QuestionResponse) => QuestionResponse
  ) =>
    setResponses((previous) => ({
      ...previous,
      [question.id]: change(
        previous[question.id] ?? { options: [], other: null }
      )
    }))

  const pick = (question: AskQuestion, value: string, checked: boolean) =>
    respond(question, (response) => {
      if (question.type === 'single') {
        if (!checked) return response
        return value === OTHER
          ? { options: [], other: response.other ?? '' }
          : { options: [value], other: null }
      }
      if (value === OTHER) {
        return { ...response, other: checked ? (response.other ?? '') : null }
      }
      return {
        ...response,
        options: checked
          ? [...response.options, value]
          : response.options.filter((o) => o !== value)
      }
    })

  // A skipped question is a blank: what was picked before Skip is dropped.
  const skip = (question: AskQuestion) =>
    setResponses((previous) => {
      const next = { ...previous }
      delete next[question.id]
      return next
    })

  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!canSubmit) return
    submit(composeAskAnswer(block, runId, responses, note, answerLabels(t)))
  }

  return (
    <div data-interactive="ask" data-state="open" className={CARD}>
      <p className="text-sm font-semibold text-pretty">{block.title}</p>
      {block.questions.length > 1 && (
        <p
          aria-live="polite"
          className="text-muted-foreground mt-1 text-[0.625rem] font-medium tabular-nums"
        >
          {t('interactive.progress', {
            current: index + 1,
            total: block.questions.length
          })}
        </p>
      )}
      <Questionnaire
        item={current}
        onItemChange={setCurrent}
        onSubmit={onSubmit}
        className="mt-3"
      >
        {block.questions.map((question) => {
          const response = responses[question.id]
          return (
            <QuestionnaireItem
              key={question.id}
              name={question.id}
              multiple={question.type === 'multi'}
              onStatusChange={(status) => {
                if (status === 'skipped') skip(question)
              }}
            >
              <QuestionnaireTitle>{question.text}</QuestionnaireTitle>
              <QuestionnaireChoices>
                {question.options.map((option) => (
                  <QuestionnaireChoice
                    key={option}
                    value={option}
                    checked={response?.options.includes(option) ?? false}
                    onChange={(event) =>
                      pick(question, option, event.target.checked)
                    }
                  >
                    {option}
                  </QuestionnaireChoice>
                ))}
                {question.other && (
                  <QuestionnaireChoice
                    value={OTHER}
                    checked={picksOther(response)}
                    onChange={(event) =>
                      pick(question, OTHER, event.target.checked)
                    }
                  >
                    {t('interactive.other')}
                  </QuestionnaireChoice>
                )}
              </QuestionnaireChoices>
              {question.other && picksOther(response) && (
                <QuestionnaireInput
                  value={response?.other ?? ''}
                  onChange={(event) => {
                    const text = event.target.value
                    respond(question, (r) => ({ ...r, other: text }))
                  }}
                  placeholder={t('interactive.otherPlaceholder')}
                  aria-label={t('interactive.otherPlaceholder')}
                />
              )}
              <QuestionnaireError>{t('interactive.chooseOrSkip')}</QuestionnaireError>
            </QuestionnaireItem>
          )
        })}
        {onLast && (
          <label className="flex flex-col gap-1.5">
            <span className="text-muted-foreground text-xs">
              {block.note || t('interactive.noteDefault')}
            </span>
            <Textarea
              value={note}
              onChange={(event) => setNote(event.target.value)}
              placeholder={t('interactive.notePlaceholder')}
              rows={2}
            />
          </label>
        )}
        <QuestionnaireActions>
          <QuestionnairePrevious>{t('interactive.previous')}</QuestionnairePrevious>
          <QuestionnaireSkip>{t('interactive.skip')}</QuestionnaireSkip>
          <QuestionnaireNext>{t('interactive.next')}</QuestionnaireNext>
          <QuestionnaireSubmit disabled={!canSubmit}>
            {block.submit || t('interactive.submit')}
          </QuestionnaireSubmit>
        </QuestionnaireActions>
      </Questionnaire>
    </div>
  )
}

function AnsweredQuestionnaire({
  block,
  body
}: {
  block: AskBlock
  body: string
}) {
  const { t } = useTranslation('chat')
  const picks = readPicks(block, body)
  return (
    <div data-interactive="ask" data-state="answered" className={CARD}>
      <p className="text-sm font-semibold text-pretty">{block.title}</p>
      <ol className="mt-3 flex flex-col gap-3">
        {block.questions.map((question, i) => (
          <li key={question.id}>
            <p className="text-sm font-medium">{`${i + 1}. ${question.text}`}</p>
            <ul className="mt-1.5 flex flex-wrap gap-1.5">
              {question.options.map((option) => (
                <Pick
                  key={option}
                  picked={picks[question.id]?.options.includes(option) ?? false}
                >
                  {option}
                </Pick>
              ))}
              {question.other && picks[question.id]?.other && (
                <Pick picked>{t('interactive.other')}</Pick>
              )}
            </ul>
          </li>
        ))}
      </ol>
      <p className="text-muted-foreground mt-3 flex items-center gap-1.5 text-xs">
        <CheckIcon aria-hidden className="size-3.5" />
        {t('interactive.answered')}
      </p>
    </div>
  )
}

function Pick({ picked, children }: { picked: boolean; children: ReactNode }) {
  return (
    <li
      data-picked={picked ? '' : undefined}
      className={cn(
        'flex items-center gap-1 rounded-lg border px-2.5 py-1 text-xs',
        picked ? 'border-primary/40 bg-primary/10' : 'text-muted-foreground'
      )}
    >
      {picked && <CheckIcon aria-hidden className="size-3" />}
      {children}
    </li>
  )
}
```

- [ ] **Step 8: Write `src/renderer/components/chat/interactive/confirmation-block.tsx`**

```tsx
// A reply's confirmation (`exodus-confirm`): what will happen, a note, and
// Approve / Reject — pending until the chat holds the answer, then the
// decision (ai-sdk's Confirmation states). The details are Markdown, drawn
// with react-markdown directly: `markdown.tsx` draws this block.
import type { ConfirmBlock } from '@exodus/shared/types/interactive'
import { composeConfirmAnswer } from '@exodus/shared/utils/interactive-answer'
import { CheckIcon, XIcon } from 'lucide-react'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import ReactMarkdown from 'react-markdown'

import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { remarkPluginsStable } from '@/lib/markdown-plugins'

import { answerLabels } from './answer-labels'
import type { BlockProps } from './questionnaire-block'

export function ConfirmationBlock({
  block,
  runId,
  answered,
  canSubmit,
  submit
}: BlockProps<ConfirmBlock>) {
  const { t } = useTranslation('chat')
  const [note, setNote] = useState('')
  const decision = answered?.head.decision ?? null
  const state = answered ? (decision ?? 'answered') : 'open'

  const send = (approved: boolean) => {
    if (!canSubmit) return
    submit(composeConfirmAnswer(block, runId, approved, note, answerLabels(t)))
  }

  return (
    <div
      data-interactive="confirm"
      data-state={state}
      className="bg-card text-card-foreground rounded-2xl border p-4"
    >
      <p className="text-sm font-semibold text-pretty">{block.title}</p>
      {block.details && (
        <section className="markdown text-muted-foreground mt-1.5 text-sm">
          <ReactMarkdown remarkPlugins={remarkPluginsStable}>
            {block.details}
          </ReactMarkdown>
        </section>
      )}
      {answered ? (
        <p className="mt-3 flex items-center gap-1.5 text-sm font-medium">
          {decision === 'reject' ? (
            <XIcon aria-hidden className="text-muted-foreground size-4" />
          ) : (
            <CheckIcon aria-hidden className="text-primary-ink size-4" />
          )}
          {decision === 'approve' && t('interactive.approved')}
          {decision === 'reject' && t('interactive.rejected')}
          {decision === null && t('interactive.answered')}
        </p>
      ) : (
        <>
          <label className="mt-3 flex flex-col gap-1.5">
            <span className="text-muted-foreground text-xs">
              {block.note || t('interactive.noteDefault')}
            </span>
            <Textarea
              value={note}
              onChange={(event) => setNote(event.target.value)}
              placeholder={t('interactive.notePlaceholder')}
              rows={2}
            />
          </label>
          <div className="mt-3 flex flex-wrap justify-end gap-2">
            <Button
              type="button"
              variant="outline"
              disabled={!canSubmit}
              onClick={() => send(false)}
            >
              {block.reject || t('interactive.reject')}
            </Button>
            <Button
              type="button"
              disabled={!canSubmit}
              onClick={() => send(true)}
            >
              {block.approve || t('interactive.approve')}
            </Button>
          </div>
        </>
      )}
    </div>
  )
}
```

- [ ] **Step 9: Write `src/renderer/components/chat/interactive/interactive-fence.tsx`**

```tsx
// Where a reply's fenced code becomes its block. `markdown.tsx` hands every
// `<pre>` whose code is an `exodus-ask` / `exodus-confirm` fence to
// `InteractiveFence`, with the `<pre>` as its fallback: drawn as the control
// only when it is the turn's block (`useInteractiveTurn`) inside a chat;
// outside a turn, invalid, second or still being written, it stays code.
import {
  interactiveKind,
  type InteractiveKind
} from '@exodus/shared/types/interactive'
import { type ReactNode, useContext } from 'react'

import { ErrorBoundary } from '@/components/card-error-boundary'

import { ConfirmationBlock } from './confirmation-block'
import { InteractiveTurnContext, useInteractiveChat } from './interactive-context'
import { QuestionnaireBlock } from './questionnaire-block'

interface HastNode {
  tagName?: string
  value?: unknown
  properties?: { className?: unknown }
  children?: HastNode[]
}

const trimNewlines = (text: string) => text.replace(/\n+$/, '')

/** A `<pre>`'s code as an interactive fence's kind and text, read off the node react-markdown hands it. */
export function fenceOf(
  node: unknown
): { kind: InteractiveKind; source: string } | null {
  const code = (node as HastNode | undefined)?.children?.[0]
  if (code?.tagName !== 'code') return null
  const className = code.properties?.className
  const classes: unknown[] = Array.isArray(className) ? className : []
  const language = classes.find(
    (c): c is string => typeof c === 'string' && c.startsWith('language-')
  )
  const kind = language ? interactiveKind(language.slice('language-'.length)) : null
  if (!kind) return null
  const source = (code.children ?? [])
    .map((child) => (typeof child.value === 'string' ? child.value : ''))
    .join('')
  return { kind, source }
}

export function InteractiveFence({
  kind,
  source,
  children
}: {
  kind: InteractiveKind
  source: string
  /** The code block, drawn when this fence is not the turn's block. */
  children: ReactNode
}) {
  const turn = useContext(InteractiveTurnContext)
  const chat = useInteractiveChat()
  const fence = turn?.fence
  if (
    !turn ||
    !chat ||
    !fence ||
    fence.kind !== kind ||
    trimNewlines(fence.source) !== trimNewlines(source)
  ) {
    return children
  }
  const props = {
    runId: turn.runId,
    answered: chat.answers.get(turn.runId) ?? null,
    canSubmit: chat.canSubmit,
    submit: chat.submit
  }
  return (
    <ErrorBoundary scope="interactive-block" fallback={children}>
      {fence.kind === 'ask' ? (
        <QuestionnaireBlock block={fence.block} {...props} />
      ) : (
        <ConfirmationBlock block={fence.block} {...props} />
      )}
    </ErrorBoundary>
  )
}
```

- [ ] **Step 10: Hand interactive fences over in `src/renderer/components/markdown.tsx`**

Add the import after `import { WorkspacePathCode } from './workspace-path-code'`:

```tsx
import { fenceOf, InteractiveFence } from './chat/interactive/interactive-fence'
```

In `code()`, replace

```tsx
        const match = /language-(\w+)/.exec(className || 'javascript')
```

with

```tsx
        // `[\w-]`: a fence named `exodus-ask` is labelled that, not `exodus`.
        const match = /language-([\w-]+)/.exec(className || 'javascript')
```

Replace the `pre()` override

```tsx
      // eslint-disable-next-line @typescript-eslint/no-unused-vars, @typescript-eslint/no-explicit-any
      pre({ className, children, node, ...rest }: any) {
        return (
          <pre {...rest} className={className}>
            {children}
          </pre>
        )
      },
```

with

```tsx
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      pre({ className, children, node, ...rest }: any) {
        const pre = (
          <pre {...rest} className={className}>
            {children}
          </pre>
        )
        // A reply's questionnaire or confirmation: the control, or this code
        // when it is not the turn's block (see interactive-fence.tsx).
        const fence = fenceOf(node)
        return fence ? (
          <InteractiveFence kind={fence.kind} source={fence.source}>
            {pre}
          </InteractiveFence>
        ) : (
          pre
        )
      },
```

- [ ] **Step 11: Give each turn its block in `src/renderer/components/chat/assistant-turn-segment.tsx`**

Add the import after `import { MemoryChangeStrip } from './memory-change-strip'`:

```tsx
import {
  InteractiveTurnContext,
  useInteractiveTurn
} from './interactive/interactive-context'
```

After

```tsx
    const galleryVideos = useMemo(
      () => collectGalleryVideos(turn.webSearchResults),
      [turn.webSearchResults]
    )
```

add

```tsx
    // The run's questionnaire or confirmation: the first one of its whole
    // answer, so one in a later paragraph stays code.
    const interactiveTurn = useInteractiveTurn(turn.runId, turn.body)
```

and wrap the answer's `<section className="group relative" data-askable="">…</section>` in the turn's context — replace

```tsx
          <section className="group relative" data-askable="">
```

with

```tsx
          <InteractiveTurnContext.Provider value={interactiveTurn}>
          <section className="group relative" data-askable="">
```

and the `</section>` that closes it (the one right before the `{/* The run's foot, over its action row …` comment) with

```tsx
          </section>
          </InteractiveTurnContext.Provider>
```

(`bunx oxfmt` in Step 14 re-indents the section.)

- [ ] **Step 12: Put the chat's answers and send around the transcript (`src/renderer/components/chat.tsx`, dirty)**

Create `/tmp/blocks/chat_edits.py`:

```python
PATH = "src/renderer/components/chat.tsx"
EDITS = [
    (
        "import { LcmStatusCard } from './chat/lcm-status-card'\n",
        "import { InteractiveProvider } from './chat/interactive/interactive-context'\nimport { LcmStatusCard } from './chat/lcm-status-card'\n",
    ),
    (
        '  return (\n    <>\n      <div className="relative flex min-h-0 flex-1 flex-col">\n',
        '  return (\n    <InteractiveProvider messages={messages} status={status} send={sendMessage}>\n      <div className="relative flex min-h-0 flex-1 flex-col">\n',
    ),
    (
        "      </div>\n    </>\n  )\n}\n",
        "      </div>\n    </InteractiveProvider>\n  )\n}\n",
    ),
]
```

```bash
cd /Users/yanceyleo/Code/exodus/exodus
python3 /tmp/blocks/dual_edit.py check /tmp/blocks/chat_edits.py   # OK … 3 edit(s)
python3 /tmp/blocks/dual_edit.py fmt /tmp/blocks/chat_edits.py     # FORMAT-OK (else adopt oxfmt's + lines, re-run)
python3 /tmp/blocks/dual_edit.py apply /tmp/blocks/chat_edits.py
```

- [ ] **Step 13: Run the tests**

Run: `bunx vitest run tests/unit/renderer/components/chat/interactive-blocks.test.ts tests/unit/renderer/components/chat/user-bubble.test.ts tests/unit/renderer/components/messages-block-order.test.ts tests/unit/renderer/components/markdown-citations.test.ts`
Expected: PASS. If the questionnaire's Submit case fails only because happy-dom does not run the primitive's form validation the same way, check in the browser (Step 15) before changing the test; do not weaken the assertion on `send`'s text.

- [ ] **Step 14: Lint, format, typecheck**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
F="src/renderer/components/chat/interactive/interactive-context.tsx src/renderer/components/chat/interactive/interactive-fence.tsx src/renderer/components/chat/interactive/questionnaire-block.tsx src/renderer/components/chat/interactive/confirmation-block.tsx src/renderer/components/chat/interactive/answer-labels.ts src/renderer/components/markdown.tsx src/renderer/components/chat/assistant-turn-segment.tsx tests/unit/renderer/components/chat/interactive-blocks.test.ts"
bunx oxlint $F src/renderer/components/chat.tsx && bunx oxfmt $F
bun run typecheck:web && bun run i18n:check | tail -1
bunx vitest run tests/unit/renderer/components/chat/interactive-blocks.test.ts
```

- [ ] **Step 15: See it in the app**

`bun run dev`, open a chat, send: "Reply with exactly this and nothing else:" followed by a line break and the fence `exodus-ask` with `{"title":"Pick","questions":[{"id":"a","text":"Which?","type":"single","options":["One","Two"],"other":true},{"id":"b","text":"And?","type":"multi","options":["X","Y"]}]}`. Expect the card with "Question 1 of 2", Previous/Skip/Next, the note on step 2, Submit; Submit adds your answer (still drawn as raw Markdown until Task 4) and the questionnaire turns into the summary with your picks and "Answered". Then a confirmation the same way (Approve / Reject, note, Markdown details). Stop the dev server.

- [ ] **Step 16: Commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
python3 /tmp/blocks/desktop_strings.py patch /tmp/blocks/strings.patch                       # PATCH-OK
python3 /tmp/blocks/dual_edit.py patch /tmp/blocks/chat_edits.py /tmp/blocks/chat.patch       # PATCH-OK
.superpowers/sdd/commit-mine.sh "feat(chat): a reply's questionnaire and confirmation are drawn as controls — the questionnaire on the shadcn Questionnaire, Approve/Reject with a note — sent through the chat's send, frozen once the chat holds the answer" \
  --patch /tmp/blocks/strings.patch --patch /tmp/blocks/chat.patch $F
git show --stat HEAD                   # the 8 files of $F, chat.tsx and the ten chat.json — never ui/questionnaire.tsx, package.json or bun.lock
git diff --stat -- src/renderer/components/chat.tsx packages/shared/src/i18n/locales   # only the user's own edits remain
```

---
### Task 4: Desktop — the user's answer drawn as a card

**Files:**
- Create: `src/renderer/components/chat/interactive/answer-title.tsx`
- Modify: `src/renderer/components/chat/user-bubble.tsx` (clean)
- Test: `tests/unit/renderer/components/chat/answer-card.test.ts`

**Interfaces:**
- Consumes: `splitAnswer`, `AnswerHead`, `composeAskAnswer`, `composeConfirmAnswer` (Task 1); `chat:interactive.answer.title` (Task 3).
- Produces: `AnswerTitle({ head }: { head: AnswerHead })` (`data-slot="answer-title"`); `UserBubble` sets `data-answer="ask"|"confirm"` on an answer's bubble.

- [ ] **Step 1: Check the file is clean**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
git diff --stat -- src/renderer/components/chat/user-bubble.tsx   # must print nothing
```

- [ ] **Step 2: Write the failing test**

Create `tests/unit/renderer/components/chat/answer-card.test.ts`:

````ts
// @vitest-environment happy-dom
// A message that answers a questionnaire or a confirmation is drawn as a card:
// the block's title, then the answers, quieter — never the fence it travels
// in. A malformed answer fence is an ordinary message.
import {
  askBlockSchema,
  confirmBlockSchema
} from '@exodus/shared/types/interactive'
import {
  composeAskAnswer,
  composeConfirmAnswer,
  type AnswerLabels
} from '@exodus/shared/utils/interactive-answer'
import { act, createElement } from 'react'
import { createRoot } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

;(
  globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }
).IS_REACT_ACT_ENVIRONMENT = true

const t = (key: string) => key
const i18n = { resolvedLanguage: 'en', language: 'en' }
vi.mock('react-i18next', () => ({ useTranslation: () => ({ t, i18n }) }))

const { UserBubble } = await import('@/components/chat/user-bubble')

const EN: AnswerLabels = {
  other: 'Other',
  addition: 'Also',
  note: 'Note',
  approved: 'Approved',
  rejected: 'Rejected'
}

let host: HTMLDivElement
let root: ReturnType<typeof createRoot>

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
  root = createRoot(host)
})

afterEach(async () => {
  await act(async () => root.unmount())
  host.remove()
})

const show = (text: string) =>
  act(async () => root.render(createElement(UserBubble, { text })))
const title = () =>
  host.querySelector('[data-slot="answer-title"]')?.textContent

describe('an answer in the user bubble', () => {
  it("draws a questionnaire's answer as its title over the answers, without the fence", async () => {
    const block = askBlockSchema.parse({
      title: 'A few details first',
      questions: [
        { id: 'where', text: 'Where?', type: 'single', options: ['Legs', 'Arms'] }
      ]
    })
    await show(
      composeAskAnswer(block, 'run-1', { where: { options: ['Legs'], other: null } }, 'Unscented lotion', EN)
    )
    expect(host.querySelector('[data-answer="ask"]')).not.toBeNull()
    expect(title()).toBe('A few details first')
    expect(
      Array.from(host.querySelectorAll('strong')).map((s) => s.textContent)
    ).toEqual(['Where?', 'Also:'])
    expect(host.textContent).toContain('Legs')
    expect(host.textContent).not.toContain('exodus-answer')
    expect(host.querySelector('pre')).toBeNull()
  })

  it("draws a confirmation's answer with its decision", async () => {
    const block = confirmBlockSchema.parse({ title: 'Send the report?' })
    await show(composeConfirmAnswer(block, 'run-1', false, '', EN))
    expect(host.querySelector('[data-answer="confirm"]')).not.toBeNull()
    expect(title()).toBe('Send the report?')
    expect(host.textContent).toContain('Rejected')
  })

  it('an answer without a title reads "Your answer"', async () => {
    await show('```exodus-answer\n{"block":"ask","ref":"r"}\n```\n\n**Q** A')
    expect(title()).toBe('interactive.answer.title')
  })

  it('a malformed answer fence is an ordinary message', async () => {
    await show('```exodus-answer\n{oops}\n```\n\nhello')
    expect(host.querySelector('[data-answer]')).toBeNull()
    expect(title()).toBeUndefined()
    expect(host.querySelector('pre')).not.toBeNull()
    expect(host.textContent).toContain('hello')
  })
})
````

- [ ] **Step 3: Run it to see it fail**

Run: `bunx vitest run tests/unit/renderer/components/chat/answer-card.test.ts`
Expected: FAIL — the first three cases (`data-answer` / `answer-title` not found); the malformed case passes already.

- [ ] **Step 4: Write `src/renderer/components/chat/interactive/answer-title.tsx`**

```tsx
import type { AnswerHead } from '@exodus/shared/utils/interactive-answer'
import { CircleCheckIcon, CircleXIcon, ListChecksIcon } from 'lucide-react'
import { useTranslation } from 'react-i18next'

/** The head of an answer's card: what it answered, by the block's title. */
export function AnswerTitle({ head }: { head: AnswerHead }) {
  const { t } = useTranslation('chat')
  const Icon =
    head.block === 'ask'
      ? ListChecksIcon
      : head.decision === 'reject'
        ? CircleXIcon
        : CircleCheckIcon
  return (
    <p className="mb-1 flex items-start gap-1.5 text-sm font-medium">
      <Icon aria-hidden className="text-primary-ink mt-0.5 size-4 shrink-0" />
      <span data-slot="answer-title" className="min-w-0">
        {head.title || t('interactive.answer.title')}
      </span>
    </p>
  )
}
```

- [ ] **Step 5: Draw the card in `src/renderer/components/chat/user-bubble.tsx`**

Add the imports — after `import { splitHealth } from '@exodus/shared/utils/health-context'`:

```tsx
import { splitAnswer } from '@exodus/shared/utils/interactive-answer'
```

and after `import { HealthContextCard } from '@/components/chat/health-context-card'`:

```tsx
import { AnswerTitle } from '@/components/chat/interactive/answer-title'
```

In the doc comment over `UserBubble`, replace

```tsx
 * (`splitHealth`), before any quote: drawn as a card of chips.
```

with

```tsx
 * (`splitHealth`), before any quote: drawn as a card of chips. One that
 * answers a questionnaire or a confirmation opens with its answer fence
 * (`splitAnswer`): drawn as a card — the block's title, then the answers,
 * quieter.
```

Replace

```tsx
  const health = splitHealth(text)
  const { quote, body } = splitQuoted(health.body)
```

with

```tsx
  const { answer, body: answered } = splitAnswer(text)
  const health = splitHealth(answered)
  const { quote, body } = splitQuoted(health.body)
```

Replace

```tsx
    <div
      data-askable=""
      className="bg-bubble text-foreground max-w-[75%] rounded-2xl rounded-br-sm px-4 py-2.5 text-base leading-relaxed wrap-break-word"
    >
```

with

```tsx
    <div
      data-askable=""
      data-answer={answer?.block}
      className="bg-bubble text-foreground max-w-[75%] rounded-2xl rounded-br-sm px-4 py-2.5 text-base leading-relaxed wrap-break-word"
    >
```

Replace

```tsx
        {health.json !== null && <HealthContextCard json={health.json} />}
```

with

```tsx
        {answer !== null && <AnswerTitle head={answer} />}
        {health.json !== null && <HealthContextCard json={health.json} />}
```

Replace

```tsx
          <div className="[&_.markdown_:not(pre)>code]:bg-foreground/7 [&_.markdown]:leading-relaxed [&_.markdown_p]:whitespace-pre-wrap">
```

with

```tsx
          <div
            className={cn(
              '[&_.markdown_:not(pre)>code]:bg-foreground/7 [&_.markdown]:leading-relaxed [&_.markdown_p]:whitespace-pre-wrap',
              // An answer's lines are quieter than its title.
              answer !== null && 'text-muted-foreground text-sm'
            )}
          >
```

- [ ] **Step 6: Run the tests**

Run: `bunx vitest run tests/unit/renderer/components/chat/answer-card.test.ts tests/unit/renderer/components/chat/user-bubble.test.ts tests/unit/renderer/components/chat/health-context.test.ts`
Expected: PASS (the bubble's existing tests unchanged).

- [ ] **Step 7: Lint, format, typecheck, look, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
F="src/renderer/components/chat/interactive/answer-title.tsx src/renderer/components/chat/user-bubble.tsx tests/unit/renderer/components/chat/answer-card.test.ts"
bunx oxlint $F && bunx oxfmt $F
bun run typecheck:web
```

`bun run dev`: answer a questionnaire as in Task 3 Step 15 — your message is now a card (list icon, the title, the lines muted with the questions bold); answer a confirmation with Reject — the ✕ icon. Stop the dev server.

```bash
.superpowers/sdd/commit-mine.sh "feat(chat): an answer to a questionnaire or a confirmation is drawn as a card in the user's bubble — the block's title, then the answers, quieter" $F
git show --stat HEAD                   # exactly the three files
```

---
### Task 5: iOS — `InteractiveBlock`, `InteractiveFence` and `InteractiveAnswer`, held to the desktop's vectors

**Files:**
- Create: `Sources/ChatFeature/Interactive/InteractiveBlock.swift`
- Create: `Sources/ChatFeature/Interactive/InteractiveAnswer.swift`
- Test: `Tests/ChatFeatureTests/InteractiveBlockTests.swift`
- Test: `Tests/ChatFeatureTests/InteractiveAnswerTests.swift`

**Interfaces:**
- Consumes: Foundation only. The vectors of Task 1 (copied verbatim).
- Produces (internal to ChatFeature): `enum InteractiveBlock { case ask(Ask), confirm(Confirm) }` with `Kind` (`.ask`, `.confirm`; `language`, `init?(language:)`, `Codable`), `Ask` (`title`, `questions: [Question]`, `note: String?`, `submit: String?`), `Ask.Question` (`id`, `text`, `type: .single|.multi`, `options: [String]`, `other: Bool`), `Confirm` (`title`, `details`, `approve`, `reject`, `note`: `String?`), `kind`, `isValid`, `static func parse(_ kind: Kind, source: String) -> InteractiveBlock?`; `struct InteractiveFence { block; source; kind; func matches(language: String?, code: String) -> Bool; static func first(in markdown: String) -> InteractiveFence? }`; `enum InteractiveAnswer` with `infoString`, `blank`, `Labels(other:addition:note:approved:rejected:)`, `Head(block:decision:ref:title:)` (`Decision.approve|.reject`), `Response(options:other:)`, `Picks(options:other:)`, `oneLine(_:)`, `composeAsk(_:ref:responses:note:labels:) -> String`, `composeConfirm(_:ref:approved:note:labels:) -> String`, `split(_:) -> (head: Head?, body: String)`, `picks(_:body:) -> [String: Picks]`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ChatFeatureTests/InteractiveBlockTests.swift`:

```swift
import Foundation
import Testing

@testable import ChatFeature

// The same vectors as the desktop's tests/unit/shared/types/interactive.test.ts — keep them in step.
private let askSource =
    #"{"title":"我想先确认一下你的具体情况","questions":[{"id":"where","text":"哪里最痒？","type":"single","options":["小腿","手臂","全身到处都痒"],"other":true},{"id":"when","text":"什么时候最痒？","type":"multi","options":["洗澡后","晚上","全天"]}],"note":"还有什么想补充的？","submit":"提交，帮我判断"}"#
private let confirmSource =
    #"{"title":"要我把这份行程写进日历吗？","details":"10 月 21–25 日，五天，17 个地点；日历「旅行」。","approve":"写进去","reject":"先不要","note":"有要改的地方可以写在这里"}"#

private func q(_ id: String, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["id": id, "text": "Q", "type": "single", "options": ["x", "y"]].merging(extra) { $1 }
}
private func json(_ object: Any) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self)
}
private func ask(_ extra: [String: Any] = [:]) -> String { json(["title": "T", "questions": [q("a")]].merging(extra) { $1 }) }
private func confirm(_ extra: [String: Any] = [:]) -> String { json(["title": "T"].merging(extra) { $1 }) }
private func repeated(_ s: String, _ n: Int) -> String { String(repeating: s, count: n) }

private let askCases: [(String, String, Bool)] = [
    ("the spec's example", askSource, true),
    ("eight questions", ask(["questions": (0..<8).map { q("q\($0)") }]), true),
    ("nine questions", ask(["questions": (0..<9).map { q("q\($0)") }]), false),
    ("no questions", ask(["questions": [Any]()]), false),
    ("an 80-character option", ask(["questions": [q("a", ["options": [repeated("x", 80), "y"]])]]), true),
    ("an 81-character option", ask(["questions": [q("a", ["options": [repeated("x", 81), "y"]])]]), false),
    ("40 emoji (80 UTF-16 units)", ask(["questions": [q("a", ["options": [repeated("😀", 40), "y"]])]]), true),
    ("41 emoji (82 UTF-16 units)", ask(["questions": [q("a", ["options": [repeated("😀", 41), "y"]])]]), false),
    ("one option", ask(["questions": [q("a", ["options": ["x"]])]]), false),
    ("nine options", ask(["questions": [q("a", ["options": (0..<9).map { String($0) }])]]), false),
    ("the same option twice", ask(["questions": [q("a", ["options": ["x", "x"]])]]), false),
    ("two questions with one id", ask(["questions": [q("a"), q("a")]]), false),
    ("an id with a capital", ask(["questions": [q("Where")]]), false),
    ("a 33-character id", ask(["questions": [q(repeated("a", 33))]]), false),
    ("a type that is neither single nor multi", ask(["questions": [q("a", ["type": "text"])]]), false),
    ("an empty title", ask(["title": ""]), false),
    ("a 201-character question", ask(["questions": [q("a", ["text": repeated("q", 201)])]]), false),
    ("a 121-character note", ask(["note": repeated("n", 121)]), false),
    ("a 41-character submit", ask(["submit": repeated("s", 41)]), false),
    ("nulls for what is optional", ask(["note": NSNull(), "submit": NSNull(), "questions": [q("a", ["other": NSNull()])]]), true),
    ("keys it does not know", ask(["colour": "red"]), true),
    ("not JSON", #"{"title":"#, false),
    ("an array", "[]", false),
]

private let confirmCases: [(String, String, Bool)] = [
    ("the spec's example", confirmSource, true),
    ("a title alone", confirm(), true),
    ("no title", json(["details": "d"]), false),
    ("a 201-character title", confirm(["title": repeated("t", 201)]), false),
    ("1000 characters of details", confirm(["details": repeated("d", 1000)]), true),
    ("1001 characters of details", confirm(["details": repeated("d", 1001)]), false),
    ("a 41-character approve", confirm(["approve": repeated("a", 41)]), false),
    ("a 41-character reject", confirm(["reject": repeated("r", 41)]), false),
    ("a 121-character note", confirm(["note": repeated("n", 121)]), false),
]

private let findCases: [(String, String, InteractiveBlock.Kind?)] = [
    ("a questionnaire after a paragraph", "Intro\n\n```exodus-ask\n\(askSource)\n```\n\nAfter", .ask),
    ("a fence still open (a reply streaming)", "Intro\n\n```exodus-ask\n\(askSource)", nil),
    ("two blocks: only the first counts", "```exodus-confirm\n\(confirmSource)\n```\n\n```exodus-ask\n\(askSource)\n```", .confirm),
    ("a first block that does not validate: none", "```exodus-ask\n{oops}\n```\n\n```exodus-confirm\n\(confirmSource)\n```", nil),
    ("inside a longer backtick fence", "````md\n```exodus-ask\n\(askSource)\n```\n````", nil),
    ("inside a tilde fence", "~~~\n```exodus-ask\n\(askSource)\n```\n~~~", nil),
    ("indented under a list item", "- item\n\n  ```exodus-ask\n  \(askSource)\n  ```", nil),
    ("after an ordinary code block", "```js\nlet a = 1\n```\n\n```exodus-confirm\n\(confirmSource)\n```", .confirm),
    ("trailing spaces after the name", "```exodus-confirm  \n\(confirmSource)\n```", .confirm),
    ("another name", "```exodus-answer\n{\"block\":\"ask\",\"ref\":\"r\"}\n```", nil),
]

@Suite("InteractiveBlock: the blocks' limits, as the desktop's zod schemas")
struct InteractiveBlockTests {
    @Test("exodus-ask", arguments: askCases)
    func askLimits(_ name: String, _ source: String, _ valid: Bool) {
        #expect((InteractiveBlock.parse(.ask, source: source) != nil) == valid, "\(name)")
    }

    @Test("exodus-confirm", arguments: confirmCases)
    func confirmLimits(_ name: String, _ source: String, _ valid: Bool) {
        #expect((InteractiveBlock.parse(.confirm, source: source) != nil) == valid, "\(name)")
    }

    @Test("a missing \"other\" is no Other; the fence's names map to kinds")
    func reading() throws {
        guard case .ask(let block)? = InteractiveBlock.parse(.ask, source: askSource) else {
            Issue.record("expected a questionnaire")
            return
        }
        #expect(block.questions.map(\.other) == [true, false])
        #expect(block.questions.map(\.type) == [.single, .multi])
        #expect(InteractiveBlock.Kind(language: "exodus-ask") == .ask)
        #expect(InteractiveBlock.Kind(language: "exodus-confirm") == .confirm)
        #expect(InteractiveBlock.Kind(language: "exodus-answer") == nil)
        #expect(InteractiveBlock.Kind.confirm.language == "exodus-confirm")
    }
}

@Suite("InteractiveFence: which fence of a reply is its block")
struct InteractiveFenceTests {
    @Test("find", arguments: findCases)
    func find(_ name: String, _ markdown: String, _ kind: InteractiveBlock.Kind?) {
        #expect(InteractiveFence.first(in: markdown)?.kind == kind, "\(name)")
    }

    @Test("the fence's text is how its code block is known")
    func matches() throws {
        let fence = try #require(InteractiveFence.first(in: "Intro\n\n```exodus-ask\n\(askSource)\n```\n"))
        #expect(fence.source == askSource)
        #expect(fence.matches(language: "exodus-ask", code: askSource))
        #expect(fence.matches(language: "exodus-ask", code: askSource + "\n"))
        #expect(!fence.matches(language: "exodus-confirm", code: askSource))
        #expect(!fence.matches(language: nil, code: askSource))
        #expect(!fence.matches(language: "exodus-ask", code: "{}"))
    }
}
```

Create `Tests/ChatFeatureTests/InteractiveAnswerTests.swift`:

```swift
import Foundation
import Testing

@testable import ChatFeature

// The same vectors as the desktop's tests/unit/shared/utils/interactive-answer.test.ts — keep them in step.
private let askSource =
    #"{"title":"我想先确认一下你的具体情况","questions":[{"id":"where","text":"哪里最痒？","type":"single","options":["小腿","手臂","全身到处都痒"],"other":true},{"id":"when","text":"什么时候最痒？","type":"multi","options":["洗澡后","晚上","全天"]}],"note":"还有什么想补充的？","submit":"提交，帮我判断"}"#
private let confirmSource =
    #"{"title":"要我把这份行程写进日历吗？","details":"10 月 21–25 日，五天，17 个地点；日历「旅行」。","approve":"写进去","reject":"先不要","note":"有要改的地方可以写在这里"}"#
private let sizesSource =
    #"{"title":"Pick a plan","questions":[{"id":"size","text":"Which sizes?","type":"multi","options":["Small, cheap","Medium","Large, roomy"],"other":true}]}"#
private let quotedSource = #"{"title":"Send \"Q3/Q4\" report?"}"#

private let zh = InteractiveAnswer.Labels(other: "其他", addition: "补充", note: "备注", approved: "同意", rejected: "拒绝")
private let en = InteractiveAnswer.Labels(
    other: "Other", addition: "Also", note: "Note", approved: "Approved", rejected: "Rejected")

private let answerCJK =
    #"```exodus-answer\#n{"block":"ask","ref":"a9f2","title":"我想先确认一下你的具体情况"}\#n```\#n\#n"#
    + #"**哪里最痒？** 小腿\#n**什么时候最痒？** 洗澡后, 晚上\#n**补充:** 用的是丝塔芙润肤乳"#
private let answerOther =
    #"```exodus-answer\#n{"block":"ask","ref":"a9f2","title":"我想先确认一下你的具体情况"}\#n```\#n\#n"#
    + #"**哪里最痒？** 其他: 脚踝 和脚背\#n**什么时候最痒？** —"#
private let answerCommas =
    #"```exodus-answer\#n{"block":"ask","ref":"r-2","title":"Pick a plan"}\#n```\#n\#n"#
    + #"**Which sizes?** Small, cheap, Large, roomy, Other"#
private let answerApprove =
    #"```exodus-answer\#n{"block":"confirm","decision":"approve","ref":"c1","title":"要我把这份行程写进日历吗？"}\#n```\#n\#n"#
    + #"**要我把这份行程写进日历吗？** 同意\#n**备注:** 第三天换成京都"#
private let answerReject =
    #"```exodus-answer\#n{"block":"confirm","decision":"reject","ref":"c2","title":"Send \"Q3/Q4\" report?"}\#n```\#n\#n"#
    + #"**Send "Q3/Q4" report?** Rejected"#

private struct NotABlock: Error {}
private func ask(_ source: String) throws -> InteractiveBlock.Ask {
    guard case .ask(let block)? = InteractiveBlock.parse(.ask, source: source) else { throw NotABlock() }
    return block
}
private func confirm(_ source: String) throws -> InteractiveBlock.Confirm {
    guard case .confirm(let block)? = InteractiveBlock.parse(.confirm, source: source) else { throw NotABlock() }
    return block
}

@Suite("InteractiveAnswer: a block's answer as the user's next message, as the desktop writes it")
struct InteractiveAnswerTests {
    @Test("a line a question, the picks in the options' order, then the closing note")
    func askAnswer() throws {
        let text = InteractiveAnswer.composeAsk(
            try ask(askSource), ref: "a9f2",
            responses: ["where": .init(options: ["小腿"]), "when": .init(options: ["晚上", "洗澡后"])],
            note: "用的是丝塔芙润肤乳", labels: zh)
        #expect(text == answerCJK)
    }

    @Test("Other with its text on one line, a blank as —, no note line when none was typed")
    func otherAndBlank() throws {
        let text = InteractiveAnswer.composeAsk(
            try ask(askSource), ref: "a9f2", responses: ["where": .init(options: [], other: "脚踝\n和脚背")],
            note: "  ", labels: zh)
        #expect(text == answerOther)
    }

    @Test("an option's commas kept, Other picked with nothing typed as the word alone")
    func commas() throws {
        let text = InteractiveAnswer.composeAsk(
            try ask(sizesSource), ref: "r-2",
            responses: ["size": .init(options: ["Large, roomy", "Small, cheap"], other: "")], note: "", labels: en)
        #expect(text == answerCommas)
    }

    @Test("a confirmation: the title and the decision, then the note")
    func confirmAnswer() throws {
        #expect(
            InteractiveAnswer.composeConfirm(
                try confirm(confirmSource), ref: "c1", approved: true, note: "第三天换成京都", labels: zh) == answerApprove)
        #expect(
            InteractiveAnswer.composeConfirm(try confirm(quotedSource), ref: "c2", approved: false, note: "\n", labels: en)
                == answerReject)
    }

    @Test("split reads the fence and the lines after it")
    func split() {
        let cjk = InteractiveAnswer.split(answerCJK)
        #expect(cjk.head == .init(block: .ask, decision: nil, ref: "a9f2", title: "我想先确认一下你的具体情况"))
        #expect(cjk.body == "**哪里最痒？** 小腿\n**什么时候最痒？** 洗澡后, 晚上\n**补充:** 用的是丝塔芙润肤乳")
        #expect(
            InteractiveAnswer.split(answerReject).head
                == .init(block: .confirm, decision: .reject, ref: "c2", title: #"Send "Q3/Q4" report?"#))
        let alone = InteractiveAnswer.split("```exodus-answer\n{\"block\":\"confirm\",\"ref\":\"r\"}\n```")
        #expect(alone.head == .init(block: .confirm, decision: nil, ref: "r", title: nil))
        #expect(alone.body == "")
    }

    @Test(
        "what is not an answer is returned whole",
        arguments: [
            "hello",
            "```exodus-answer\n{oops}\n```\n\nhi",
            "```exodus-answer\n{\"block\":\"poll\",\"ref\":\"r\"}\n```\n\nhi",
            "```exodus-answer\n{\"block\":\"ask\"}\n```\n\nhi",
            "```exodus-answer\n{\"block\":\"ask\",\"ref\":\"r\"}",
        ])
    func notAnAnswer(_ text: String) {
        let split = InteractiveAnswer.split(text)
        #expect(split.head == nil)
        #expect(split.body == text)
    }

    @Test("picks read each question back from its line")
    func picks() throws {
        let block = try ask(askSource)
        #expect(
            InteractiveAnswer.picks(block, body: InteractiveAnswer.split(answerCJK).body) == [
                "where": .init(options: ["小腿"], other: false), "when": .init(options: ["洗澡后", "晚上"], other: false),
            ])
        #expect(
            InteractiveAnswer.picks(block, body: InteractiveAnswer.split(answerOther).body) == [
                "where": .init(options: [], other: true), "when": .init(options: [], other: false),
            ])
        #expect(
            InteractiveAnswer.picks(try ask(sizesSource), body: InteractiveAnswer.split(answerCommas).body) == [
                "size": .init(options: ["Small, cheap", "Large, roomy"], other: true)
            ])
        #expect(InteractiveAnswer.picks(try ask(sizesSource), body: "") == ["size": .init(options: [], other: false)])
    }

    @Test("picks are read back without knowing the language they were written in")
    func picksWithoutLabels() throws {
        let block = try ask(sizesSource)
        let japanese = InteractiveAnswer.composeAsk(
            block, ref: "r", responses: ["size": .init(options: ["Medium"], other: "特大")], note: "メモ",
            labels: .init(other: "その他", addition: "補足", note: "メモ", approved: "承認済み", rejected: "却下済み"))
        #expect(
            InteractiveAnswer.picks(block, body: InteractiveAnswer.split(japanese).body) == [
                "size": .init(options: ["Medium"], other: true)
            ])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git diff --stat                     # note the user's paths; they stay as they are
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd -only-testing:ChatFeatureTests/InteractiveBlockTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'InteractiveBlock' in scope`, `TEST FAILED`.

- [ ] **Step 3: Write `Sources/ChatFeature/Interactive/InteractiveBlock.swift`**

```swift
import Foundation

/// The questionnaire and the confirmation a reply can ask with (spec 2026-10-06): a fenced block whose info string
/// names it (`exodus-ask`, `exodus-confirm`) and whose body is one JSON object. One that validates is drawn as a
/// control; anything else stays the code block it is. The desktop has the same rules
/// (`packages/shared/src/types/interactive.ts`), held to the same vectors; lengths are UTF-16 units, as zod counts.
enum InteractiveBlock: Equatable, Sendable {
    case ask(Ask)
    case confirm(Confirm)

    enum Kind: String, Codable, Sendable {
        case ask, confirm

        /// The fence's info string.
        var language: String { "exodus-" + rawValue }

        init?(language: String) {
            guard language.hasPrefix("exodus-") else { return nil }
            self.init(rawValue: String(language.dropFirst("exodus-".count)))
        }
    }

    struct Ask: Decodable, Equatable, Sendable {
        struct Question: Decodable, Equatable, Sendable {
            enum Kind: String, Decodable, Sendable { case single, multi }

            let id: String
            let text: String
            let type: Kind
            let options: [String]
            /// Adds "Other…", a choice the user types into.
            let other: Bool

            private enum CodingKeys: String, CodingKey { case id, text, type, options, other }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                text = try container.decode(String.self, forKey: .text)
                type = try container.decode(Kind.self, forKey: .type)
                options = try container.decode([String].self, forKey: .options)
                other = try container.decodeIfPresent(Bool.self, forKey: .other) ?? false
            }
        }

        let title: String
        let questions: [Question]
        /// The closing field's label; the phone's own when absent or empty.
        let note: String?
        /// The button's label; the phone's own when absent or empty.
        let submit: String?
    }

    struct Confirm: Decodable, Equatable, Sendable {
        let title: String
        /// Markdown.
        let details: String?
        let approve: String?
        let reject: String?
        let note: String?
    }

    var kind: Kind {
        switch self {
        case .ask: .ask
        case .confirm: .confirm
        }
    }

    /// A fence's body as its block, or nil when it is not one JSON object within the limits.
    static func parse(_ kind: Kind, source: String) -> InteractiveBlock? {
        let data = Data(source.utf8)
        let decoder = JSONDecoder()
        let block: InteractiveBlock? =
            switch kind {
            case .ask: (try? decoder.decode(Ask.self, from: data)).map(InteractiveBlock.ask)
            case .confirm: (try? decoder.decode(Confirm.self, from: data)).map(InteractiveBlock.confirm)
            }
        guard let block, block.isValid else { return nil }
        return block
    }

    var isValid: Bool {
        switch self {
        case .ask(let ask):
            Self.required(ask.title, 200) && (1...8).contains(ask.questions.count)
                && Set(ask.questions.map(\.id)).count == ask.questions.count
                && Self.within(ask.note, 120) && Self.within(ask.submit, 40)
                && ask.questions.allSatisfy { question in
                    Self.isID(question.id) && Self.required(question.text, 200)
                        && (2...8).contains(question.options.count)
                        && Set(question.options).count == question.options.count
                        && question.options.allSatisfy { Self.required($0, 80) }
                }
        case .confirm(let confirm):
            Self.required(confirm.title, 200) && Self.within(confirm.details, 1000)
                && Self.within(confirm.approve, 40) && Self.within(confirm.reject, 40) && Self.within(confirm.note, 120)
        }
    }

    private static func required(_ text: String, _ max: Int) -> Bool { !text.isEmpty && text.utf16.count <= max }
    private static func within(_ text: String?, _ max: Int) -> Bool { (text?.utf16.count ?? 0) <= max }
    private static let idCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789_-")
    private static func isID(_ id: String) -> Bool { (1...32).contains(id.count) && id.allSatisfy(idCharacters.contains) }
}

/// A reply's block and the text of its fence — how the Markdown's code block is known as it.
struct InteractiveFence: Equatable, Sendable {
    let block: InteractiveBlock
    let source: String

    var kind: InteractiveBlock.Kind { block.kind }

    func matches(language: String?, code: String) -> Bool {
        language.flatMap(InteractiveBlock.Kind.init(language:)) == kind && Self.trimmed(code) == Self.trimmed(source)
    }

    /// A reply's block: its first `exodus-ask` / `exodus-confirm` fence that opens a line at the left margin — not
    /// inside another fence, a list or a quote — and is closed. Only that first one counts: when it does not validate
    /// the reply has none, and a second is code either way. A fence still open (a reply being written) is not one yet.
    static func first(in markdown: String) -> InteractiveFence? {
        let lines = markdown.components(separatedBy: "\n")
        var open: (char: Character, length: Int)?
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let run = fenceRun(line)
            if let current = open {
                if let run, run.char == current.char, run.length >= current.length, isBlank(run.rest) { open = nil }
                index += 1
                continue
            }
            if line.hasPrefix("```"), let kind = InteractiveBlock.Kind(language: trimmingTrailing(line.dropFirst(3))) {
                var end = index + 1
                while end < lines.count {
                    if let close = fenceRun(lines[end]), close.char == "`", isBlank(close.rest) {
                        let source = lines[(index + 1)..<end].joined(separator: "\n")
                        return InteractiveBlock.parse(kind, source: source).map { InteractiveFence(block: $0, source: source) }
                    }
                    end += 1
                }
                return nil
            }
            if let run { open = (run.char, run.length) }
            index += 1
        }
        return nil
    }

    /// A line that opens or closes a fence: up to three spaces, then three or more backticks or tildes.
    private static func fenceRun(_ line: String) -> (char: Character, length: Int, rest: Substring)? {
        var start = line.startIndex
        var spaces = 0
        while spaces < 3, start < line.endIndex, line[start] == " " {
            start = line.index(after: start)
            spaces += 1
        }
        guard start < line.endIndex, line[start] == "`" || line[start] == "~" else { return nil }
        let char = line[start]
        var end = start
        while end < line.endIndex, line[end] == char { end = line.index(after: end) }
        let length = line.distance(from: start, to: end)
        return length >= 3 ? (char, length, line[end...]) : nil
    }

    private static func isBlank(_ text: Substring) -> Bool { text.allSatisfy(\.isWhitespace) }

    private static func trimmingTrailing(_ text: Substring) -> String {
        var end = text.endIndex
        while end > text.startIndex, text[text.index(before: end)].isWhitespace { end = text.index(before: end) }
        return String(text[..<end])
    }

    private static func trimmed(_ text: String) -> Substring {
        var end = text.endIndex
        while end > text.startIndex, text[text.index(before: end)] == "\n" { end = text.index(before: end) }
        return text[..<end]
    }
}
```

- [ ] **Step 4: Write `Sources/ChatFeature/Interactive/InteractiveAnswer.swift`**

```swift
import Foundation

/// A questionnaire's or a confirmation's answer, as the user's next message: a leading `exodus-answer` fence naming the
/// block it answers, a blank line, then the answer in plain words — a line a question. Plain text, like `QuotedText`
/// and `HealthContext`, so every provider reads it as what it is; the transcript reads it back with `split` to draw it
/// as a card and to freeze the block it names. Held to the desktop's vectors
/// (`packages/shared/src/utils/interactive-answer.ts`).
enum InteractiveAnswer {
    static let infoString = "exodus-answer"
    /// An unanswered question's line.
    static let blank = "—"
    private static var opening: String { "```" + infoString + "\n" }  // l10n:ignore: markdown syntax
    private static let closing = "\n```"  // l10n:ignore: markdown syntax

    /// The words an answer is written with, in the answering phone's language (`Labels.current`).
    struct Labels: Equatable, Sendable {
        /// Before an "Other…" choice's text: `Other: …`.
        var other: String
        /// The questionnaire's closing line.
        var addition: String
        /// The confirmation's note line.
        var note: String
        var approved: String
        var rejected: String
    }

    /// What the fence says: the block, the run whose reply holds it, its title, a confirmation's decision. Encoded with
    /// sorted keys, as the desktop writes them.
    struct Head: Codable, Equatable, Sendable {
        enum Decision: String, Codable, Sendable { case approve, reject }

        var block: InteractiveBlock.Kind
        var decision: Decision?
        var ref: String
        var title: String?

        private enum CodingKeys: String, CodingKey { case block, decision, ref, title }
    }

    /// One question's answer: the options picked, and the "Other…" text (nil: Other not picked).
    struct Response: Equatable, Sendable {
        var options: [String] = []
        var other: String?
    }

    /// One question's picks, as an answer reads back.
    struct Picks: Equatable, Sendable {
        var options: [String]
        var other: Bool
    }

    /// Typed text on one line: a line break is a space.
    static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func composeAsk(
        _ block: InteractiveBlock.Ask, ref: String, responses: [String: Response], note: String, labels: Labels
    ) -> String {
        var lines = block.questions.map { question -> String in
            let response = responses[question.id]
            var parts = question.options.filter { response?.options.contains($0) == true }
            if question.other, let other = response?.other {
                let text = oneLine(other)
                parts.append(text.isEmpty ? labels.other : labels.other + ": " + text)
            }
            return "**" + question.text + "** " + (parts.isEmpty ? blank : parts.joined(separator: ", "))
        }
        let extra = oneLine(note)
        if !extra.isEmpty { lines.append("**" + labels.addition + ":** " + extra) }
        return fence(Head(block: .ask, ref: ref, title: block.title)) + "\n\n" + lines.joined(separator: "\n")
    }

    static func composeConfirm(
        _ block: InteractiveBlock.Confirm, ref: String, approved: Bool, note: String, labels: Labels
    ) -> String {
        var lines = ["**" + block.title + "** " + (approved ? labels.approved : labels.rejected)]
        let extra = oneLine(note)
        if !extra.isEmpty { lines.append("**" + labels.note + ":** " + extra) }
        let head = Head(block: .confirm, decision: approved ? .approve : .reject, ref: ref, title: block.title)
        return fence(head) + "\n\n" + lines.joined(separator: "\n")
    }

    private static func fence(_ head: Head) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = (try? encoder.encode(head)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return opening + json + closing
    }

    /// A message's text as its answer fence and the lines after it. Only a fence that opens the message counts; it
    /// ends at the first line that is exactly the closing fence, and its JSON must name a block and a run. Anything
    /// else is an ordinary message, returned whole.
    static func split(_ text: String) -> (head: Head?, body: String) {
        guard text.hasPrefix(opening) else { return (nil, text) }
        let rest = text.dropFirst(opening.count)
        var end = rest.range(of: closing + "\n")
        if end == nil, rest.hasSuffix(closing) { end = rest.range(of: closing, options: .backwards) }
        guard let end, let head = try? JSONDecoder().decode(Head.self, from: Data(rest[..<end.lowerBound].utf8)),
            !head.ref.isEmpty
        else { return (nil, text) }
        return (head, rest[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The picks an answer carried, read back from its lines without its labels — so an answer written in another
    /// language freezes its block all the same. A question's line starts with `**<question>** `; its options are
    /// matched longest first, separated by ", ", and what is left over is an Other answer.
    static func picks(_ block: InteractiveBlock.Ask, body: String) -> [String: Picks] {
        let lines = body.components(separatedBy: "\n")
        var out: [String: Picks] = [:]
        for question in block.questions {
            let prefix = "**" + question.text + "** "
            var picked: Set<String> = []
            var other = false
            if let line = lines.first(where: { $0.hasPrefix(prefix) }) {
                let rest = line.dropFirst(prefix.count)
                if rest != blank {
                    let options = question.options.sorted { $0.utf16.count > $1.utf16.count }
                    var at = rest.startIndex
                    while at < rest.endIndex {
                        let tail = rest[at...]
                        guard
                            let option = options.first(where: { option in
                                tail.hasPrefix(option)
                                    && (tail.count == option.count || tail.dropFirst(option.count).hasPrefix(", "))
                            })
                        else {
                            other = question.other
                            break
                        }
                        picked.insert(option)
                        at = rest.index(at, offsetBy: option.count + 2, limitedBy: rest.endIndex) ?? rest.endIndex
                    }
                }
            }
            out[question.id] = Picks(options: question.options.filter(picked.contains), other: other)
        }
        return out
    }
}

// In an extension, so the memberwise `Head(block:decision:ref:title:)` stays.
extension InteractiveAnswer.Head {
    /// Read leniently, as the desktop does: a title or a decision of another shape is left out, not fatal.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        block = try container.decode(InteractiveBlock.Kind.self, forKey: .block)
        ref = try container.decode(String.self, forKey: .ref)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        decision = (try? container.decodeIfPresent(String.self, forKey: .decision)).flatMap(Decision.init(rawValue:))
    }
}
```

- [ ] **Step 5: Run the tests**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd -only-testing:ChatFeatureTests/InteractiveBlockTests -only-testing:ChatFeatureTests/InteractiveFenceTests -only-testing:ChatFeatureTests/InteractiveAnswerTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: a `Test run with N tests … passed` line with N > 0 and no `✘` line (every argument of the parameterized tests passes); `0 error(s)`. If a vector fails, fix the Swift side — the desktop's vectors are the contract.

- [ ] **Step 6: Commit**

```bash
git diff --stat                        # only the four new files besides the user's own paths
.superpowers/sdd/commit-mine.sh "feat(chat): the questionnaire and confirmation blocks' wire on the phone — limits, which fence of a reply is its block, the answer as plain text — held to the desktop's vectors" \
  Sources/ChatFeature/Interactive/InteractiveBlock.swift Sources/ChatFeature/Interactive/InteractiveAnswer.swift \
  Tests/ChatFeatureTests/InteractiveBlockTests.swift Tests/ChatFeatureTests/InteractiveAnswerTests.swift
git show --stat HEAD                   # exactly the four files
```

---
### Task 6: iOS — the strings, MarkdownKit's hook for fenced blocks, and `sendText` past the composer

**Files:**
- Modify: `Resources/App/Localizable.xcstrings` (dirty — `/tmp/blocks/add_keys.py` + patch)
- Create: `Sources/ChatFeature/Interactive/InteractiveText.swift`
- Create: `Sources/MarkdownKit/MarkdownFencedBlocks.swift`
- Modify: `Sources/MarkdownKit/MarkdownBlockView.swift` (clean)
- Modify: `Sources/ChatFeature/ChatDetailViewModel.swift` (dirty — `/tmp/blocks/dual_edit.py`)
- Test: `Tests/ChatFeatureTests/InteractiveTextTests.swift`
- Test: `Tests/MarkdownKitTests/MarkdownFencedBlocksTests.swift`
- Test: `Tests/ChatFeatureTests/ChatDetailViewModelAnswerTests.swift`

**Interfaces:**
- Consumes: `InteractiveAnswer.Labels` (Task 5); `ChatDetailViewModel`'s `hasLoadedHistory`, `isTurnInFlight`, `supportsAttempts`, `RunAttempts.autoChoose`, `startTurn(with:)`, `Self.newMessageId()`, `Self.nowMs`, `ChatMessage.userMessage(id:text:timestampMs:)`.
- Produces: 15 keys `ios:chat.block.{other, otherPlaceholder, noteDefault, notePlaceholder, submit, approve, reject, approved, rejected, answered, sent, answer.other, answer.addition, answer.note, answer.title}`; `enum InteractiveText` (`other`, `approved`, `rejected`, `sent`, `answerOther`, `answerAddition`, `answerNote`: `String`); `InteractiveAnswer.Labels.current`; MarkdownKit `public struct MarkdownFencedBlocks: Sendable { init(languages: Set<String>, draw: @escaping @MainActor @Sendable (String, String) -> AnyView?); @MainActor func view(language: String?, code: String) -> AnyView? }`, `EnvironmentValues.markdownFencedBlocks: MarkdownFencedBlocks?`; `ChatDetailViewModel.canAnswer: Bool`, `ChatDetailViewModel.sendText(_ text: String) async`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ChatFeatureTests/InteractiveTextTests.swift`:

```swift
import Testing

@testable import ChatFeature

@Suite("InteractiveText: the words an answer is written with")
struct InteractiveTextTests {
    @Test("the phone's labels, in English")
    func labels() {
        #expect(
            InteractiveAnswer.Labels.current
                == .init(other: "Other", addition: "Also", note: "Note", approved: "Approved", rejected: "Rejected"))
        #expect(InteractiveText.other == "Other…")
        #expect(InteractiveText.sent == "Sent")
    }
}
```

Create `Tests/MarkdownKitTests/MarkdownFencedBlocksTests.swift`:

```swift
import SwiftUI
import Testing

@testable import MarkdownKit

@MainActor
@Suite("MarkdownFencedBlocks: a host draws the fenced blocks it names")
struct MarkdownFencedBlocksTests {
    @Test("a reserved fence parses as a code block whose language is its whole name")
    func parses() {
        let blocks = MarkdownParser.parse("Before\n\n```exodus-ask\n{\"title\":\"T\"}\n```")
        guard case .codeBlock(let language, let code)? = blocks.last?.kind else {
            Issue.record("expected a code block")
            return
        }
        #expect(language == "exodus-ask")
        #expect(code == "{\"title\":\"T\"}")
    }

    @Test("only a named language reaches the host, and the host's nil draws the code")
    func asksOnlyForItsLanguages() {
        let fenced = MarkdownFencedBlocks(languages: ["exodus-ask"]) { _, code in
            code == "mine" ? AnyView(Text(verbatim: "drawn")) : nil
        }
        #expect(fenced.view(language: "exodus-ask", code: "mine") != nil)
        #expect(fenced.view(language: "exodus-ask", code: "another") == nil)
        #expect(fenced.view(language: "swift", code: "mine") == nil)
        #expect(fenced.view(language: nil, code: "mine") == nil)
    }
}
```

Create `Tests/ChatFeatureTests/ChatDetailViewModelAnswerTests.swift`:

```swift
import Foundation
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

private final class AnswerMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    /// A `POST /api/v1/chat` answered but never finished: a reply still on its way.
    nonisolated(unsafe) static var holdsChatPostOpen = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let isChatPost = request.httpMethod == "POST" && request.url?.path == "/api/v1/chat"
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
                headerFields: isChatPost ? ["Content-Type": "text/event-stream"] : nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            if !(isChatPost && Self.holdsChatPostOpen) { client?.urlProtocolDidFinishLoading(self) }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// The bodies of `POST /api/v1/chat`, recorded behind a lock (the handler runs on a URLProtocol thread).
private final class ChatPosts: Sendable {
    private let storage = Mutex<[Data]>([])
    func record(_ body: Data) { storage.withLock { $0.append(body) } }
    var bodies: [String] { storage.withLock { $0.map { String(decoding: $0, as: UTF8.self) } } }
}

private let reply = """
    data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"Done."}}\n\n\
    data: {"type":"done","messages":[{"id":"u2","role":"user","content":"ok"},{"id":"a2","role":"assistant","content":"Done."}]}\n\n
    """
private let answer = "```exodus-answer\n{\"block\":\"confirm\",\"decision\":\"approve\",\"ref\":\"u1\",\"title\":\"Go?\"}\n```\n\n**Go?** Approved"

extension URLRequest {
    fileprivate func bodyData() -> Data {
        guard let stream = httpBodyStream else { return httpBody ?? Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// The history (an empty chat, as a page or as rows — whichever the build asks for) and the reply.
private func serve(historyStatus: Int = 200, holdReplyOpen: Bool = false, posts: ChatPosts) {
    AnswerMockURLProtocol.holdsChatPostOpen = holdReplyOpen
    AnswerMockURLProtocol.handler = { request in
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        if method == "GET", path.hasSuffix("/page") {
            let page = #"{"messages":[],"sources":[],"questions":[],"hasOlder":false,"olderCursor":null}"#
            return (historyStatus, Data(page.utf8))
        }
        if method == "GET", path.hasPrefix("/api/v1/chat/") { return (historyStatus, Data("[]".utf8)) }
        if method == "POST", path == "/api/v1/chat" {
            posts.record(request.bodyData())
            return (200, Data(reply.utf8))
        }
        return (404, Data(#"{"type":"error","error":{"code":"NOT_FOUND","message":"Not found"}}"#.utf8))
    }
}

@MainActor
private func makeModel(_ suite: String = #function) -> ChatDetailViewModel {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let config = ServerConfigStore(userDefaults: defaults)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AnswerMockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return ChatDetailViewModel(
        chatId: "c1", apiClient: APIClient(session: session, serverConfig: config),
        streamManager: ChatStreamManager(sseClient: SSEClient(session: session)), serverConfig: config)
}

@MainActor
@Suite("ChatDetailViewModel.sendText: a block's answer is sent past the composer", .serialized)
struct ChatDetailViewModelAnswerTests {
    @Test("the answer is sent as the next message; the composer keeps what was being typed")
    func sendsPastTheComposer() async throws {
        let posts = ChatPosts()
        serve(posts: posts)
        let model = makeModel()
        await model.loadHistory()
        model.composerText = "half-typed"
        #expect(model.canAnswer)
        await model.sendText(answer)
        #expect(posts.bodies.count == 1)
        let body = try #require(posts.bodies.first)
        #expect(body.contains("exodus-answer"))
        #expect(body.contains("Approved"))
        #expect(model.composerText == "half-typed")
    }

    @Test("nothing is sent before the history is known, or while a reply is on its way")
    func waitsForHistoryAndForTheTurnInFlight() async throws {
        let posts = ChatPosts()
        serve(historyStatus: 500, posts: posts)
        let failed = makeModel("failed-history")
        await failed.loadHistory()
        #expect(!failed.canAnswer)
        await failed.sendText(answer)
        #expect(posts.bodies.isEmpty)

        serve(holdReplyOpen: true, posts: posts)
        let model = makeModel("in-flight")
        await model.loadHistory()
        let first = Task { await model.sendText(answer) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !model.isTurnInFlight {
            try #require(ContinuousClock.now < deadline, "timed out waiting for the turn")
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(!model.canAnswer)
        await model.sendText(answer)
        #expect(posts.bodies.count == 1)
        await model.stop()
        first.cancel()
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git diff --stat                        # note the user's paths
git diff --stat -- Sources/MarkdownKit/MarkdownBlockView.swift   # must print nothing
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd -only-testing:ChatFeatureTests/InteractiveTextTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'InteractiveText' in scope` (and `type 'InteractiveAnswer.Labels' has no member 'current'`), `TEST FAILED`.

- [ ] **Step 3: Write the key script**

Create `/tmp/blocks/add_keys.py` (`mkdir -p /tmp/blocks` first):

```python
# Inserts the interactive blocks' keys into the String Catalog named on the command line, each in its sorted place
# and in Xcode's own formatting, without rewriting any other line (so the user's uncommitted edits stay as they are).
# Usage, from the repo root: python3 /tmp/blocks/add_keys.py CATALOG
import json
import sys

LANGS = ["de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "zh-HK", "zh-Hant"]

# (key, comment, {language: text})
KEYS = [
    ("ios:chat.block.other", "Questionnaire in an answer: the choice that lets the user type an answer of their own.",
     {"en": "Other…", "de": "Andere …", "es": "Otra…", "fr": "Autre…", "it": "Altro…", "ja": "その他…", "ko": "기타…", "pt-BR": "Outra…", "zh-HK": "其他…", "zh-Hant": "其他…"}),
    ("ios:chat.block.otherPlaceholder", "Questionnaire in an answer: placeholder of the field under Other….",
     {"en": "Your answer", "de": "Deine Antwort", "es": "Tu respuesta", "fr": "Ta réponse", "it": "La tua risposta", "ja": "回答を入力", "ko": "답변 입력", "pt-BR": "Sua resposta", "zh-HK": "你嘅答案", "zh-Hant": "你的答案"}),
    ("ios:chat.block.noteDefault", "Questionnaire or confirmation in an answer: label of the closing free-text field when the model gave none.",
     {"en": "Anything else?", "de": "Noch etwas?", "es": "¿Algo más?", "fr": "Autre chose ?", "it": "Altro da aggiungere?", "ja": "ほかに伝えたいことは？", "ko": "더 하고 싶은 말이 있나요?", "pt-BR": "Mais alguma coisa?", "zh-HK": "仲有冇嘢想補充？", "zh-Hant": "還有什麼想補充的嗎？"}),
    ("ios:chat.block.notePlaceholder", "Placeholder of the closing free-text field of a questionnaire or confirmation: it may be left empty.",
     {"en": "Optional", "de": "Optional", "es": "Opcional", "fr": "Facultatif", "it": "Facoltativo", "ja": "任意", "ko": "선택 사항", "pt-BR": "Opcional", "zh-HK": "可選填", "zh-Hant": "選填"}),
    ("ios:chat.block.submit", "Questionnaire in an answer: the button that sends the answers, when the model named none.",
     {"en": "Submit", "de": "Senden", "es": "Enviar", "fr": "Envoyer", "it": "Invia", "ja": "送信", "ko": "보내기", "pt-BR": "Enviar", "zh-HK": "提交", "zh-Hant": "提交"}),
    ("ios:chat.block.approve", "Confirmation in an answer: the button that lets the assistant go ahead, when the model named none.",
     {"en": "Approve", "de": "Zustimmen", "es": "Aprobar", "fr": "Approuver", "it": "Approva", "ja": "承認", "ko": "승인", "pt-BR": "Aprovar", "zh-HK": "同意", "zh-Hant": "同意"}),
    ("ios:chat.block.reject", "Confirmation in an answer: the button that tells the assistant not to go ahead, when the model named none.",
     {"en": "Reject", "de": "Ablehnen", "es": "Rechazar", "fr": "Refuser", "it": "Rifiuta", "ja": "却下", "ko": "거절", "pt-BR": "Recusar", "zh-HK": "拒絕", "zh-Hant": "拒絕"}),
    ("ios:chat.block.approved", "A confirmation the user approved; also the word written in the answer sent to the assistant.",
     {"en": "Approved", "de": "Zugestimmt", "es": "Aprobado", "fr": "Approuvé", "it": "Approvato", "ja": "承認済み", "ko": "승인함", "pt-BR": "Aprovado", "zh-HK": "已同意", "zh-Hant": "已同意"}),
    ("ios:chat.block.rejected", "A confirmation the user rejected; also the word written in the answer sent to the assistant.",
     {"en": "Rejected", "de": "Abgelehnt", "es": "Rechazado", "fr": "Refusé", "it": "Rifiutato", "ja": "却下済み", "ko": "거절함", "pt-BR": "Recusado", "zh-HK": "已拒絕", "zh-Hant": "已拒絕"}),
    ("ios:chat.block.answered", "Under a questionnaire or confirmation the user has already answered.",
     {"en": "Answered", "de": "Beantwortet", "es": "Respondido", "fr": "Répondu", "it": "Risposto", "ja": "回答済み", "ko": "답변함", "pt-BR": "Respondido", "zh-HK": "已回答", "zh-Hant": "已回答"}),
    ("ios:chat.block.sent", "VoiceOver announcement after the user sent a questionnaire's or confirmation's answer.",
     {"en": "Sent", "de": "Gesendet", "es": "Enviado", "fr": "Envoyé", "it": "Inviato", "ja": "送信しました", "ko": "보냈어요", "pt-BR": "Enviado", "zh-HK": "已傳送", "zh-Hant": "已傳送"}),
    ("ios:chat.block.answer.other", "Written in the answer sent to the assistant, before what the user typed under Other…: e.g. Other: ankles.",
     {"en": "Other", "de": "Andere", "es": "Otra", "fr": "Autre", "it": "Altro", "ja": "その他", "ko": "기타", "pt-BR": "Outra", "zh-HK": "其他", "zh-Hant": "其他"}),
    ("ios:chat.block.answer.addition", "Written in the answer sent to the assistant, before what the user typed in a questionnaire's closing field.",
     {"en": "Also", "de": "Außerdem", "es": "Además", "fr": "En plus", "it": "Inoltre", "ja": "補足", "ko": "추가", "pt-BR": "Além disso", "zh-HK": "補充", "zh-Hant": "補充"}),
    ("ios:chat.block.answer.note", "Written in the answer sent to the assistant, before the note typed under a confirmation.",
     {"en": "Note", "de": "Notiz", "es": "Nota", "fr": "Note", "it": "Nota", "ja": "メモ", "ko": "메모", "pt-BR": "Observação", "zh-HK": "備註", "zh-Hant": "備註"}),
    ("ios:chat.block.answer.title", "Title of the card that shows the user's answer to a questionnaire or confirmation, when it names no block title.",
     {"en": "Your answer", "de": "Deine Antwort", "es": "Tu respuesta", "fr": "Ta réponse", "it": "La tua risposta", "ja": "あなたの回答", "ko": "내 답변", "pt-BR": "Sua resposta", "zh-HK": "你嘅答案", "zh-Hant": "你的回答"}),
]


def block(key, comment, values):
    entry = {
        "comment": comment,
        "extractionState": "manual",
        "localizations": {lang: {"stringUnit": {"state": "translated", "value": text}} for lang, text in values.items()},
    }
    body = json.dumps(entry, indent=2, separators=(",", " : "), ensure_ascii=False, sort_keys=True)
    return "    " + json.dumps(key, ensure_ascii=False) + " : " + body.replace("\n", "\n    ")


path = sys.argv[1]
text = open(path, encoding="utf-8").read()
for key, comment, values in KEYS:
    assert set(values) == set(LANGS), (key, sorted(set(LANGS) ^ set(values)))
    keys = list(json.loads(text)["strings"])
    assert key not in keys, key + " is already in " + path
    # Before the first key, in file order, that sorts after this one: the catalog is sorted.
    after = next(k for k in keys if k > key)
    marker = "\n    " + json.dumps(after, ensure_ascii=False) + " : {\n"
    assert text.count(marker) == 1, after
    text = text.replace(marker, "\n" + block(key, comment, values) + "," + marker, 1)
json.loads(text)  # still a catalog
open(path, "w", encoding="utf-8").write(text)
print("added", len(KEYS), "keys to", path)
```

- [ ] **Step 4: Apply it to the working catalog and to a copy of the committed one, and verify**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git show HEAD:Resources/App/Localizable.xcstrings > /tmp/blocks/head.xcstrings
cp /tmp/blocks/head.xcstrings /tmp/blocks/mine.xcstrings
python3 /tmp/blocks/add_keys.py /tmp/blocks/mine.xcstrings
python3 /tmp/blocks/add_keys.py Resources/App/Localizable.xcstrings
python3 - <<'PY'
import json
work = json.load(open('Resources/App/Localizable.xcstrings', encoding='utf-8'))['strings']
mine = json.load(open('/tmp/blocks/mine.xcstrings', encoding='utf-8'))['strings']
head = json.load(open('/tmp/blocks/head.xcstrings', encoding='utf-8'))['strings']
new = sorted(set(mine) - set(head))
assert len(new) == 15, len(new)
assert all(k.startswith('ios:chat.block.') for k in new), new
assert [k for k in head if head[k] != mine[k]] == []
for k in new:
    assert work.get(k) == mine[k], k
    assert set(mine[k]['localizations']) == {'en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pt-BR', 'zh-Hant', 'zh-HK'}, k
print('OK', len(new), 'new')
PY
```
Expected: `added 15 keys …` twice, then `OK 15 new`.

- [ ] **Step 5: Write `Sources/ChatFeature/Interactive/InteractiveText.swift`**

```swift
import Foundation

/// The interactive blocks' words in the user's language. An answer is written with the answering phone's words
/// (`InteractiveAnswer.Labels.current`); the model reads them as they are.
enum InteractiveText {
    static var other: String {
        String(
            localized: "ios:chat.block.other", defaultValue: "Other…",
            comment: "Questionnaire in an answer: the choice that lets the user type an answer of their own.")
    }
    static var approved: String {
        String(
            localized: "ios:chat.block.approved", defaultValue: "Approved",
            comment: "A confirmation the user approved; also the word written in the answer sent to the assistant.")
    }
    static var rejected: String {
        String(
            localized: "ios:chat.block.rejected", defaultValue: "Rejected",
            comment: "A confirmation the user rejected; also the word written in the answer sent to the assistant.")
    }
    static var sent: String {
        String(
            localized: "ios:chat.block.sent", defaultValue: "Sent",
            comment: "VoiceOver announcement after the user sent a questionnaire's or confirmation's answer.")
    }
    static var answerOther: String {
        String(
            localized: "ios:chat.block.answer.other", defaultValue: "Other",
            comment:
                "Written in the answer sent to the assistant, before what the user typed under Other…: e.g. Other: ankles.")
    }
    static var answerAddition: String {
        String(
            localized: "ios:chat.block.answer.addition", defaultValue: "Also",
            comment:
                "Written in the answer sent to the assistant, before what the user typed in a questionnaire's closing field.")
    }
    static var answerNote: String {
        String(
            localized: "ios:chat.block.answer.note", defaultValue: "Note",
            comment: "Written in the answer sent to the assistant, before the note typed under a confirmation.")
    }
}

extension InteractiveAnswer.Labels {
    /// The words this phone writes an answer with.
    static var current: Self {
        Self(
            other: InteractiveText.answerOther, addition: InteractiveText.answerAddition,
            note: InteractiveText.answerNote, approved: InteractiveText.approved, rejected: InteractiveText.rejected)
    }
}
```

- [ ] **Step 6: Write `Sources/MarkdownKit/MarkdownFencedBlocks.swift` and route code blocks through it**

```swift
import SwiftUI

/// Fenced blocks a host draws itself — a chat answer's questionnaire, say — instead of as code. MarkdownKit knows
/// nothing of them: a code block whose language the host names is offered to `draw`, and `nil` draws it as code.
public struct MarkdownFencedBlocks: Sendable {
    public let languages: Set<String>
    private let draw: @MainActor @Sendable (_ language: String, _ code: String) -> AnyView?

    public init(languages: Set<String>, draw: @escaping @MainActor @Sendable (String, String) -> AnyView?) {
        self.languages = languages
        self.draw = draw
    }

    @MainActor
    public func view(language: String?, code: String) -> AnyView? {
        guard let language, languages.contains(language) else { return nil }
        return draw(language, code)
    }
}

extension EnvironmentValues {
    /// Set by a host around the Markdown whose fenced blocks it draws; read only by code blocks.
    @Entry public var markdownFencedBlocks: MarkdownFencedBlocks?
}

/// A code block, or what the host draws for it. Its own view, so only code blocks read the host's hook.
struct MarkdownFencedCode: View {
    let language: String?
    let code: String
    @Environment(\.markdownFencedBlocks) private var fenced

    var body: some View {
        if let drawn = fenced?.view(language: language, code: code) {
            drawn
        } else {
            MarkdownCodeBlockView(language: language, code: code)
        }
    }
}
```

In `Sources/MarkdownKit/MarkdownBlockView.swift`, replace

```swift
        case .codeBlock(let language, let code):
            MarkdownCodeBlockView(language: language, code: code)
```

with

```swift
        case .codeBlock(let language, let code):
            MarkdownFencedCode(language: language, code: code)
```

- [ ] **Step 7: Add `canAnswer` and `sendText` (`Sources/ChatFeature/ChatDetailViewModel.swift`, dirty)**

Create `/tmp/blocks/vm_edits.py` (from the repo root `/tmp/blocks/dual_edit.py` is the one in Shared tooling):

```python
PATH = "Sources/ChatFeature/ChatDetailViewModel.swift"
EDITS = [
    (
        "    public func sendInitial(_ text: String) async {\n"
        "        guard !sentInitial else { return }\n"
        "        sentInitial = true\n"
        "        composerText = text\n"
        "        await sendMessage()\n"
        "    }\n",
        "    public func sendInitial(_ text: String) async {\n"
        "        guard !sentInitial else { return }\n"
        "        sentInitial = true\n"
        "        composerText = text\n"
        "        await sendMessage()\n"
        "    }\n"
        "\n"
        "    /// Whether a block in the transcript may be answered now: as the composer, once the history is known and\n"
        "    /// while nothing is in flight.\n"
        "    public var canAnswer: Bool { hasLoadedHistory && !isTurnInFlight }\n"
        "\n"
        "    /// A questionnaire's or a confirmation's answer (`InteractiveAnswer`), sent as a typed message is but past the\n"
        "    /// composer: what is being typed there, its quote and its pictures stay for the next message.\n"
        "    public func sendText(_ text: String) async {\n"
        "        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)\n"
        "        guard canAnswer, !text.isEmpty else { return }\n"
        "        if supportsAttempts { messages = RunAttempts.autoChoose(messages) }\n"
        "        await startTurn(with: .userMessage(id: Self.newMessageId(), text: text, timestampMs: Self.nowMs))\n"
        "    }\n",
    ),
]
```

```bash
python3 /tmp/blocks/dual_edit.py check /tmp/blocks/vm_edits.py    # OK … 1 edit(s)
python3 /tmp/blocks/dual_edit.py apply /tmp/blocks/vm_edits.py
```

- [ ] **Step 8: Run the tests and the audit**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd -only-testing:ChatFeatureTests/InteractiveTextTests -only-testing:ChatFeatureTests/ChatDetailViewModelAnswerTests -only-testing:ChatFeatureTests/ChatDetailViewModelTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme MarkdownKit -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: both `Test run with N tests … passed`, no `✘`; `0 error(s)` (warnings that `ios:chat.block.otherPlaceholder`, `noteDefault`, `notePlaceholder`, `submit`, `approve`, `reject`, `answered`, `answer.title` are not referenced yet are expected until Tasks 7–8).

- [ ] **Step 9: Build the patches and commit**

```bash
python3 - <<'PY'
import difflib
head = open('/tmp/blocks/head.xcstrings', encoding='utf-8').read().splitlines(keepends=True)
mine = open('/tmp/blocks/mine.xcstrings', encoding='utf-8').read().splitlines(keepends=True)
with open('/tmp/blocks/catalog.patch', 'w', encoding='utf-8') as f:
    f.writelines(difflib.unified_diff(head, mine, 'a/Resources/App/Localizable.xcstrings', 'b/Resources/App/Localizable.xcstrings'))
PY
GIT_INDEX_FILE=/tmp/blocks/check.idx git read-tree HEAD
GIT_INDEX_FILE=/tmp/blocks/check.idx git apply --cached --check /tmp/blocks/catalog.patch && echo PATCH-OK
rm -f /tmp/blocks/check.idx
python3 /tmp/blocks/dual_edit.py patch /tmp/blocks/vm_edits.py /tmp/blocks/vm.patch    # PATCH-OK
.superpowers/sdd/commit-mine.sh "feat(chat): the interactive blocks' words in ten languages, MarkdownKit lets a host draw a fenced block itself, and a block's answer is sent past the composer" \
  --patch /tmp/blocks/catalog.patch --patch /tmp/blocks/vm.patch \
  Sources/ChatFeature/Interactive/InteractiveText.swift Sources/MarkdownKit/MarkdownFencedBlocks.swift \
  Sources/MarkdownKit/MarkdownBlockView.swift Tests/ChatFeatureTests/InteractiveTextTests.swift \
  Tests/MarkdownKitTests/MarkdownFencedBlocksTests.swift Tests/ChatFeatureTests/ChatDetailViewModelAnswerTests.swift
git show --stat HEAD           # these six files, the catalog and ChatDetailViewModel.swift
git diff --stat -- Resources/App/Localizable.xcstrings Sources/ChatFeature/ChatDetailViewModel.swift   # the user's own edits only
```

---
### Task 7: iOS — the questionnaire and the confirmation drawn in an answer, sent through the view model, frozen by the answer

**Files:**
- Create: `Sources/ChatFeature/Interactive/InteractiveBlockView.swift`
- Create: `Sources/ChatFeature/Interactive/QuestionnaireBlockView.swift`
- Create: `Sources/ChatFeature/Interactive/ConfirmationBlockView.swift`
- Modify: `Sources/ChatFeature/AssistantTurnView.swift` (clean) — `TranscriptActions`, `TranscriptRows`, `AssistantTurnView`
- Modify: `Sources/ChatFeature/ChatDetailView.swift` (dirty — `/tmp/blocks/dual_edit.py`)
- Test: `Tests/ChatFeatureTests/InteractiveRenderingTests.swift`

**Interfaces:**
- Consumes: Task 5 (`InteractiveBlock`, `InteractiveFence.first(in:)`, `matches`, `InteractiveAnswer.composeAsk/composeConfirm/split/picks`, `Response`, `Picks`, `Head`); Task 6 (`InteractiveText`, `Labels.current`, `MarkdownFencedBlocks`, `\.markdownFencedBlocks`, `ChatDetailViewModel.canAnswer`, `sendText(_:)`); `CardStyle`, `CardSurface`, `MarkdownView`, `ChatMessage.answerText`, `Segment`.
- Produces: `struct InteractiveAnswered: Equatable, Sendable { head: InteractiveAnswer.Head; body: String }`; `enum InteractiveRendering { static func answers(in: [Segment]) -> [String: InteractiveAnswered]; static func fencedBlocks(fence:runId:answered:canAnswer:sendAnswer:) -> MarkdownFencedBlocks? }`; `InteractiveBlockView`, `QuestionnaireBlockView`, `ConfirmationBlockView`, `InteractiveOptionRow`, `InteractiveNoteField`, `InteractiveAnsweredLine`; `TranscriptActions.canAnswer: Bool` and `.sendAnswer: @MainActor @Sendable (String) -> Void`; `AssistantTurnView.answered: InteractiveAnswered?`, `.canAnswer: Bool`, `.sendAnswer`, `nonisolated var asks: Bool`.

- [ ] **Step 1: Write the failing test**

Create `Tests/ChatFeatureTests/InteractiveRenderingTests.swift`:

```swift
import Foundation
import Models
import Testing

@testable import ChatFeature

private let confirmSource = #"{"title":"Send the report?","details":"To **Ann**."}"#
private let reply = "Here is the plan.\n\n```exodus-confirm\n\(confirmSource)\n```"
private let answer =
    #"```exodus-answer\#n{"block":"confirm","decision":"approve","ref":"u1","title":"Send the report?"}\#n```\#n\#n"#
    + "**Send the report?** Approved"

@MainActor
@Suite("Interactive blocks in an answer")
struct InteractiveRenderingTests {
    @Test("answers are read off the transcript's user messages, by the run each names")
    func answers() {
        let segments: [Segment] = [
            .user(.userMessage(id: "u1", text: "Send it", timestampMs: 1)),
            .assistantTurn(AssistantTurn(runId: "u1", body: reply)),
            .user(.userMessage(id: "u2", text: answer, timestampMs: 2)),
        ]
        let answers = InteractiveRendering.answers(in: segments)
        #expect(Array(answers.keys) == ["u1"])
        #expect(answers["u1"]?.head.decision == .approve)
        #expect(answers["u1"]?.body == "**Send the report?** Approved")
    }

    @Test("a turn's Markdown is offered its own block only")
    func fencedBlocks() throws {
        #expect(
            InteractiveRendering.fencedBlocks(
                fence: nil, runId: "u1", answered: nil, canAnswer: true, sendAnswer: { _ in }) == nil)
        let fence = try #require(InteractiveFence.first(in: reply))
        let blocks = try #require(
            InteractiveRendering.fencedBlocks(
                fence: fence, runId: "u1", answered: nil, canAnswer: true, sendAnswer: { _ in }))
        #expect(blocks.languages == ["exodus-confirm"])
        #expect(blocks.view(language: "exodus-confirm", code: confirmSource) != nil)
        #expect(blocks.view(language: "exodus-confirm", code: #"{"title":"Another"}"#) == nil)
        #expect(blocks.view(language: "exodus-ask", code: confirmSource) == nil)
    }

    @Test("a settled turn redraws when its block is answered, and on a turn starting only when it asks")
    func equality() {
        let asking = AssistantTurn(runId: "u1", body: reply)
        let plain = AssistantTurn(runId: "u9", body: "Just text.")
        func view(_ turn: AssistantTurn, answered: InteractiveAnswered? = nil, canAnswer: Bool) -> AssistantTurnView {
            AssistantTurnView(turn: turn, isStreaming: false, error: nil, answered: answered, canAnswer: canAnswer)
        }
        let head = InteractiveAnswer.Head(block: .confirm, decision: .approve, ref: "u1", title: "Send the report?")
        let answered = InteractiveAnswered(head: head, body: "**Send the report?** Approved")
        #expect(view(plain, canAnswer: true) == view(plain, canAnswer: false))
        #expect(view(asking, canAnswer: true) != view(asking, canAnswer: false))
        #expect(view(asking, canAnswer: true) != view(asking, answered: answered, canAnswer: true))
        #expect(
            view(asking, answered: answered, canAnswer: true) == view(asking, answered: answered, canAnswer: false))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git diff --stat -- Sources/ChatFeature/AssistantTurnView.swift   # must print nothing
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd -only-testing:ChatFeatureTests/InteractiveRenderingTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'InteractiveRendering' in scope`, `TEST FAILED`.

- [ ] **Step 3: Write `Sources/ChatFeature/Interactive/InteractiveBlockView.swift`**

```swift
import MarkdownKit
import Models
import SwiftUI

/// A block's answer as the transcript holds it: the fence's head and the lines after it.
struct InteractiveAnswered: Equatable, Sendable {
    let head: InteractiveAnswer.Head
    let body: String
}

enum InteractiveRendering {
    /// Every block answered so far, by the run whose reply holds it — read off the transcript's user messages, so a
    /// chat opened again finds its blocks frozen with nothing stored.
    static func answers(in segments: [Segment]) -> [String: InteractiveAnswered] {
        var answers: [String: InteractiveAnswered] = [:]
        for segment in segments {
            guard case .user(let message) = segment else { continue }
            let split = InteractiveAnswer.split(message.answerText)
            if let head = split.head { answers[head.ref] = InteractiveAnswered(head: head, body: split.body) }
        }
        return answers
    }

    /// What a turn's Markdown draws for its fenced blocks: its own block (`fence`) as the control, every other fence
    /// as code. Nil when the turn holds no block.
    static func fencedBlocks(
        fence: InteractiveFence?, runId: String, answered: InteractiveAnswered?, canAnswer: Bool,
        sendAnswer: @escaping @MainActor @Sendable (String) -> Void
    ) -> MarkdownFencedBlocks? {
        guard let fence else { return nil }
        return MarkdownFencedBlocks(languages: [fence.kind.language]) { language, code in
            guard fence.matches(language: language, code: code) else { return nil }
            return AnyView(
                InteractiveBlockView(
                    fence: fence, runId: runId, answered: answered, canAnswer: canAnswer, sendAnswer: sendAnswer))
        }
    }
}

/// A reply's block, drawn by its kind.
struct InteractiveBlockView: View {
    let fence: InteractiveFence
    let runId: String
    let answered: InteractiveAnswered?
    let canAnswer: Bool
    let sendAnswer: @MainActor @Sendable (String) -> Void

    var body: some View {
        switch fence.block {
        case .ask(let block):
            QuestionnaireBlockView(
                block: block, runId: runId, answered: answered, canAnswer: canAnswer, sendAnswer: sendAnswer)
        case .confirm(let block):
            ConfirmationBlockView(
                block: block, runId: runId, answered: answered, canAnswer: canAnswer, sendAnswer: sendAnswer)
        }
    }
}

/// One choice of a question: a 44 pt row in the tone's accent — a radio for one answer, a checkbox for several.
struct InteractiveOptionRow: View {
    let title: String
    let isMulti: Bool
    let isOn: Bool
    let isEnabled: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol)
                    .imageScale(.large)
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(isOn ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.fill.quaternary), in: CardStyle.innerShape)
            .contentShape(CardStyle.innerShape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
    }

    private var symbol: String {
        switch (isMulti, isOn) {
        case (true, true): "checkmark.square.fill"
        case (true, false): "square"
        case (false, true): "largecircle.fill.circle"
        case (false, false): "circle"
        }
    }
}

/// The closing free-text field of a block: the model's label, or "Anything else?".
struct InteractiveNoteField: View {
    let label: String?
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            TextField(text: $text, prompt: Text("ios:chat.block.notePlaceholder"), axis: .vertical) { title }
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(.fill.tertiary, in: CardStyle.innerShape)
        }
    }

    @ViewBuilder
    private var title: some View {
        if let label, !label.isEmpty {
            Text(verbatim: label)
        } else {
            Text("ios:chat.block.noteDefault")
        }
    }
}

/// "Answered", under a frozen block.
struct InteractiveAnsweredLine: View {
    var body: some View {
        Label {
            Text("ios:chat.block.answered")
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 4: Write `Sources/ChatFeature/Interactive/QuestionnaireBlockView.swift`**

```swift
import SwiftUI

/// A reply's questionnaire (`exodus-ask`) as a card in the answer: its title, the questions numbered, each choice a
/// 44 pt row, "Other…" opening a line to type on, the closing note and Submit. Submit sends the answers as the user's
/// next message (`InteractiveAnswer`); once the transcript holds that message the card is frozen with its picks.
struct QuestionnaireBlockView: View {
    typealias Question = InteractiveBlock.Ask.Question

    let block: InteractiveBlock.Ask
    let runId: String
    let answered: InteractiveAnswered?
    let canAnswer: Bool
    let sendAnswer: @MainActor @Sendable (String) -> Void

    @State private var responses: [String: InteractiveAnswer.Response] = [:]
    @State private var note = ""
    @State private var selections = 0
    @State private var sent = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let frozen = answered.map { InteractiveAnswer.picks(block, body: $0.body) }
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: block.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(block.questions.enumerated()), id: \.element.id) { index, question in
                questionView(question, number: index + 1, frozen: frozen?[question.id])
            }
            if answered != nil {
                InteractiveAnsweredLine()
            } else {
                InteractiveNoteField(label: block.note, text: $note)
                Button(action: submit) {
                    submitLabel
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAnswer)
            }
        }
        .padding(CardStyle.inset)
        .modifier(CardSurface())
        .animation(reduceMotion ? nil : .smooth, value: answered != nil)
        .sensoryFeedback(.selection, trigger: selections)
        .sensoryFeedback(.success, trigger: sent)
    }

    private func questionView(_ question: Question, number: Int, frozen: InteractiveAnswer.Picks?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "\(number). \(question.text)")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(question.options, id: \.self) { option in
                InteractiveOptionRow(
                    title: option, isMulti: question.type == .multi,
                    isOn: frozen.map { $0.options.contains(option) } ?? isPicked(question, option),
                    isEnabled: answered == nil
                ) { pick(question, option) }
            }
            if question.other {
                InteractiveOptionRow(
                    title: InteractiveText.other, isMulti: question.type == .multi,
                    isOn: frozen?.other ?? (responses[question.id]?.other != nil), isEnabled: answered == nil
                ) { pickOther(question) }
                if answered == nil, responses[question.id]?.other != nil {
                    TextField(text: otherText(question), prompt: Text("ios:chat.block.otherPlaceholder")) {
                        Text("ios:chat.block.otherPlaceholder")
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.fill.tertiary, in: CardStyle.innerShape)
                }
            }
        }
    }

    @ViewBuilder
    private var submitLabel: some View {
        if let label = block.submit, !label.isEmpty {
            Text(verbatim: label)
        } else {
            Text("ios:chat.block.submit")
        }
    }

    private func isPicked(_ question: Question, _ option: String) -> Bool {
        responses[question.id]?.options.contains(option) ?? false
    }

    private func pick(_ question: Question, _ option: String) {
        var response = responses[question.id] ?? .init()
        if question.type == .single {
            response = .init(options: [option], other: nil)
        } else if let index = response.options.firstIndex(of: option) {
            response.options.remove(at: index)
        } else {
            response.options.append(option)
        }
        responses[question.id] = response
        selections += 1
    }

    private func pickOther(_ question: Question) {
        var response = responses[question.id] ?? .init()
        if question.type == .single {
            response = .init(options: [], other: response.other ?? "")
        } else {
            response.other = response.other == nil ? "" : nil
        }
        responses[question.id] = response
        selections += 1
    }

    private func otherText(_ question: Question) -> Binding<String> {
        Binding(
            get: { responses[question.id]?.other ?? "" },
            set: { responses[question.id, default: .init(options: [], other: "")].other = $0 })
    }

    private func submit() {
        guard canAnswer, answered == nil else { return }
        sendAnswer(InteractiveAnswer.composeAsk(block, ref: runId, responses: responses, note: note, labels: .current))
        sent += 1
        AccessibilityNotification.Announcement(InteractiveText.sent).post()
    }
}
```

- [ ] **Step 5: Write `Sources/ChatFeature/Interactive/ConfirmationBlockView.swift`**

```swift
import MarkdownKit
import SwiftUI

/// A reply's confirmation (`exodus-confirm`): what will happen (Markdown), a note, Reject (bordered) and Approve
/// (prominent, the tone's accent) — side by side, one over the other at accessibility sizes. Once the transcript holds
/// the answer it shows the decision instead.
struct ConfirmationBlockView: View {
    let block: InteractiveBlock.Confirm
    let runId: String
    let answered: InteractiveAnswered?
    let canAnswer: Bool
    let sendAnswer: @MainActor @Sendable (String) -> Void

    @State private var note = ""
    @State private var sent = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: block.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let details = block.details, !details.isEmpty {
                MarkdownView(text: details, isStreaming: false)
            }
            if let answered {
                decision(answered.head.decision)
            } else {
                InteractiveNoteField(label: block.note, text: $note)
                buttons
            }
        }
        .padding(CardStyle.inset)
        .modifier(CardSurface())
        .animation(reduceMotion ? nil : .smooth, value: answered != nil)
        .sensoryFeedback(.success, trigger: sent)
    }

    private var buttons: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button { send(approved: false) } label: {
                rejectLabel.frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Button { send(approved: true) } label: {
                approveLabel.font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .disabled(!canAnswer)
    }

    @ViewBuilder
    private var approveLabel: some View {
        if let label = block.approve, !label.isEmpty {
            Text(verbatim: label)
        } else {
            Text("ios:chat.block.approve")
        }
    }

    @ViewBuilder
    private var rejectLabel: some View {
        if let label = block.reject, !label.isEmpty {
            Text(verbatim: label)
        } else {
            Text("ios:chat.block.reject")
        }
    }

    @ViewBuilder
    private func decision(_ decision: InteractiveAnswer.Head.Decision?) -> some View {
        switch decision {
        case .approve?:
            Label {
                Text("ios:chat.block.approved")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
        case .reject?:
            Label {
                Text("ios:chat.block.rejected")
            } icon: {
                Image(systemName: "xmark.circle.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        case nil:
            InteractiveAnsweredLine()
        }
    }

    private func send(approved: Bool) {
        guard canAnswer, answered == nil else { return }
        sendAnswer(
            InteractiveAnswer.composeConfirm(block, ref: runId, approved: approved, note: note, labels: .current))
        sent += 1
        AccessibilityNotification.Announcement(InteractiveText.sent).post()
    }
}
```

- [ ] **Step 6: Wire it into the transcript (`Sources/ChatFeature/AssistantTurnView.swift`)**

In `TranscriptActions`, after

```swift
    /// Opens a folded answer (its run id) read-only.
    var showOtherVersion: (_ runId: String) -> Void = { _ in }
```

add

```swift
    /// Whether a reply's questionnaire or confirmation may be answered now (not while a turn is in flight).
    var canAnswer = false
    /// Sends a block's answer as the user's next message.
    var sendAnswer: @MainActor @Sendable (_ text: String) -> Void = { _ in }
```

In `TranscriptRows.body`, replace

```swift
        let liveErrorTurnId = TranscriptRules.liveErrorTurnId(segments: segments, live: liveError)
```

with

```swift
        let liveErrorTurnId = TranscriptRules.liveErrorTurnId(segments: segments, live: liveError)
        let answers = InteractiveRendering.answers(in: segments)
```

and replace

```swift
                        regenerate: actions.regenerate, showSources: actions.showSources, choose: actions.choose,
                        showOtherVersion: actions.showOtherVersion
                    )
                    .equatable()
```

with

```swift
                        regenerate: actions.regenerate, showSources: actions.showSources, choose: actions.choose,
                        showOtherVersion: actions.showOtherVersion, answered: answers[turn.runId],
                        canAnswer: actions.canAnswer, sendAnswer: actions.sendAnswer
                    )
                    .equatable()
```

In `AssistantTurnView`, replace

```swift
    var showOtherVersion: (_ runId: String) -> Void = { _ in }
    @Environment(\.searchMediaLoader) private var searchMediaLoader
```

with

```swift
    var showOtherVersion: (_ runId: String) -> Void = { _ in }
    /// The answer to this turn's questionnaire or confirmation, once the transcript holds one.
    nonisolated var answered: InteractiveAnswered?
    /// Whether the turn's block may be answered now.
    nonisolated var canAnswer = false
    var sendAnswer: @MainActor @Sendable (_ text: String) -> Void = { _ in }
    @Environment(\.searchMediaLoader) private var searchMediaLoader
```

replace

```swift
            && lhs.choiceEnabled == rhs.choiceEnabled
    }
```

with

```swift
            && lhs.choiceEnabled == rhs.choiceEnabled && lhs.answered == rhs.answered
            && (lhs.canAnswer == rhs.canAnswer || !lhs.asks)
    }

    /// The turn holds a block still waiting for its answer, so whether one may be sent changes how it looks. Read only
    /// when `canAnswer` changed (a turn starting or ending), never per streamed frame.
    nonisolated var asks: Bool { answered == nil && turn.body.contains("```exodus-") }
```

and in the `answer` view builder of `extension AssistantTurnView`, replace

```swift
        let streaming = TranscriptRules.streamingBlockId(blocks, isStreaming: isStreaming)
```

with

```swift
        let streaming = TranscriptRules.streamingBlockId(blocks, isStreaming: isStreaming)
        // The turn's questionnaire or confirmation: the first one of its whole answer, so one in a later paragraph
        // stays code.
        let fenced = InteractiveRendering.fencedBlocks(
            fence: InteractiveFence.first(in: turn.body), runId: turn.runId, answered: answered,
            canAnswer: canAnswer && !isStreaming, sendAnswer: sendAnswer)
```

and

```swift
        .environment(\.editDiffsStartOpen, FileCardRules.editsStartOpen(editCount: FileCardRules.editCount(in: turn)))
        .environment(\.toolCardsAreLive, isStreaming)
```

with

```swift
        .environment(\.editDiffsStartOpen, FileCardRules.editsStartOpen(editCount: FileCardRules.editCount(in: turn)))
        .environment(\.toolCardsAreLive, isStreaming)
        .environment(\.markdownFencedBlocks, fenced)
```

- [ ] **Step 7: Hand the chat's answer path to the transcript (`Sources/ChatFeature/ChatDetailView.swift`, dirty)**

Create `/tmp/blocks/view_edits.py`:

```python
PATH = "Sources/ChatFeature/ChatDetailView.swift"
EDITS = [
    (
        "            showOtherVersion: { [viewModel] runId in otherVersion = viewModel.otherVersion(runId: runId) })\n",
        "            showOtherVersion: { [viewModel] runId in otherVersion = viewModel.otherVersion(runId: runId) },\n"
        "            canAnswer: viewModel.canAnswer,\n"
        "            sendAnswer: { [viewModel] text in Task { await viewModel.sendText(text) } })\n",
    ),
]
```

```bash
python3 /tmp/blocks/dual_edit.py check /tmp/blocks/view_edits.py    # OK … 1 edit(s)
python3 /tmp/blocks/dual_edit.py apply /tmp/blocks/view_edits.py
```

- [ ] **Step 8: Run the tests, build the app, audit**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: every ChatFeature test passes (`InteractiveRenderingTests` included); `** BUILD SUCCEEDED **`; `0 error(s)` (only `ios:chat.block.answer.title` may still warn as unreferenced, until Task 8). The views are seen in Task 9's gallery.

- [ ] **Step 9: Commit**

```bash
python3 /tmp/blocks/dual_edit.py patch /tmp/blocks/view_edits.py /tmp/blocks/view.patch    # PATCH-OK
.superpowers/sdd/commit-mine.sh "feat(chat): a reply's questionnaire and confirmation are drawn as cards on the phone — 44 pt choices in the tone, room to type, Submit or Approve/Reject — sent past the composer and frozen once the transcript holds the answer" \
  --patch /tmp/blocks/view.patch \
  Sources/ChatFeature/Interactive/InteractiveBlockView.swift Sources/ChatFeature/Interactive/QuestionnaireBlockView.swift \
  Sources/ChatFeature/Interactive/ConfirmationBlockView.swift Sources/ChatFeature/AssistantTurnView.swift \
  Tests/ChatFeatureTests/InteractiveRenderingTests.swift
git show --stat HEAD           # these five files and ChatDetailView.swift
git diff --stat -- Sources/ChatFeature/ChatDetailView.swift   # the user's own edits only
```

---
### Task 8: iOS — the user's answer drawn as a card

**Files:**
- Create: `Sources/ChatFeature/Interactive/InteractiveAnswerCard.swift`
- Modify: `Sources/ChatFeature/AssistantTurnView.swift` (`UserBubble.bubble`)
- Test: `Tests/ChatFeatureTests/InteractiveAnswerCardTests.swift`

**Interfaces:**
- Consumes: `InteractiveAnswer.split`, `InteractiveAnswer.Head` (Task 5); key `ios:chat.block.answer.title` (Task 6).
- Produces: `InteractiveAnswerCard(head: InteractiveAnswer.Head, text: String)`, `InteractiveAnswerCard.Line(label: String?, value: String)`, `static func lines(_ text: String) -> [Line]`, `static func symbol(for head: InteractiveAnswer.Head) -> String`.

- [ ] **Step 1: Write the failing test**

Create `Tests/ChatFeatureTests/InteractiveAnswerCardTests.swift`:

```swift
import Testing

@testable import ChatFeature

@Suite("InteractiveAnswerCard: an answer drawn as what it is")
struct InteractiveAnswerCardTests {
    @Test("each line's bold lead and what follows it; a line without one, and blank lines")
    func lines() {
        let lines = InteractiveAnswerCard.lines("**Where?** Legs, Arms\n\n**Also:** unscented lotion\nplain words\n")
        #expect(
            lines == [
                .init(label: "Where?", value: "Legs, Arms"), .init(label: "Also:", value: "unscented lotion"),
                .init(label: nil, value: "plain words"),
            ])
    }

    @Test("the card's symbol says what was answered and how")
    func symbol() {
        #expect(InteractiveAnswerCard.symbol(for: .init(block: .ask, ref: "r", title: "T")) == "checklist")
        #expect(
            InteractiveAnswerCard.symbol(for: .init(block: .confirm, decision: .approve, ref: "r", title: "T"))
                == "checkmark.circle")
        #expect(
            InteractiveAnswerCard.symbol(for: .init(block: .confirm, decision: .reject, ref: "r", title: "T"))
                == "xmark.circle")
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git diff --stat -- Sources/ChatFeature/AssistantTurnView.swift   # must print nothing (Task 7 committed it)
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd -only-testing:ChatFeatureTests/InteractiveAnswerCardTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'InteractiveAnswerCard' in scope`, `TEST FAILED`.

- [ ] **Step 3: Write `Sources/ChatFeature/Interactive/InteractiveAnswerCard.swift`**

```swift
import SwiftUI

/// A user message that answers a questionnaire or a confirmation (`InteractiveAnswer`), drawn as what it is: the
/// block's title, then the answers, quieter — not the fence and the bold Markdown it travels as.
struct InteractiveAnswerCard: View {
    struct Line: Equatable {
        let label: String?
        let value: String
    }

    let head: InteractiveAnswer.Head
    let text: String

    /// An answer's lines as the card draws them: the bold lead (a question, "Also:") and what follows it.
    static func lines(_ text: String) -> [Line] {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                let afterLead = line.index(line.startIndex, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
                guard line.hasPrefix("**"), let close = line.range(of: "** ", range: afterLead..<line.endIndex) else {
                    return Line(label: nil, value: line)
                }
                return Line(label: String(line[afterLead..<close.lowerBound]), value: String(line[close.upperBound...]))
            }
    }

    static func symbol(for head: InteractiveAnswer.Head) -> String {
        switch (head.block, head.decision) {
        case (.ask, _): "checklist"
        case (.confirm, .reject?): "xmark.circle"
        case (.confirm, _): "checkmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                title
            } icon: {
                Image(systemName: Self.symbol(for: head)).foregroundStyle(.tint)
            }
            .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(Self.lines(text).enumerated()), id: \.offset) { _, line in
                    lineText(line).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var title: some View {
        if let title = head.title, !title.isEmpty {
            Text(verbatim: title)
        } else {
            Text("ios:chat.block.answer.title")
        }
    }

    private func lineText(_ line: Line) -> Text {
        guard let label = line.label else { return Text(verbatim: line.value) }
        var lead = AttributedString(label)
        lead.inlinePresentationIntent = .stronglyEmphasized
        return Text(lead + AttributedString(" " + line.value))
    }
}
```

- [ ] **Step 4: Draw it in `UserBubble` (`Sources/ChatFeature/AssistantTurnView.swift`)**

In `UserBubble.bubble`, replace

```swift
            let health = HealthContext.split(text)
            let parts = QuotedText.split(health.body)
            VStack(alignment: .leading, spacing: 6) {
                if let json = health.json {
                    HealthContextCard(json: json)
                }
                if let quote = parts.quote {
```

with

```swift
            // One that answers a questionnaire or a confirmation opens with its answer fence (`InteractiveAnswer`):
            // drawn as a card instead, the block's title over the answers.
            let answer = InteractiveAnswer.split(text)
            let health = HealthContext.split(text)
            let parts = QuotedText.split(health.body)
            VStack(alignment: .leading, spacing: 6) {
                if let head = answer.head {
                    InteractiveAnswerCard(head: head, text: answer.body)
                } else if let json = health.json {
                    HealthContextCard(json: json)
                }
                if answer.head == nil, let quote = parts.quote {
```

and

```swift
                if !parts.body.isEmpty {
                    message(parts.body)
                }
```

with

```swift
                if answer.head == nil, !parts.body.isEmpty {
                    message(parts.body)
                }
```

- [ ] **Step 5: Run the tests, build, audit**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd -only-testing:ChatFeatureTests/InteractiveAnswerCardTests -only-testing:ChatFeatureTests/UserBubbleRulesTests -only-testing:ChatFeatureTests/HealthContextCardTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
python3 scripts/l10n.py audit 2>&1 | grep "ios:chat.block" || echo "every ios:chat.block key is referenced"
```
Expected: tests pass; `** BUILD SUCCEEDED **`; `0 error(s)`; `every ios:chat.block key is referenced`.

- [ ] **Step 6: Commit**

```bash
git diff --stat                        # only these three files besides the user's own paths
.superpowers/sdd/commit-mine.sh "feat(chat): an answer to a questionnaire or a confirmation is drawn as a card in the user's bubble on the phone — the block's title, then the answers, quieter" \
  Sources/ChatFeature/Interactive/InteractiveAnswerCard.swift Sources/ChatFeature/AssistantTurnView.swift \
  Tests/ChatFeatureTests/InteractiveAnswerCardTests.swift
git show --stat HEAD                   # exactly the three files
```

---

### Task 9: iOS — gallery states, screenshots, device checklist

**Files:**
- Create: `Sources/ChatFeature/MessageGalleryInteractive.swift`
- Modify: `Sources/ChatFeature/MessageGallery.swift` (dirty — `/tmp/blocks/dual_edit.py`)
- Create: `docs/chat-interactive-blocks-device-checklist.md`

**Interfaces:**
- Consumes: everything above; `MessageGalleryFixtures.Run`, `MessageGalleryFixtures.runs`, `MessageGalleryLaunch.section`, `TranscriptActions(canAnswer:sendAnswer:)`.
- Produces (DEBUG): `MessageGalleryFixtures.interactiveRuns`, `MessageGalleryFixtures.namedSection(_:) -> Int?`; `-MessageGallerySection ask|confirm|answered`.

- [ ] **Step 1: Write the gallery runs (`Sources/ChatFeature/MessageGalleryInteractive.swift`)**

```swift
#if DEBUG
import Foundation

/// The gallery's runs for the interactive blocks: a questionnaire waiting for its answer, a confirmation waiting for
/// its, and a questionnaire answered — frozen with its picks, the answer under it as a card, and the reply after it.
/// `-MessageGallerySection ask|confirm|answered` scrolls to one.
extension MessageGalleryFixtures {
    static let askSource =
        #"{"title":"A few details first","questions":[{"id":"where","text":"Where does it itch most?","type":"single","options":["Lower legs","Arms","All over"],"other":true},{"id":"when","text":"When is it worst?","type":"multi","options":["After a shower","At night","All day"]}],"note":"Anything else I should know?","submit":"Send"}"#
    static let confirmSource =
        #"{"title":"Add this trip to your calendar?","details":"**Oct 21–25**, five days, 17 stops; calendar *Travel*.","approve":"Add it","reject":"Not now","note":"Anything to change?"}"#

    static let interactiveRuns: [Run] = [
        Run(
            title: "A questionnaire in the answer",
            json: interactiveRun(
                id: "ib1", question: "My legs itch after every shower. What can I do?",
                reply: "That's common when the air is dry. A few details first, so I can be specific:\n\n```exodus-ask\n\(askSource)\n```")),
        Run(
            title: "A confirmation before an action",
            json: interactiveRun(
                id: "ib2", question: "Put the Kyoto trip in my calendar.",
                reply: "Here's what I'd add:\n\n```exodus-confirm\n\(confirmSource)\n```")),
        Run(title: "Answered: the block frozen, the answer as a card", json: answeredRun()),
    ]

    /// The run index a `-MessageGallerySection` name stands for.
    static func namedSection(_ name: String) -> Int? {
        let offset: Int? =
            switch name {
            case "ask": 0
            case "confirm": 1
            case "answered": 2
            default: nil
            }
        return offset.map { runs.count - interactiveRuns.count + $0 }
    }

    private static func interactiveRun(
        id: String, question: String, reply: String, then rest: [[String: Any]] = []
    ) -> String {
        let messages: [[String: Any]] =
            [
                ["id": id, "runId": id, "role": "user", "content": question, "timestamp": 1000],
                [
                    "id": "\(id)a", "runId": id, "role": "assistant", "content": [["type": "text", "text": reply]],
                    "stopReason": "stop", "timestamp": 1200,
                ],
            ] + rest
        let data = (try? JSONSerialization.data(withJSONObject: messages)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func answeredRun() -> String {
        guard case .ask(let ask)? = InteractiveBlock.parse(.ask, source: askSource) else { return "[]" }
        let answer = InteractiveAnswer.composeAsk(
            ask, ref: "ib3",
            responses: ["where": .init(options: ["Lower legs"]), "when": .init(options: ["After a shower", "At night"])],
            note: "I use an unscented lotion.", labels: .current)
        let rest: [[String: Any]] = [
            ["id": "ib4", "runId": "ib4", "role": "user", "content": answer, "timestamp": 1400],
            [
                "id": "ib4a", "runId": "ib4", "role": "assistant",
                "content": [
                    [
                        "type": "text",
                        "text":
                            "Then it's most likely dry skin from hot showers. Keep them short and lukewarm, and put the lotion on within three minutes, while your skin is still damp.",
                    ]
                ],
                "stopReason": "stop", "timestamp": 1600,
            ],
        ]
        return interactiveRun(
            id: "ib3", question: "My legs itch after every shower. What can I do?",
            reply: "A few details first, so I can be specific:\n\n```exodus-ask\n\(askSource)\n```", then: rest)
    }
}
#endif
```

- [ ] **Step 2: Add them to the gallery (`Sources/ChatFeature/MessageGallery.swift`, dirty)**

Create `/tmp/blocks/gallery_edits.py`:

```python
PATH = "Sources/ChatFeature/MessageGallery.swift"
EDITS = [
    (
        '    static var section: Int? { value(after: "-MessageGallerySection").flatMap { Int($0) } }\n',
        '    /// A number, or a name of the interactive blocks\' runs (`MessageGalleryFixtures.namedSection`).\n'
        '    static var section: Int? {\n'
        '        value(after: "-MessageGallerySection").flatMap { Int($0) ?? MessageGalleryFixtures.namedSection($0) }\n'
        '    }\n',
    ),
    (
        "                sheet = sourcesSheet(in: prepared, turnId: turnId, marker: marker)\n            })\n",
        "                sheet = sourcesSheet(in: prepared, turnId: turnId, marker: marker)\n"
        "            },\n"
        "            // A block can be filled in here; Submit sends nothing.\n"
        "            canAnswer: true, sendAnswer: { _ in })\n",
    ),
    ("    ] + bubbleRuns\n", "    ] + bubbleRuns + interactiveRuns\n"),
]
```

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
python3 /tmp/blocks/dual_edit.py check /tmp/blocks/gallery_edits.py    # OK … 3 edit(s)
python3 /tmp/blocks/dual_edit.py apply /tmp/blocks/gallery_edits.py
tuist generate --no-open
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: `** BUILD SUCCEEDED **`; `0 error(s)`.

- [ ] **Step 3: Take the screenshots**

Write `/tmp/blocks/shots.sh`:

```bash
#!/bin/bash
# Light, dark and AX screenshots of the interactive blocks' gallery runs. Run from the repo root.
set -euo pipefail
SIM=992425B7-F06B-4CE5-9288-95C71C2F1D44
APP=app.yancey.exodus.exodus-ios
OUT=.superpowers/blocks
mkdir -p "$OUT"
shoot() {
  local name=$1; shift
  xcrun simctl terminate "$SIM" "$APP" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$APP" "$@" >/dev/null
  sleep 5
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null
}
SECTIONS="ask confirm answered"
for mode in light dark; do
  xcrun simctl ui "$SIM" appearance "$mode"
  for s in $SECTIONS; do shoot "$mode-$s" -MessageGallery -MessageGallerySection "$s"; done
done
xcrun simctl ui "$SIM" appearance light
xcrun simctl ui "$SIM" content_size accessibility-extra-extra-extra-large
for s in $SECTIONS; do shoot "ax-$s" -MessageGallery -MessageGallerySection "$s"; done
xcrun simctl ui "$SIM" content_size large
echo done
```

```bash
xcrun simctl boot 992425B7-F06B-4CE5-9288-95C71C2F1D44 2>/dev/null || true
xcrun simctl install 992425B7-F06B-4CE5-9288-95C71C2F1D44 /tmp/blocks-dd/Build/Products/Debug-iphonesimulator/Exodus.app
bash /tmp/blocks/shots.sh
```

Expected: `done`. Read every PNG in `.superpowers/blocks/` and check against spec §5:
- `ask`: the question bubble, the reply's sentence, then a card: "A few details first" (headline), "1. Where does it itch most?" with three radio rows and "Other…", "2. When is it worst?" with three checkbox rows, "Anything else I should know?" over a field reading "Optional", and a full-width tinted "Send". No grey code block anywhere.
- `confirm`: "Add this trip to your calendar?", the details with **Oct 21–25** bold and *Travel* italic, the note field "Anything to change?", "Not now" (bordered) and "Add it" (tinted) side by side.
- `answered`: the questionnaire with "Lower legs", "After a shower" and "At night" ticked in the accent, the others plain, "Answered" with a checkmark, no field and no Send; under it your bubble as a card — the checklist icon, "A few details first", then "**Where does it itch most?** Lower legs", "**When is it worst?** After a shower, At night", "**Also:** I use an unscented lotion." in grey; then the reply.
- Dark: rows and the card readable, the accent visible; AX: rows wrap onto several lines, nothing clipped, the confirmation's two buttons one over the other.
Fix mismatches before committing (re-run the script after a fix). Tap an option in a running gallery: the selection tap plays on a device (not in the simulator).

- [ ] **Step 4: Write the device checklist (`docs/chat-interactive-blocks-device-checklist.md`)**

```markdown
# Interactive blocks — device checklist

Phase 1 of `docs/superpowers/specs/2026-10-06-interactive-blocks-design.md`: the questionnaire (`exodus-ask`) and the
confirmation (`exodus-confirm`), on the desktop and on the iPhone.

## Desktop

- [ ] Ask "My legs itch after every shower — what should I do?": the reply ends with a questionnaire, one question at a time ("Question 1 of 2"), Previous / Skip / Next, and on the last question "Anything else?" and Submit. Submit: your answer appears as a card (the title, then the answers, quieter); the next reply uses the answers; the questionnaire above becomes a summary with your picks and "Answered".
- [ ] Skip every question and Submit: each is sent as "—" and the reply carries on with what it has.
- [ ] Ask "Add a dentist appointment next Tuesday at 10 to my calendar": a confirmation says what will happen before anything is done. Reject with a note: nothing is added. Ask again, Approve: it is added.
- [ ] While a reply is being written, Submit, Approve and Reject are disabled.
- [ ] While the reply streams the block shows as grey code, and becomes the control once its closing fence arrives.
- [ ] Reload the chat (or scroll back to an older page): answered blocks are still answered, an unanswered one is still open.
- [ ] A tool that asks for approval (a terminal command outside the workspace) still shows its approval card, not a confirmation block.
- [ ] Ask the assistant to show the questionnaire's JSON format inside a code block: it stays code.

## iPhone (paired with the desktop)

- [ ] The same questionnaire on the phone: a card, the questions numbered, 44 pt rows in the tone's accent; a tap plays the selection tap; "Other…" opens a field to type in; Submit plays the success tap and VoiceOver says "Sent". Your bubble shows the answer card; the block shows your picks and "Answered".
- [ ] Answer on the phone, open the chat on the desktop: the block is frozen there with your picks, and the other way round — with the phone and the desktop in different languages.
- [ ] A confirmation on the phone: details drawn as Markdown, the note field, Reject (bordered) and Approve (tinted); at the largest accessibility text size the buttons stack.
- [ ] VoiceOver: each option reads as a toggle button with its state; the title, then the questions in order.
- [ ] Reduce Motion on: the block freezes without animating.
- [ ] Airplane mode, Submit: the run's error line appears under your answer; back online, Regenerate sends it again.
- [ ] Type in the composer, then answer a block: the composer still holds what you typed.
```

- [ ] **Step 5: Run every ChatFeature and MarkdownKit test once more, and the desktop's**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme MarkdownKit -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/blocks-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
cd /Users/yanceyleo/Code/exodus/exodus
bunx vitest run tests/unit/shared/types/interactive.test.ts tests/unit/shared/utils/interactive-answer.test.ts tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts tests/unit/renderer/components/chat/interactive-blocks.test.ts tests/unit/renderer/components/chat/answer-card.test.ts
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
python3 /tmp/blocks/dual_edit.py patch /tmp/blocks/gallery_edits.py /tmp/blocks/gallery.patch   # PATCH-OK
.superpowers/sdd/commit-mine.sh "feat(chat): interactive blocks in the message gallery — a questionnaire, a confirmation, one answered with its card — and a device checklist for both apps" \
  --patch /tmp/blocks/gallery.patch \
  Sources/ChatFeature/MessageGalleryInteractive.swift docs/chat-interactive-blocks-device-checklist.md
git show --stat HEAD           # these two files and MessageGallery.swift
git diff --stat -- Sources/ChatFeature/MessageGallery.swift   # the user's own edits only
```

---

## Self-Review

**Spec coverage:**
- §1 one mechanism (reserved fence + JSON), answer as plain text, room to type everywhere (Other line per question when allowed, a closing note on every questionnaire, a note on every confirmation), desktop on `questionnaire.tsx`, iOS in its own design language → Tasks 1, 3, 5, 7.
- §2.1 `exodus-ask` / `exodus-confirm` shapes and limits (zod and the Swift decoder, the same vectors), unknown / invalid → code, one block per message → Tasks 1, 5 (+ Decisions 4, 5).
- §2.2 the answer: leading `exodus-answer` fence, `{block, ref}` (+ `title`, `decision` — Decision 2), lines as specified, localized words (Decision 3); the prompt's rule about it → Task 2; both clients draw it as a card via `splitAnswer` / `InteractiveAnswer.split` → Tasks 4, 8.
- §2.3 frozen by ref match from loaded messages, nothing stored; desktop disabled/summary state, iOS disabled + "Answered"; a block renders only once its fence is closed → Tasks 3, 7 (+ Decisions 1, 6).
- §3 the prompt section, only in the chat's prompt, ~40 lines (20), both examples, the answer rule → Task 2 (+ Decision 9).
- §4 desktop: `markdown.tsx` hands `exodus-ask`/`exodus-confirm` to `InteractiveFence` (from `pre()`, Decision 12), zod in `packages/shared/src/types/interactive.ts`, `QuestionnaireBlock` on the Questionnaire primitive (Decision 7), `ConfirmationBlock` pending/approved/rejected, `composeAnswer`/`splitAnswer` in `utils/interactive-answer.ts`, sent through `useChat.sendMessage` with the composer untouched, a block in an older run still answers, the user bubble's card → Tasks 1, 3, 4.
- §5 iOS: MarkdownKit `.codeBlock` → `InteractiveBlockView` (through `markdownFencedBlocks`, Decision 10), `QuestionnaireBlockView`, `ConfirmationBlockView`, `InteractiveAnswer.compose` on the same vectors, `UserBubble` card, Dynamic Type (wrapping rows, stacking buttons), VoiceOver (toggle traits, "Sent"), Reduce Motion, haptics → Tasks 5–8 (+ Decisions 11, 13).
- §6 streaming (open fence = code), invalid / over limits / second block = code, disabled while streaming, offline (normal failure path — Decision 8), reopened chat (ref match), blanks allowed (`—`, Skip on the desktop) → Tasks 1, 3, 5, 6, 7.
- §7 testing: shared vitest vectors and zod limits → Task 1; desktop happy-dom (blocks render, invalid → `<pre>`, submit sends the composed text, frozen has no submit, the bubble's card) → Tasks 3, 4; iOS Swift Testing on the same vectors, decoder limits, MarkdownKit block detection, gallery ask/confirm/answered with light/dark/AX screenshots → Tasks 5, 6, 9; the prompt only for chat → Task 2.
- Non-goals respected: no tool-approval change, no structured wire, no DB tables, no editing after submission.

**Placeholder scan:** every code step has complete code; every command has its expected output. The one conditional instruction (Task 3 Step 13, happy-dom and the primitive's form validation) says what to check and forbids weakening the assertion.

**Type consistency:** desktop `parseInteractiveBlock(kind, source)`, `findInteractiveBlock(markdown)`, `interactiveKind(language)`, `InteractiveFence {kind, block, source}`, `composeAskAnswer(block, ref, responses, note, labels)`, `composeConfirmAnswer(block, ref, approved, note, labels)`, `splitAnswer(text) → {answer, body}`, `readPicks(block, body)`, `AnswerLabels {other, addition, note, approved, rejected}`, `QuestionResponse {options, other}`, `Answered {head, body}`, `answersIn`, `InteractiveProvider {messages, status, send}`, `useInteractiveChat`, `InteractiveTurnContext`, `useInteractiveTurn(runId, body)`, `fenceOf`, `InteractiveFence {kind, source, children}`, `BlockProps {block, runId, answered, canSubmit, submit}`, `answerLabels(t)`, `AnswerTitle {head}`; iOS `InteractiveBlock.parse(_:source:)`, `.Kind(language:)`, `.language`, `InteractiveFence.first(in:)`, `.matches(language:code:)`, `InteractiveAnswer.composeAsk(_:ref:responses:note:labels:)`, `.composeConfirm(_:ref:approved:note:labels:)`, `.split(_:) → (head, body)`, `.picks(_:body:)`, `Labels.current`, `Head(block:decision:ref:title:)`, `Response(options:other:)`, `Picks(options:other:)`, `InteractiveText.*`, `MarkdownFencedBlocks(languages:draw:)`, `.view(language:code:)`, `\.markdownFencedBlocks`, `ChatDetailViewModel.canAnswer`, `.sendText(_:)`, `InteractiveAnswered(head:body:)`, `InteractiveRendering.answers(in:)`, `.fencedBlocks(fence:runId:answered:canAnswer:sendAnswer:)`, `TranscriptActions.canAnswer/.sendAnswer`, `AssistantTurnView.answered/.canAnswer/.sendAnswer/.asks`, `InteractiveAnswerCard(head:text:)`, `.lines(_:)`, `.symbol(for:)`, `MessageGalleryFixtures.interactiveRuns/.namedSection(_:)` — used with these names in every task.

**Review Focus:** each of the five lines has its test in the owning task (Tasks 1, 3, 4, 5, 6).
