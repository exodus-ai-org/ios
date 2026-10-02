# Health trends, archive, period reports and habits — design

Date: 2026-10-02 · Status: approved in brainstorming, awaiting spec review
Repos: `exodus-ios` (almost all of it) and `exodus` (one stateless route)
Prototype: `.superpowers/brainstorm/36445-1790902464/content/health-calendar-proto.html` (interactive; cell style **C**)

## 1. Goal

Health shows today well; it should also show **direction**: whether sleep, activity and recovery are getting better week over week and month over month, keep every daily note so the past can be read again, write weekly / monthly / quarterly / yearly reports from that archive, and support 21-day habits ("it takes 21 days to change a habit").

### Decided by the user vs. assumed

| Decided by the user | Recommended and accepted |
|---|---|
| Look-back trends + trends woven into the note first; habits on top | Built in three shippable phases (§8) |
| A calendar is the interaction for the archive | Trends and archive live together on one calendar page; the home gets a "This week" card |
| Day cells: style **C** — the day's state as the cell colour, a small ring in the corner | — |
| Archive **on the phone only**; the desktop keeps no health data (why Health has no desktop entry) | Reports are generated through a stateless desktop route, like the daily note |
| Days before the archive: filled from HealthKit, no backfilled notes | No model calls for history |
| Period reports: generated automatically on the first Health open after the period ends | At most 2 per open, newest first |
| Habits: presets only, checked automatically | Up to 3 at a time |
| Comparisons against one's own past are what makes the note valuable | Keep baseline/trend comparisons everywhere |

### Non-goals
- No sync of the archive to the desktop or iCloud (App Review: no health data in iCloud).
- No backfilled notes for days before the archive.
- No manual check-in habits (only habits Health can check).
- No widgets for trends in this spec.

## 2. Data and storage (phone)

### 2.1 Daily note archive — `HealthArchive`
- `ReportCache` keeps today's note in `Application Support/Health/report.json`. Every time a note is stored, it is also written to `Health/archive/YYYY/MM/DD.json` (`ArchivedDay`: the full `HealthSummary`, the day's `HealthSnapshot`, `generatedAt`). One entry per day; a regenerated note overwrites that day.
- Same protection as `report.json`: `.completeFileProtection`, `isExcludedFromBackup`.
- Revoking consent still clears today's report (as now); the archive stays. The Health menu gains **Clear archive** (confirmation; deletes `Health/archive` including reports).
- A corrupt or unreadable file reads as "no note that day".

### 2.2 Any day's numbers — `DayRecord`
- `DayRecord { day, sleepMin?, steps?, stepGoal, exerciseMin?, hrvMs?, restingHr?, waterCups?, bedtime?, mood: OdyMood }`, computed locally from HealthKit for any past day by generalising `SnapshotBuilder` (today-only today) to `snapshot(for day:)`, with the same rules for Ody's state.
- An in-memory cache keyed by day; today is never cached (it changes).

### 2.3 Trend maths — `TrendMath` (pure)
- For a `Period` (week Mon–Sun, calendar month, quarter, year, or any N-day window ending on a day): averages, min/max, target-hit rate (steps ≥ goal, sleep ≥ 7 h by default), count of days with data, and the change against the previous equal-length period (absolute and relative; "flat" under 3 %).
- One implementation for the home card, the calendar header, report inputs and habits.

### 2.4 Period reports — `PeriodReport`
- Stored at `Health/archive/reports/2026-W40.json`, `2026-09.json`, `2026-Q3.json`, `2026.json` (ISO week numbering).
- Content: `headline`, `headlineHighlight?`, `insights[]` (category, title, verbatim highlights, stat), `comparisons[]` (metric, current, previous, direction), `nudge?`, `generatedAt`, `period`.

### 2.5 Habits — `HabitStore`
- At most 3 active habits; each `{ id, kind, target, startDay }` with kinds: steps ≥ goal (default 8,000), sleep ≥ N h, in bed before HH:MM, exercise ≥ 30 min, water ≥ N cups. Stored locally (UserDefaults, small).
- Progress is derived from `DayRecord`s: days hit since start, current streak, day N of 21; never stored.

