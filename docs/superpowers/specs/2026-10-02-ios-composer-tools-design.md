# iOS composer tools — design

Date: 2026-10-02 · Status: approved in chat, awaiting spec review
Repos: `exodus-ios` only (the desktop route already accepts everything below)
Desktop reference: `src/renderer/components/composer-tools.tsx` (`ComposerToolsButton`, `ActiveToolPills`), `file-preview.tsx`

## 1. Goal

The phone's composer gets the desktop's `+` button, so a question asked from the phone can carry pictures, a reasoning effort and Deep Research, and the connected MCP tools can be looked up — as on the computer.

### Decided by the user vs. assumed

| Decided by the user | Recommended and accepted |
|---|---|
| Same four entries as the desktop's `+` menu | One `+` button left of the text field |
| Pictures from the photo library **and the camera** | Pictures are downscaled on the phone before sending |
| — | Choices last for the app session, not per chat, like the desktop's atoms |
| — | Active choices show as removable pills above the field (`ActiveToolPills`) |

### Non-goals
- Files other than images (PDF, documents): the wire (`userContentSchema`) carries only text and image blocks; a separate feature.
- Editing MCP servers from the composer (Settings › MCP already does that); the composer's list is read-only.
- Per-chat memory of the choices.

## 2. The menu (`+`)

A `Menu` on a `plus` glyph, left of the field, tinted when something is active (the desktop's blue trigger):

1. **Photo Library** — `PhotosPicker`, images only, several at once.
2. **Take Photo** — the camera (`UIImagePickerController` with `.camera`, wrapped), hidden when the device has no camera (simulator).
3. **Reasoning** — a submenu of the levels the **current model** supports, `off` first (`SettingsSnapshot.providerConfig.modelSnapshot.reasoningLevels`, the desktop's `useAvailableEffortLevels`); the entry is hidden when the model lists none. The chosen level shows beside the entry.
4. **Deep Research** — a toggle. Deep Research and a reasoning level exclude each other, as on the desktop: turning Deep Research on sets reasoning `off`; picking a level other than `off` turns Deep Research off.
5. **MCP Tools (N)** — only when N > 0 (`GET /api/v1/mcp/tools`); opens a sheet listing each server's tools with their descriptions (Markdown), read-only, with a line pointing to Settings › MCP.

Strings come from the desktop's keys where they exist (`chat:composerTools.*`, `chat:composer.reasoning*`, `chat:advancedTools.deepResearch`); new `ios:chat.composer.*` keys (Photo Library, Take Photo) in ten languages.

## 3. Pictures

- Picked pictures are decoded and **downscaled on the phone**: longest side ≤ 2048 px, JPEG quality 0.85 (PNG kept only when it has transparency), so a 12 MP photo is a few hundred KB, not 5 MB of base64.
- They sit in the composer as **removable 56 pt squares** above the field (the desktop's `FilePreview`: `size-14`, rounded, an ✕ at the corner), in pick order. At most **10** per message; the menu's photo entries are disabled at 10.
- Sending: the user message's `content` becomes `[{type:"text",text}, {type:"image",mimeType,data:<data URL>}…]` (the desktop's shape; `ChatMessage.userMessage(id:content:timestampMs:)` already builds it). A message may be pictures only (no text): Send is enabled when there is text **or** a picture.
- The sent message shows its pictures through the existing `UserImageStrip` (squares, +N).
- Camera: `NSCameraUsageDescription` widened to cover taking photos for a chat as well as scanning the pairing code.

## 4. Sending

`ChatStreamManager`'s body gains the session's choices: `advancedTools: ["Deep Research"]` when on (the desktop's `AdvancedTools.DeepResearch` value) and `reasoningEffort` when not `off`. The desktop route already reads both (`routes/chat.ts`: Deep Research forces `high`; `off` sends no reasoning option). Nothing changes on the desktop.

Regenerate re-sends with the choices as they are at that moment (the desktop's behaviour).

## 5. State

One `ComposerTools` observable for the app session (injected through the environment from the app shell, like the tone): `reasoningEffort`, `deepResearch`, and the model's `reasoningLevels` (refreshed from `/api/v1/settings` when a chat opens and when the model changes in Settings). A level the new model does not support falls back to `off`. Picked pictures belong to the chat's composer (its view model), and are cleared after sending, like the text.

## 6. Pills

Above the field, beside a quote if one is set: a pill per active choice — the reasoning level ("Reasoning: High") and "Deep Research" — each with an ✕ that turns it off; the desktop's `ActiveToolPills`.

## 7. Errors and edge cases
- A picture that fails to decode is skipped with a short notice; the others stay.
- Camera or Photos access denied: the system's own prompt/denial; the camera entry then explains and links to Settings (one alert).
- Settings unreachable: the Reasoning entry is hidden (no levels known); Deep Research still works.
- No MCP tools / endpoint fails: the entry is hidden.
- Reduce Motion, Dynamic Type (menu and pills are system controls; pills wrap), VoiceOver labels for the picture squares ("Picture 2 of 3, remove") and pills.

## 8. Testing
- Unit: downscale (size cap, JPEG vs PNG with alpha), content building (text only / pictures only / both), send body (`advancedTools`, `reasoningEffort`, omitted when off), mutual exclusion, level fallback when the model changes, 10-picture cap.
- `-MessageGallery`/composer gallery states: empty, three pictures, pills on; screenshots light/dark/AX.
- Device checklist: camera, Photos, a pictures-only message, Deep Research from the phone.
