# Exodus iOS

A native iPhone client for the desktop Exodus app (`universal-client`): it lists chats, sends messages,
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

Run `pnpm dev` in `../universal-client`; it serves the API on port 60223. The default address,
`http://localhost:60223`, works from the Simulator on the same Mac. On a real iPhone open Settings (gear),
then 连接, and enter the Mac's LAN IP or `<name>.local` with the port, e.g. `http://192.168.1.10:60223`.
iOS asks once for local-network permission.

## Security note

The app talks plain HTTP to the desktop server. That server has no authentication and listens on all
network interfaces, so anyone on the same network can call it, including reading the provider API keys
stored in the desktop's settings. Use a network you trust. A token header is the follow-up named in spec section 8.
