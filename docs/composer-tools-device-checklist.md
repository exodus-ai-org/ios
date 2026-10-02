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
