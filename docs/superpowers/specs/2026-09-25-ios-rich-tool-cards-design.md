# exodus-ios: rich tool cards — design

Status: approved in conversation on 2026-09-25 after the owner reviewed the DEBUG "Card prototypes" page on device
("其他我看原型没啥问题, 细节等做完继续调"). Principle: the desktop is the hub; iOS matches the chat interaction and is a
remote for the computer (memory `product-principle-hub-and-ios`).

## 1. Scope

Real cards in the transcript (inside `ThinkingTimeline` steps / the run foot), replacing the generic JSON card, for:

| Tool / item | Card (the prototype's ★ choice) | Data |
|---|---|---|
| `read_file` | path + size header, preview that expands in place | result `{path, content, size}` |
| `write_file` | path, bytes, appended; content preview | args `{path, content, append}`, result `{path, bytes, appended}` |
| `edit_file` | unified diff built from args `old_string`/`new_string`; open for one edit, collapsed when a run has ≥3 | args + result `{replacements, linesBefore, linesAfter}` |
| `computer_use` | latest screenshot while running; filmstrip when finished (frames kept on the phone during the stream; history shows the final frame only) | live `{sessionId, step, action, thumbnail, awaitingHuman}`, end `{outcome, steps, summary}` / `{error}` |
| `deep_research` | progress while streaming, inline report preview when done, opens the full report | result `{id}` → `GET /api/v1/deep-research/result/:id` (+ messages) |
| `weather` | compact now + curve + 3 days; Details opens in place (desktop's card) | `WeatherResult` (WMO codes, local ISO times) |
| `image_generation` | the beui "image forming" loading effect (Metal shader + `TimelineView`, reduced-motion fallback), then the image with zoom | `details.images[]` with `mediaId` served by the desktop (`/api/v1/media/…`, device token); legacy `dataUrl`/`url` rows |
| `map_itinerary` | MapKit: `Marker` per place, `MapPolyline` between waypoints per day (optionally `MKDirections`), first 4 stops listed; tap → full-screen map (page or sheet) with day switching and place detail | `MapItineraryDetails` incl. `notice` |
| web search images / videos | image grid + video cards under the answer, like the desktop's `ImageGallery` / `VideoCards` | `webSearchResults` of the run |
| `update_memory` | the memory strip at the run foot: running → done (keys, before→after, Undo) → undone / partial / stale; failed; partly updated | `details.changes`, `POST /api/v1/memory/undo` |
| used memories | "Used N memories · keys" line at the run foot → sheet with entries (deleted greyed) and "This is wrong" (prefills + focuses the composer) | SSE `memories_used`, `GET /api/v1/memory/usage?chatId=` |

Out of scope: `create_artifact` (network-less WKWebView sandbox, its own project), terminal (exists), editing memory
entries from the sheet.

## 2. Rules

- Colour: the chosen colour tone (iOS-native mapping) for accents, charts, routes and pins.
- Strings: catalog keys; reuse the desktop's `chat:` keys (`memoryStrip.*`, `usedMemories.*`, `imageGeneration.*`,
  weather, deep research) after a `Vendor/exodus-locales` subtree sync; `ios:chat.card.*` only for phone-only copy.
- Render cost: settled turns never re-render while a later turn streams (the existing `AssistantTurnView` Equatable
  contract); card views take value types, decoding happens once per message.
- Network: images and screenshots come from the desktop through the paired session (token, pinned TLS); nothing is
  cached to disk beyond URLCache-free memory caches (the session is ephemeral).
- Errors: an undecodable `details` falls back to the generic card and reports through `LogReporter`.
- Accessibility: Dynamic Type up to AX sizes, VoiceOver labels, reduced motion.

## 3. Testing

Pure decoders and view-models per card with fixtures copied from the desktop's real shapes (the prototype fixtures);
`Equatable`/render-count tests for the transcript; snapshot-style screenshots via the gallery; `xcodebuild test` for
ChatFeature/Models/NetworkingKit/MarkdownKit; l10n audit exit 0.