## 3. Screens

### 3.1 Home — "This week" card
- Under today's note: seven style-C cells (Mon–Sun), average sleep and daily steps with ↑/↓ against last week. Tap → calendar in week view.
- When a period report was generated in the last 2 days: a line "September report ready" on the card.

### 3.2 Calendar page (pushed from Health)
- Segmented: **Week · Month · Quarter · Year**; ‹ › pages; future days are empty cells.
- Header: three stats (average sleep, daily steps, HRV) with change vs the previous period.
- Report card under the header when that period has a report (or "Will be written when your computer is reachable" if pending).
- Body: Month → style-C month grid; Week → 7 large cells with a little more data; Quarter / Year → per-month bars (3 / 12), tap → that month.
- Screen titles (screenshots): "Health · October 2026", "Health · Week 40", etc.

### 3.3 Day sheet
- With a note: the archived insight-story cards exactly as on that day's home.
- Without: the day's numbers and "No note for this day".
- "Ask about this day" → Health's ask box with that day's `DayRecord` attached.

### 3.4 Report page
- The insight-story layout of the daily note: coloured headline, insight cards, comparisons, the nudge. "Ask about this report" like 3.3.

### 3.5 Habits (phase 3)
- A "Habits" section at the bottom of the calendar page: up to 3 cards ("Day 9 / 21", streak); "+" opens the preset picker.
- Selecting a habit highlights its hit days on the calendar and dims the rest.
- Day 21: Ody celebrates (confetti, haptic) and offers to remember the habit (existing memory suggestion flow).

### 3.6 Everywhere
- Light/dark, Dynamic Type up to AX sizes, VoiceOver labels for cells ("October 1, rested, sleep 7 h 40, 9,120 steps"), 10 languages via `scripts/l10n.py`, Reduce Motion respected.

## 4. Desktop route — `POST /api/v1/health/period-report`
- Same pattern as `/api/v1/health/summary`: LAN auth, lock and origin gates; **stores nothing**, logs no bodies.
- Request (zod, strict): `{ period: { kind, start, end }, current: Aggregates, previous: Aggregates|null, notes: [{ day, headline, insights: [{category, title}] }], habits: [{ kind, target, daysHit, streak, dayOfTwentyOne }], locale }`.
- Reads relevant memories only when the user enabled memory in chat (as the daily note).
- Response: the `PeriodReport` shape (§2.4); lenient parse like `parseHealthSummary` (strip invalid insights, degrade to headline-only); retry once.

## 5. Generation schedule
- On each Health appear: compute due periods (last week, last month, last quarter, last year) without a stored report; generate newest first, at most 2 per open, only with summary consent and a reachable computer with a model.
- Failure → mark pending in memory; try again on the next open. Never auto-regenerate an existing report; a manual refresh exists on the report page.

## 6. Error handling
- Offline / no model: report pending (§5); calendar, trends and habits are local and unaffected.
- No consent: no reports; everything local still works.
- Sparse data: the report says how many days had data; trends show "—" without a previous period.
- Corrupt archive file: treated as no note.

## 7. Testing
- iOS unit tests: `TrendMath` (averages, deltas, flat threshold, hit rates, week/month/quarter/year boundaries, leap year, DST), `HealthArchive` (write/read/overwrite/corrupt/clear), `DayRecord` builder with a fake HealthKit source, due-period scheduling and the 2-per-open cap, habit progress and streaks.
- Desktop vitest: request/response schemas, lenient parsing, no persistence.
- `-HealthGallery` states for calendar (week/month/quarter/year), day sheet with and without note, report page, habits; screenshots in light/dark/AX; `docs/health-device-checklist.md` extended.

## 8. Phases
1. Archive + `DayRecord` + `TrendMath` + calendar + home "This week" card + "Clear archive".
2. Period reports (desktop route + scheduling + report page + report cards).
3. 21-day habits.

Each phase ships on its own.
