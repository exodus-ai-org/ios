# Health — on-device checklist

Things the simulator cannot show. Run on a real iPhone (iOS 27) with an Apple Watch's sleep data if possible.

- [ ] Poke Ody: soft haptic, squash and spring back; a tired Ody yawns.
- [ ] A tired Ody's eyes are half-lidded.
- [ ] Scrub the hero left: the knob and the time follow the finger (left = earlier, right = later); sky darkens, Ody lies down and sinks in deep sleep; a selection tick at each stage edge; fling carries on and settles; "Back to now" springs home with a tick.
- [ ] A tap on "Back to now" works.
- [ ] Scrubbing the hypnogram horizontally does not fight vertical scrolling of the page.
- [ ] A right swipe that starts anywhere on the hero (Ody's scene or the stage track) scrubs — rubber-banding at now — and never moves the drawer; one that starts on the cards opens the drawer.
- [ ] A swipe from the left edge below the hero opens the drawer with no lag.
- [ ] Pull to refresh: Ody stretches with growing resistance; release writes the note again; success haptic when done.
- [ ] Remember: card flies into the bindle, bindle bounces, success haptic; Settings → Memory shows the entry.
- [ ] Step goal reached: confetti once that day, not again on reopening.
- [ ] Body detail: tapping the glass logs 250 ml (visible in the Health app); the water leans as the phone tilts; 8th cup gives a success haptic.
- [ ] Recovery detail: the heartbeat wave pulses at the resting heart rate.
- [ ] Zoom transitions: a card grows into its detail header and shrinks back.
- [ ] Reduce Motion on: Ody still, no confetti, the memory card fades instead of flying, no slosh, scrub without momentum.
- [ ] Lock the phone on Health, unlock: data reloads without errors.
- [ ] Deny Health access in Settings → Health → Exodus: home shows the no-data Ody with the explanation and Open Settings.
- [ ] End to end with the desktop running (paired, model key set): ladybug menu → write sample health data → pull to refresh → a real note appears → Remember → Settings → Memory shows it → ask "Why am I tired?" → Chat opens a new chat showing the health card and an answer.

## Calendar and archive (trends phase 1)

- [ ] The home's "This week" card shows Monday–Sunday, today outlined, days to come pale; tapping it opens the calendar on this week.
- [ ] Week · Month · Quarter · Year switch with a selection tick; ‹ › slide the page in from its side with a tick; › is disabled on the current period; with Reduce Motion the page cross-fades and cells don't shrink when pressed.
- [ ] On a phone with a year of Apple Watch sleep, the Year view appears within about a second, and paging back and forth through months reads instantly the second time.
- [ ] Today's cell and the home card pick up new steps after a walk (leave Health and come back).
- [ ] Tap a past day with a note: the sheet is titled with the date and shows that day's note as it was, its weekday where "Today" was. Tap a day before the archive began: its numbers and "No note for this day".
- [ ] In a day sheet, ask a question with the day attached: a new chat opens with the health card showing that day's numbers and the date.
- [ ] VoiceOver on a month cell reads like "October 1, Rested or active, Sleep 7h 40m, 9,120 steps"; the header tiles read "Avg. sleep, 7h 12m, Up 20m, vs last week".
- [ ] Largest accessibility text size: the month grid keeps seven columns; the week becomes rows; the stat tiles and the home card's numbers stack.
- [ ] Turn off "Write daily notes": today's note goes, past notes still open from the calendar.
- [ ] Health menu → Clear archive → confirm: success tap; past days now say "No note for this day"; today's note is still on the home.
- [ ] Lock the phone while Health is open, unlock: the calendar and today's note load without errors (the archive's files are protected while locked).
- [ ] Change the iPhone's region to United States (weeks start Sunday): the calendar still runs Monday–Sunday and the week number is unchanged.

## Period reports (trends phase 2)

- [ ] With "Write daily notes" on and the computer reachable, open Health the day after a week (or month) ends: after the day's note, the calendar on that period shows its report card within a minute, and the home shows "<period> report ready" under This week for two days.
- [ ] One open writes at most two reports (desktop log: at most two "Period report written" lines per Health open); the rest come on the next open, newest first.
- [ ] Quit the desktop app and open Health: the calendar on last month says "Will be written when your computer is reachable." with Write now; start the desktop, tap Write now: Ody writes, the card becomes the report, success tap.
- [ ] Report page: "Monthly report" over the coloured headline, the insight cards, "vs last month" with green/orange arrows (resting heart rate down is green), the idea, "Written …"; when the month had gaps, "N of M days had data".
- [ ] Write again: the old report stays while the spinner shows, then the new one, success tap. With the computer off: the old report stays and one line says it couldn't be written.
- [ ] Ask about the report: a new chat opens with the Health card and the question; the answer talks about that period's numbers.
- [ ] Turn "Write daily notes" off while a report is being written: it never appears; kept reports still open; no "Will be written" card shows.
- [ ] Health menu → Clear archive: the confirmation mentions reports; afterwards the calendar shows no report cards.
- [ ] VoiceOver: a comparison row reads "Resting heart rate, 59 bpm, Down, was 61 bpm"; the report card reads its kind and headline with "Opens the report."
- [ ] Largest accessibility text size: comparison rows stack, the report card and the home line wrap. Reduce Motion: the report page's cards appear without rising.
- [ ] The desktop's log for these calls carries timings and counts only — no numbers or sentences from the report.
