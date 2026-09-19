# Exodus iOS

A native iPhone client for the desktop Exodus app (`exodus`): it lists chats, sends messages,
streams the replies and edits the AI-provider settings, all through the desktop's local HTTP server.
It stores nothing but the server address. Swift 6, SwiftUI, no third-party dependencies. See the
[design spec](docs/superpowers/specs/2026-09-18-chat-settings-mvp-design.md) and the
[implementation plan](docs/superpowers/plans/2026-09-19-chat-settings-mvp.md).

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

The schemes are `Models`, `NetworkingKit`, `ChatFeature` and `SettingsFeature`. There is no `ModelsTests`
scheme: each module's scheme runs its test target. `-only-testing:` takes the Swift type name
(`-only-testing:ChatFeatureTests/ChatListViewModelTests`), not the `@Suite` display string; a wrong name
matches nothing and still prints `** TEST SUCCEEDED **`, so look for a `Test run with N tests` line.

## Modules

- `Models`: Codable wire types shared with the desktop (chat messages, SSE events, settings).
- `NetworkingKit`: REST and SSE clients, `ChatStreamManager` (keeps a reply streaming while you navigate), the stored server address.
- `ChatFeature`: chat list and chat detail (history, streaming send, Stop).
- `SettingsFeature`: server address and AI-provider settings.
- `PhilharmonicFeature`: placeholder for a later phase.
- `App`: composition root and the Chat/Philharmonic switcher.

## Connecting to the desktop

Run the desktop app from `../exodus` (`bun start`); it serves the API on port 60223 under `/api/v1`, the
versioned prefix this app addresses. The default address, `http://localhost:60223`, works from the Simulator
on the same Mac. On a real iPhone open Settings (gear),
then Connection, and enter the Mac's LAN IP or `<name>.local` with the port, e.g. `http://192.168.1.10:60223`.
iOS asks once for local-network permission.

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

Rules the audit enforces or relies on:

- Never build a sentence by concatenation; give the whole sentence a key with placeholders.
- Never pass a ternary of two string literals to a SwiftUI text initializer, because it can resolve to the
  non-localizing `String` overload. Use `if`/`else` with one literal per branch.
- User data (chat titles, search snippets, server text, model names) is shown from a `String` variable or
  `Text(verbatim:)`, never as a literal key.

Translations other than English are machine-generated unless they were copied from the desktop, and native
speakers have not reviewed them.

## Security note

The app talks plain HTTP to the desktop server. That server has no authentication and listens on all
network interfaces, so anyone on the same network can call it, including reading the provider API keys
stored in the desktop's settings. Use a network you trust. A token header is the follow-up named in spec section 8.
