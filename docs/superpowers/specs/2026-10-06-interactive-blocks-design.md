# Interactive blocks — questionnaire and confirmation (phase 1)

Date: 2026-10-06 · Status: implemented (phase 1, both repos, 2026-10-06); amended after the whole-branch reviews — see the notes marked *(amended)*
Repos: `exodus` (desktop: prompt, block parsing, renderer) and `exodus-ios` (renderer)
References: ChatGPT's in-chat questionnaire (user's screenshots 2026-10-03), `src/renderer/components/ui/questionnaire.tsx` (the user's shadcn Questionnaire), https://elements.ai-sdk.dev/components/confirmation

## 1. Goal

When the model needs the user's choice or go-ahead, it asks with a native control inside the answer instead of prose — a questionnaire (choices, with room to type) or a confirmation (approve / reject, with room to type) — and the user's answer goes back as a message the model reads like any other.

### Decided by the user vs. recommended

| Decided by the user | Recommended and accepted |
|---|---|
| Phase 1 is questionnaire + confirmation; illustrated steps, entity panels and TradingView stocks are phase 2 | One mechanism for every block: a fenced code block with a reserved language, JSON inside, rendered natively by both clients (the `exodus-health` pattern) |
| The answer travels back as **plain text** every provider reads | A leading `exodus-answer` fence lets the clients draw the answer as a compact card; the text after it is the same words, so nothing is lost on a client that does not know the fence |
| Even a choice or a confirmation must leave room to type | Every questionnaire has a free-text line per question ("Other…" when a question allows it) and one closing "Anything else?" field; every confirmation has a note field |
| Desktop uses the user's `questionnaire.tsx`; iOS follows Exodus's own design language | iOS draws the block as a grouped form inside the answer, Dynamic Type and VoiceOver complete |

### Non-goals
- No change to tool approvals (`approval_required` / `decideApproval`): a confirmation block is the *model* asking before it acts, by its own judgement; tool approvals stay the kernel's gate.
- No structured wire for answers; no new DB tables; no server state per block.
- No block editing after submission (a submitted block is frozen; the user types a new message to change their mind).

## 2. The wire

### 2.1 Blocks the model emits (assistant → clients)

A fenced block whose info string is the block's name and whose body is one JSON object. The clients render a known block natively; an unknown `exodus-*` block, or one whose JSON fails validation, renders as the ordinary code block it is (the reader still sees the content).

**Questionnaire — `exodus-ask`**
```json
{
  "title": "我想先确认一下你的具体情况",
  "questions": [
    { "id": "where", "text": "哪里最痒？", "type": "single", "options": ["小腿", "手臂", "全身到处都痒"], "other": true },
    { "id": "when", "text": "什么时候最痒？", "type": "multi", "options": ["洗澡后", "晚上", "全天"] }
  ],
  "note": "还有什么想补充的？",
  "submit": "提交，帮我判断"
}
```
- `questions`: 1–8; `id` `[a-z0-9_-]{1,32}` unique; `text` ≤ 200 chars; `type` `single` (radio) or `multi` (checkbox); `options` 2–8 strings ≤ 80 chars; `other` (default false) adds an "Other…" option with a text line.
- `note` (optional, ≤ 120): the closing free-text field's label; when absent the label is the client's default ("Anything else?"). The field is always present.
- `submit` (optional, ≤ 40): the button's label; default "Submit".
- Limits are validated by zod (desktop) and by the Swift decoder (iOS); a block over the limits is not a block. Lengths count UTF-16 units on both sides.
- *(amended)* `title`, every question `text` and every option are one line (no `\n`/`\r`), and question texts are distinct within a block — the answer is read back one line per question, so a newline or a repeated question would misread the picks.

**Confirmation — `exodus-confirm`**
```json
{
  "title": "要我把这份行程写进日历吗？",
  "details": "10 月 21–25 日，五天，17 个地点；日历「旅行」。",
  "approve": "写进去",
  "reject": "先不要",
  "note": "有要改的地方可以写在这里"
}
```
- `title` ≤ 200 (required); `details` ≤ 1000 Markdown (optional); `approve` / `reject` ≤ 40 (optional, defaults "Approve" / "Reject"); `note` ≤ 120 label (optional; the field is always present).

A message may hold at most one interactive block; a second is rendered as code. *(amended)* The block is the message's **first** top-level closed fence with a reserved name, found by position (so a later fence with identical text is code, and a fence that opens in one text block and closes after a tool card is code). Both scanners follow CommonMark here: a backtick fence's info string may not contain a backtick (so ```` ```npm i``` ```` on one line is not an opener), only spaces and tabs count as blank after the info string or the closing run, and CRLF is normalised before scanning.

### 2.2 The answer (clients → model)

The user's answer is a **plain-text user message**: a leading `exodus-answer` fence with a small JSON (`{"block":"ask"|"confirm","ref":"<message id>"}`), a blank line, then the answer as prose, like `quoted-text.ts` and `health-context.ts`:

```
```exodus-answer
{"block":"ask","ref":"a9f2…"}
```

**哪里最痒？** 小腿
**什么时候最痒？** 洗澡后, 晚上
**补充:** 用的是丝塔芙润肤乳
```

- Questionnaire: one line per question, `**<question>** <choices joined by ", ">`; "Other…" with text becomes `其他: <text>`; an unanswered question is listed as `—`; the closing note line only when typed.
- Confirmation: `**<title>** 同意` / `拒绝` (the client's localized "Approved"/"Rejected" words, not the button labels), then `**备注:** <note>` when typed.
- The desktop's chat route and the system prompt learn the fence so the model reads it as an answer to its block (the prompt says: "a user message opening with ```exodus-answer answers the questionnaire or confirmation you asked; act on it, do not ask again").
- Both clients draw a user message that opens with the fence as an **answer card** (the title, then the lines, muted) instead of a bubble of raw Markdown; `splitAnswer` mirrors `splitHealth`.

### 2.3 Rendering a block that has been answered

A block is **frozen** once the chat holds a later user message whose `exodus-answer` `ref` names the block's message id: choices shown read-only with the picks, the submit button gone (desktop: `disabled` state; iOS: `.disabled` + a checkmark line "Answered"). The ref is matched client-side from the messages already loaded; nothing is stored. While a reply streams, a block renders only after its fence is closed (no half-parsed forms).

## 3. The prompt (desktop)

`src/main/lib/ai/prompts` (wherever the chat's system prompt is built) gains one section, `interactive blocks`, present only for providers that run the chat (not Health or period reports): when the answer depends on facts only the user has, ask with an `exodus-ask` block — at most once per reply, 1–8 questions, short options; *(amended)* before a hard stop (the prompt's existing `<hard_stops>` list) or an action that reaches outside this machine (sending, booking, a calendar entry, money), ask with `exodus-confirm` first — inside the workspace the model acts freely, as the existing tool rules say, so ordinary file writes need no confirmation (the first draft said "writing files", which contradicted those rules); never emit either block inside another fence, a list or a table; write them in the user's language. Include both JSON examples. The section is ~40 lines; it is read by every chat turn, so it stays short.

## 4. Desktop renderer

- `markdown.tsx` `code()` sees `language-exodus-ask` / `language-exodus-confirm` and hands the fence body to `InteractiveBlock` (new `src/renderer/components/chat/interactive/`): parse → validate (zod in `packages/shared/src/types/interactive.ts`, shared with the route) → render `QuestionnaireBlock` (built on `ui/questionnaire.tsx`: `QuestionnaireItem`/`Choices`/`Choice`/`Input`/`Submit`) or `ConfirmationBlock` (two buttons + note textarea, states pending / approved / rejected like ai-sdk's Confirmation).
- Submit builds the answer text (`packages/shared/src/utils/interactive-answer.ts`: `composeAnswer`, `splitAnswer`) and sends it through the composer's send path (`useChat.sendMessage` with the text; attachments none), so it streams like a typed message; the composer's own draft is untouched.
- The user bubble (`user-bubble.tsx`) draws an `exodus-answer` message as the answer card.
- A block in a message that is not the chat's last run still works (the answer is a new message at the end); frozen state per §2.3.

## 5. iOS renderer

- MarkdownKit's `.codeBlock(language:code:)` with `exodus-ask` / `exodus-confirm` → `InteractiveBlockView` (new `Sources/ChatFeature/Interactive/`): `QuestionnaireBlockView` (a card: title, numbered questions, radio/checkbox rows as 44 pt buttons with the tone's accent, "Other…" with a `TextField`, the closing note `TextField`, a prominent Submit) and `ConfirmationBlockView` (title, details as Markdown, note field, Approve (prominent, tone) / Reject (bordered)). Submission calls the chat's `sendMessage` path with the composed text (`InteractiveAnswer.compose`, mirror of the desktop's, held to the same test vectors).
- `UserBubble` draws an `exodus-answer` message as the answer card (`InteractiveAnswer.split`).
- Dynamic Type: rows wrap; at accessibility sizes buttons stack. VoiceOver: each option a toggle button with its state; Submit announces "Sent". Reduce Motion: no animated freeze.
- Haptic: `.selection` on an option, `.success` on submit (via `.sensoryFeedback`).

## 6. Edge cases
- Streaming: a fence still open renders as code (grey) until closed, then swaps to the control.
- Invalid JSON / over limits / second block in one message: ordinary code block.
- Submit while a reply is streaming: the button is disabled (same rule as the composer).
- Offline on submit *(amended)*: the answer is appended to the chat before the send, like a typed message, so the block freezes with its picks and the failure shows on the answer's own turn; the user retries with Regenerate / Retry there. (The first draft said the answer stays in the fields; that is not how either client's send path works, and a retry from the turn is the same gesture as for any failed message.)
- A confirmation's `details` Markdown draws remote images through the chat's tap-to-load policy on both clients — never loaded on sight — so an injected image URL cannot carry chat text out.
- The "other version" sheet and the compared columns draw a block read-only: nothing live, no submit.
- On the phone, a block's in-progress picks are held outside the row view (keyed by the message id), so scrolling the lazy transcript away and back keeps them; they clear when the block freezes.
- A chat reopened later: frozen state restored from the messages (ref match); nothing else to persist.
- Unanswered required state: there is none — the user may submit with blanks (listed as `—`).

## 7. Testing
- Shared (vitest): `composeAnswer`/`splitAnswer` round-trip vectors (CJK, commas in options, Other, blanks, confirmation approve/reject/note), zod limits (reject 9 questions, 81-char option, two blocks).
- Desktop (vitest, happy-dom): Markdown renders the two blocks; invalid → `<pre>`; submit calls send with the composed text; a frozen block has no submit; the user bubble draws the answer card.
- iOS (Swift Testing): `InteractiveAnswer` held to the same vectors as the desktop; decoder limits; `MarkdownKit` block detection; a `-MessageGallery` run for ask / confirm / answered, screenshots light/dark/AX.
- Prompt: a vitest that the system prompt contains the section only for chat.

## 8. Phase 2 (later spec)
Illustrated steps (`exodus-cards`, images from search results), entity panels (`[name](entity:…)` → Wikipedia summary through a desktop route), TradingView mini charts (`exodus-stock`, desktop iframe / iOS web view).
