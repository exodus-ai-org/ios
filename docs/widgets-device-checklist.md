# Widgets — on-device checklist

Things the simulator cannot show, or this repo's tooling cannot drive (adding a widget to the Home Screen has no
command-line route). Run on a real iPhone (iOS 27), paired with the desktop, after `-WidgetGallery` looks right.

- [ ] Add the small and the medium Exodus widget to the Home Screen, both Lock Screen widgets (circular and
      rectangular), and the Ask control to Control Center. Each appears under "Exodus" in its gallery.
- [ ] Open the app and the drawer (Recents load): within a moment the medium widget shows the three newest chats,
      newest first, each with its time.
- [ ] Open Health with the summary consent on: the small widget's top line shows today's sleep and steps, and
      Ody's face matches Health's hero (sleepy when it is tired or recovering, happy when it is happy, active or
      rested, content otherwise).
- [ ] Turn the consent off in Health's menu: the health line and the suggestion chip leave both widgets.
- [ ] Tap every element:
  - [ ] Ask (small, medium capsule, circular): a new chat with the keyboard up.
  - [ ] "Plan my day": a new chat with the text in the composer, not sent.
  - [ ] The health suggestion chip: Health with the question in its ask box and the attach chip on, not sent.
  - [ ] A recent chat: that chat.
  - [ ] Rectangular with today's note: Health. Without it ("Ask Exodus"): a new chat.
- [ ] Lock the phone: on the Lock Screen and in StandBy the chat titles and health numbers are redacted until
      unlocked.
- [ ] Control Center's Ask, and the Action button set to it: a new chat with the keyboard up, the app unlocking
      first when Face ID is due.
- [ ] Unpair in Settings → Computer: the recents and the health line vanish from the widgets.
- [ ] Through the day: in the evening the night sky with white text and stars; at noon the warm sky with dark
      text. Every hour the sky moves on without opening the app.
- [ ] Tinted and clear Home Screen (Edit → Customize): no sky, Ody's outline, everything legible.
- [ ] Largest text size (Settings → Accessibility → Larger Text): titles truncate, nothing overlaps or is cut off.
