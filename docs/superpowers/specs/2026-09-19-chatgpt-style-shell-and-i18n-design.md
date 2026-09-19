# exodus-ios: ChatGPT-style shell + i18n Design

Status: design approved by the user in conversation and spec reviewed (2026-09-19); implementation plan written
Date: 2026-09-19

## 1. Context and goal

The Chat + Settings MVP (`2026-09-18-chat-settings-mvp-design.md`, pushed as of `8e1f76d`) opens on a
chat list and pushes a chat on top of it. This change does two things at once:

1. **Reshape the UI after the ChatGPT iOS app.** The app launches into a new, empty chat. The chat
   list becomes a left slide-out drawer: the main screen is a rounded card that is pushed to the
   right, over a sidebar with workspaces, search, a "Recents" list, a New chat button and Settings.
   Reference screenshots (not in the repo): the user's `~/Desktop/IMG_6240.PNG` (main screen) and
   `IMG_6241.PNG` (drawer open). Everything inside the shell uses native SwiftUI components; only
   the sliding container is custom, because iOS has no native phone drawer.
2. **Internationalize from the first day** instead of retrofitting. The user's lesson from the
   desktop app: doing i18n last is very expensive. Every user-visible string goes through a String
   Catalog from now on, including the strings that already exist.

This spec supersedes two MVP non-goals: cross-chat search (now built) and locale support (now
built, following the phone's language; still no in-app switch).

**Prerequisite found while planning.** On 2026-09-19 the desktop repo (now `~/Code/exodus/exodus`;
the `universal-client` folder is gone) mounted every route under a versioned `/api/v1` prefix and
named `exodus-ios` as a client that must follow. Against the current server the shipped app's
unversioned paths are all 404. The implementation plan's first task moves every endpoint to
`/api/v1/...`; every path in this spec means the `/api/v1` form, and the older documents under
`docs/superpowers/` predate it.

## 2. Non-goals

- Projects (the desktop's project grouping) and renaming chats.
- Restyling message bubbles (only the shell, composer and empty state change).
- A real Philharmonic screen. Its sidebar row is present but disabled; the placeholder view stays.
- An iPad-specific layout. The iPhone layout runs on iPad with the drawer width capped.
- Right-to-left languages, an in-app language picker, following the desktop's `language` setting.
- Scrolling to the matching message from a search result, and highlighting the match.
- Committed UI tests. The drawer and search are verified in the simulator (§11).

## 3. Findings from the prototype

A throwaway Tuist project outside the repo (custom drawer with native `NavigationStack`/`List`/
toolbars inside) was driven with XCUITest on the iPhone 17 iOS 27.0 simulator:

| Question | Result |
| --- | --- |
| Edge swipe opens, left swipe closes | Works (`DragGesture` on the container). |
| Native `.searchable` (+ `.searchToolbarBehavior(.minimize)`) in the sidebar | Does nothing when tapped inside the drawer; the default placement renders no field. It works in a plain full-screen `NavigationStack`. **Not used.** |
| Hand-built search field (`TextField` in a glass capsule) | Works: focus, keyboard, live filtering. |
| Composer above the keyboard in the card | Works if the container ignores only `.container` safe areas, never `.all`. |
| Native `NavigationSplitView` instead of a custom drawer | Rejected: on iPhone it is a push transition, not a card slide-out. |
| Cosmetic | The sidebar showed through the translucent keyboard, and its bottom bar ghosted through. Fixed by §5 and §7. |
| Not verified | Real device feel, VoiceOver, Reduce Motion, iPad. |

## 4. Architecture

Dependency direction is unchanged: App → features → NetworkingKit → Models.

| Module | File | Change |
| --- | --- | --- |
| App | `Sources/App/SideDrawer.swift` | New. Generic sliding container (§5). |
| App | `Sources/App/AppShell.swift` | New. Replaces `RootView.swift` (deleted) (§6). |
| App | `Sources/App/AppWorkspace.swift` | Drop `rawValue` as display text; `title: LocalizedStringResource`. |
| App | `Sources/App/ExodusApp.swift` | Root view becomes `AppShell`. |
| App | `Resources/App/Localizable.xcstrings`, `InfoPlist.xcstrings` | New (§10). |
| App | `Project.swift` | Known regions and development region; English permission string. |
| ChatFeature | `ChatSidebarView.swift` | New. Replaces `ChatListView.swift` (deleted) (§7). |
| ChatFeature | `ChatSearchViewModel.swift` | New (§8). |
| ChatFeature | `ChatListViewModel.swift` | `delete(_:)` returns `Bool`; drop `relativeTime` and its tests (rows show titles only). |
| ChatFeature | `ChatDetailView.swift` | Glass composer, empty state, keyboard dismissal (§9). |
| ChatFeature | `ChatDetailViewModel.swift` | Optional initial title; localized fallback titles and error strings. |
| Models | `ChatSearchHit.swift` | New (§8). |
| NetworkingKit | `APIClient.swift` | `get(_:query:)` (§8). Client-generated error text localized. |
| SettingsFeature, PhilharmonicFeature | views and view model | String externalization only. |
| repo | `scripts/l10n.py`, `README.md` | New l10n tool (add, fill, seed, audit); README i18n section. |

## 5. SideDrawer (App target)

`SideDrawer<Sidebar: View, Content: View>` takes `@Binding var isOpen: Bool` and two view builders.

**Geometry and visuals.** `drawerWidth = min(0.78 × container width, 360 pt)`. Layers, back to
front: the sidebar (width `drawerWidth`, at the leading edge) and the content card (full container
size) offset by `x = clamp(base + drag, 0 … drawerWidth)`, where `base` is `drawerWidth` when open.
`progress = x / drawerWidth`. The card has the system background, continuous rounded corners of
`40 × min(progress × 4, 1)`, a shadow at `0.15 × progress` opacity, and a scrim (`systemBackground`
at `0.6 × progress`) that catches taps. The container uses `.ignoresSafeArea(.container)`.

**Gestures.** One `DragGesture(minimumDistance: 12)` attached with `simultaneousGesture` and
considered only when the drag is horizontal-dominant. When closed it starts only from
`startLocation.x < 28 pt`; when open it starts anywhere. On release the drawer opens if
`base + predictedEndTranslation.width > drawerWidth / 2`, animated. Tapping the scrim closes it.
The main screen's toolbar button toggles it. Opening dismisses the keyboard
(`UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), …)`).

**Motion.** `.snappy`. With Reduce Motion on: `.easeInOut(duration: 0.2)` and a fixed corner radius.

**Accessibility.** Closed: the sidebar layer has opacity 0, no hit testing and is hidden from
accessibility (this also removes the see-through artifact from §3). Open: the content card is
hidden from accessibility, and the scrim is a single button labeled "Close sidebar";
`accessibilityAction(.escape)` closes the drawer. The toolbar button's label is "Open sidebar" /
"Close sidebar".

No swipe actions exist on sidebar rows (§7), so the close gesture never competes with a row swipe.

## 6. AppShell (App target)

State: `activeChat: ActiveChat` (`id: String`, `title: String?`; a new chat is a fresh lowercased
UUID with no title), `isSidebarOpen`, `workspace: AppWorkspace` (always `.chat` today),
`showSettings`, `recentsReloadToken`.

The shell owns the card's `NavigationStack` (single root, no pushes) and its toolbar: leading
circular glass button `sidebar.leading` that toggles the drawer, trailing `square.and.pencil` that
starts a new chat. The card shows `ChatDetailView(...).id(activeChat.id)` so a chat change
recreates its view model, or `PhilharmonicPlaceholderView` for `.philharmonic` (unreachable while
the row is disabled).

| Event | Effect |
| --- | --- |
| Launch | New chat, drawer closed. |
| Drawer opens | Sidebar reloads Recents silently (no spinner when a list is already shown). |
| Select a Recents row or search result | `activeChat = (id, title)`; close the drawer. |
| New chat (sidebar pill or top-right button) | `activeChat` becomes a new chat; close the drawer. |
| Delete a chat from the sidebar | If it is the active chat, switch to a new chat. |
| Gear | Present `SettingsView` as a sheet over the shell; on dismiss bump `recentsReloadToken`. |
| Drawer closes | Sidebar leaves search mode and clears the query. |

The old workspace `Menu` and "Switch between Chat and Philharmonic" hint are removed.

## 7. Sidebar (`ChatSidebarView`, ChatFeature)

```swift
public struct ChatSidebarView<Workspaces: View>: View {
    public init(
        apiClient: APIClient, activeChatId: String, isOpen: Bool, reloadToken: Int,
        onSelectChat: @escaping (String, String?) -> Void,   // id, title
        onNewChat: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onDeleteChat: @escaping (String) -> Void,
        @ViewBuilder workspaces: () -> Workspaces
    )
}
```

Its own `NavigationStack` and `List(.plain)`. The workspace rows are a slot filled by the shell
(the enum lives in App): Chat (selected) and Philharmonic (disabled, "Coming soon").

**Normal mode.** Large title "Exodus"; a circular magnifier button top-trailing; the workspace
section; a "Recents" section with one row per chat, title only, the active chat highlighted. Rows
have a long-press `contextMenu` with a destructive "Delete" (no swipe actions). Bottom bar: a
prominent glass "New chat" pill (leading) and a glass gear button (trailing) via `ToolbarSpacer`.
Loading, empty and failure states are the MVP's (spinner only before the first load, "No chats
yet", "Can't load chats" with Retry, pull to refresh, one error surface), rewritten to fit the
narrow column. Reloads the user did not ask for (the drawer opening, Settings closing) use a new
`ChatListViewModel.refresh()`: it replaces the list silently and, while a list is on screen, drops
a failure instead of raising an alert (a stale list is still useful, and an alert on every drawer
open while offline would be noise); pull to refresh still uses `load()`. Titles can be long and
multi-line (real data: up to 1211 characters), so a row collapses whitespace and shows one line. Deletion keeps the MVP's `deletedIDs` guard so a chat does not reappear from a
concurrent reload; the view calls `onDeleteChat` only when `delete(_:)` returned `true`.

**Search mode** (entered from the magnifier). A top safe-area bar holds a glass capsule with a
magnifier icon, a `TextField("Search")` (focused on entry, `.submitLabel(.search)`, a clear button
when non-empty) and a "Cancel" button. The title collapses to inline and empty, the workspace
section is hidden, and the bottom toolbar is hidden (`.toolbarVisibility(.hidden, for: .bottomBar)`) so it
cannot ghost through the keyboard. An empty query shows Recents; a non-empty query shows the
results of §8. Cancel, or the drawer closing, leaves search mode.

## 8. Search

**Server contract** (`GET /api/v1/chat/search?query=<text>`, verified against the running desktop
on 2026-09-19): a bare JSON array (no envelope, no pagination, provider order) of message database
rows plus the chat's `title`. Fields
used: `id`, `chatId`, `role`, `searchText`, `title`, `createdAt`. `searchText` is the indexable text
of a user or assistant message (text blocks only; thinking blocks and tool-result rows are
excluded) and may be null. Other columns (`content`, `usage`, `toolName`, …) are ignored. The plan's
first task smoke-checks the endpoint.

**`Models.ChatSearchHit`** (`Decodable, Equatable, Sendable, Identifiable`): `id`, `chatId`,
`role`, `searchText: String?`, `title: String`, `createdAt: String?`. Decoding requires only `id`,
`chatId` and `title`; everything else is `decodeIfPresent`.

**`APIClient.get<T>(_ path: String, query: [URLQueryItem] = [])`.** Builds the URL with
`URLComponents`: callers pass query items instead of embedding `?query=` in the path
(`appendingPathComponent` would percent-encode the `?`). Query values are percent-encoded
with the URL-query-allowed set minus `+ & = # ? ;`, so `c++ & 100%` reaches the server intact. The
existing `get(_:)` calls and tests are unchanged.

**`ChatSearchViewModel`** (`@Observable @MainActor`, init takes `apiClient` and
`debounce: Duration = .milliseconds(300)`; tests inject a short one):

- State: `phase` (`idle`, `results([ChatSearchResult])`, `empty`, `failed(String)`) and
  `isSearching: Bool`. `ChatSearchResult` is `Identifiable, Equatable`: `id` (the chat id), `title`,
  `snippet`.
- A trimmed-empty query cancels work and sets `idle` with no request.
- Otherwise: cancel the previous task, bump a `generation`, set `isSearching`, sleep the debounce,
  request, and apply the outcome only if the generation is unchanged (stale responses are dropped).
  The previous `phase` stays visible while a new query is in flight; a progress view shows only
  while the phase is still `idle`.
- Success groups the hits by `chatId` in first-seen order, one result per chat, capped at 50 chats,
  and sets `results` or `empty`. Failure (never a cancellation) sets `failed(message)`; `retry()`
  reruns the current query.
- Snippet: from `searchText`, take the first case- and diacritic-insensitive match of the trimmed
  query, 40 characters before and 80 after, collapse runs of whitespace to one space, and add "…"
  where truncated. A non-nil `searchText` with no match uses its first 120 characters; a nil
  `searchText` yields no snippet (the row shows only the title).

A result row shows the title (one line) and the snippet (two lines, secondary). Tapping it calls
`onSelectChat(chatId, title)`. Empty and failed phases show "No results" and "Search failed" with
Retry.

## 9. Main screen

- **Top bar** (§6): drawer toggle, title, New chat. The inline title comes from `ChatDetailView`
  (`navigationTitle`). `ChatDetailViewModel` gains an optional initial title, so a chat opened from
  the sidebar or search shows its real title; the localized fallback is "New chat" for an empty
  transcript and "Chat" otherwise. Every title shown is collapsed to one line. This closes the MVP
  follow-up "real chat title in the detail screen".
- **Composer**: a `safeAreaBar(edge: .bottom)` glass capsule with a `TextField("Ask Exodus")`
  (1 to 5 lines) and a circular prominent glass button that is Send (`arrow.up`, disabled when
  `!canSend`) or, while a turn is in flight, Stop (`stop.fill`). The transcript uses
  `.scrollDismissesKeyboard(.interactively)`.
- **Empty state** for a loaded, empty, idle chat: a centered "What can I help with?". It never shows
  during the initial history load (`hasLoadedHistory`).
- Unchanged: message rows and bubbles, streaming, the pending "…" row, Stop, re-attaching to a
  running stream, pull-to-refresh history retry, the error alert.

## 10. Internationalization

**Mechanism.** String Catalogs (`.xcstrings`) in the App target: `Resources/App/Localizable.xcstrings`
and `Resources/App/InfoPlist.xcstrings` (the `NSLocalNetworkUsageDescription` permission text; its
English source moves into `Project.swift`). The feature modules are static frameworks linked into
the app, so `Bundle.main` is the right bundle for all of them and no `bundle:` argument is needed.
`Project.swift` sets `options: .options(defaultKnownRegions: ["en", "zh-Hant", "zh-HK", "ja", "ko", "fr", "de", "es", "pt-BR", "it"], developmentRegion: "en")`.

**Keys are the English source text.** `Text("Search")`, `Label`, `Button`, `navigationTitle`,
`TextField` and the other SwiftUI initializers localize literals automatically; anything else uses
`String(localized: "…")` or `LocalizedStringResource`. Rules:

- No sentence assembled by concatenation. Interpolations (`\(name)`) become `%@`/`%lld` keys.
- User data (chat titles, snippets, server text) is never a key: use a `String` variable or
  `Text(verbatim:)`.
- No `rawValue` as display text. Enums expose `title: LocalizedStringResource`.
- Brand names ("Exodus", "Philharmonic") are marked `shouldTranslate: false`.
- Ambiguous strings ("Chat" the workspace vs. "Chat" the fallback title) carry a `comment`.
- Text produced inside Models/NetworkingKit/view models (client-generated errors such as "Invalid
  server URL") uses `String(localized:)`. Server-provided error text is shown verbatim.
- Dates and numbers use system formatters, which follow the locale.

**Languages** (the desktop's set, `packages/shared/src/i18n/locales.ts` in the desktop repo `exodus`):

| Catalog language | Source of wording |
| --- | --- |
| `en` | source language |
| `zh-Hant` | desktop `zh-Hant-TW` |
| `zh-HK` | desktop `zh-Hant-HK` |
| `ja`, `ko`, `fr`, `de`, `es`, `pt-BR`, `it` | desktop catalogs |

There is deliberately no `zh-Hans`: the desktop makes Simplified Chinese fall back to English
(`resolveLocale`), and iOS matches it. Adding Simplified Chinese later is one more catalog column.
For every English string that also exists in the desktop catalogs
(`packages/shared/src/i18n/locales/<locale>/*.json`), the desktop's translation is reused
(`scripts/l10n.py seed-from-desktop` copies it); the rest is translated when the catalogs are filled in. Those translations have not been
reviewed by a native speaker, and the README says so.

**Language selection.** iOS picks the language from the phone's preferences; users can also set a
per-app language in Settings. There is no in-app picker and the desktop's `language` setting is not
read. Acceptance check: with the simulator in `zh-Hans`, the app shows English. If iOS instead
picks a Traditional catalog for Simplified users, ship an explicit `zh-Hans` column whose values
equal the English source (added to the shipped set and documented in the README).

**Existing strings.** The hard-coded Chinese ("即将支持", "连接", the Philharmonic placeholder line,
the local-network permission text) becomes English source plus translations. The known strings are
inventoried in the plan; the audit below is the source of truth for completeness.

**Audit (`scripts/l10n.py audit`, Python 3, standard library only)**, modeled on the desktop's
`catalog-audit` and `no-hardcoded-strings` tests. It fails when:

1. a catalog key has no translated value in a shipped language (unless `shouldTranslate: false`);
2. a translation's placeholders (`%@`, `%lld`, `%1$@`, …) differ from the source's;
3. a catalog contains a language outside the shipped set;
4. a SwiftUI/`String(localized:)` string literal under `Sources/` is missing from the catalog
   (interpolations are normalized to placeholders; suppress a false positive with a trailing
   `// l10n:ignore`);
5. Swift source outside comments contains CJK characters;
6. a ternary of two string literals appears in Swift source (handed to a SwiftUI text initializer it
   may resolve to the non-localizing `String` overload; suppress a non-text use such as an SF Symbol
   name with `// l10n:ignore`).

Keys never referenced by code are reported as warnings.

## 11. Testing and verification

**Unit tests (Swift Testing)**, written before the code they cover:

- `ChatSearchViewModelTests`: empty query issues no request; debounce coalesces rapid edits; an
  older response arriving after a newer query is dropped; grouping keeps first-seen order, one
  result per chat, capped at 50; snippet windowing, whitespace collapse, no-match and nil fallbacks;
  failure sets `failed` and `retry()` recovers; cancellation is never surfaced.
- `APIClientTests`: query encoding for `c++ & 100%`, CJK, spaces and `#`; a path with `?` is not
  mangled; existing tests still pass.
- `ChatSearchHitTests`: decodes a real row with extra columns; null `searchText`.
- `ChatListViewModelTests`: `delete(_:)` returns `true` on success and `false` on failure; the
  `relativeTime` tests are removed with the function.
- `ChatDetailViewModelTests`: initial title, fallback titles.

Tests assert structure, not copy; where copy is asserted it is compared with `String(localized:)`
of the same key. The unit-test bundles are not hosted by the app and carry no catalogs, so any copy
resolves to the English key.

**Simulator verification** (screenshots kept as evidence, driven by a temporary XCUITest that is not
committed): drawer open by edge swipe, close by left swipe and by tapping the scrim; search open,
type, results, Cancel; composer above the keyboard; the same screens with
`-AppleLanguages (de)` (long labels), `(zh-Hant)` and `(zh-Hans)` (expect English); Dynamic Type
at a large size. `python3 scripts/l10n.py audit` and every module's tests must pass.

**Human walkthrough** on a device, after the plan's last task: real-device drag feel, VoiceOver
through the drawer, Reduce Motion, a chat streamed end to end, search against real history.

## 12. Risks and known limits

- The drawer's gesture code is ours to maintain, and it is verified in the simulator only.
- The sidebar search field is hand-built because `.searchable` was inert inside the drawer on the
  iOS 27.0 simulator (§3). If a later SDK fixes that, it can be swapped in.
- Nine non-English catalogs are AI-translated unless copied from the desktop, and unreviewed.
- Using `Bundle.main` for all strings relies on the feature modules staying static frameworks.
- Search quality is the desktop's: `searchText` only, unpaginated, provider order.
- No automated UI regression tests for the drawer (they would need a stub server); the simulator
  checklist and the human walkthrough stand in.
- The app still requires an iOS 27+ device (deployment target 27.0).

## 13. Suggested build order (the plan owns the final task list)

0. Adopt `/api/v1` everywhere (fixes the shipped app against the current desktop).
1. i18n foundation: `Project.swift` options, empty catalogs, the audit script, externalize every
   existing string with English source only.
2. `APIClient.get(_:query:)`, `ChatSearchHit`, `ChatSearchViewModel` (TDD).
3. `SideDrawer` and `AppShell`; delete `RootView`.
4. `ChatSidebarView` with Recents, states, context-menu delete and the search UI; delete
   `ChatListView`.
5. `ChatDetailView` restyle and the initial-title change.
6. Fill all catalogs (reusing desktop wording); the audit goes green.
7. Simulator verification, README, memory notes, human walkthrough checklist.
