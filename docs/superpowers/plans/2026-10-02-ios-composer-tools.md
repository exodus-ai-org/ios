# iOS Composer Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The phone's composer gets the desktop's `+`: pictures from Photos and the camera (downscaled on the phone, sent as image blocks), a reasoning effort and Deep Research for the app session (shown as removable pills), and a read-only list of the computer's MCP tools.

**Architecture:** Three pure, tested layers come first. `TurnOptions` (Models) is what a send asks besides the question; `ChatStreamManager` encodes it as the desktop's `advancedTools` / `reasoningEffort`. `ComposerPicture` (ChatFeature) decodes, downscales and re-encodes a picked picture with ImageIO; `ComposerAttachments` holds up to ten; `ComposerContent` builds the user message's `content` exactly as the desktop's `use-chat.ts` does. `ComposerTools` is one `@Observable` for the app session (made by `AppShell`, handed to the chat screen through the environment, like the tone) holding the effort, Deep Research, the current model's levels and the MCP tools, with the desktop's mutual exclusion and a fallback to `off`. The view model keeps the chat's pictures and reads `ComposerTools` when a turn starts. The views (`+` menu, picture squares, pills, MCP sheet, camera) live in new files; the files that hold the user's uncommitted work get only small, anchored edits.

**Tech Stack:** Swift 6, SwiftUI (iOS 27: `Menu`, `photosPicker`, `fullScreenCover`, `glassEffect`, `.buttonStyle(.glass)`, `ViewThatFits`, `sensoryFeedback`), PhotosUI, UIKit `UIImagePickerController` through `UIViewControllerRepresentable`, ImageIO + UniformTypeIdentifiers, AVFoundation (camera permission), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-02-ios-composer-tools-design.md` (all of it). Desktop reference: `exodus/src/renderer/components/composer-tools.tsx` (`ComposerToolsButton`, `ActiveToolPills`, `useAdvancedToolToggle`, `useAvailableEffortLevels`), `file-preview.tsx` (`FilePreview`), `src/renderer/hooks/use-chat.ts:197-233` (how `content` is built), `src/main/lib/server/schemas/chat.ts:35-95` (`userContentSchema`, `postRequestBodySchema`: `advancedTools: z.array(z.enum(AdvancedTools))`, `reasoningEffort: EffortLevelSchema.optional()`).

## Decisions (spec gaps, resolved here)

1. **Strings are new `ios:chat.composer.*` keys.** The spec says to reuse the desktop's `chat:composerTools.*`, `common:composer.reasoning*` and `chat:advancedTools.deepResearch`, but none of them is in the iOS catalog (`Resources/App/Localizable.xcstrings`), and a desktop key must also stay in sync with `Vendor/exodus-locales`. So every label gets an `ios:` key (20 keys, Task 4), with the desktop's own translations wherever it has them (`Vendor/exodus-locales/*/chat.json`, `common.json`). Existing keys reused as they are: `common:action.add` (the `+`'s VoiceOver label, as the desktop's `t('action.add')`), `common:action.cancel`, `common:action.close`, `ios:settings.pairing.cameraDeniedTitle` ("Camera access is off") and `ios:settings.pairing.openSystemSettings` ("Open Settings").
2. **"Deep Research", title case** (the spec, and the app's existing `ios:chat.message.tool.deepResearch`), not the desktop's "Deep research". The levels read Off, Low, Medium, High, Extra high, Max (the desktop's).
3. **Reasoning levels offered:** `off` first, then the levels in the desktop's order (`off low medium high xhigh max`) that the model's `modelSnapshot.reasoningLevels` lists. Unknown names are ignored. A model that lists nothing, or only `off`, hides the entry. (The desktop filters its list by `supported.includes`, which shows `off` only when listed; its own snapshots always list `off` — `resolve-model.ts:32-50` — so the result is the same.)
4. **Settings unreachable:** a failed read keeps the levels and MCP tools last read; the entries are hidden only while nothing has been read (spec §7: "no levels known"). Deep Research is offered whenever `ComposerTools` exists.
5. **When levels are read** (`ComposerTools.refresh`): when a chat opens (`activeChat.id`, initially too), when the Settings sheet closes (the model may have changed), and when the app comes back to the foreground — all from `AppShell`, next to the tone's refresh. A chosen level the new model lacks falls back to `off` at that moment.
6. **"Transparency" means an alpha channel** (`kCGImagePropertyHasAlpha` of the source): such a picture stays PNG; everything else (HEIC, JPEG, opaque PNG screenshots) becomes JPEG 0.85. No per-pixel scan. Re-encoding from a thumbnail also drops the photo's metadata (GPS among it) — intended.
7. **`content` on the wire:** text alone stays a plain string (the wire is unchanged for every message without pictures); with pictures it is `[{type:"text",text}?, {type:"image",mimeType,data:<data URL>}…]`, the text block only when there is text (desktop `use-chat.ts:204-225`). A quote with pictures and nothing typed sends the quote as the text.
8. **A picture that fails to decode** is reported through the composer's existing notice banner (`StreamNotice`, warning): "A picture couldn’t be read and was left out." / "%lld pictures couldn’t be read and were left out." The others are added.
9. **Camera permission:** the first time, the system asks (a refusal there is the system's own answer, nothing more is shown); on a later Take Photo with access refused or restricted, one alert explains and offers Open Settings. Photos needs no permission (`PhotosPicker` runs out of process).
10. **The ten-picture cap:** the photo picker's `maxSelectionCount` is the room left; both photo entries are disabled at ten; anything past ten that still arrives is dropped silently (`ComposerAttachments.append` returns how many).
11. **MCP Tools (N):** N is the entry's subtitle (the desktop shows the bare count at the row's end). The sheet is read-only and closes with the system close button (`Button("common:action.close", role: .close)`, as `SourcesSheet`).
12. **Tint:** the `+` is tinted with the chat's tone ink while a choice is on (the desktop's blue), not system blue — the chat screen's own rule (`ChatDetailView.swift:224-229`). Pills use the same ink on a 12 % fill.
13. **Pills** sit in their own row under the quote, above the field: side by side, or one under the other when they do not fit (`ViewThatFits` — "pills wrap"). Deep Research and a level exclude each other, so at most one pill shows in practice; the layout still takes two.
14. **How the view model reads the session's choices:** `ChatDetailView` reads `ComposerTools` from the environment and hands it to its view model (`viewModel.composerTools = composerTools`) at the top of its existing `.task`, before `onAppear` and `sendInitial`. `startTurn` reads `composerTools?.turnOptions` when the turn starts, so Regenerate uses the choices of that moment.
15. **`TurnOptions` and `ReasoningEffort` live in Models**, so NetworkingKit can encode them; `reasoningEffort` is left out of the body when off (a nil optional is not encoded), `advancedTools` is `["Deep Research"]` or `[]`.
16. **Haptics:** one `.selection` tick whenever the session's choices change (menu or pill), via `.sensoryFeedback` on the `+`. Picking pictures has none (the system picker closing is the feedback).
17. **Gallery:** `-MessageGallery -MessageGalleryComposer <empty|pictures|full|reasoning|research|mcp>` shows the real composer pieces over the message gallery (new `ComposerGallery.swift`; `MessageGallery.swift` gets a three-line hunk; `ExodusApp.swift` is not touched).
18. **Committing edits to files that hold the user's work:** through `dual_edit.py` (see Shared tooling): each edit is an exact (old, new) pair whose `old` exists both in the committed file and in the working file, so the commit is HEAD + our edits and nothing of the user's. `ChatStreamManager`'s body edit is anchored on lines that both versions share, so it does not depend on the user's uncommitted protocol-2 `Body`.

## Global Constraints

- Repo `/Users/yanceyleo/Code/exodus/exodus-ios`, branch `maintenance`. Read `.superpowers/sdd/constraints.md` once; where it differs from this list (its simulator line, `git add -p`), this list wins.
- **Commits only through the helper**, from the repo root: `.superpowers/sdd/commit-mine.sh "<subject>" [--patch FILE.patch ...] <paths you own>`. Never run `git add`, `git commit`, `git commit -a`, `git stash`, `git reset`, `git restore` or `git checkout -- <file>`. After each commit run `git show --stat HEAD` and confirm it lists ONLY your files; if not, STOP and report BLOCKED (do not repair history).
- **These files hold the user's uncommitted edits:** `Sources/ChatFeature/ChatDetailView.swift`, `Sources/ChatFeature/ChatDetailViewModel.swift`, `Sources/NetworkingKit/ChatStreamManager.swift`, `Sources/ChatFeature/MessageGallery.swift`, `Resources/App/Localizable.xcstrings` (all edited by this plan), and `Sources/App/ExodusApp.swift`, `Sources/Models/ChatMessage.swift`, `Tests/ChatFeatureTests/ChatDetailViewModelTests.swift`, `Tests/NetworkingKitTests/ChatStreamManagerTests.swift` (never touched by this plan — new test files instead). Never rewrite such a file whole and never hand-edit it: the four Swift files change only through `/tmp/composer/dual_edit.py`, the catalog only through `/tmp/composer/add_keys.py`. `Resources/App/Assets.xcassets/LaunchLogo.imageset/Contents.json` is pre-staged by someone else and must stay staged and out of every commit.
- Run `git diff --stat` at the start and end of every task and compare: only the files your task names may have changed. A file committed whole (a `<path>` argument to the helper) must be one you created, or one whose `git diff --stat -- <file>` was empty before you started.
- Never push.
- Swift 6 language mode, iOS 27.0 deployment target, Tuist 4.208 with buildable folders. **After creating any new file under `Sources/` or `Tests/`, run `tuist generate --no-open` before building**: a new Swift file under `Sources/ChatFeature` is otherwise compiled into the `ExodusIos_ChatFeature` resource target and cannot see the module's types. Run it again after the `Project.swift` edit (Task 4).
- Native frameworks only (PhotosUI, UIKit, ImageIO, UniformTypeIdentifiers, AVFoundation); no new packages.
- Builds and tests: simulator `992425B7-F06B-4CE5-9288-95C71C2F1D44` (iPhone 18 Pro Max, iOS 27), `-derivedDataPath /tmp/composer-dd`. Tests: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme <ChatFeature|NetworkingKit|Models> -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd [-only-testing:<Target>Tests/<TypeName>] 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"`. A wrong `-only-testing` name still prints SUCCEEDED — confirm a `Test run with N tests` line with N > 0. App build: `xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`.
- `python3 scripts/l10n.py audit 2>&1 | tail -1` prints `0 error(s)` at the end of every task (warnings about keys not referenced yet are fine until Task 6). Never run `scripts/l10n.py add`, `fill` or `save`: they rewrite the whole catalog and would drag the user's edits into a commit.
- Strings: new keys are `ios:chat.composer.<element>`, all ten languages (en, zh-Hant, zh-HK, ja, ko, fr, de, es, pt-BR, it) from Task 4. Views use the key literal (`Text("ios:chat.composer.photoLibrary")`); code uses `String(localized: "…", defaultValue: "<exact English>", comment: "…")` whose `defaultValue` equals the catalog's English exactly. Never concatenate a sentence; never pass a ternary of two string literals to a text initializer; user data and numbers go through `Text(verbatim:)`.
- Wire values, verbatim: `advancedTools` holds `"Deep Research"` (desktop `AdvancedTools.DeepResearch`); `reasoningEffort` is one of `off low medium high xhigh max` (desktop `EffortLevelSchema`) and is left out when `off`; an image block is `{"type":"image","mimeType":…,"data":"data:<mime>;base64,…"}`.
- Pictures: longest side ≤ 2048 px, JPEG quality 0.85, PNG kept only with an alpha channel; 56 pt squares in the composer (rounded, ✕ at the corner); at most 10 per message.
- Haptics only through `.sensoryFeedback` (no sounds). Reduce Motion: every composer animation is `reduceMotion ? nil : .snappy(duration: 0.2)` (the composer's existing curve).
- Match the surrounding code: doc comments short and plain, saying *why*; no comment noise; Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`).
- Do not dispatch subagents from inside a task.

## Shared tooling: `/tmp/composer/dual_edit.py`

Every task that edits one of the four Swift files with the user's work uses this helper. Create it once (the first task that needs it is Task 1); later tasks check it exists.

```python
#!/usr/bin/env python3
"""Edits a file that also holds someone else's uncommitted work, and commits only our part.

    dual_edit.py check EDITS.py          every edit applies to the working file and to HEAD's (nothing written)
    dual_edit.py apply EDITS.py          applies the edits to the working file (an edit already in is skipped)
    dual_edit.py patch EDITS.py OUT      writes OUT: HEAD's file -> HEAD's file with the edits, for commit-mine.sh --patch

EDITS.py defines PATH (repo-relative) and EDITS, a list of (old, new) exact-text pairs applied in order; each `old`
must occur once in the file as committed and once in the working file. Run from the repo root. Never hand-edit the
file: to change something, append an (old, new) pair whose `old` is text an earlier edit wrote, and run `apply` again.
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


if mode == "check":
    strict(head, "HEAD")
    strict(work, "working file")
    print("OK", path, len(edits), "edit(s) apply to HEAD and to the working file")
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
    # The patch must apply to HEAD through a private index (the shared one is never touched).
    idx = tempfile.mktemp(prefix="dual-idx.")
    env = dict(os.environ, GIT_INDEX_FILE=idx)
    subprocess.run(["git", "read-tree", "HEAD"], env=env, check=True)
    subprocess.run(["git", "apply", "--cached", "--check", out], env=env, check=True)
    os.remove(idx)
    print("PATCH-OK", out)
else:
    sys.exit("mode is check, apply or patch")
```

Workflow for such a file: write the task's `EDITS.py` → `dual_edit.py check` (prints `OK`) → `dual_edit.py apply` → build and test → (a fix is a new (old, new) pair appended to `EDITS.py`, then `apply` again) → at commit time `dual_edit.py patch EDITS.py X.patch` (prints `PATCH-OK`) → `commit-mine.sh … --patch X.patch` → `git diff -- <file>` afterwards shows only the user's own edits. Every anchor in this plan was checked against HEAD `e326426` and the working tree on 2026-10-02.

## Review Focus

- A portrait iPhone photo, stored landscape with an EXIF rotation: it must arrive upright and capped on its longest side, not sideways. Test: `ComposerPictureTests.aPhotoStoredTurnedComesOutUpright` (Task 2).
- The model switched on the desktop to one without the chosen level, then a send from the phone: the level falls back to `off` on the next refresh and nothing the model cannot take is sent. Test: `ComposerToolsTests.aRefreshToAModelWithoutTheLevelTurnsItOff` (Task 3).
- Eight pictures already waiting and five more picked: exactly ten, in pick order, and no "couldn't be read" banner for the ones that did not fit. Test: `ComposerSendTests.picksPastTheLimitAreLeftOutQuietly` (Task 5).
- "Ask about this" on a selection, a picture added, nothing typed: Send is enabled and the message carries the quote as its text, then the picture. Test: `ComposerSendTests.aQuoteWithPicturesAndNothingTypedSendsTheQuote` (Task 5).
- Deep Research turned on after an answer, then Regenerate: the re-asked question carries Deep Research (the choices of that moment, as the desktop). Test: `ComposerSendTests.regenerateTakesTheChoicesOfThatMoment` (Task 5).

---

## File Structure

**Models — new**
- `Sources/Models/TurnOptions.swift` — `ReasoningEffort` (the desktop's `EffortLevel`), `TurnOptions` (`advancedTools`, `wireReasoningEffort`).

**NetworkingKit — modified (user's work in it; `dual_edit.py`)**
- `Sources/NetworkingKit/ChatStreamManager.swift` — `send(…, options:)` (`:101-105`), `makeRequest` internal with `options` (`:119`, `:266-294`), `Body.reasoningEffort`.

**ChatFeature — new**
- `Sources/ChatFeature/ComposerPicture.swift` — `ComposerPicture` (prepare: decode, downscale, re-encode), `ComposerAttachments` (≤ 10), `ComposerContent` (the message's `content`).
- `Sources/ChatFeature/ComposerTools.swift` — `ComposerTools` (session state, mutual exclusion, levels, fallback, MCP tools, refresh), `ComposerToolsSource`.
- `Sources/ChatFeature/ComposerText.swift` — strings code puts together (level names, the pill, VoiceOver, notices).
- `Sources/ChatFeature/ComposerToolsViews.swift` — `ComposerToolsButton` (the `+` menu and its pickers, sheet, alert), `ComposerPictureStrip`, `ComposerToolPills`, `McpToolsSheet`.
- `Sources/ChatFeature/CameraPicker.swift` — `CameraPicker` (UIKit camera), `CameraAccess`.
- `Sources/ChatFeature/ComposerGallery.swift` — DEBUG: `ComposerGalleryState`, `ComposerGalleryBar`.

**ChatFeature — modified (user's work in them; `dual_edit.py`)**
- `Sources/ChatFeature/ChatDetailViewModel.swift` — `attachments`, `composerTools`, `canSend` (`:178-181`), `sendMessage` (`:305-315`), `addPictures`/`removePicture` (before `:317`), `startTurn` (`:425`).
- `Sources/ChatFeature/ChatDetailView.swift` — environment (`:40`), `.task` (`:173-174`), `composer` (`:241-260`), `composerRow` (`:262-265`).
- `Sources/ChatFeature/MessageGallery.swift` — one `else if` in the gallery's `safeAreaBar` (`:126-132`).

**App — modified (clean; committed whole)**
- `Sources/App/AppShell.swift` — `@State composerTools`, environment on the chat (`:143`), refreshes (`:107`, `:119-122`).
- `Project.swift` — `NSCameraUsageDescription` (`:62-63`).

**Resources**
- `Resources/App/Localizable.xcstrings` — 20 `ios:chat.composer.*` keys in ten languages (user's work in it; committed as a patch of only these keys).
- `Resources/App/InfoPlist.xcstrings` — `NSCameraUsageDescription` in ten languages (clean; committed whole).

**Tests**
- `Tests/ModelsTests/TurnOptionsTests.swift`, `Tests/NetworkingKitTests/ChatRequestOptionsTests.swift`
- `Tests/ChatFeatureTests/ComposerPictureTests.swift` (with `PictureFixture`, used by later test files), `ComposerToolsTests.swift`, `ComposerTextTests.swift`, `ComposerSendTests.swift`, `ComposerToolsViewsTests.swift`

**Docs**: `docs/composer-tools-device-checklist.md` (new).

**Existing code reused, not changed:** `ChatMessage.userMessage(id:content:timestampMs:)` (`Sources/Models/ChatMessage.swift:88-101`) builds the message from a `content` value; `UserImageStrip`/`UserImages.dataURLs(of:)` (`Sources/ChatFeature/UserImages.swift`) show a sent message's pictures as squares with +N; `ComputerUseFrameStore.decodeScreenshot(_:maxPixelWidth:)` (`Sources/ChatFeature/ComputerUseFrames.swift:149`) decodes a data URL for the composer's thumbnails; `SettingsSnapshot.providerConfig?.modelSnapshot?.reasoningLevels` (`Sources/Models/Settings.swift:13-16`, `:300`) read through `GET /api/v1/settings` as `ColorToneModel.refresh` does (`Sources/SettingsFeature/ColorToneModel.swift:38`); `McpToolsResponse`/`McpTool` (`Sources/Models/SkillsAndMcp.swift:75-112`) from `GET /api/v1/mcp/tools` as `McpSettingsViewModel.load` reads it (`Sources/SettingsFeature/McpSettingsViewModel.swift:34`); the camera-denied alert pattern of `PairingSection` (`Sources/SettingsFeature/PairingSection.swift:76-85`); `MarkdownView(text:isStreaming:)` (MarkdownKit). Not reused: `MarkdownImageLoader.downsample` (`Sources/MarkdownKit/MarkdownImageLoader.swift:76`) caps the *width*, and the spec caps the *longest side*.

---

### Task 1: `TurnOptions`, and the send body carries them

**Files:**
- Create: `Sources/Models/TurnOptions.swift`
- Modify: `Sources/NetworkingKit/ChatStreamManager.swift:101-105, :119, :266-294` (through `/tmp/composer/dual_edit.py`)
- Test: `Tests/ModelsTests/TurnOptionsTests.swift`, `Tests/NetworkingKitTests/ChatRequestOptionsTests.swift`

**Interfaces:**
- Consumes: `ChatMessage.userMessage(id:text:timestampMs:)`, `ServerConfigStore(userDefaults:)`.
- Produces:
  - `public enum ReasoningEffort: String, CaseIterable, Sendable, Hashable { case off, low, medium, high, xhigh, max }`
  - `public struct TurnOptions: Equatable, Sendable { static let deepResearchTool = "Deep Research"; var deepResearch: Bool; var reasoningEffort: ReasoningEffort; init(deepResearch: Bool = false, reasoningEffort: ReasoningEffort = .off); var advancedTools: [String]; var wireReasoningEffort: String? }`
  - `ChatStreamManager.send(chatId:messages:serverConfig:options: TurnOptions = TurnOptions()) -> AsyncStream<ChatStreamUpdate>`
  - `static func ChatStreamManager.makeRequest(chatId:messages:serverConfig:options: TurnOptions = TurnOptions()) -> URLRequest?` (internal)

- [ ] **Step 1: Write the failing tests**

Create `Tests/ModelsTests/TurnOptionsTests.swift`:

```swift
import Foundation
import Testing

@testable import Models

/// The composer's choices as the desktop's route reads them (`postRequestBodySchema`).
@Suite("TurnOptions")
struct TurnOptionsTests {
    @Test("no choices ask for no tool and no effort")
    func noChoices() {
        let options = TurnOptions()
        #expect(options.advancedTools == [])
        #expect(options.wireReasoningEffort == nil)
    }

    @Test("Deep Research is named as the desktop's AdvancedTools names it")
    func deepResearch() {
        #expect(TurnOptions(deepResearch: true).advancedTools == ["Deep Research"])
    }

    @Test("a level is sent by its desktop name, and off is left out")
    func levels() {
        #expect(TurnOptions(reasoningEffort: .xhigh).wireReasoningEffort == "xhigh")
        #expect(TurnOptions(reasoningEffort: .max).wireReasoningEffort == "max")
        #expect(TurnOptions(reasoningEffort: .off).wireReasoningEffort == nil)
    }

    @Test("the levels are the desktop's EffortLevel, in its order")
    func order() {
        #expect(ReasoningEffort.allCases.map(\.rawValue) == ["off", "low", "medium", "high", "xhigh", "max"])
    }
}
```

Create `Tests/NetworkingKitTests/ChatRequestOptionsTests.swift`:

```swift
import Foundation
import Models
import Testing

@testable import NetworkingKit

/// The composer's choices on the wire: `advancedTools` and `reasoningEffort` (desktop `postRequestBodySchema`).
@Suite("Chat request options")
struct ChatRequestOptionsTests {
    private func body(_ options: TurnOptions, _ suite: String = #function) throws -> [String: Any] {
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: suite)!)
        let question = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)
        let request = try #require(
            ChatStreamManager.makeRequest(chatId: "c1", messages: [question], serverConfig: config, options: options))
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("no choices: no tools, and no reasoningEffort key at all")
    func noChoices() throws {
        let body = try body(TurnOptions())
        #expect((body["advancedTools"] as? [String]) == [])
        #expect(!body.keys.contains("reasoningEffort"))
    }

    @Test("Deep Research goes in advancedTools as \"Deep Research\"")
    func deepResearch() throws {
        let body = try body(TurnOptions(deepResearch: true))
        #expect((body["advancedTools"] as? [String]) == ["Deep Research"])
        #expect(!body.keys.contains("reasoningEffort"))
    }

    @Test("a level other than off is sent by its name")
    func level() throws {
        let body = try body(TurnOptions(reasoningEffort: .high))
        #expect(body["reasoningEffort"] as? String == "high")
        #expect((body["advancedTools"] as? [String]) == [])
    }

    @Test("off is left out, as no reasoning option")
    func off() throws {
        #expect(!(try body(TurnOptions(reasoningEffort: .off))).keys.contains("reasoningEffort"))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git diff --stat                    # note the user's files before you start
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ModelsTests/TurnOptionsTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'TurnOptions' in scope` (and `ReasoningEffort`), `TEST FAILED`.

- [ ] **Step 3: Write `TurnOptions`**

Create `Sources/Models/TurnOptions.swift`:

```swift
import Foundation

/// A reasoning effort, as the desktop's `EffortLevel` (`settings-schema.ts`), in its order. `off` asks for no
/// reasoning option.
public enum ReasoningEffort: String, CaseIterable, Sendable, Hashable {
    case off, low, medium, high, xhigh, max
}

/// What a send asks of the run besides the question: the composer's `+` choices (the desktop's `advancedToolsAtom` and
/// `reasoningEffortAtom`), read when the turn starts.
public struct TurnOptions: Equatable, Sendable {
    /// The desktop's `AdvancedTools.DeepResearch`, as `advancedTools` carries it.
    public static let deepResearchTool = "Deep Research"

    public var deepResearch: Bool
    public var reasoningEffort: ReasoningEffort

    public init(deepResearch: Bool = false, reasoningEffort: ReasoningEffort = .off) {
        self.deepResearch = deepResearch
        self.reasoningEffort = reasoningEffort
    }

    /// The body's `advancedTools`.
    public var advancedTools: [String] { deepResearch ? [Self.deepResearchTool] : [] }

    /// The body's `reasoningEffort`: nil when off, so the key is left out and the route sets no reasoning option.
    public var wireReasoningEffort: String? { reasoningEffort == .off ? nil : reasoningEffort.rawValue }
}
```

- [ ] **Step 4: Run the Models tests**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ModelsTests/TurnOptionsTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `Test run with 4 tests passed`, `TEST SUCCEEDED`.

- [ ] **Step 5: Create the shared helper and this task's edits**

Create `/tmp/composer/dual_edit.py` with the code in **Shared tooling** above (`mkdir -p /tmp/composer` first).

Create `/tmp/composer/csm_edits.py`:

```python
PATH = "Sources/NetworkingKit/ChatStreamManager.swift"
EDITS = [
    (
        """        messages: [ChatMessage],
        serverConfig: ServerConfigStore
    ) -> AsyncStream<ChatStreamUpdate> {
""",
        """        messages: [ChatMessage],
        serverConfig: ServerConfigStore,
        options: TurnOptions = TurnOptions()
    ) -> AsyncStream<ChatStreamUpdate> {
""",
    ),
    (
        "        let request = Self.makeRequest(chatId: chatId, messages: messages, serverConfig: serverConfig)\n",
        "        let request = Self.makeRequest(\n"
        "            chatId: chatId, messages: messages, serverConfig: serverConfig, options: options)\n",
    ),
    (
        """    private static func makeRequest(
        chatId: String,
        messages: [ChatMessage],
        serverConfig: ServerConfigStore
    ) -> URLRequest? {
""",
        """    /// Internal, not private: its tests read the body it builds.
    static func makeRequest(
        chatId: String,
        messages: [ChatMessage],
        serverConfig: ServerConfigStore,
        options: TurnOptions = TurnOptions()
    ) -> URLRequest? {
""",
    ),
    (
        "            let advancedTools: [String]\n",
        "            let advancedTools: [String]\n"
        "            /// Left out when off: a nil optional is not encoded.\n"
        "            let reasoningEffort: String?\n",
    ),
    (
        "advancedTools: []",
        "advancedTools: options.advancedTools,\n"
        "                reasoningEffort: options.wireReasoningEffort",
    ),
]
```

The last pair replaces only the `advancedTools: []` argument, which both the committed `Body(id:messages:advancedTools:)` call and the user's uncommitted `Body(id:message:advancedTools:protocol:)` call contain; `reasoningEffort` is declared right after `advancedTools` in both, so the memberwise order holds in both.

- [ ] **Step 6: Apply the edits**

```bash
python3 /tmp/composer/dual_edit.py check /tmp/composer/csm_edits.py     # OK … 5 edit(s) apply to HEAD and to the working file
python3 /tmp/composer/dual_edit.py apply /tmp/composer/csm_edits.py
git diff -- Sources/NetworkingKit/ChatStreamManager.swift | grep -E "^[+-] " | head -30
```
Expected: the user's protocol-2 lines plus ours; in the working file the call now reads:

```swift
        request.httpBody = try? JSONEncoder().encode(
            Body(id: chatId, message: messages.last, advancedTools: options.advancedTools,
                reasoningEffort: options.wireReasoningEffort, protocol: 2))
```

- [ ] **Step 7: Run the NetworkingKit tests (new and existing)**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme NetworkingKit -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `TEST SUCCEEDED`, no `✘`; `-only-testing:NetworkingKitTests/ChatRequestOptionsTests` alone reports 4 tests. Also run the ChatFeature suite once (the existing `ChatDetailViewModelTests.sendMessageSendsTheQuestion` pins the body keys `["id", "message", "advancedTools", "protocol"]`, which must still hold because `reasoningEffort` is left out when off):

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ChatDetailViewModelTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1                                  # 0 error(s)
python3 /tmp/composer/dual_edit.py patch /tmp/composer/csm_edits.py /tmp/composer/csm.patch   # PATCH-OK
.superpowers/sdd/commit-mine.sh "feat(chat): a send can ask for Deep Research and a reasoning effort, named as the desktop's route reads them and left out when off" \
  --patch /tmp/composer/csm.patch \
  Sources/Models/TurnOptions.swift Tests/ModelsTests/TurnOptionsTests.swift Tests/NetworkingKitTests/ChatRequestOptionsTests.swift
git show --stat HEAD           # exactly these four files
git diff -- Sources/NetworkingKit/ChatStreamManager.swift | grep -c "options"   # 0: what is left uncommitted is only the user's
```

---

### Task 2: `ComposerPicture`, `ComposerAttachments`, `ComposerContent`

**Files:**
- Create: `Sources/ChatFeature/ComposerPicture.swift`
- Test: `Tests/ChatFeatureTests/ComposerPictureTests.swift`

**Interfaces:**
- Consumes: `JSONValue` (Models), `ChatMessage.userMessage(id:content:timestampMs:)`, `ChatMessage.contentBlocks`, `UserImages.dataURLs(of:)`.
- Produces:
  - `public struct ComposerPicture: Identifiable, Equatable, Sendable { let id: UUID; let mimeType: String; let dataURL: String; let pixelWidth: Int; let pixelHeight: Int }` with internal `init(id: UUID = UUID(), mimeType:dataURL:pixelWidth:pixelHeight:)`, `static let maxPixelSize = 2048`, `static let jpegQuality = 0.85`, `enum PrepareError: Error { case undecodable, unencodable }`, `static func prepare(_ data: Data) throws -> ComposerPicture`, `@concurrent static func prepared(_ data: Data) async throws -> ComposerPicture`.
  - `public struct ComposerAttachments: Equatable, Sendable { static let limit = 10; private(set) var pictures: [ComposerPicture]; public init(); var isEmpty: Bool; var isFull: Bool; var room: Int; @discardableResult mutating func append(_ more: [ComposerPicture]) -> Int; mutating func remove(_ id: ComposerPicture.ID); mutating func removeAll() }`
  - `enum ComposerContent { static func content(text: String, pictures: [ComposerPicture]) -> JSONValue }`
  - Test target: `enum PictureFixture { static func data(width:height:opaque:png:) -> Data; static func rotatedJPEG(width:height:) -> Data; static func decoded(_:) -> (width: Int, height: Int, type: String)?; static func picture(_ n: Int = 0) -> ComposerPicture }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ChatFeatureTests/ComposerPictureTests.swift`:

```swift
import Foundation
import ImageIO
import Models
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import ChatFeature

/// Pictures as Photos and the camera hand them over, and a way to read a prepared one back.
enum PictureFixture {
    /// A flat picture, `width` × `height` pixels: opaque, or with its lower half transparent; PNG or JPEG.
    static func data(width: Int, height: Int, opaque: Bool = true, png: Bool = false) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let draw: (UIGraphicsImageRendererContext) -> Void = { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: opaque ? size.height : size.height / 2))
        }
        return png ? renderer.pngData(actions: draw) : renderer.jpegData(withCompressionQuality: 1, actions: draw)
    }

    /// A JPEG stored `width` × `height` whose EXIF orientation (6) says to show it turned a quarter clockwise — how an
    /// iPhone stores a portrait photo.
    static func rotatedJPEG(width: Int, height: Int) -> Data {
        let image = UIImage(data: data(width: width, height: height))!.cgImage!
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    /// The pixel size and type of a prepared picture, read back from its data URL.
    static func decoded(_ picture: ComposerPicture) -> (width: Int, height: Int, type: String)? {
        guard let base64 = picture.dataURL.split(separator: ",", maxSplits: 1).last,
            let data = Data(base64Encoded: String(base64)),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            let type = CGImageSourceGetType(source)
        else { return nil }
        return (width, height, type as String)
    }

    /// A picture already prepared; `n` tells them apart by their data URL.
    static func picture(_ n: Int = 0) -> ComposerPicture {
        ComposerPicture(mimeType: "image/jpeg", dataURL: "data:image/jpeg;base64,\(n)", pixelWidth: 1, pixelHeight: 1)
    }
}

@Suite("A picked picture, prepared for the wire")
struct ComposerPictureTests {
    @Test("a 12 MP photo comes out 2048 px on its longest side, as JPEG")
    func aLargePhotoIsCapped() throws {
        let picture = try ComposerPicture.prepare(PictureFixture.data(width: 4032, height: 3024))
        let out = try #require(PictureFixture.decoded(picture))
        #expect(out.width == 2048 && out.height == 1536)
        #expect(out.type == UTType.jpeg.identifier)
        #expect(picture.mimeType == "image/jpeg")
        #expect(picture.dataURL.hasPrefix("data:image/jpeg;base64,"))
        #expect(picture.pixelWidth == 2048 && picture.pixelHeight == 1536)
    }

    @Test("a portrait photo is capped on its height")
    func aPortraitPhotoIsCappedOnItsHeight() throws {
        let out = try #require(PictureFixture.decoded(try ComposerPicture.prepare(PictureFixture.data(width: 3024, height: 4032))))
        #expect(out.width == 1536 && out.height == 2048)
    }

    @Test("a photo stored turned, with its EXIF orientation, comes out upright")
    func aPhotoStoredTurnedComesOutUpright() throws {
        let out = try #require(PictureFixture.decoded(try ComposerPicture.prepare(PictureFixture.rotatedJPEG(width: 400, height: 300))))
        #expect(out.width == 300 && out.height == 400)
    }

    @Test("a small picture keeps its size")
    func aSmallPictureKeepsItsSize() throws {
        let out = try #require(PictureFixture.decoded(try ComposerPicture.prepare(PictureFixture.data(width: 800, height: 600))))
        #expect(out.width == 800 && out.height == 600)
    }

    @Test("a picture with transparency stays PNG")
    func transparencyStaysPNG() throws {
        let picture = try ComposerPicture.prepare(PictureFixture.data(width: 300, height: 200, opaque: false, png: true))
        let out = try #require(PictureFixture.decoded(picture))
        #expect(picture.mimeType == "image/png")
        #expect(picture.dataURL.hasPrefix("data:image/png;base64,"))
        #expect(out.type == UTType.png.identifier)
        #expect(out.width == 300 && out.height == 200)
    }

    @Test("an opaque PNG, such as a screenshot, becomes JPEG")
    func anOpaquePNGBecomesJPEG() throws {
        let picture = try ComposerPicture.prepare(PictureFixture.data(width: 300, height: 200, png: true))
        #expect(picture.mimeType == "image/jpeg")
    }

    @Test("what is not a picture is refused")
    func notAPicture() {
        #expect(throws: ComposerPicture.PrepareError.undecodable) {
            try ComposerPicture.prepare(Data("not a picture".utf8))
        }
    }
}

@Suite("The composer's pictures, at most ten")
struct ComposerAttachmentsTests {
    @Test("ten fit; the rest are turned away, in pick order")
    func tenFit() {
        var attachments = ComposerAttachments()
        let picked = (0..<12).map(PictureFixture.picture)
        #expect(attachments.append(picked) == 2)
        #expect(attachments.pictures == Array(picked.prefix(10)))
        #expect(attachments.isFull)
        #expect(attachments.room == 0)
    }

    @Test("the room left is what the photo picker may still add")
    func room() {
        var attachments = ComposerAttachments()
        #expect(attachments.isEmpty && attachments.room == 10)
        attachments.append((0..<3).map(PictureFixture.picture))
        #expect(attachments.room == 7)
        #expect(!attachments.isFull && !attachments.isEmpty)
    }

    @Test("removing one makes room for one")
    func removing() {
        var attachments = ComposerAttachments()
        let picked = (0..<10).map(PictureFixture.picture)
        attachments.append(picked)
        attachments.remove(picked[3].id)
        #expect(attachments.pictures.count == 9)
        #expect(!attachments.pictures.contains(picked[3]))
        #expect(attachments.append([PictureFixture.picture(99)]) == 0)
        #expect(attachments.isFull)
    }

    @Test("removeAll empties it")
    func removeAll() {
        var attachments = ComposerAttachments()
        attachments.append([PictureFixture.picture()])
        attachments.removeAll()
        #expect(attachments.isEmpty)
    }
}

@Suite("A question's content, as the desktop builds it")
struct ComposerContentTests {
    let first = ComposerPicture(mimeType: "image/jpeg", dataURL: "data:image/jpeg;base64,AAA", pixelWidth: 1, pixelHeight: 1)
    let second = ComposerPicture(mimeType: "image/png", dataURL: "data:image/png;base64,BBB", pixelWidth: 1, pixelHeight: 1)

    private func image(_ picture: ComposerPicture) -> JSONValue {
        .object(["type": .string("image"), "mimeType": .string(picture.mimeType), "data": .string(picture.dataURL)])
    }

    @Test("text alone is a plain string, as before")
    func textAlone() {
        #expect(ComposerContent.content(text: "hi", pictures: []) == .string("hi"))
    }

    @Test("pictures alone are image blocks, with no empty text block")
    func picturesAlone() {
        #expect(ComposerContent.content(text: "", pictures: [first, second]) == .array([image(first), image(second)]))
    }

    @Test("text and pictures: the text block first, then the pictures in order")
    func textAndPictures() {
        let content = ComposerContent.content(text: "Which is warmer?", pictures: [first, second])
        #expect(content == .array([.object(["type": .string("text"), "text": .string("Which is warmer?")]), image(first), image(second)]))
    }

    @Test("blank text with a picture adds no text block")
    func blankText() {
        #expect(ComposerContent.content(text: "  \n", pictures: [first]) == .array([image(first)]))
    }

    @Test("the message reads back as the transcript shows it")
    func readsBack() {
        let message = ChatMessage.userMessage(
            id: "u1", content: ComposerContent.content(text: "look", pictures: [first]), timestampMs: 0)
        #expect(message.contentBlocks == [.text("look"), .image(mimeType: "image/jpeg", dataURL: first.dataURL)])
        #expect(UserImages.dataURLs(of: message) == [first.dataURL])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
git diff --stat
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ComposerPictureTests -only-testing:ChatFeatureTests/ComposerAttachmentsTests -only-testing:ChatFeatureTests/ComposerContentTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'ComposerPicture' in scope`, `TEST FAILED`.

- [ ] **Step 3: Write `ComposerPicture.swift`**

Create `Sources/ChatFeature/ComposerPicture.swift`:

```swift
import Foundation
import ImageIO
import Models
import UniformTypeIdentifiers

/// A picture waiting in the composer, ready for the wire: decoded, turned upright, downscaled on the phone (longest side
/// at most `maxPixelSize`) and re-encoded — JPEG, or PNG when it has an alpha channel — so a 12 MP photo is a few
/// hundred KB of base64, not 5 MB. Encoding from a thumbnail also leaves the photo's metadata (its location among it)
/// behind.
public struct ComposerPicture: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let mimeType: String
    /// `data:<mimeType>;base64,…`: the desktop stores an attachment's data URL in the image block's `data`.
    public let dataURL: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    static let maxPixelSize = 2048
    static let jpegQuality = 0.85

    enum PrepareError: Error {
        case undecodable, unencodable
    }

    init(id: UUID = UUID(), mimeType: String, dataURL: String, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.mimeType = mimeType
        self.dataURL = dataURL
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// Anything ImageIO reads (HEIC from Photos, JPEG from the camera, PNG screenshots), prepared for sending.
    static func prepare(_ data: Data) throws -> ComposerPicture {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw PrepareError.undecodable }
        // The thumbnail applies the EXIF orientation, so the size asked for is the longest side either way.
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixelSize),
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw PrepareError.undecodable
        }
        let keepsAlpha = (properties[kCGImagePropertyHasAlpha] as? Bool) == true
        let type = keepsAlpha ? UTType.png : UTType.jpeg
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, type.identifier as CFString, 1, nil) else {
            throw PrepareError.unencodable
        }
        let quality = keepsAlpha ? nil : [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, quality)
        guard CGImageDestinationFinalize(destination) else { throw PrepareError.unencodable }
        let mimeType = keepsAlpha ? "image/png" : "image/jpeg"
        return ComposerPicture(
            mimeType: mimeType, dataURL: "data:\(mimeType);base64,\((encoded as Data).base64EncodedString())",
            pixelWidth: image.width, pixelHeight: image.height)
    }

    /// Off the main actor: a 48 MP photo takes a moment to decode.
    @concurrent
    static func prepared(_ data: Data) async throws -> ComposerPicture {
        try prepare(data)
    }
}

/// The pictures the next message carries, in pick order, at most `limit` (the menu's photo entries are off at the
/// limit, and the photo picker is told the room left).
public struct ComposerAttachments: Equatable, Sendable {
    public static let limit = 10

    public private(set) var pictures: [ComposerPicture] = []

    public init() {}

    public var isEmpty: Bool { pictures.isEmpty }
    public var isFull: Bool { pictures.count >= Self.limit }
    /// How many more fit: the photo picker's selection limit.
    public var room: Int { max(0, Self.limit - pictures.count) }

    /// Adds in order as many as fit; returns how many did not.
    @discardableResult
    public mutating func append(_ more: [ComposerPicture]) -> Int {
        let fitting = more.prefix(room)
        pictures += fitting
        return more.count - fitting.count
    }

    public mutating func remove(_ id: ComposerPicture.ID) {
        pictures.removeAll { $0.id == id }
    }

    public mutating func removeAll() {
        pictures.removeAll()
    }
}

/// A user message's `content` as the desktop's `send` builds it (`use-chat.ts`): text alone is a plain string; with
/// pictures it is an array — the text block when there is text, then one image block per picture, in order.
enum ComposerContent {
    static func content(text: String, pictures: [ComposerPicture]) -> JSONValue {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pictures.isEmpty else { return .string(text) }
        var blocks: [JSONValue] = []
        if !text.isEmpty {
            blocks.append(.object(["type": .string("text"), "text": .string(text)]))
        }
        for picture in pictures {
            blocks.append(
                .object([
                    "type": .string("image"), "mimeType": .string(picture.mimeType), "data": .string(picture.dataURL),
                ]))
        }
        return .array(blocks)
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ComposerPictureTests -only-testing:ChatFeatureTests/ComposerAttachmentsTests -only-testing:ChatFeatureTests/ComposerContentTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `Test run with 16 tests passed`, `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1          # 0 error(s)
git diff --stat                                       # unchanged from the start of the task
.superpowers/sdd/commit-mine.sh "feat(chat): a picked picture is prepared on the phone — upright, at most 2048 px on its longest side, JPEG unless it has transparency — and the composer holds ten" \
  Sources/ChatFeature/ComposerPicture.swift Tests/ChatFeatureTests/ComposerPictureTests.swift
git show --stat HEAD
```

---

### Task 3: `ComposerTools` — the session's choices, the model's levels, the MCP tools

**Files:**
- Create: `Sources/ChatFeature/ComposerTools.swift`
- Test: `Tests/ChatFeatureTests/ComposerToolsTests.swift`

**Interfaces:**
- Consumes: `ReasoningEffort`, `TurnOptions` (Task 1); `SettingsSnapshot`, `McpToolsResponse` (Models); `APIClient.get` (NetworkingKit).
- Produces:
  - `@MainActor @Observable public final class ComposerTools { public init(); private(set) var reasoningEffort: ReasoningEffort; private(set) var deepResearch: Bool; private(set) var reasoningLevels: [ReasoningEffort]; private(set) var mcpGroups: [McpToolsResponse.Group]; var mcpToolCount: Int; var isActive: Bool; var turnOptions: TurnOptions; func setEffort(_:); func setDeepResearch(_:); func adopt(reasoningLevels: [String]); func adopt(mcpTools: McpToolsResponse); static func levels(_ supported: [String]) -> [ReasoningEffort]; func refresh(from: ComposerToolsSource) async }` (all members public except `levels`).
  - `public struct ComposerToolsSource: Sendable { var reasoningLevels: @Sendable () async throws -> [String]; var mcpTools: @Sendable () async throws -> McpToolsResponse; public init(reasoningLevels:mcpTools:); public init(apiClient: APIClient) }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ChatFeatureTests/ComposerToolsTests.swift`:

```swift
import Foundation
import Models
import Testing

@testable import ChatFeature

private let mcpJSON = #"""
    {"tools":[{"mcpServerName":"files","tools":[{"name":"read_file","description":"Reads a file."},{"name":"write_file","description":""}]},
              {"mcpServerName":"github","tools":[{"name":"search_issues","description":"Searches issues."}]},
              {"mcpServerName":"idle","tools":[]}]}
    """#

/// A computer that answers with `levels` and `tools` (JSON), or fails where one is nil.
private func source(levels: [String]?, tools: String?) -> ComposerToolsSource {
    ComposerToolsSource(
        reasoningLevels: {
            guard let levels else { throw URLError(.cannotConnectToHost) }
            return levels
        },
        mcpTools: {
            guard let tools else { throw URLError(.cannotConnectToHost) }
            return try JSONDecoder().decode(McpToolsResponse.self, from: Data(tools.utf8))
        })
}

@MainActor
@Suite("The composer's + choices")
struct ComposerToolsTests {
    private func tools(levels: [String] = ["off", "low", "medium", "high", "xhigh", "max"]) -> ComposerTools {
        let tools = ComposerTools()
        tools.adopt(reasoningLevels: levels)
        return tools
    }

    @Test("nothing is on at first")
    func startsOff() {
        let tools = ComposerTools()
        #expect(tools.reasoningEffort == .off && !tools.deepResearch && !tools.isActive)
        #expect(tools.turnOptions == TurnOptions())
        #expect(tools.reasoningLevels.isEmpty && tools.mcpToolCount == 0)
    }

    @Test("turning Deep Research on sets the effort off")
    func deepResearchTurnsTheEffortOff() {
        let tools = tools()
        tools.setEffort(.high)
        tools.setDeepResearch(true)
        #expect(tools.reasoningEffort == .off)
        #expect(tools.turnOptions == TurnOptions(deepResearch: true))
        #expect(tools.isActive)
    }

    @Test("picking a level other than off turns Deep Research off")
    func aLevelTurnsDeepResearchOff() {
        let tools = tools()
        tools.setDeepResearch(true)
        tools.setEffort(.low)
        #expect(!tools.deepResearch)
        #expect(tools.turnOptions == TurnOptions(reasoningEffort: .low))
    }

    @Test("picking off leaves Deep Research on")
    func offKeepsDeepResearch() {
        let tools = tools()
        tools.setDeepResearch(true)
        tools.setEffort(.off)
        #expect(tools.deepResearch)
    }

    @Test("the levels are off first, then the model's in the desktop's order; unknown names are ignored")
    func levelsInOrder() {
        #expect(ComposerTools.levels(["high", "off", "low", "bogus"]) == [.off, .low, .high])
        #expect(ComposerTools.levels(["medium"]) == [.off, .medium])
    }

    @Test("a model that does not reason hides the entry")
    func noReasoning() {
        #expect(ComposerTools.levels([]) == [])
        #expect(ComposerTools.levels(["off"]) == [])
    }

    @Test("a level the new model lacks falls back to off; one it has is kept")
    func fallback() {
        let tools = tools()
        tools.setEffort(.max)
        tools.adopt(reasoningLevels: ["off", "low", "high"])
        #expect(tools.reasoningEffort == .off)
        tools.setEffort(.high)
        tools.adopt(reasoningLevels: ["off", "high"])
        #expect(tools.reasoningEffort == .high)
        tools.adopt(reasoningLevels: [])
        #expect(tools.reasoningEffort == .off)
    }

    @Test("a level the model does not offer cannot be picked")
    func unsupportedLevel() {
        let tools = tools(levels: ["off", "low"])
        tools.setEffort(.max)
        #expect(tools.reasoningEffort == .off)
    }

    @Test("a refresh reads the model's levels and the connected servers' tools")
    func refresh() async {
        let tools = ComposerTools()
        await tools.refresh(from: source(levels: ["off", "medium"], tools: mcpJSON))
        #expect(tools.reasoningLevels == [.off, .medium])
        #expect(tools.mcpToolCount == 3)
        #expect(tools.mcpGroups.map(\.mcpServerName) == ["files", "github"])
    }

    @Test("a refresh to a model without the chosen level turns it off")
    func aRefreshToAModelWithoutTheLevelTurnsItOff() async {
        let tools = ComposerTools()
        await tools.refresh(from: source(levels: ["off", "low", "high"], tools: mcpJSON))
        tools.setEffort(.high)
        await tools.refresh(from: source(levels: ["off", "low"], tools: mcpJSON))
        #expect(tools.reasoningEffort == .off)
        #expect(tools.turnOptions.wireReasoningEffort == nil)
    }

    @Test("a failed refresh keeps what was known")
    func aFailedRefreshKeepsWhatWasKnown() async {
        let tools = ComposerTools()
        await tools.refresh(from: source(levels: ["off", "high"], tools: mcpJSON))
        tools.setEffort(.high)
        await tools.refresh(from: source(levels: nil, tools: nil))
        #expect(tools.reasoningLevels == [.off, .high])
        #expect(tools.reasoningEffort == .high)
        #expect(tools.mcpToolCount == 3)
    }

    @Test("a computer never reached hides Reasoning and MCP Tools, and Deep Research still works")
    func neverReached() async {
        let tools = ComposerTools()
        await tools.refresh(from: source(levels: nil, tools: nil))
        #expect(tools.reasoningLevels.isEmpty && tools.mcpToolCount == 0)
        tools.setDeepResearch(true)
        #expect(tools.turnOptions.advancedTools == ["Deep Research"])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
git diff --stat
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ComposerToolsTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'ComposerTools' in scope`, `TEST FAILED`.

- [ ] **Step 3: Write `ComposerTools.swift`**

Create `Sources/ChatFeature/ComposerTools.swift`:

```swift
import Foundation
import Models
import NetworkingKit
import Observation

/// The composer's `+` choices for the whole app session, as the desktop's atoms keep them: a reasoning effort and Deep
/// Research, which exclude each other (`useAdvancedToolToggle`), and what the menu needs to know — the efforts the
/// current model supports and the tools the computer's MCP servers offer. One instance, made by the app shell and
/// handed to each chat screen; a turn reads `turnOptions` when it starts.
@MainActor
@Observable
public final class ComposerTools {
    public private(set) var reasoningEffort: ReasoningEffort = .off
    public private(set) var deepResearch = false
    /// What the Reasoning submenu offers, `off` first. Empty — the entry hidden — for a model that does not reason, or
    /// before the computer's settings have been read once.
    public private(set) var reasoningLevels: [ReasoningEffort] = []
    /// The connected servers' tools, by server, for the read-only sheet.
    public private(set) var mcpGroups: [McpToolsResponse.Group] = []

    public init() {}

    public var mcpToolCount: Int { mcpGroups.reduce(0) { $0 + $1.tools.count } }

    /// Something is on: the `+` is tinted and pills show.
    public var isActive: Bool { deepResearch || reasoningEffort != .off }

    public var turnOptions: TurnOptions { TurnOptions(deepResearch: deepResearch, reasoningEffort: reasoningEffort) }

    /// A level the model offers (or off). One other than off turns Deep Research off.
    public func setEffort(_ level: ReasoningEffort) {
        guard level == .off || reasoningLevels.contains(level) else { return }
        reasoningEffort = level
        if level != .off { deepResearch = false }
    }

    /// Turning Deep Research on sets the effort off.
    public func setDeepResearch(_ on: Bool) {
        deepResearch = on
        if on { reasoningEffort = .off }
    }

    /// The levels of the model now selected (`modelSnapshot.reasoningLevels`). A chosen level it lacks falls back to off.
    public func adopt(reasoningLevels supported: [String]) {
        reasoningLevels = Self.levels(supported)
        if !reasoningLevels.contains(reasoningEffort) { reasoningEffort = .off }
    }

    /// The connected servers' tools; a server with none is left out.
    public func adopt(mcpTools: McpToolsResponse) {
        mcpGroups = mcpTools.tools.filter { !$0.tools.isEmpty }
    }

    /// Off first, then the known levels the model lists, in the desktop's order; none when it lists no level but off.
    static func levels(_ supported: [String]) -> [ReasoningEffort] {
        let levels = ReasoningEffort.allCases.filter { $0 != .off && supported.contains($0.rawValue) }
        return levels.isEmpty ? [] : [.off] + levels
    }

    /// Reads the current model's levels and the MCP tools again. A read that fails keeps what was known: an entry is
    /// hidden only while nothing is.
    public func refresh(from source: ComposerToolsSource) async {
        async let levels = try? source.reasoningLevels()
        async let tools = try? source.mcpTools()
        if let levels = await levels { adopt(reasoningLevels: levels) }
        if let tools = await tools { adopt(mcpTools: tools) }
    }
}

/// Where `ComposerTools` reads from: the computer, or a test's stand-in.
public struct ComposerToolsSource: Sendable {
    public var reasoningLevels: @Sendable () async throws -> [String]
    public var mcpTools: @Sendable () async throws -> McpToolsResponse

    public init(
        reasoningLevels: @escaping @Sendable () async throws -> [String],
        mcpTools: @escaping @Sendable () async throws -> McpToolsResponse
    ) {
        self.reasoningLevels = reasoningLevels
        self.mcpTools = mcpTools
    }
}

extension ComposerToolsSource {
    /// `GET /api/v1/settings` (the selected model's snapshot, the desktop's `useAvailableEffortLevels`) and
    /// `GET /api/v1/mcp/tools`, through the paired session.
    public init(apiClient: APIClient) {
        self.init(
            reasoningLevels: {
                let settings: SettingsSnapshot = try await apiClient.get("/api/v1/settings")
                return settings.providerConfig?.modelSnapshot?.reasoningLevels ?? []
            },
            mcpTools: { try await apiClient.get("/api/v1/mcp/tools") })
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ComposerToolsTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `Test run with 12 tests passed`, `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1          # 0 error(s)
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(chat): the composer's + choices for the app session — a reasoning effort or Deep Research, never both, the model's levels with a fallback to off, and the MCP tools" \
  Sources/ChatFeature/ComposerTools.swift Tests/ChatFeatureTests/ComposerToolsTests.swift
git show --stat HEAD
```

---

### Task 4: The strings, in ten languages, and the camera prompt

`Resources/App/Localizable.xcstrings` carries the user's uncommitted edits. The keys are inserted *textually* (each in its sorted place, in Xcode's formatting) into the working catalog and, identically, into a copy of the committed one; the commit is the difference between the committed catalog and that copy, so only these keys enter it. `Resources/App/InfoPlist.xcstrings` and `Project.swift` are clean and committed whole.

**Files:**
- Create: `Sources/ChatFeature/ComposerText.swift`
- Modify: `Resources/App/Localizable.xcstrings` (20 new keys, patch), `Resources/App/InfoPlist.xcstrings` (`NSCameraUsageDescription`), `Project.swift:62-63`
- Test: `Tests/ChatFeatureTests/ComposerTextTests.swift`

**Interfaces:**
- Consumes: `ReasoningEffort` (Task 1).
- Produces: `enum ComposerText { static func level(_: ReasoningEffort) -> String; static func reasoningPill(_: ReasoningEffort) -> String; static func removePicture(_ position: Int, of count: Int) -> String; static func unreadable(_ count: Int) -> String; static func noDescription(_ name: String) -> String }`, and these keys (exact English; every `defaultValue:` must match):

| Key | English |
|---|---|
| `ios:chat.composer.photoLibrary` | Photo Library |
| `ios:chat.composer.takePhoto` | Take Photo |
| `ios:chat.composer.reasoning` | Reasoning |
| `ios:chat.composer.level.off` | Off |
| `ios:chat.composer.level.low` | Low |
| `ios:chat.composer.level.medium` | Medium |
| `ios:chat.composer.level.high` | High |
| `ios:chat.composer.level.xhigh` | Extra high |
| `ios:chat.composer.level.max` | Max |
| `ios:chat.composer.reasoningPill` | Reasoning: %@ |
| `ios:chat.composer.deepResearch` | Deep Research |
| `ios:chat.composer.mcpTools` | MCP Tools |
| `ios:chat.composer.mcpSheet.title` | Available MCP Tools |
| `ios:chat.composer.mcpSheet.description` | Tools from the MCP servers that are on. Turn servers on or off in Settings › MCP Servers. |
| `ios:chat.composer.mcpSheet.noDescription` | No description for %@. |
| `ios:chat.composer.removePicture` | Remove picture %lld of %lld |
| `ios:chat.composer.turnOff` | Turns it off. |
| `ios:chat.composer.unreadableOne` | A picture couldn’t be read and was left out. |
| `ios:chat.composer.unreadableSome` | %lld pictures couldn’t be read and were left out. |
| `ios:chat.composer.cameraDeniedMessage` | Allow Exodus to use the camera in Settings to take a photo for this chat. |

- [ ] **Step 1: Write the failing test**

Create `Tests/ChatFeatureTests/ComposerTextTests.swift`:

```swift
import Foundation
import Models
import Testing

@testable import ChatFeature

/// The English the catalog's keys fall back to (the test bundle carries no catalog).
@Suite("The composer's strings")
struct ComposerTextTests {
    @Test("the levels read as on the desktop")
    func levels() {
        #expect(ReasoningEffort.allCases.map(ComposerText.level) == ["Off", "Low", "Medium", "High", "Extra high", "Max"])
    }

    @Test("the reasoning pill names the level")
    func pill() {
        #expect(ComposerText.reasoningPill(.high) == "Reasoning: High")
        #expect(ComposerText.reasoningPill(.xhigh) == "Reasoning: Extra high")
    }

    @Test("a picture's ✕ says which picture it removes")
    func removePicture() {
        #expect(ComposerText.removePicture(2, of: 3) == "Remove picture 2 of 3")
    }

    @Test("one unreadable picture, and several")
    func unreadable() {
        #expect(ComposerText.unreadable(1) == "A picture couldn’t be read and was left out.")
        #expect(ComposerText.unreadable(3) == "3 pictures couldn’t be read and were left out.")
    }

    @Test("a tool without a description says so")
    func noDescription() {
        #expect(ComposerText.noDescription("get_me") == "No description for get_me.")
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
git diff --stat                                        # note the catalog's foreign edits before you start
git diff --stat -- Resources/App/InfoPlist.xcstrings Project.swift   # must print nothing: both are committed whole
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ComposerTextTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'ComposerText' in scope`, `TEST FAILED`.

- [ ] **Step 3: Write the key script**

Create `/tmp/composer/add_keys.py`:

```python
# Inserts the composer's keys into the String Catalog named on the command line, each in its sorted place and in
# Xcode's own formatting, without rewriting any other line (so the user's uncommitted edits stay as they are).
# Usage, from the repo root: python3 /tmp/composer/add_keys.py CATALOG
import json
import sys

LANGS = ["de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "zh-HK", "zh-Hant"]

# (key, comment, {language: text}) — English first in each row, then the nine others.
KEYS = [
    ("ios:chat.composer.photoLibrary", "Composer + menu: pick pictures from the photo library to send with the next message.",
     {"en": "Photo Library", "de": "Fotomediathek", "es": "Fototeca", "fr": "Photothèque", "it": "Libreria foto", "ja": "写真ライブラリ", "ko": "사진 보관함", "pt-BR": "Fototeca", "zh-HK": "相片圖庫", "zh-Hant": "照片圖庫"}),
    ("ios:chat.composer.takePhoto", "Composer + menu: take a photo with the camera to send with the next message.",
     {"en": "Take Photo", "de": "Foto aufnehmen", "es": "Hacer foto", "fr": "Prendre une photo", "it": "Scatta foto", "ja": "写真を撮る", "ko": "사진 찍기", "pt-BR": "Tirar foto", "zh-HK": "影相", "zh-Hant": "拍照"}),
    ("ios:chat.composer.reasoning", "Composer + menu: submenu choosing how much the model reasons before answering.",
     {"en": "Reasoning", "de": "Reasoning", "es": "Razonamiento", "fr": "Raisonnement", "it": "Ragionamento", "ja": "推論", "ko": "추론", "pt-BR": "Raciocínio", "zh-HK": "推理", "zh-Hant": "推理"}),
    ("ios:chat.composer.level.off", "Reasoning level: no reasoning.",
     {"en": "Off", "de": "Aus", "es": "Desactivado", "fr": "Désactivé", "it": "Disattivato", "ja": "オフ", "ko": "끄기", "pt-BR": "Desativado", "zh-HK": "關閉", "zh-Hant": "關閉"}),
    ("ios:chat.composer.level.low", "Reasoning level: low effort.",
     {"en": "Low", "de": "Niedrig", "es": "Bajo", "fr": "Faible", "it": "Basso", "ja": "低", "ko": "낮음", "pt-BR": "Baixo", "zh-HK": "低", "zh-Hant": "低"}),
    ("ios:chat.composer.level.medium", "Reasoning level: medium effort.",
     {"en": "Medium", "de": "Mittel", "es": "Medio", "fr": "Moyen", "it": "Medio", "ja": "中", "ko": "보통", "pt-BR": "Médio", "zh-HK": "中", "zh-Hant": "中"}),
    ("ios:chat.composer.level.high", "Reasoning level: high effort.",
     {"en": "High", "de": "Hoch", "es": "Alto", "fr": "Élevé", "it": "Alto", "ja": "高", "ko": "높음", "pt-BR": "Alto", "zh-HK": "高", "zh-Hant": "高"}),
    ("ios:chat.composer.level.xhigh", "Reasoning level: above high.",
     {"en": "Extra high", "de": "Sehr hoch", "es": "Extra alto", "fr": "Très élevé", "it": "Molto alto", "ja": "非常に高い", "ko": "매우 높음", "pt-BR": "Extra alto", "zh-HK": "超高", "zh-Hant": "超高"}),
    ("ios:chat.composer.level.max", "Reasoning level: the most the model allows.",
     {"en": "Max", "de": "Maximal", "es": "Máximo", "fr": "Maximum", "it": "Massimo", "ja": "最大", "ko": "최대", "pt-BR": "Máximo", "zh-HK": "最高", "zh-Hant": "最高"}),
    ("ios:chat.composer.reasoningPill", "Pill over the message field while a reasoning level is on; tapping it turns reasoning off. %@ is the level, e.g. High.",
     {"en": "Reasoning: %@", "de": "Reasoning: %@", "es": "Razonamiento: %@", "fr": "Raisonnement : %@", "it": "Ragionamento: %@", "ja": "推論: %@", "ko": "추론: %@", "pt-BR": "Raciocínio: %@", "zh-HK": "推理：%@", "zh-Hant": "推理：%@"}),
    ("ios:chat.composer.deepResearch", "Composer + menu toggle, and the pill over the message field while it is on: the next message starts a Deep Research.",
     {"en": "Deep Research", "de": "Tiefenrecherche", "es": "Investigación profunda", "fr": "Recherche approfondie", "it": "Ricerca approfondita", "ja": "ディープリサーチ", "ko": "심층 리서치", "pt-BR": "Pesquisa aprofundada", "zh-HK": "深度研究", "zh-Hant": "深度研究"}),
    ("ios:chat.composer.mcpTools", "Composer + menu: opens the list of tools the computer's MCP servers offer. MCP is the Model Context Protocol.",
     {"en": "MCP Tools", "de": "MCP-Tools", "es": "Herramientas MCP", "fr": "Outils MCP", "it": "Strumenti MCP", "ja": "MCPツール", "ko": "MCP 도구", "pt-BR": "Ferramentas MCP", "zh-HK": "MCP 工具", "zh-Hant": "MCP 工具"}),
    ("ios:chat.composer.mcpSheet.title", "Title of the sheet listing the MCP servers' tools.",
     {"en": "Available MCP Tools", "de": "Verfügbare MCP-Tools", "es": "Herramientas MCP disponibles", "fr": "Outils MCP disponibles", "it": "Strumenti MCP disponibili", "ja": "利用可能なMCPツール", "ko": "사용 가능한 MCP 도구", "pt-BR": "Ferramentas MCP disponíveis", "zh-HK": "可用的 MCP 工具", "zh-Hant": "可用的 MCP 工具"}),
    ("ios:chat.composer.mcpSheet.description", "Under the MCP tools sheet's title. Settings › MCP Servers is this app's Settings page of that name.",
     {"en": "Tools from the MCP servers that are on. Turn servers on or off in Settings › MCP Servers.",
      "de": "Tools der aktiven MCP-Server. Server schalten Sie unter Einstellungen › MCP-Server ein oder aus.",
      "es": "Herramientas de los servidores MCP activos. Activa o desactiva servidores en Ajustes › Servidores MCP.",
      "fr": "Outils des serveurs MCP actifs. Activez ou désactivez des serveurs dans Réglages › Serveurs MCP.",
      "it": "Strumenti dei server MCP attivi. Attiva o disattiva i server in Impostazioni › Server MCP.",
      "ja": "有効なMCPサーバーのツールです。サーバーのオン／オフは「設定」›「MCPサーバー」で切り替えられます。",
      "ko": "켜져 있는 MCP 서버의 도구입니다. 설정 › MCP 서버에서 서버를 켜거나 끌 수 있습니다.",
      "pt-BR": "Ferramentas dos servidores MCP ativos. Ative ou desative servidores em Ajustes › Servidores MCP.",
      "zh-HK": "已開啟的 MCP 伺服器所提供的工具。可在「設定」›「MCP 伺服器」中開啟或關閉伺服器。",
      "zh-Hant": "已開啟的 MCP 伺服器所提供的工具。可在「設定」›「MCP 伺服器」中開啟或關閉伺服器。"}),
    ("ios:chat.composer.mcpSheet.noDescription", "MCP tools sheet: a tool its server gave no description. %@ is the tool's name.",
     {"en": "No description for %@.", "de": "Keine Beschreibung für %@.", "es": "Sin descripción para %@.", "fr": "Aucune description pour %@.", "it": "Nessuna descrizione per %@.", "ja": "%@の説明はありません。", "ko": "%@에 대한 설명이 없습니다.", "pt-BR": "Nenhuma descrição para %@.", "zh-HK": "%@ 沒有說明。", "zh-Hant": "%@ 沒有說明。"}),
    ("ios:chat.composer.removePicture", "VoiceOver label of the ✕ on a picture waiting in the composer. The first %lld is its position, the second how many there are.",
     {"en": "Remove picture %lld of %lld", "de": "Bild %lld von %lld entfernen", "es": "Quitar imagen %lld de %lld", "fr": "Retirer l’image %lld sur %lld", "it": "Rimuovi immagine %lld di %lld", "ja": "%2$lld枚中%1$lld枚目の画像を削除", "ko": "%2$lld개 중 %1$lld번째 사진 제거", "pt-BR": "Remover imagem %lld de %lld", "zh-HK": "移除第 %1$lld 張相片（共 %2$lld 張）", "zh-Hant": "移除第 %1$lld 張照片（共 %2$lld 張）"}),
    ("ios:chat.composer.turnOff", "VoiceOver hint of a pill over the message field (Reasoning, Deep Research): tapping it turns that choice off.",
     {"en": "Turns it off.", "de": "Schaltet es aus.", "es": "Lo desactiva.", "fr": "Le désactive.", "it": "Lo disattiva.", "ja": "オフにします。", "ko": "끕니다.", "pt-BR": "Desativa.", "zh-HK": "關閉此選項。", "zh-Hant": "關閉此選項。"}),
    ("ios:chat.composer.unreadableOne", "Banner over the composer: one of the pictures just picked could not be read, so it was not added.",
     {"en": "A picture couldn’t be read and was left out.", "de": "Ein Bild konnte nicht gelesen werden und wurde weggelassen.", "es": "No se pudo leer una imagen y se ha omitido.", "fr": "Une image n’a pas pu être lue et a été ignorée.", "it": "Non è stato possibile leggere un’immagine, che è stata esclusa.", "ja": "読み込めない画像が1枚あったため、除外しました。", "ko": "사진 1장을 읽을 수 없어 제외했습니다.", "pt-BR": "Não foi possível ler uma imagem, e ela foi deixada de fora.", "zh-HK": "有 1 張相片無法讀取，已略過。", "zh-Hant": "有 1 張照片無法讀取，已略過。"}),
    ("ios:chat.composer.unreadableSome", "Banner over the composer: several pictures just picked could not be read, so they were not added. %lld is how many (2 or more).",
     {"en": "%lld pictures couldn’t be read and were left out.", "de": "%lld Bilder konnten nicht gelesen werden und wurden weggelassen.", "es": "No se pudieron leer %lld imágenes y se han omitido.", "fr": "%lld images n’ont pas pu être lues et ont été ignorées.", "it": "Non è stato possibile leggere %lld immagini, che sono state escluse.", "ja": "読み込めない画像が%lld枚あったため、除外しました。", "ko": "사진 %lld장을 읽을 수 없어 제외했습니다.", "pt-BR": "Não foi possível ler %lld imagens, e elas foram deixadas de fora.", "zh-HK": "有 %lld 張相片無法讀取，已略過。", "zh-Hant": "有 %lld 張照片無法讀取，已略過。"}),
    ("ios:chat.composer.cameraDeniedMessage", "Alert when Take Photo is chosen but camera access was refused. Exodus is the app's name and stays as is.",
     {"en": "Allow Exodus to use the camera in Settings to take a photo for this chat.", "de": "Erlauben Sie Exodus in den Einstellungen den Kamerazugriff, um ein Foto für diesen Chat aufzunehmen.", "es": "Permite que Exodus use la cámara en Ajustes para hacer una foto para este chat.", "fr": "Autorisez Exodus à utiliser l’appareil photo dans les Réglages pour prendre une photo pour cette discussion.", "it": "Consenti a Exodus di usare la fotocamera nelle Impostazioni per scattare una foto per questa chat.", "ja": "このチャット用に写真を撮るには、「設定」で Exodus にカメラの使用を許可してください。", "ko": "이 채팅에 사진을 찍으려면 설정에서 Exodus의 카메라 사용을 허용하세요.", "pt-BR": "Permita que o Exodus use a câmera nos Ajustes para tirar uma foto para este chat.", "zh-HK": "請在「設定」中允許 Exodus 使用相機，以便為這個對話影相。", "zh-Hant": "請在「設定」中允許 Exodus 使用相機，以便為這個聊天拍照。"}),
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
    # Before the first key, in file order, that sorts after this one: the catalog is sorted (one stray entry at
    # its very end sorts after every ios:chat key, so it is never the one found).
    after = next(k for k in keys if k > key)
    marker = "\n    " + json.dumps(after, ensure_ascii=False) + " : {\n"
    assert text.count(marker) == 1, after
    text = text.replace(marker, "\n" + block(key, comment, values) + "," + marker, 1)
json.loads(text)  # still a catalog
open(path, "w", encoding="utf-8").write(text)
print("added", len(KEYS), "keys to", path)
```

(This script was dry-run on copies of both catalogs on 2026-10-02: 20 keys, 1 320 added lines, every placeholder set matching English.)

- [ ] **Step 4: Apply it to the working catalog and to a copy of the committed one, and verify**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git show HEAD:Resources/App/Localizable.xcstrings > /tmp/composer/head.xcstrings
cp /tmp/composer/head.xcstrings /tmp/composer/mine.xcstrings
python3 /tmp/composer/add_keys.py /tmp/composer/mine.xcstrings
python3 /tmp/composer/add_keys.py Resources/App/Localizable.xcstrings
python3 - <<'PY'
import json
work = json.load(open('Resources/App/Localizable.xcstrings', encoding='utf-8'))['strings']
mine = json.load(open('/tmp/composer/mine.xcstrings', encoding='utf-8'))['strings']
head = json.load(open('/tmp/composer/head.xcstrings', encoding='utf-8'))['strings']
new = sorted(set(mine) - set(head))
assert len(new) == 20, len(new)
for k in new:
    assert work.get(k) == mine[k], k
    assert set(mine[k]['localizations']) == {'en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pt-BR', 'zh-Hant', 'zh-HK'}, k
print('OK', len(new))
PY
```
Expected: `added 20 keys …` twice, then `OK 20`.

- [ ] **Step 5: Write `ComposerText.swift`**

Create `Sources/ChatFeature/ComposerText.swift`:

```swift
import Foundation
import Models

/// The composer's `+` strings that code puts together; the views use the other keys as literals.
enum ComposerText {
    static func level(_ level: ReasoningEffort) -> String {
        switch level {
        case .off:
            String(localized: "ios:chat.composer.level.off", defaultValue: "Off", comment: "Reasoning level: no reasoning.")
        case .low:
            String(localized: "ios:chat.composer.level.low", defaultValue: "Low", comment: "Reasoning level: low effort.")
        case .medium:
            String(
                localized: "ios:chat.composer.level.medium", defaultValue: "Medium",
                comment: "Reasoning level: medium effort.")
        case .high:
            String(localized: "ios:chat.composer.level.high", defaultValue: "High", comment: "Reasoning level: high effort.")
        case .xhigh:
            String(
                localized: "ios:chat.composer.level.xhigh", defaultValue: "Extra high",
                comment: "Reasoning level: above high.")
        case .max:
            String(
                localized: "ios:chat.composer.level.max", defaultValue: "Max",
                comment: "Reasoning level: the most the model allows.")
        }
    }

    static func reasoningPill(_ level: ReasoningEffort) -> String {
        let name = Self.level(level)
        return String(
            localized: "ios:chat.composer.reasoningPill", defaultValue: "Reasoning: \(name)",
            comment: "Pill over the message field while a reasoning level is on. %@ is the level, e.g. High.")
    }

    static func removePicture(_ position: Int, of count: Int) -> String {
        String(
            localized: "ios:chat.composer.removePicture", defaultValue: "Remove picture \(position) of \(count)",
            comment: "VoiceOver label of the ✕ on a picture waiting in the composer.")
    }

    static func unreadable(_ count: Int) -> String {
        if count == 1 {
            return String(
                localized: "ios:chat.composer.unreadableOne", defaultValue: "A picture couldn’t be read and was left out.",
                comment: "Banner over the composer: one picked picture could not be read.")
        }
        return String(
            localized: "ios:chat.composer.unreadableSome",
            defaultValue: "\(count) pictures couldn’t be read and were left out.",
            comment: "Banner over the composer: several picked pictures could not be read. %lld is how many.")
    }

    static func noDescription(_ name: String) -> String {
        String(
            localized: "ios:chat.composer.mcpSheet.noDescription", defaultValue: "No description for \(name).",
            comment: "MCP tools sheet: a tool its server gave no description. %@ is the tool's name.")
    }
}
```

- [ ] **Step 6: Run the test and the audit**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ComposerTextTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: `Test run with 5 tests passed`; audit `0 error(s)` (the 11 keys only views use show as "not referenced" warnings until Task 6).

- [ ] **Step 7: Widen the camera prompt**

In `Project.swift` (`:62-63`), replace

```swift
                        "Exodus uses the camera to scan the pairing code shown on your computer.",
```

with

```swift
                        "Exodus uses the camera to scan the pairing code shown on your computer, and to take photos you add to a chat.",
```

Then set the localized text (the file is clean; this load-and-save keeps Xcode's formatting — it round-trips byte for byte):

```bash
python3 - <<'PY'
import json
path = 'Resources/App/InfoPlist.xcstrings'
catalog = json.load(open(path, encoding='utf-8'))
entry = catalog['strings']['NSCameraUsageDescription']
entry['comment'] = "Camera permission prompt: scanning the pairing code, and taking photos for a chat. Exodus is the app's name and stays as is."
text = {
    'en': "Exodus uses the camera to scan the pairing code shown on your computer, and to take photos you add to a chat.",
    'de': "Exodus verwendet die Kamera, um den auf Ihrem Computer angezeigten Kopplungscode zu scannen und Fotos aufzunehmen, die Sie einem Chat hinzufügen.",
    'es': "Exodus usa la cámara para escanear el código de vinculación que aparece en tu ordenador y para hacer fotos que añades a un chat.",
    'fr': "Exodus utilise l’appareil photo pour scanner le code de jumelage affiché sur votre ordinateur et pour prendre les photos que vous ajoutez à une discussion.",
    'it': "Exodus usa la fotocamera per scansionare il codice di abbinamento mostrato sul tuo computer e per scattare le foto che aggiungi a una chat.",
    'ja': "Exodus はコンピュータに表示されたペアリングコードのスキャンと、チャットに追加する写真の撮影にカメラを使用します。",
    'ko': "Exodus는 컴퓨터에 표시된 페어링 코드를 스캔하고 채팅에 추가할 사진을 찍기 위해 카메라를 사용합니다.",
    'pt-BR': "O Exodus usa a câmera para escanear o código de pareamento exibido no seu computador e para tirar fotos que você adiciona a um chat.",
    'zh-HK': "Exodus 使用相機掃描電腦上顯示的配對碼，以及拍攝你加入對話的相片。",
    'zh-Hant': "Exodus 使用相機掃描電腦上顯示的配對碼，以及拍攝你加入聊天的照片。",
}
assert set(entry['localizations']) == set(text)
for lang, value in text.items():
    entry['localizations'][lang]['stringUnit']['value'] = value
open(path, 'w', encoding='utf-8').write(
    json.dumps(catalog, indent=2, separators=(',', ' : '), ensure_ascii=False, sort_keys=True) + '\n')
PY
git diff --stat -- Resources/App/InfoPlist.xcstrings Project.swift      # InfoPlist ~11 lines, Project.swift 1 line
tuist generate --no-open
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
plutil -p /tmp/composer-dd/Build/Products/Debug-iphonesimulator/Exodus.app/Info.plist | grep NSCameraUsageDescription
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: `** BUILD SUCCEEDED **`; the plist line shows the new English; `0 error(s)`.

- [ ] **Step 8: Build the catalog patch and commit**

```bash
python3 - <<'PY'
import difflib
head = open('/tmp/composer/head.xcstrings', encoding='utf-8').read().splitlines(keepends=True)
mine = open('/tmp/composer/mine.xcstrings', encoding='utf-8').read().splitlines(keepends=True)
with open('/tmp/composer/catalog.patch', 'w', encoding='utf-8') as f:
    f.writelines(difflib.unified_diff(head, mine, 'a/Resources/App/Localizable.xcstrings', 'b/Resources/App/Localizable.xcstrings'))
PY
GIT_INDEX_FILE=/tmp/composer/check.idx git read-tree HEAD
GIT_INDEX_FILE=/tmp/composer/check.idx git apply --cached --check /tmp/composer/catalog.patch && echo PATCH-OK
rm -f /tmp/composer/check.idx
.superpowers/sdd/commit-mine.sh "feat(chat): the composer's + strings in ten languages, and a camera prompt that also covers taking photos for a chat" \
  --patch /tmp/composer/catalog.patch \
  Sources/ChatFeature/ComposerText.swift Tests/ChatFeatureTests/ComposerTextTests.swift \
  Resources/App/InfoPlist.xcstrings Project.swift
git show --stat HEAD           # these five files; Localizable.xcstrings about +1320 lines
git diff --stat                # the catalog still shows the user's own edits, nothing of ours
```

---

### Task 5: The view model sends pictures and the session's choices

**Files:**
- Modify: `Sources/ChatFeature/ChatDetailViewModel.swift:28, :178-181, :305-315, :317, :425` (through `/tmp/composer/dual_edit.py`)
- Test: `Tests/ChatFeatureTests/ComposerSendTests.swift`

**Interfaces:**
- Consumes: `ComposerPicture.prepared`, `ComposerAttachments`, `ComposerContent.content(text:pictures:)` (Task 2); `ComposerTools.turnOptions` (Task 3); `ComposerText.unreadable` (Task 4); `ChatStreamManager.send(…, options:)`, `TurnOptions` (Task 1); `PictureFixture` (Task 2's test file); `ChatPageFixture` (existing test helper).
- Produces on `ChatDetailViewModel`: `public var attachments: ComposerAttachments`, `@ObservationIgnored public var composerTools: ComposerTools?`, `public func addPictures(_ items: [Data?]) async`, `public func removePicture(_ id: ComposerPicture.ID)`; `canSend` true with pictures and no text.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ChatFeatureTests/ComposerSendTests.swift`:

```swift
import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

/// The computer, as far as a send needs it: a chat page (`history`, a bare array of rows) and an empty `done`.
private final class ComposerMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var history = "[]"
    static let sends = SendLog()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isSend = request.httpMethod == "POST" && request.url?.path == "/api/v1/chat"
        let body: Data
        if isSend {
            Self.sends.record(request.composerBody())
            body = Data("data: {\"type\":\"done\",\"messages\":[]}\n\n".utf8)
        } else {
            body = ChatPageFixture.wrap(Data(Self.history.utf8), path: request.url?.path ?? "")
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: isSend ? ["Content-Type": "text/event-stream"] : nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The send bodies, recorded on URLProtocol's thread and read by the test.
private final class SendLog: Sendable {
    private let bodies = Mutex<[Data]>([])

    func record(_ body: Data) { bodies.withLock { $0.append(body) } }
    func reset() { bodies.withLock { $0.removeAll() } }
    var count: Int { bodies.withLock { $0.count } }

    /// The last send's JSON body.
    func last() throws -> [String: Any] {
        let data = try #require(bodies.withLock { $0.last })
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The last send's question `content` as blocks; nil when it is a plain string.
    func lastBlocks() throws -> [[String: Any]]? {
        (try last()["message"] as? [String: Any])?["content"] as? [[String: Any]]
    }
}

extension URLRequest {
    /// URLSession hands a protocol the body as a stream.
    fileprivate func composerBody() -> Data {
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

private let answeredChat = #"""
    [{"id":"u1","runId":"u1","chatId":"c1","role":"user","content":"hi","createdAt":"2026-09-18T12:00:00.000Z"},
     {"id":"a1","runId":"u1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"hello"}],"stopReason":"stop","createdAt":"2026-09-18T12:00:05.000Z"}]
    """#

@MainActor
@Suite("Composer send", .serialized)
struct ComposerSendTests {
    /// A chat over the mock, its history loaded; `history` is its rows.
    private func loadedViewModel(history: String = "[]", _ suite: String = #function) async -> ChatDetailViewModel {
        ComposerMockURLProtocol.history = history
        ComposerMockURLProtocol.sends.reset()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComposerMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let vm = ChatDetailViewModel(
            chatId: "c1", apiClient: APIClient(session: session, serverConfig: config),
            streamManager: ChatStreamManager(sseClient: SSEClient(session: session)), serverConfig: config)
        await vm.loadHistory()
        return vm
    }

    @Test("pictures alone can be sent, as image blocks, and leave the composer empty")
    func picturesAlone() async throws {
        let vm = await loadedViewModel()
        #expect(!vm.canSend)
        vm.attachments.append([PictureFixture.picture(1)])
        #expect(vm.canSend)
        await vm.sendMessage()
        let blocks = try #require(try ComposerMockURLProtocol.sends.lastBlocks())
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "image")
        #expect(blocks[0]["mimeType"] as? String == "image/jpeg")
        #expect(blocks[0]["data"] as? String == PictureFixture.picture(1).dataURL)
        #expect(vm.attachments.isEmpty)
    }

    @Test("text and pictures go in one message: the text first, then the pictures in pick order")
    func textAndPictures() async throws {
        let vm = await loadedViewModel()
        vm.composerText = "Which is warmer?"
        vm.attachments.append([PictureFixture.picture(1), PictureFixture.picture(2)])
        await vm.sendMessage()
        let blocks = try #require(try ComposerMockURLProtocol.sends.lastBlocks())
        #expect(blocks.map { $0["type"] as? String } == ["text", "image", "image"])
        #expect(blocks[0]["text"] as? String == "Which is warmer?")
        #expect(blocks[1]["data"] as? String == PictureFixture.picture(1).dataURL)
        #expect(blocks[2]["data"] as? String == PictureFixture.picture(2).dataURL)
        #expect(vm.composerText.isEmpty && vm.attachments.isEmpty)
    }

    @Test("blank text and no pictures send nothing")
    func nothingToSend() async {
        let vm = await loadedViewModel()
        vm.composerText = "  \n"
        #expect(!vm.canSend)
        await vm.sendMessage()
        #expect(ComposerMockURLProtocol.sends.count == 0)
    }

    @Test("a quote with pictures and nothing typed sends the quote as the text, then the pictures")
    func aQuoteWithPicturesAndNothingTypedSendsTheQuote() async throws {
        let vm = await loadedViewModel()
        vm.askAbout("Daikin was sold.")
        vm.attachments.append([PictureFixture.picture(1)])
        #expect(vm.canSend)
        await vm.sendMessage()
        let blocks = try #require(try ComposerMockURLProtocol.sends.lastBlocks())
        let quote = QuotedText.compose(quote: "Daikin was sold.", text: "").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(blocks.map { $0["type"] as? String } == ["text", "image"])
        #expect(blocks[0]["text"] as? String == quote)
        #expect(vm.quote == nil)
    }

    @Test("text alone is still a plain string, with no tools and no effort, when the session has no choices")
    func textAloneUnchanged() async throws {
        let vm = await loadedViewModel()
        vm.composerText = "hi"
        await vm.sendMessage()
        let body = try ComposerMockURLProtocol.sends.last()
        #expect((body["message"] as? [String: Any])?["content"] as? String == "hi")
        #expect((body["advancedTools"] as? [String]) == [])
        #expect(!body.keys.contains("reasoningEffort"))
    }

    @Test("the session's choices ride along: a reasoning level, then Deep Research")
    func choicesRideAlong() async throws {
        let vm = await loadedViewModel()
        let tools = ComposerTools()
        tools.adopt(reasoningLevels: ["off", "low", "high"])
        tools.setEffort(.high)
        vm.composerTools = tools
        vm.composerText = "think hard"
        await vm.sendMessage()
        var body = try ComposerMockURLProtocol.sends.last()
        #expect(body["reasoningEffort"] as? String == "high")
        #expect((body["advancedTools"] as? [String]) == [])

        tools.setDeepResearch(true)
        vm.composerText = "now research it"
        await vm.sendMessage()
        body = try ComposerMockURLProtocol.sends.last()
        #expect((body["advancedTools"] as? [String]) == ["Deep Research"])
        #expect(!body.keys.contains("reasoningEffort"))
    }

    @Test("Regenerate re-asks with the choices as they are at that moment")
    func regenerateTakesTheChoicesOfThatMoment() async throws {
        let vm = await loadedViewModel(history: answeredChat)
        let tools = ComposerTools()
        vm.composerTools = tools
        tools.setDeepResearch(true)
        #expect(vm.canRegenerate)
        await vm.regenerate()
        let body = try ComposerMockURLProtocol.sends.last()
        #expect((body["advancedTools"] as? [String]) == ["Deep Research"])
    }

    @Test("an unreadable picture is left out with a notice; the readable one stays")
    func unreadablePictures() async {
        let vm = await loadedViewModel()
        await vm.addPictures([Data("not a picture".utf8), PictureFixture.data(width: 40, height: 30), nil])
        #expect(vm.attachments.pictures.count == 1)
        #expect(vm.notice == StreamNotice(level: .warning, message: ComposerText.unreadable(2)))
    }

    @Test("picks past the limit are left out quietly, in pick order")
    func picksPastTheLimitAreLeftOutQuietly() async {
        let vm = await loadedViewModel()
        let waiting = (0..<8).map(PictureFixture.picture)
        vm.attachments.append(waiting)
        await vm.addPictures((0..<5).map { _ in PictureFixture.data(width: 40, height: 30) })
        #expect(vm.attachments.pictures.count == 10)
        #expect(Array(vm.attachments.pictures.prefix(8)) == waiting)
        #expect(vm.notice == nil)
    }

    @Test("a picture can be taken out again")
    func removing() async {
        let vm = await loadedViewModel()
        let picture = PictureFixture.picture(1)
        vm.attachments.append([picture])
        vm.removePicture(picture.id)
        #expect(vm.attachments.isEmpty && !vm.canSend)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
git diff --stat
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ComposerSendTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: value of type 'ChatDetailViewModel' has no member 'attachments'` (and `composerTools`, `addPictures`, `removePicture`), `TEST FAILED`.

- [ ] **Step 3: Write the view model's edits**

Check `/tmp/composer/dual_edit.py` exists (Task 1); if not, create it from **Shared tooling**. Create `/tmp/composer/vm_edits.py`:

```python
PATH = "Sources/ChatFeature/ChatDetailViewModel.swift"
EDITS = [
    (
        "    public var composerText: String = \"\"\n",
        """    public var composerText: String = ""
    /// The pictures the next message carries, in pick order: sent with the text, and cleared with it.
    public var attachments = ComposerAttachments()
    /// The app session's reasoning effort and Deep Research (`ComposerTools`), read when a turn starts — a Regenerate
    /// too, with the choices as they are then, as on the desktop. Handed over by the chat screen; nil asks for neither.
    @ObservationIgnored public var composerTools: ComposerTools?
""",
    ),
    (
        """        hasLoadedHistory && !isTurnInFlight
            && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
""",
        """        // A message may be pictures alone, as on the desktop.
        hasLoadedHistory && !isTurnInFlight
            && (!composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
""",
    ),
    (
        """        let text = quote.map { QuotedText.compose(quote: $0, text: typed) } ?? typed
        composerText = ""
        quote = nil

        if supportsAttempts { messages = RunAttempts.autoChoose(messages) }
        await startTurn(
            with: .userMessage(id: Self.newMessageId(), text: text, timestampMs: Self.nowMs))
""",
        """        let text = quote.map { QuotedText.compose(quote: $0, text: typed) } ?? typed
        let pictures = attachments.pictures
        composerText = ""
        quote = nil
        attachments.removeAll()

        if supportsAttempts { messages = RunAttempts.autoChoose(messages) }
        await startTurn(
            with: .userMessage(
                id: Self.newMessageId(), content: ComposerContent.content(text: text, pictures: pictures),
                timestampMs: Self.nowMs))
""",
    ),
    (
        "    @ObservationIgnored private var appliedDraft = false\n",
        """    /// Pictures from Photos or the camera (nil: one that could not be loaded), prepared off the main actor and added in
    /// pick order as far as `ComposerAttachments.limit` allows. One that cannot be read is left out with a notice; the
    /// others stay.
    public func addPictures(_ items: [Data?]) async {
        var prepared: [ComposerPicture] = []
        var unreadable = 0
        for item in items {
            guard let item, let picture = try? await ComposerPicture.prepared(item) else {
                unreadable += 1
                continue
            }
            prepared.append(picture)
        }
        attachments.append(prepared)
        if unreadable > 0 { show(StreamNotice(level: .warning, message: ComposerText.unreadable(unreadable))) }
    }

    public func removePicture(_ id: ComposerPicture.ID) { attachments.remove(id) }

    @ObservationIgnored private var appliedDraft = false
""",
    ),
    (
        "        let updates = await streamManager.send(chatId: chatId, messages: messages, serverConfig: serverConfig)\n",
        """        let options = composerTools?.turnOptions ?? TurnOptions()
        let updates = await streamManager.send(
            chatId: chatId, messages: messages, serverConfig: serverConfig, options: options)
""",
    ),
]
```

Text alone still goes through `ComposerContent` as `.string(text)`, the same `content` the old `.userMessage(id:text:timestampMs:)` built — the existing `ChatDetailViewModelTests` keep passing unchanged.

- [ ] **Step 4: Apply them**

```bash
python3 /tmp/composer/dual_edit.py check /tmp/composer/vm_edits.py     # OK … 5 edit(s)
python3 /tmp/composer/dual_edit.py apply /tmp/composer/vm_edits.py
```

- [ ] **Step 5: Run the new tests and the whole ChatFeature suite**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ComposerSendTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `Test run with 10 tests passed`; then the whole suite `TEST SUCCEEDED` with no `✘`.

- [ ] **Step 6: Commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1                                    # 0 error(s)
python3 /tmp/composer/dual_edit.py patch /tmp/composer/vm_edits.py /tmp/composer/vm.patch   # PATCH-OK
.superpowers/sdd/commit-mine.sh "feat(chat): a question can carry pictures, or be pictures alone, and every turn — Regenerate too — asks with the session's reasoning effort or Deep Research" \
  --patch /tmp/composer/vm.patch Tests/ChatFeatureTests/ComposerSendTests.swift
git show --stat HEAD           # ChatDetailViewModel.swift (+~35) and the test file only
git diff -- Sources/ChatFeature/ChatDetailViewModel.swift | grep -c "attachments"   # 0
```

---

### Task 6: The `+` menu, the picture squares, the pills, the MCP sheet, the camera

**Files:**
- Create: `Sources/ChatFeature/ComposerToolsViews.swift`, `Sources/ChatFeature/CameraPicker.swift`
- Test: `Tests/ChatFeatureTests/ComposerToolsViewsTests.swift`

**Interfaces:**
- Consumes: `ComposerTools` (Task 3), `ComposerAttachments`, `ComposerPicture` (Task 2), `ComposerText` (Task 4), `McpToolsResponse.Group`, `McpTool` (Models), `MarkdownView(text:isStreaming:)` (MarkdownKit), `ComputerUseFrameStore.decodeScreenshot(_:maxPixelWidth:)`.
- Produces (all internal to ChatFeature):
  - `struct ComposerToolsButton: View { init(tools: ComposerTools?, attachments: ComposerAttachments, onPictures: @escaping ([Data?]) -> Void) }`
  - `struct ComposerPictureStrip: View { init(pictures: [ComposerPicture], onRemove: @escaping (ComposerPicture.ID) -> Void) }`
  - `struct ComposerToolPills: View { init(tools: ComposerTools); enum Pill: Hashable { case reasoning(ReasoningEffort), deepResearch }; static func pills(for: ComposerTools) -> [Pill]; static func turnOff(_: Pill, in: ComposerTools) }`
  - `struct McpToolsSheet: View { init(groups: [McpToolsResponse.Group]); static func description(of: McpTool) -> String }`
  - `struct CameraPicker: UIViewControllerRepresentable { init(onFinish: @escaping (Data?) -> Void) }`
  - `enum CameraAccess: Equatable { case open, ask, explain; static func decision(for: AVAuthorizationStatus) -> CameraAccess }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ChatFeatureTests/ComposerToolsViewsTests.swift`:

```swift
import AVFoundation
import Foundation
import Models
import Testing

@testable import ChatFeature

@MainActor
@Suite("The composer's + views")
struct ComposerToolsViewsTests {
    @Test("Take Photo opens the camera when allowed, lets the system ask the first time, and explains once refused")
    func cameraAccess() {
        #expect(CameraAccess.decision(for: .authorized) == .open)
        #expect(CameraAccess.decision(for: .notDetermined) == .ask)
        #expect(CameraAccess.decision(for: .denied) == .explain)
        #expect(CameraAccess.decision(for: .restricted) == .explain)
    }

    @Test("no pill while nothing is on")
    func noPills() {
        #expect(ComposerToolPills.pills(for: ComposerTools()).isEmpty)
    }

    @Test("a reasoning level shows its pill, and its ✕ turns reasoning off")
    func reasoningPill() {
        let tools = ComposerTools()
        tools.adopt(reasoningLevels: ["off", "high"])
        tools.setEffort(.high)
        #expect(ComposerToolPills.pills(for: tools) == [.reasoning(.high)])
        ComposerToolPills.turnOff(.reasoning(.high), in: tools)
        #expect(tools.reasoningEffort == .off)
        #expect(ComposerToolPills.pills(for: tools).isEmpty)
    }

    @Test("Deep Research shows its pill, and its ✕ turns it off")
    func deepResearchPill() {
        let tools = ComposerTools()
        tools.setDeepResearch(true)
        #expect(ComposerToolPills.pills(for: tools) == [.deepResearch])
        ComposerToolPills.turnOff(.deepResearch, in: tools)
        #expect(!tools.deepResearch)
    }

    @Test("a tool's description is its own, or a line saying it has none")
    func toolDescription() {
        #expect(McpToolsSheet.description(of: McpTool(name: "read_file", description: "Reads **a file**.")) == "Reads **a file**.")
        #expect(McpToolsSheet.description(of: McpTool(name: "get_me")) == "No description for get_me.")
        #expect(McpToolsSheet.description(of: McpTool(name: "ping", description: "  \n")) == "No description for ping.")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
git diff --stat
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ComposerToolsViewsTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'CameraAccess' in scope` (and `ComposerToolPills`, `McpToolsSheet`), `TEST FAILED`.

- [ ] **Step 3: Write `CameraPicker.swift`**

Create `Sources/ChatFeature/CameraPicker.swift`:

```swift
import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What Take Photo does about the camera's permission: open it, let the system ask (the first time only — a refusal
/// there is the system's own answer), or, once refused, explain and point to Settings.
enum CameraAccess: Equatable {
    case open, ask, explain

    static func decision(for status: AVAuthorizationStatus) -> CameraAccess {
        switch status {
        case .authorized: .open
        case .notDetermined: .ask
        default: .explain
        }
    }
}

/// The system camera: SwiftUI has no camera view, so UIKit's picker. Hands back the photo as full-quality JPEG (its
/// orientation kept in the EXIF), or nil when cancelled; `ComposerPicture` downscales it like any picked picture.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 1))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
```

- [ ] **Step 4: Write `ComposerToolsViews.swift`**

Create `Sources/ChatFeature/ComposerToolsViews.swift`:

```swift
import AVFoundation
import MarkdownKit
import Models
import PhotosUI
import SwiftUI
import UIKit

/// The composer's `+` (the desktop's `ComposerToolsButton`): pictures from Photos or the camera, the reasoning effort,
/// Deep Research, and the tools the computer's MCP servers offer. It presents its own pickers, sheet and alert; picked
/// pictures go to `onPictures` as data (nil for one Photos could not hand over).
struct ComposerToolsButton: View {
    /// nil in a preview: the menu offers pictures only.
    let tools: ComposerTools?
    let attachments: ComposerAttachments
    let onPictures: ([Data?]) -> Void

    @State private var showsPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var showsMcpTools = false
    @State private var explainsCamera = false

    var body: some View {
        Menu {
            Section {
                Button {
                    showsPhotos = true
                } label: {
                    Label("ios:chat.composer.photoLibrary", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(attachments.isFull)
                // No camera on the Simulator: the entry is not offered at all.
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        Task { await openCamera() }
                    } label: {
                        Label("ios:chat.composer.takePhoto", systemImage: "camera")
                    }
                    .disabled(attachments.isFull)
                }
            }
            if let tools {
                Section {
                    if !tools.reasoningLevels.isEmpty {
                        reasoningMenu(tools)
                    }
                    Toggle(isOn: Binding(get: { tools.deepResearch }, set: { tools.setDeepResearch($0) })) {
                        Label("ios:chat.composer.deepResearch", systemImage: "binoculars")
                    }
                }
                if tools.mcpToolCount > 0 {
                    Section {
                        Button {
                            showsMcpTools = true
                        } label: {
                            Label {
                                Text("ios:chat.composer.mcpTools")
                                Text(verbatim: "\(tools.mcpToolCount)")
                            } icon: {
                                Image(systemName: "hammer")
                            }
                        }
                    }
                }
            }
        } label: {
            Label("common:action.add", systemImage: "plus")
                .labelStyle(.iconOnly)
                // Tinted while a choice is on, as the desktop's blue `+` — here the chat's tone, like the rest of it.
                .foregroundStyle(tools?.isActive == true ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        // In the order written, as on the desktop: pictures, then how the answer is made, then the tools.
        .menuOrder(.fixed)
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityIdentifier("composerTools")
        .photosPicker(
            isPresented: $showsPhotos, selection: $photoSelection, maxSelectionCount: max(1, attachments.room),
            selectionBehavior: .ordered, matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task {
                var loaded: [Data?] = []
                for item in items { loaded.append(try? await item.loadTransferable(type: Data.self)) }
                onPictures(loaded)
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { data in
                showsCamera = false
                if let data { onPictures([data]) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsMcpTools) {
            McpToolsSheet(groups: tools?.mcpGroups ?? [])
        }
        .alert("ios:settings.pairing.cameraDeniedTitle", isPresented: $explainsCamera) {
            Button("ios:settings.pairing.openSystemSettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("common:action.cancel", role: .cancel) {}
        } message: {
            Text("ios:chat.composer.cameraDeniedMessage")
        }
        // One tick per choice changed, from the menu or a pill's ✕.
        .sensoryFeedback(.selection, trigger: tools?.turnOptions)
    }

    /// A submenu whose row shows the level now chosen; inside, the model's levels with a check on the chosen one.
    private func reasoningMenu(_ tools: ComposerTools) -> some View {
        Menu {
            Picker(
                "ios:chat.composer.reasoning",
                selection: Binding(get: { tools.reasoningEffort }, set: { tools.setEffort($0) })
            ) {
                ForEach(tools.reasoningLevels, id: \.self) { level in
                    Text(verbatim: ComposerText.level(level)).tag(level)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label {
                Text("ios:chat.composer.reasoning")
                Text(verbatim: ComposerText.level(tools.reasoningEffort))
            } icon: {
                Image(systemName: "brain")
            }
        }
    }

    private func openCamera() async {
        switch CameraAccess.decision(for: AVCaptureDevice.authorizationStatus(for: .video)) {
        case .open:
            showsCamera = true
        case .ask:
            if await AVCaptureDevice.requestAccess(for: .video) { showsCamera = true }
        case .explain:
            explainsCamera = true
        }
    }
}

/// The pictures waiting in the composer (the desktop's `FilePreview`): rounded squares in pick order, each with a ✕ at
/// its corner. Scrolls sideways when ten do not fit.
struct ComposerPictureStrip: View {
    let pictures: [ComposerPicture]
    let onRemove: (ComposerPicture.ID) -> Void

    @State private var thumbnails: [ComposerPicture.ID: UIImage] = [:]
    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 56

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(pictures.enumerated()), id: \.element.id) { index, picture in
                    tile(picture, position: index + 1)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            // Room for the ✕ that reaches past each square's corner.
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .task(id: pictures.map(\.id)) { await decode() }
    }

    private func tile(_ picture: ComposerPicture, position: Int) -> some View {
        // The desktop's 56 pt square, growing with the text size up to a point.
        let side = min(scaledSide, 88)
        return ZStack {
            if let image = thumbnails[picture.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator), lineWidth: 0.5))
        .accessibilityHidden(true)
        .overlay(alignment: .topTrailing) {
            Button {
                onRemove(picture.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 20, height: 20)
                    .background(Color(.label), in: .circle)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                    // A 44 pt target around the 20 pt mark.
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .offset(x: 18, y: -18)
            .accessibilityLabel(Text(verbatim: ComposerText.removePicture(position, of: pictures.count)))
        }
    }

    /// Thumbnails three times the square: sharp on any phone. One for a picture gone is dropped.
    private func decode() async {
        for picture in pictures where thumbnails[picture.id] == nil {
            if let image = await ComputerUseFrameStore.decodeScreenshot(picture.dataURL, maxPixelWidth: 264) {
                thumbnails[picture.id] = image
            }
        }
        let shown = Set(pictures.map(\.id))
        thumbnails = thumbnails.filter { shown.contains($0.key) }
    }
}

/// The choices that are on, over the field (the desktop's `ActiveToolPills`): one pill each, a tap turning it off.
struct ComposerToolPills: View {
    let tools: ComposerTools

    enum Pill: Hashable {
        case reasoning(ReasoningEffort)
        case deepResearch
    }

    static func pills(for tools: ComposerTools) -> [Pill] {
        var pills: [Pill] = []
        if tools.reasoningEffort != .off { pills.append(.reasoning(tools.reasoningEffort)) }
        if tools.deepResearch { pills.append(.deepResearch) }
        return pills
    }

    static func turnOff(_ pill: Pill, in tools: ComposerTools) {
        switch pill {
        case .reasoning: tools.setEffort(.off)
        case .deepResearch: tools.setDeepResearch(false)
        }
    }

    var body: some View {
        let pills = Self.pills(for: tools)
        if !pills.isEmpty {
            // Side by side, or one under the other when a large text size leaves no room.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { ForEach(pills, id: \.self) { pillButton($0) } }
                VStack(alignment: .leading, spacing: 6) { ForEach(pills, id: \.self) { pillButton($0) } }
            }
        }
    }

    private func pillButton(_ pill: Pill) -> some View {
        Button {
            Self.turnOff(pill, in: tools)
        } label: {
            HStack(spacing: 4) {
                switch pill {
                case .reasoning(let level):
                    Image(systemName: "brain").accessibilityHidden(true)
                    Text(verbatim: ComposerText.reasoningPill(level))
                case .deepResearch:
                    Image(systemName: "binoculars").accessibilityHidden(true)
                    Text("ios:chat.composer.deepResearch")
                }
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.tint.opacity(0.12), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("ios:chat.composer.turnOff"))
    }
}

/// The tools the computer's MCP servers offer (the desktop composer's MCP dialog), by server, each described in
/// Markdown. Read-only: servers are turned on and off in Settings › MCP Servers.
struct McpToolsSheet: View {
    let groups: [McpToolsResponse.Group]
    @Environment(\.dismiss) private var dismiss

    /// The server's description, or a line saying it gave none.
    static func description(of tool: McpTool) -> String {
        let text = tool.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? ComposerText.noDescription(tool.name) : text
    }

    var body: some View {
        NavigationStack {
            List {
                Text("ios:chat.composer.mcpSheet.description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                ForEach(groups, id: \.mcpServerName) { group in
                    Section {
                        ForEach(group.tools) { tool in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: tool.name)
                                    .font(.subheadline.monospaced().weight(.medium))
                                MarkdownView(text: Self.description(of: tool), isStreaming: false)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(verbatim: group.mcpServerName)
                    }
                }
            }
            .navigationTitle(Text("ios:chat.composer.mcpSheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
```

- [ ] **Step 5: Run the tests, the suite and the audit**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd -only-testing:ChatFeatureTests/ComposerToolsViewsTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
python3 scripts/l10n.py audit 2>&1 | grep "ios:chat.composer" || echo "every composer key is referenced"
```
Expected: `Test run with 5 tests passed`; the whole suite `TEST SUCCEEDED`; `0 error(s)`; `every composer key is referenced`.

- [ ] **Step 6: Commit**

```bash
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(chat): the composer's + menu — Photos, the camera, a reasoning submenu, Deep Research, the MCP tools sheet — with picture squares and removable pills" \
  Sources/ChatFeature/ComposerToolsViews.swift Sources/ChatFeature/CameraPicker.swift Tests/ChatFeatureTests/ComposerToolsViewsTests.swift
git show --stat HEAD
```

---

### Task 7: The chat screen shows them; the app shell keeps the session's choices

**Files:**
- Modify: `Sources/ChatFeature/ChatDetailView.swift:40, :173-174, :241-260, :262-265` (through `/tmp/composer/dual_edit.py`)
- Modify: `Sources/App/AppShell.swift:41, :107, :119-122, :143`, and a new private method (clean file; committed whole)

**Interfaces:**
- Consumes: `ComposerTools`, `ComposerToolsSource(apiClient:)` (Task 3); `ComposerToolsButton`, `ComposerPictureStrip`, `ComposerToolPills` (Task 6); `viewModel.attachments`, `viewModel.composerTools`, `viewModel.addPictures`, `viewModel.removePicture` (Task 5).
- Produces: the chat screen reads `@Environment(ComposerTools.self) private var composerTools: ComposerTools?`; `AppShell` injects `.environment(composerTools)` on `ChatDetailView`.

- [ ] **Step 1: Write the chat screen's edits**

Check `git diff --stat -- Sources/App/AppShell.swift` prints nothing (it is committed whole). Create `/tmp/composer/view_edits.py`:

```python
PATH = "Sources/ChatFeature/ChatDetailView.swift"
EDITS = [
    (
        "    @Environment(\\.scenePhase) private var scenePhase\n",
        "    @Environment(\\.scenePhase) private var scenePhase\n"
        "    /// The app session's `+` choices, from the app shell; nil (a preview) leaves the menu with pictures only.\n"
        "    @Environment(ComposerTools.self) private var composerTools: ComposerTools?\n",
    ),
    (
        """        .task {
            await viewModel.onAppear()
""",
        """        .task {
            // First: a turn reads the session's choices when it starts, and one may start right below.
            viewModel.composerTools = composerTools
            await viewModel.onAppear()
""",
    ),
    (
        """                ComposerQuote(text: quote, onRemove: viewModel.removeQuote)
                    .transition(.opacity)
            }
            composerRow
""",
        """                ComposerQuote(text: quote, onRemove: viewModel.removeQuote)
                    .transition(.opacity)
            }
            if !viewModel.attachments.isEmpty {
                ComposerPictureStrip(pictures: viewModel.attachments.pictures, onRemove: viewModel.removePicture)
                    .transition(.opacity)
            }
            if let composerTools, composerTools.isActive {
                ComposerToolPills(tools: composerTools)
                    .transition(.opacity)
            }
            composerRow
""",
    ),
    (
        "        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: viewModel.quote)\n",
        "        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: viewModel.quote)\n"
        "        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: viewModel.attachments)\n"
        "        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: composerTools?.turnOptions)\n",
    ),
    (
        """        return HStack(alignment: .bottom, spacing: 8) {
            TextField("ios:chat.composer.placeholder", text: $viewModel.composerText, axis: .vertical)
""",
        """        return HStack(alignment: .bottom, spacing: 8) {
            ComposerToolsButton(tools: composerTools, attachments: viewModel.attachments) { items in
                Task { await viewModel.addPictures(items) }
            }
            // Reaches into the composer's padding, so its circle sits as far from the edge as Send's on the other side.
            .padding(.leading, -10)
            TextField("ios:chat.composer.placeholder", text: $viewModel.composerText, axis: .vertical)
""",
    ),
]
```

```bash
python3 /tmp/composer/dual_edit.py check /tmp/composer/view_edits.py     # OK … 5 edit(s)
python3 /tmp/composer/dual_edit.py apply /tmp/composer/view_edits.py
```

- [ ] **Step 2: Give the app shell the session's choices (targeted edits in `AppShell.swift`)**

After `    @State private var healthAsk: String?` (`:41`) insert:

```swift
    /// The composer's `+` choices (reasoning effort, Deep Research) for the whole app session, as the desktop keeps them,
    /// with the current model's levels and the MCP tools the menu offers.
    @State private var composerTools = ComposerTools()
```

Replace `            onDismiss: { recentsReloadToken += 1 }` (`:107`) with:

```swift
            onDismiss: {
                recentsReloadToken += 1
                // The model may have changed there, and with it the reasoning levels.
                refreshComposerTools()
            }
```

Replace

```swift
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await toneModel?.refresh(apiClient: apiClient) } }
        }
```

(`:120-122`) with:

```swift
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await toneModel?.refresh(apiClient: apiClient) }
                refreshComposerTools()
            }
        }
        // A chat opening reads the current model's levels and the MCP tools (the desktop may have changed either).
        .onChange(of: activeChat.id, initial: true) { refreshComposerTools() }
```

In `detail`'s `.chat` case, replace

```swift
            // A different chat is a different view model.
            .id(activeChat.id)
```

(`:142-143`) with:

```swift
            // A different chat is a different view model.
            .id(activeChat.id)
            .environment(composerTools)
```

Before `    private func setSidebar(open: Bool) {` (`:213`) insert:

```swift
    private func refreshComposerTools() {
        Task { await composerTools.refresh(from: ComposerToolsSource(apiClient: apiClient)) }
    }

```

- [ ] **Step 3: Build the app and run the ChatFeature suite**

```bash
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: `** BUILD SUCCEEDED **`; `TEST SUCCEEDED` with no `✘`; `0 error(s)`.

- [ ] **Step 4: See it in a chat on the Simulator**

With the desktop app running on this Mac (the Simulator reaches it at the manual address `http://localhost:60223`):

```bash
xcrun simctl install 992425B7-F06B-4CE5-9288-95C71C2F1D44 /tmp/composer-dd/Build/Products/Debug-iphonesimulator/Exodus.app
xcrun simctl launch 992425B7-F06B-4CE5-9288-95C71C2F1D44 app.yancey.exodus.exodus-ios
```
Check: the `+` sits left of the field, as far from the composer's edge as Send on the right; it opens Photo Library (no Take Photo on the Simulator), Reasoning with the model's levels and the chosen one beside it, Deep Research, and MCP Tools with its count when the desktop has MCP servers on; choosing High shows "Reasoning: High" over the field and tints the `+`; turning Deep Research on replaces it with "Deep Research"; Photo Library → two pictures → two squares with ✕; Send with nothing typed sends them and the question shows its pictures above the bubble. If the desktop is not running, Task 8's gallery covers the visuals; note that here.

- [ ] **Step 5: Commit**

```bash
git diff --stat
python3 /tmp/composer/dual_edit.py patch /tmp/composer/view_edits.py /tmp/composer/view.patch   # PATCH-OK
.superpowers/sdd/commit-mine.sh "feat(chat): the composer shows the + left of the field, the pictures waiting and the pills; the app keeps the choices for the session and reads the model's levels when a chat opens" \
  --patch /tmp/composer/view.patch Sources/App/AppShell.swift
git show --stat HEAD           # ChatDetailView.swift and AppShell.swift only
git diff -- Sources/ChatFeature/ChatDetailView.swift | grep -c "ComposerTools"   # 0
```

---

### Task 8: Gallery states, screenshots, device checklist

**Files:**
- Create: `Sources/ChatFeature/ComposerGallery.swift`, `docs/composer-tools-device-checklist.md`
- Modify: `Sources/ChatFeature/MessageGallery.swift:129-131` (through `/tmp/composer/dual_edit.py`)

**Interfaces:**
- Consumes: `ComposerToolsButton`, `ComposerPictureStrip`, `ComposerToolPills`, `McpToolsSheet` (Task 6); `ComposerTools` (Task 3); `ComposerAttachments`, `ComposerPicture` (Task 2); `MessageGalleryFixtures.picture(_:width:height:)` (`MessageGallery.swift:426`).
- Produces: `-MessageGallery -MessageGalleryComposer empty | pictures | full | reasoning | research | mcp`.

- [ ] **Step 1: Write the gallery bar**

Create `Sources/ChatFeature/ComposerGallery.swift`:

```swift
#if DEBUG
import Foundation
import Models
import SwiftUI
import UIKit

/// `-MessageGallery -MessageGalleryComposer <state>`: the composer's `+` pieces over the message gallery, for
/// screenshots — `empty`, `pictures` (three), `full` (ten, Reasoning on), `reasoning`, `research`, `mcp` (the sheet).
enum ComposerGalleryState: String {
    case empty, pictures, full, reasoning, research, mcp

    static var launch: ComposerGalleryState? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-MessageGalleryComposer"), index + 1 < arguments.count else {
            return nil
        }
        return ComposerGalleryState(rawValue: arguments[index + 1])
    }
}

/// The real composer pieces around a stand-in field, laid out as `ChatDetailView.composer` lays them out.
struct ComposerGalleryBar: View {
    let state: ComposerGalleryState

    @State private var tools = ComposerTools()
    @State private var attachments = ComposerAttachments()
    @State private var showsMcpTools = false
    @Environment(\.accentGlyph) private var accentGlyph
    @Environment(\.toneAccent) private var toneAccent
    @Environment(\.toneInk) private var toneInk
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                ComposerPictureStrip(pictures: attachments.pictures) { attachments.remove($0) }
            }
            if tools.isActive {
                ComposerToolPills(tools: tools)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ComposerToolsButton(tools: tools, attachments: attachments) { _ in }
                    .padding(.leading, -10)
                Text("ios:chat.composer.placeholder")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                Button {} label: {
                    Label("chat:composer.send", systemImage: "arrow.up")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(colorScheme == .dark ? accentGlyph : .white)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(colorScheme == .dark ? toneAccent : toneInk)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        // As the chat screen: what tints is the tone's ink.
        .tint(toneInk)
        .task { prepare() }
        .sheet(isPresented: $showsMcpTools) { McpToolsSheet(groups: tools.mcpGroups) }
    }

    private func prepare() {
        tools.adopt(reasoningLevels: ["off", "low", "medium", "high", "xhigh"])
        if let mcp = Self.mcpTools { tools.adopt(mcpTools: mcp) }
        let colors: [UIColor] = [
            .systemOrange, .systemIndigo, .systemPink, .systemGreen, .systemYellow, .systemRed, .systemTeal,
            .systemBlue, .systemPurple, .systemBrown,
        ]
        switch state {
        case .empty:
            break
        case .pictures:
            attachments.append(Self.pictures(Array(colors.prefix(3))))
        case .full:
            attachments.append(Self.pictures(colors))
            tools.setEffort(.high)
        case .reasoning:
            tools.setEffort(.high)
        case .research:
            tools.setDeepResearch(true)
        case .mcp:
            showsMcpTools = true
        }
    }

    /// Flat pictures, portrait and landscape by turns, as the desktop stores them.
    private static func pictures(_ colors: [UIColor]) -> [ComposerPicture] {
        colors.enumerated().map { index, color in
            let (width, height): (CGFloat, CGFloat) = index.isMultiple(of: 2) ? (300, 400) : (400, 300)
            return ComposerPicture(
                mimeType: "image/png", dataURL: MessageGalleryFixtures.picture(color, width: width, height: height),
                pixelWidth: Int(width), pixelHeight: Int(height))
        }
    }

    private static let mcpTools: McpToolsResponse? = {
        let json = #"""
            {"tools":[{"mcpServerName":"filesystem","tools":[{"name":"read_file","description":"Reads a file **as text**. Paths are relative to the allowed folders."},{"name":"list_directory","description":"Lists a folder's entries:\n- files\n- folders"}]},
                      {"mcpServerName":"github","tools":[{"name":"search_issues","description":"Searches issues and pull requests."},{"name":"get_me","description":""}]}]}
            """#
        return try? JSONDecoder().decode(McpToolsResponse.self, from: Data(json.utf8))
    }()
}
#endif
```

- [ ] **Step 2: Route the flag (one `else if` in `MessageGallery.swift`)**

Create `/tmp/composer/gallery_edits.py`:

```python
PATH = "Sources/ChatFeature/MessageGallery.swift"
EDITS = [
    (
        """                } else if MessageGalleryLaunch.quote {
                    standInComposer
                }
""",
        """                } else if MessageGalleryLaunch.quote {
                    standInComposer
                } else if let state = ComposerGalleryState.launch {
                    ComposerGalleryBar(state: state)
                }
""",
    ),
]
```

```bash
git diff --stat
python3 /tmp/composer/dual_edit.py check /tmp/composer/gallery_edits.py     # OK … 1 edit(s)
python3 /tmp/composer/dual_edit.py apply /tmp/composer/gallery_edits.py
tuist generate --no-open
```

- [ ] **Step 3: Build, install, and take the screenshots**

Write `/tmp/composer/shots.sh`:

```bash
#!/bin/bash
# Light, dark, AX and one tone's screenshots of the composer's gallery states. Run from the repo root.
set -euo pipefail
SIM=992425B7-F06B-4CE5-9288-95C71C2F1D44
APP=app.yancey.exodus.exodus-ios
OUT=.superpowers/composer
mkdir -p "$OUT"
shoot() {
  local name=$1; shift
  xcrun simctl terminate "$SIM" "$APP" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$APP" "$@" >/dev/null
  sleep 4
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null
}
STATES="empty pictures full reasoning research mcp"
for s in $STATES; do shoot "light-$s" -MessageGallery -MessageGalleryComposer "$s"; done
shoot tone-reasoning -MessageGallery -MessageGalleryComposer reasoning -ColorTone violet
xcrun simctl ui "$SIM" appearance dark
for s in $STATES; do shoot "dark-$s" -MessageGallery -MessageGalleryComposer "$s"; done
xcrun simctl ui "$SIM" appearance light
xcrun simctl ui "$SIM" content_size accessibility-extra-extra-extra-large
for s in pictures full reasoning mcp; do shoot "ax-$s" -MessageGallery -MessageGalleryComposer "$s"; done
xcrun simctl ui "$SIM" content_size large
echo done
```

```bash
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcrun simctl install 992425B7-F06B-4CE5-9288-95C71C2F1D44 /tmp/composer-dd/Build/Products/Debug-iphonesimulator/Exodus.app
bash /tmp/composer/shots.sh
```

Expected: `** BUILD SUCCEEDED **`, `done`. Read every PNG in `.superpowers/composer/` and check against spec §2, §3 and §6:
- `empty`: a glass `+` circle left of "Ask Exodus", as far from the composer's left edge as Send is from the right; not tinted.
- `pictures`: three 56 pt rounded squares above the field, orange/indigo/pink in that order, each with a dark ✕ disc at its top-right corner, not clipped.
- `full`: ten squares scrolling sideways (the row runs off the right edge), then the "Reasoning: High" pill, then the field; the `+` tinted.
- `reasoning`: the pill alone, ink-coloured on a light tone fill, brain glyph, ✕; `tone-reasoning`: the same in violet.
- `research`: "Deep Research" pill with binoculars.
- `mcp`: the sheet at medium height, "Available MCP Tools", the description line, "filesystem" and "github" sections, bold Markdown rendered, the bullet list rendered, and "No description for get_me." under `get_me`.
- Dark: ✕ discs visible (light disc on dark), pills legible. AX: squares capped at 88 pt and still in one scrolling row; the pill wraps its text rather than overflowing; the sheet's rows grow.
Fix mismatches before committing (re-run the script after a fix; a fix to `MessageGallery.swift` is a pair appended to `gallery_edits.py`).

- [ ] **Step 4: Write the device checklist**

Create `docs/composer-tools-device-checklist.md`:

```markdown
# Composer tools — on-device checklist

What the Simulator cannot show (it has no camera, and its Photos holds a handful of samples). Run on a real iPhone
(iOS 27), paired with the desktop, after the `-MessageGalleryComposer` screenshots look right.

- [ ] `+` → Photo Library: the picker allows as many as there is room for (ten at first), in the order tapped; the
      pictures appear as squares above the field in that order. A HEIC portrait shows upright.
- [ ] With ten pictures waiting, Photo Library and Take Photo are greyed out in the menu; remove one with its ✕ and
      both come back.
- [ ] `+` → Take Photo, first time: the system asks for the camera, and its text mentions taking photos for a chat.
      Allow → the camera opens; take a photo → "Use Photo" → a square appears. Cancel leaves nothing.
- [ ] Refuse camera access (or turn it off in Settings › Exodus), then Take Photo: "Camera access is off" with Open
      Settings, which opens the app's page in Settings.
- [ ] Send a pictures-only message (nothing typed): Send is enabled; the question shows its pictures above an absent
      bubble; the answer describes them. On the desktop the same chat shows the pictures on the question.
- [ ] Send text and three pictures: the question shows the squares above its bubble; tapping one opens them full screen.
- [ ] A 48 MP ProRAW-sized photo: it is added within about a second, and the send is not noticeably slow on cellular
      (the picture went downscaled: about 2048 px).
- [ ] Reasoning: the submenu lists only the levels the current model has (Off first); the chosen one shows beside
      "Reasoning". Choose High → "Reasoning: High" pill, `+` tinted, a selection tick. Send: the desktop log / run shows
      high effort.
- [ ] Turn Deep Research on: the Reasoning pill goes and "Deep Research" shows. Send a question: a Deep Research card
      starts, as from the desktop.
- [ ] Tap a pill: it goes, with a tick; VoiceOver reads it as "Reasoning: High, button, Turns it off."
- [ ] On the desktop, switch to a model without the chosen level (or without reasoning); back on the phone open a chat:
      the level is Off (or Reasoning is gone from the menu).
- [ ] Open another chat and come back: the choices are still on (they belong to the app session). Quit the app and
      reopen: they are off again.
- [ ] `+` → MCP Tools (N): the sheet lists each server's tools with Markdown descriptions; N matches the desktop's count;
      with no MCP server on, the entry is not in the menu.
- [ ] Lock the computer (or quit the desktop app) and open a chat: Reasoning and MCP Tools keep what was last read, or
      are absent if nothing was ever read; Deep Research and the pictures still work.
- [ ] VoiceOver on the squares: "Remove picture 2 of 3, button"; the `+` reads "Add".
- [ ] Largest accessibility text size: the squares stay in one sideways row, the pill wraps, nothing overlaps Send.
- [ ] Reduce Motion on: squares and pills appear and go without scaling or sliding.
```

- [ ] **Step 5: Final checks and commit**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme NetworkingKit -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/composer-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1          # 0 error(s)
git diff --stat
python3 /tmp/composer/dual_edit.py patch /tmp/composer/gallery_edits.py /tmp/composer/gallery.patch   # PATCH-OK
.superpowers/sdd/commit-mine.sh "feat(chat): composer gallery states for the + — pictures, ten of them, the pills, the MCP sheet — and the device checklist" \
  --patch /tmp/composer/gallery.patch Sources/ChatFeature/ComposerGallery.swift docs/composer-tools-device-checklist.md
git show --stat HEAD           # MessageGallery.swift (+2), ComposerGallery.swift, the checklist
```
Expected: three `TEST SUCCEEDED`; audit `0 error(s)`; the commit lists exactly the three files.

---

## Self-Review

**Spec coverage:**
- §1 goal, the four entries, Photos and camera, downscaling, session-long choices, pills → Tasks 2, 3, 6, 7.
- §1 non-goals: no file types but images (`matching: .images`, camera images only); MCP sheet read-only, pointing to Settings › MCP Servers; no per-chat memory (one `ComposerTools` in `AppShell`) → Tasks 3, 6, 7.
- §2.1 Photo Library, several at once → Task 6 (`photosPicker`, `.ordered`, room left). §2.2 Take Photo, hidden without a camera → Task 6 (`isSourceTypeAvailable`), Task 4 (prompt text). §2.3 Reasoning, the model's levels, off first, hidden when none, chosen level shown → Tasks 3 (`levels`), 6 (`reasoningMenu`). §2.4 Deep Research and mutual exclusion → Task 3. §2.5 MCP Tools (N), only when N > 0, Markdown sheet, read-only, line to Settings → Tasks 3, 6. Strings in ten languages → Task 4 (Decision 1 on which keys).
- §3 downscale ≤ 2048, JPEG 0.85, PNG with alpha → Task 2. 56 pt squares with ✕, pick order, max 10, entries disabled at 10 → Tasks 2, 6. Content shape, pictures-only, Send enabled with a picture → Tasks 2, 5. Sent pictures via `UserImageStrip` → existing; checked in Task 2 (`readsBack`) and the device checklist. Camera usage text → Task 4.
- §4 `advancedTools: ["Deep Research"]`, `reasoningEffort` when not off; Regenerate with the choices of that moment → Tasks 1, 5.
- §5 one `ComposerTools` injected from the app shell; levels refreshed when a chat opens and when Settings changes the model; fallback to off; pictures belong to the chat's view model and clear on send → Tasks 3, 5, 7.
- §6 pills with ✕ → Tasks 6, 7.
- §7 decode failure notice; camera denial alert; Settings unreachable; MCP endpoint failing; Reduce Motion, Dynamic Type, VoiceOver labels → Tasks 3, 5, 6, 7, 8.
- §8 unit tests (downscale, content, body, exclusion, fallback, cap) → Tasks 1, 2, 3, 5; gallery states and light/dark/AX screenshots → Task 8; device checklist → Task 8.

**Placeholder scan:** every code step carries the code; the edits to files with the user's work are given as exact (old, new) pairs, each checked against HEAD and the working tree.

**Type consistency:** `TurnOptions(deepResearch:reasoningEffort:)`, `.advancedTools`, `.wireReasoningEffort` (Task 1) are what `ChatStreamManager` (Task 1), `ComposerTools.turnOptions` (Task 3) and the view model (Task 5) use. `ComposerPicture(mimeType:dataURL:pixelWidth:pixelHeight:)`, `.prepare`, `.prepared`, `ComposerAttachments.append/remove/removeAll/isEmpty/isFull/room`, `ComposerContent.content(text:pictures:)` (Task 2) are what Tasks 5, 6 and 8 call. `ComposerTools.setEffort/setDeepResearch/adopt(reasoningLevels:)/adopt(mcpTools:)/refresh(from:)/mcpGroups/mcpToolCount/isActive` (Task 3) match Tasks 5–8. `ComposerText.level/reasoningPill/removePicture(_:of:)/unreadable/noDescription` (Task 4) match Tasks 5 and 6. `PictureFixture.picture/data` (Task 2) are used in Task 5.

**Review Focus:** the five lines each have their test in the owning task (Tasks 2, 3, 5).
