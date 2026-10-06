# Interactive blocks — device checklist

Phase 1 of `docs/superpowers/specs/2026-10-06-interactive-blocks-design.md`: the questionnaire (`exodus-ask`) and the
confirmation (`exodus-confirm`), on the desktop and on the iPhone.

## Desktop

- [ ] Ask "My legs itch after every shower — what should I do?": the reply ends with a questionnaire, one question at a time ("Question 1 of 2"), Previous / Skip / Next, and on the last question "Anything else?" and Submit. Submit: your answer appears as a card (the title, then the answers, quieter); the next reply uses the answers; the questionnaire above becomes a summary with your picks and "Answered".
- [ ] Skip every question and Submit: each is sent as "—" and the reply carries on with what it has.
- [ ] Ask "Add a dentist appointment next Tuesday at 10 to my calendar": a confirmation says what will happen before anything is done. Reject with a note: nothing is added. Ask again, Approve: it is added.
- [ ] While a reply is being written, Submit, Approve and Reject are disabled.
- [ ] While the reply streams the block shows as grey code, and becomes the control once its closing fence arrives.
- [ ] Reload the chat (or scroll back to an older page): answered blocks are still answered, an unanswered one is still open.
- [ ] Keyboard: Tab and the arrow keys move across the options, Enter on a focused option picks it, Enter in the note field submits the step, Cmd+Enter submits.
- [ ] A tool that asks for approval (a terminal command outside the workspace) still shows its approval card, not a confirmation block.
- [ ] Ask the assistant to show the questionnaire's JSON format inside a code block: it stays code.

## iPhone (paired with the desktop)

- [ ] The same questionnaire on the phone: a card, the questions numbered, 44 pt rows in the tone's accent; a tap plays the selection tap; "Other…" opens a field to type in; Submit plays the success tap and VoiceOver says "Sent". Your bubble shows the answer card; the block shows your picks and "Answered".
- [ ] Answer on the phone, open the chat on the desktop: the block is frozen there with your picks, and the other way round — with the phone and the desktop in different languages.
- [ ] A confirmation on the phone: details drawn as Markdown, the note field, Reject (bordered) and Approve (tinted); at the largest accessibility text size the buttons stack.
- [ ] Submit / Approve / Reject are disabled while a reply is being written; they enable when it ends.
- [ ] A block whose fence is still open while streaming shows as a code block, then becomes the control when it closes.
- [ ] Pick a few options, scroll far up the chat and back: the picks, the Other text and the note are still there.
- [ ] Dark mode: Submit and Approve draw their label in the colour the send button's arrow uses, readable on the tone's accent.
- [ ] VoiceOver: each option reads as a switch, "on" or "off"; the title, then the questions in order.
- [ ] Reduce Motion on: the block freezes without animating.
- [ ] Airplane mode, Submit: the run's error line appears under your answer; back online, Regenerate sends it again.
- [ ] Type in the composer, then answer a block: the composer still holds what you typed.
