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

## Build and run

```sh
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
shows a QR code: `exodus://pair?h=<hosts>&p=60224&c=<one-time code>&f=<certificate fingerprint>&n=<name>`
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
`Resources/App/InfoPlist.xcstrings`. Both are keyed by the English source text. SwiftUI string literals
(`Text("Save")`, `Button("Cancel")`, `.navigationTitle(...)`) localize automatically; other code uses
`String(localized: "…")` or `LocalizedStringResource("…")`. The modules are static frameworks, so every
string resolves from the app's main bundle.

The shipped languages are English (the source), Traditional Chinese for Taiwan (`zh-Hant`) and for Hong Kong
(`zh-HK`), Japanese, Korean, French, German, Spanish, Brazilian Portuguese and Italian. There is no Simplified
Chinese, matching the desktop: a Simplified Chinese phone shows English.

`scripts/l10n.py` (Python 3.9, standard library only) maintains the catalogs:

```sh
python3 scripts/l10n.py add "Text" --comment "Where it appears and what any %@ stands for."
python3 scripts/l10n.py fill translations.json   # {"Text": {"de": "…", "ja": "…"}}
python3 scripts/l10n.py seed-from-desktop ~/Code/exodus/exodus/packages/shared/src/i18n/locales
python3 scripts/l10n.py audit                    # add --source-only while strings are still being added
```

`add` creates the key, `fill` merges translations, `seed-from-desktop` copies the desktop's translation of every
string whose English text matches one of its own, and `audit` fails when a Swift literal is missing from the
catalog, a shipped language is untranslated or a placeholder differs from the English.

What the audit actually reads is limited, so prefer the forms it checks. It finds string literals passed to
`Text`, `Label`, `Button`, `TextField`, `SecureField`, `Section`, `Picker`, `Toggle`, `ContentUnavailableView`,
`.navigationTitle`, `.accessibilityLabel`/`.accessibilityHint`/`.accessibilityValue`, `.alert`,
`String(localized:)` and `LocalizedStringResource`, plus CJK characters in Swift source outside comments, and
ternaries of two string literals. Other initializers are NOT checked — `Menu`, `NavigationLink`,
`LabeledContent`, `Link`, `.confirmationDialog`, `.help`, `.badge` and `.searchable(prompt:)` among them — so a
literal passed to one of those would ship untranslated without the audit noticing. Use a checked form, or
extend the tool first.

Rules the audit enforces or relies on:

- Never build a sentence by concatenation; give the whole sentence a key with placeholders.
- Never pass a ternary of two string literals to a SwiftUI text initializer, because it can resolve to the
  non-localizing `String` overload. Use `if`/`else` with one literal per branch.
- User data (chat titles, search snippets, server text, model names) is shown from a `String` variable or
  `Text(verbatim:)`, never as a literal key.

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
