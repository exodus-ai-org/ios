# Exodus iOS

A native iPhone client for the desktop Exodus app (`exodus`): a ChatGPT-style slide-out drawer lists your
Recents and searches them, and the chat beside it sends messages, streams the replies and edits the
AI-provider settings, all through the desktop's local HTTP server. It stores nothing but the server address.
Swift 6 and SwiftUI: prefer native frameworks as much as possible and reach for a third-party library only
where it is clearly worthwhile — today the app has none. See the MVP
[design spec](docs/superpowers/specs/2026-09-18-chat-settings-mvp-design.md) and
[implementation plan](docs/superpowers/plans/2026-09-19-chat-settings-mvp.md), and the drawer and
localization work in its
[design spec](docs/superpowers/specs/2026-09-19-chatgpt-style-shell-and-i18n-design.md) and
[implementation plan](docs/superpowers/plans/2026-09-19-chatgpt-style-shell-and-i18n.md).

## Requirements

- Xcode 27 with the iOS 27 SDK (every target deploys to iOS 27.0).
- Tuist 4.208.0: `brew install --cask tuist`. The Xcode project is generated and gitignored.
- The Metal Toolchain component: the image-generation card's dither shader (`Sources/ChatFeature/ImageForming.metal`)
  is compiled by it, and a fresh Xcode install may not have it (the build then fails on that file with "cannot
  execute tool 'metal' due to missing Metal Toolchain"). Install it once with
  `xcodebuild -downloadComponent MetalToolchain`.

## Build and run

```sh
tuist install                # a fresh clone: fetches the Swift packages (swift-markdown) first
tuist generate --no-open
open ExodusIos.xcworkspace   # run the App scheme, or from the command line:
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "generic/platform=iOS Simulator"
```

Regenerate after adding or removing files. `DEVELOPMENT_TEAM` in `Project.swift` is the author's; change it for your device.

## Tests

```sh
xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "platform=iOS Simulator,name=iPhone 17"
```

The schemes are `Models`, `NetworkingKit`, `ChatFeature`, `SettingsFeature` and `App`. There is no
`ModelsTests` scheme: each module's scheme runs its test target. `-only-testing:` takes the Swift type name
(`-only-testing:ChatFeatureTests/ChatListViewModelTests`), not the `@Suite` display string; a wrong name
matches nothing and still prints `** TEST SUCCEEDED **`, so look for a `Test run with N tests` line.

## Modules

- `Models`: Codable wire types shared with the desktop (chat messages, SSE events, settings).
- `NetworkingKit`: REST and SSE clients, `ChatStreamManager` (keeps a reply streaming while you navigate), the stored server address.
- `ChatFeature`: chat sidebar (Recents, search) and chat detail (history, streaming send, Stop).
- `SettingsFeature`: server address and AI-provider settings.
- `OdyKit`: Ody as a living SwiftUI character (breath, blink, poke, eight faces), the ten state scenes, the day sky,
  confetti and the heartbeat wave — art from the desktop's `brand/art.mjs`.
- `HealthFeature`: the Health workspace — reads Apple Health through `HealthDataSource`, builds the day's snapshot,
  asks the computer for a daily note (`POST /api/v1/health/summary`), and hands questions to Chat with the numbers
  attached. Every note is kept on the phone by day (`HealthArchive`: `Application Support/Health/archive`, complete
  file protection, never backed up), and a calendar shows any past day and the trend by week, month, quarter and
  year (`DayRecord`, `TrendMath`, `TrendsView`); `-HealthGallery calendar-month` (and `-week`, `-quarter`, `-year`,
  `day-note`, `day-empty`) opens it on preview data. Each finished week, month, quarter and year gets a report on the
  next Health open (`PeriodReports`; `POST /api/v1/health/period-report`, kept in `archive/reports`), shown on the
  calendar, on the home and on its own page (`-HealthGallery report-page`, `report-card`, `report-pending`,
  `report-home`). Design: [spec](docs/superpowers/specs/2026-10-01-health-workspace-design.md),
  [trends spec](docs/superpowers/specs/2026-10-02-health-trends-design.md).
- `WidgetKitShared`: what the app and its widgets share — the snapshot (`WidgetSnapshot`: up to three recent chat
  titles and today's health glance, never a message) kept in the App Group `group.app.yancey.exodus`, the
  `exodus://` links a widget opens (`DeepLink`: a new chat, pre-filled but never sent; a chat; Health's ask box)
  and the rules an entry is drawn by. Design: [spec](docs/superpowers/specs/2026-10-01-ios-widgets-design.md).
- `WidgetUI`: the widgets' views — the small and medium Home Screen widgets over the Health hero's sky at the
  entry's hour, the two Lock Screen widgets, and Ody's outline on tinted screens.
- `ExodusWidgets` (`Widgets/Sources`, embedded in the App): the widget extension — Ask (small, medium), Today (Lock
  Screen) and the Ask control for Control Center and the Action button. It links only the two widget modules and
  `OdyKit`, never `NetworkingKit` or the keychain: it reads the snapshot the App writes. Launch the App with
  `-WidgetGallery` (DEBUG) to see every widget on fixtures; [device checklist](docs/widgets-device-checklist.md).
- `PhilharmonicFeature`: placeholder for a later phase.
- `App`: composition root, the drawer shell (`SideDrawer`, `AppShell`, and `DrawerPhysics` — the
  drawer's gesture, spring and rubber-band math, tested on its own) and the workspace list.

## Connecting to the desktop

Run the desktop app from `../exodus` (`bun start`); it serves the API on port 60223 under `/api/v1`, the
versioned prefix this app addresses. The default address, `http://localhost:60223`, works from the Simulator
on the same Mac. On a real iPhone open Settings (gear),
then Connection, and enter the Mac's LAN IP or `<name>.local` with the port, e.g. `http://192.168.1.10:60223`.
iOS asks once for local-network permission.

## Connecting to the computer

A device reaches Exodus only after it has been **paired**. On the computer, Settings → Devices → Pair a device
shows a QR code: `exodus://pair?h=<hosts>&p=63129&c=<one-time code>&f=<certificate fingerprint>&n=<name>`
(`PairingLink`). Settings → Computer here scans it (`QRScannerView`, VisionKit) — or pastes the link, which is
what the Simulator does — and `ServerConnection.pair` trades the code for a per-device token over HTTPS.

- **Trust is the pin.** The computer's certificate is self-signed; `PinnedSessionDelegate` accepts exactly the
  certificate whose SHA-256 came with the QR code, checks no CA and no host name (so an IP, a `.local` name or a
  tailnet name all work), and does so during the TLS handshake — before a byte of any request is sent. With no
  pin, no TLS server is trusted at all. `ServerConnection.session` is the one `URLSession` that carries it;
  `APIClient` and `SSEClient` both use it.
- **The token is behind Face ID.** `KeychainCredentialStore` keeps it in one Keychain item with access control
  `biometryCurrentSet` or device passcode, this device only, never synced — a device without a passcode cannot
  pair. `UnlockGate` reads it on a cold start and again after more than five minutes in the background
  (`ServerConnection.backgroundGrace`); in between it lives in memory only.
- **Every address in the QR code is kept.** The desktop lists each of its addresses (the LAN IP, the
  Tailscale IP, its `.local` name); `APIClient` tries them in turn when one is unreachable and remembers the one
  that answered (`PairedServer.lastGoodHost`), so the same pairing works on the home Wi-Fi and, over Tailscale,
  from anywhere. The certificate pin does not depend on the address.
- **Revoked means unpaired.** A `401` to a request that carried our token clears the credential, and the app is
  back at pairing.
- **The Simulator needs none of it.** Unpaired, requests go to the manual address (`http://localhost:60223`),
  the computer's plaintext listener — which is bound to loopback, so a real device cannot use it.

The desktop side is `src/main/lib/lan/` in the exodus repo; its design is
`docs/superpowers/specs/2026-09-20-lan-pairing-sandbox-isolation-design.md` there.

## Localization

Every user-visible string lives in `Resources/App/Localizable.xcstrings`, and the permission prompt in
`Resources/App/InfoPlist.xcstrings` (keyed by the Info.plist key, `NSCameraUsageDescription`). In
`Localizable.xcstrings` the key is symbolic, never the English text, and every entry carries an explicit `en`
value: that is what the screen shows in English. There are two kinds of key:

- `<namespace>:<dotted.path>` for a string the desktop app also has (`chat:composer.send`,
  `common:action.cancel`), spelled exactly like the desktop's own `t()` key. Its translations come from the
  desktop, not from this repo.
- `ios:<module>.<screen>.<element>` for a string only this app has (`ios:settings.pairing.unpair`). Its
  translations are written here.

SwiftUI string literals (`Text("chat:composer.send")`, `Button("common:action.cancel")`,
`.navigationTitle(...)`) still localize automatically, but the literal is now the key, and SwiftUI shows the
catalog's value for the current language. A string with an interpolation, and any string outside a view, uses
`String(localized: "ios:…", defaultValue: "English text", comment: "…")`; `LocalizedStringResource("…")` also
takes a key. The modules are static frameworks, so every string resolves from the app's main bundle.

The shipped languages are English (the source), Traditional Chinese for Taiwan (`zh-Hant`) and for Hong Kong
(`zh-HK`), Japanese, Korean, French, German, Spanish, Brazilian Portuguese and Italian. There is no Simplified
Chinese, matching the desktop: a Simplified Chinese phone shows English.

`scripts/l10n.py` (Python 3.9, standard library only) maintains the catalogs:

```sh
python3 scripts/l10n.py add "ios:chat.detail.copyButton" --en-value "Copy" --comment "Where it appears and what any %@ stands for."
python3 scripts/l10n.py fill translations.json   # {"ios:chat.detail.copyButton": {"de": "…", "ja": "…"}}
python3 scripts/l10n.py sync-from-desktop        # Vendor/exodus-locales by default
python3 scripts/l10n.py audit                    # add --source-only while strings are still being added
python3 -m unittest Tests.L10nScriptTests.test_l10n   # the script's own tests
```

`add` creates the key (an `ios:` key needs `--en-value`; a desktop key needs none, the sync writes it), `fill`
merges translations into an `ios:` key, and `sync-from-desktop` copies the desktop's translations, all ten
languages, into every catalog key that is not an `ios:` key (`zh-Hant-TW` becomes `zh-Hant`, `zh-Hant-HK`
becomes `zh-HK`; `{{x}}` becomes `%@` and a literal `%` becomes `%%`). To use a desktop string, `add` its key,
use it at a call site and run the sync; a desktop key that is not in the catalog is never created. `ios:` keys
are never touched. A desktop plural (`approval.truncatedNote_one`, `…_other`) is added under its base key
(`chat:approval.truncatedNote`) and synced as a catalog plural: each language gets the forms the desktop has, and
`{{count}}` becomes `%lld`, because the plural rule needs a number: its call site passes an `Int`, not a
`String`, and `{{count}}` must be the English text's first placeholder. A language that orders the placeholders
differently from the English (ja and ko `chat:placeDetail.pagination`: "{{total}}件中{{index}}件目") gets
positional ones (`%2$@件中%1$@件目`) and is listed as a note. A shared key the desktop lacks in any language
(renamed or removed there?) is an error, and so is one the desktop writes with i18next markup (`<1>…</1>`,
`<strong>`), one added with a plural suffix instead of its base key, or one whose languages do not all have the
same placeholders: such a string gets an `ios:` key of its own. Either error is listed and makes the sync exit
1, after it has updated and saved every other key. Without a catalog (the hostless unit tests) a
`String(localized:)` shows its `defaultValue:`, so a plural's call site branches on the count and gives each
English form as its own `defaultValue:`. `audit` fails when a Swift literal names a key that is not in the
catalog (exact match), an entry has no explicit `en`, a shipped language is untranslated, a placeholder differs
from the English, a `String(localized:)` call has no `defaultValue:` or one whose text differs from the
catalog's `en` (for a plural, from every English form), or a key that is not `ios:` is missing from
`Vendor/exodus-locales` (its text would have no recorded source).

The sync overwrites every shared key's translations on every run. A stale translation is a bug, not a feature:
never hand-edit a shared key (the next sync reverts it, and the fix belongs in the desktop's catalog), and re-run
the sync whenever `Vendor/exodus-locales` is refreshed. Refresh it from a desktop commit, never its working
tree. `git subtree pull` refuses a dirty working tree, so when this checkout has uncommitted work, pull in a
throwaway worktree and fast-forward (the commit touches only `Vendor/`). A scratch clone keeps the split branch
out of the desktop repository:

```sh
git clone -q --no-checkout ~/Code/exodus/exodus /tmp/exodus-split       # add -b <branch> for a branch other than master
git -C /tmp/exodus-split subtree split --prefix=packages/shared/src/i18n/locales <commit> -b exodus-locales-split
git worktree add --detach /tmp/ios-subtree HEAD
git -C /tmp/ios-subtree subtree pull --prefix=Vendor/exodus-locales /tmp/exodus-split exodus-locales-split --squash \
  -m "chore(locales): sync the desktop catalogs (<what>)"
git merge --ff-only "$(git -C /tmp/ios-subtree rev-parse HEAD)"
git worktree remove /tmp/ios-subtree && rm -rf /tmp/exodus-split
```

Then `python3 scripts/l10n.py sync-from-desktop`. The subtree pull commits by itself; the sync's result is left
to review and commit.

What the audit actually reads is limited, so prefer the forms it checks. It finds string literals passed to
`Text`, `Label`, `Button`, `TextField`, `SecureField`, `Section`, `Picker`, `Toggle`, `ContentUnavailableView`,
`.navigationTitle`, `.accessibilityLabel`/`.accessibilityHint`/`.accessibilityValue`, `.alert`,
`String(localized:)` and `LocalizedStringResource`, and each must be a catalog key; it also flags CJK
characters in Swift source outside comments, and ternaries of two string literals. Other initializers are NOT
checked — `Menu`, `NavigationLink`, `LabeledContent`, `Link`, `.confirmationDialog`, `.help`, `.badge` and
`.searchable(prompt:)` among them — so a literal passed to one of those would ship untranslated without the audit
noticing. Use a checked form, or extend the tool first.

Rules the audit enforces or relies on:

- Never build a sentence by concatenation; give the whole sentence a key with placeholders.
- Never pass a ternary of two string literals to a SwiftUI text initializer, because it can resolve to the
  non-localizing `String` overload. Use `if`/`else` with one literal per branch.
- User data (chat titles, search snippets, server text, model names) is shown from a `String` variable or
  `Text(verbatim:)`, never as a literal key.
- `String(localized:)` in non-view code carries `defaultValue:` with the English text. The unit-test targets
  are hostless (no test host, so no catalog in `Bundle.main`), and without `defaultValue:` the call returns the
  raw key, so a test that compares the text fails. Views keep the plain literal.
- A key shared with the desktop that has a placeholder gets `%@` from the sync (`{{count}}` becomes `%@`), so
  its call site interpolates a `String` (`String(n)`, `n.formatted()`, a formatted `Date`), never a raw `Int` or
  `Date`: Xcode derives `%lld` from an `Int` argument, which no longer matches the `%@` in the translations,
  and the audit cannot see argument types. The one exception is a shared plural's count (`%lld`), which is
  passed as an `Int`. An `ios:` key with a placeholder keeps the typed one Xcode derives from its argument
  (`ios:networking.error.httpStatus` is `HTTP %lld`, passed an `Int`).

Translations other than English are machine-generated unless they were copied from the desktop, and native
speakers have not reviewed them.

## Known limits

The sidebar's search field is hand-built rather than `.searchable`, because `.searchable` was inert inside the
drawer on the iOS 27.0 simulator. There are no automated UI tests for the drawer: a committed test would need a
stub server, so the drawer, the search flow, German, French, Japanese and Traditional Chinese (Taiwan), plus the
Simplified Chinese fallback to English, were checked by hand in the Simulator with a temporary XCUITest target
that is not part of this repository. Korean, Spanish, Brazilian Portuguese, Italian and Hong Kong Chinese have
not been looked at on screen. Opening a chat whose last message is very tall under-scrolls: the transcript
parks part-way up that message instead of at the bottom, so the end of the newest reply has to be
scrolled down to. Reproduced in the Simulator and left as it is.

## Security note

The app talks plain HTTP to the desktop server. That server has no authentication and listens on all
network interfaces, so anyone on the same network can call it, including reading the provider API keys
stored in the desktop's settings. Use a network you trust. A token header is the follow-up named in spec section 8.
