# Health Trends 2 — Period Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Health writes a report for every finished week, month, quarter and year — automatically on the first Health open after it ends, through a stateless desktop route — keeps it on the phone next to the daily notes, shows it as a card on the calendar, as a "report ready" line on the home's This week card, and on its own page told like the daily note.

**Architecture:** The desktop gets one stateless route, `POST /api/v1/health/period-report`, modelled exactly on `/api/v1/health/summary` (zod-strict request, memories only when memory is on for chats, one retry, lenient parsing, nothing stored, no bodies logged); its schemas and `parsePeriodReport` live next to `parseHealthSummary` in `packages/shared/src/types/health.ts`, and the desktop works out each comparison's direction from the numbers it was sent. On the phone, three pure tested layers come first: `PeriodReport` / `PeriodReportRequest` (wire + file shape), `PeriodReportInput` (a period's aggregates, the period before's and its kept notes → the request, clipped to the desktop's limits) and `PeriodReportStore` (`archive/reports/<id>.json`, protected, never backed up); then `PeriodReportSchedule` (the last finished week/month/quarter/year, newest first) and `PeriodReports`, an `@Observable` the home model owns, which writes the due ones on each Health open — at most two, only with consent, stopping at the first failure — and answers "ready / writing / pending / missing" for any period. The views (report page, comparisons card, calendar card, home line) read `PeriodReports`.

**Tech Stack:** Desktop: TypeScript, Hono, zod, vitest, bun. iOS: Swift 6, SwiftUI (iOS 27: `NavigationStack` value routes, `sensoryFeedback`, `AnyLayout`), Foundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-02-health-trends-design.md` — this plan is §8 phase 2: §2.4, §3.1 (the "report ready" line), §3.2 (the report card and "Will be written when your computer is reachable"), §3.4, §4, §5, §6 (report parts), §7 (desktop vitest: schemas, lenient parsing, no persistence; iOS: due-period scheduling and the 2-per-open cap; gallery states for the report page and card). Phase 1 plan (conventions and the seams used here): `docs/superpowers/plans/2026-10-02-health-trends-1-archive-calendar.md` — `Period.reportID(calendar:)`, `Aggregates: Codable`, `HealthArchive.clear()` deleting all of `archive/`, the slot under `TrendStatsHeader` in `TrendsView`.

## Decisions (spec gaps, resolved here)

1. **`insights[].title` is one sentence** (spec §2.4/§4 name it `title`): it plays the daily insight's `text` role — highlights are verbatim substrings of it, at most 160 characters. A note sent in the request carries its daily insights' `text` as `title`.
2. **`headlineCategory` is added** to the report (optional, as in the daily note) so the headline's phrase gets its category's gradient through the existing `ReportStory`.
3. **The desktop's answer has no `generatedAt`**: the phone stamps it when it keeps the report (the "ready in the last 2 days" line runs on the phone's clock). The desktop echoes `period` **from the request**, never the model's. The kept file also holds the `current` / `previous` aggregates it was written from (as `ArchivedDay` keeps the day's snapshot): "Ask about this report" sends them and the page's "21 of 30 days had data" reads them.
4. **Wire shapes:** `period = { kind: week|month|quarter|year, start, end }` with `end` the **last day, inclusive** ("2026-09-30"); `previous` is `.nullish()` (Swift leaves a nil optional out) and every `MetricSummary` number is `.nullish()` for the same reason. `habits` is always `[]` in phase 2; the schema already takes up to 3 (`kind: steps|sleep|bedtime|exercise|water`, numeric `target` — a bedtime is minutes after midnight).
5. **Comparisons:** `metric ∈ sleep, steps, exercise, hrv, restingHr, water`; `current` / `previous` are the model's display strings (≤ 24 characters); the **direction is recomputed by the desktop** from the averages sent (under 3 % = flat, as `TrendMath.change`); a comparison whose metric has no average this period or the period before is dropped (so no previous period → no comparisons), one per metric. The phone colours better/worse — up is better except the resting heart rate.
6. **Lenient parse:** invalid insights (unknown category, not a string, out of shape) are stripped one by one; a highlight not in its title is dropped; a headline phrase not in the headline and a nudge over 140 are dropped; up to 5 insights, several per category allowed. A report whose insights all fall away is **headline-only** (`insights: []`): the route retries once for it and keeps it on the second answer. Null (→ retry, then `AI_GENERATION_FAILED`) only without a usable headline (1–80 characters).
7. **What is due:** only the **last** finished week, month, quarter and year (no backlog), ordered by end date newest first and, when two ended together, the shorter first (on 1 October: September, then Q3, then week 39, then last year). A period with no data at all costs no call, never shows pending and does not count toward the cap. The cap counts calls that brought a report; the **first failure ends the open** and the rest wait for the next one.
8. **When:** on each Health appear (`HealthRootView.task`) and each return to the foreground, **after** the daily note (one thing at a time to the computer), never from pull-to-refresh; also right after consent is granted. Not before Apple Health access was asked (`odyState == .permission`). Two opens at once share one run.
9. **Pending** is in memory only (spec: "mark pending in memory"). The calendar card shows "Will be written when your computer is reachable." only for a due period that has data, while consent is on, with a **Write now** button. Revoking consent stops the run (a report in flight is not kept), clears pending; kept reports stay readable (like kept notes). **Clear archive** deletes the reports (they live in `archive/reports/`), and the last finished periods count as due again on the next open.
10. **Manual refresh** = **Write again** in the report page's toolbar (needs consent); the earlier report stays on screen and on disk until the new one is in; success tap on a new report; a failure shows one line under the report.
11. **The request's notes:** a week's and a month's notes carry their headline and insight sentences; a quarter's and a year's only headlines (a year stays a small request). Headlines are cut to 120 and titles to 200 **UTF-16 units** (zod counts JavaScript string length), so an emoji-heavy or old long note never makes the desktop reject the request forever.
12. **The home line:** the newest report kept within the last 48 h among the last finished periods: "%@ report ready" with the calendar's own title ("September 2026 report ready", "Week 39 report ready"). It is a second link under the week inside the same card (the week opens the calendar, the line opens the report), so `WeekCard` loses its own background and the home draws the card.
13. **Report page layout** (spec §3.4 order): eyebrow "Monthly report" over the coloured headline and the insight cards (`ReportStory`, without its idea), the comparisons card headed "vs last month" (the calendar's existing `versusLabel`), then the idea (`NudgeCard`, made internal), then "21 of 30 days had data" when sparse and "Written Oct 1". Ask box suggestions: "What changed most in this period?" and "What should I focus on next?". The question's attachment is `{period, current, previous, headline, insights}` — Chat's card shows its generic "Health" chip for a block that is not a day.
14. **The Clear-archive confirmation** now says notes **and reports**: the existing key `ios:health.archive.confirmMessage` gets the new English and nine translations (textual replace of that one entry).
15. **Timeout** 180 s for the period route (a longer prompt than the day's 120 s).
16. **No desktop strings**: the desktop has no Health UI (user's decision), so no `packages/shared/src/i18n` change.

## Global Constraints

- Two repos, both on branch `maintenance`, **never push**: iOS `/Users/yanceyleo/Code/exodus/exodus-ios`, desktop `/Users/yanceyleo/Code/exodus/exodus`. Read `exodus-ios/.superpowers/sdd/constraints.md` once; where it differs from this list (simulator, `git add -p`), this list wins.
- **Commits only through each repo's helper**, from that repo's root: `.superpowers/sdd/commit-mine.sh "<subject>" [--patch FILE.patch ...] <paths you own>` (iOS: `/Users/yanceyleo/Code/exodus/exodus-ios/.superpowers/sdd/commit-mine.sh`; desktop: `/Users/yanceyleo/Code/exodus/exodus/.superpowers/sdd/commit-mine.sh`, whose commit runs the desktop's pre-commit hook: `lint-staged` (oxlint + oxfmt) → `bun run typecheck` → `bun run i18n:check`). Never run `git add`, `git commit`, `git commit -a`, `git stash`, `git reset`, `git restore`, `git checkout -- <file>`, and never `--no-verify`. After each commit run `git show --stat HEAD` and confirm it lists ONLY your files; if not, or if the hook fails on files that are not yours, STOP and report BLOCKED (do not repair history, do not touch the user's files).
- **Both trees hold the user's uncommitted work.** iOS: `Resources/App/Localizable.xcstrings` (edited by this plan only through `/tmp/health2/add_keys.py`), `Sources/App/ExodusApp.swift` and many ChatFeature/Settings files (never touched), and `Resources/App/Assets.xcassets/LaunchLogo.imageset/Contents.json` pre-staged by someone else (must stay staged and out of every commit). Desktop: ~170 dirty paths (never touched). Every other file this plan edits was clean on 2026-10-02 (iOS HEAD `2d45d86`, desktop HEAD `d4715615`). Run `git diff --stat` at the start and end of every task: only the files your task names may change. **Before editing a file, run `git diff --stat -- <file>`; if it is no longer empty (the user edited it meanwhile), edit it only through `/tmp/health2/dual_edit.py` (Shared tooling) and commit its patch.**
- iOS: Swift 6 language mode, iOS 27.0 deployment target, Tuist 4.208 with buildable folders. **After creating any new file under `Sources/` or `Tests/`, run `tuist generate --no-open` before building** (otherwise a new `Sources/HealthFeature` file compiles into the resource-bundle target and cannot see the module's types).
- iOS builds/tests: simulator `992425B7-F06B-4CE5-9288-95C71C2F1D44`, `-derivedDataPath /tmp/health2-dd`. Tests: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd [-only-testing:HealthFeatureTests/<TypeName>] 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"`. A wrong `-only-testing` name still prints SUCCEEDED — confirm a `Test run with N tests` line with N > 0. App build: same with `build -scheme App` and `grep -E "error:|BUILD (SUCCEEDED|FAILED)"`.
- Desktop tests: from `/Users/yanceyleo/Code/exodus/exodus`, `bunx vitest run <path>`. Before a desktop commit: `bunx oxlint <your files>` and `bunx oxfmt <your files>` (so the hook changes nothing), then `bun run typecheck:node` and `bun run typecheck:shared`.
- **Health data stays on the phone** except what this route receives per request; the desktop stores nothing for it (no DB write, no file, no memory write), logs timings and counts only, never a number or a sentence. The desktop keeps no health data (user's decision: no Health entry on the desktop).
- **Trends against the person's own past are what makes the note valuable** (user's explicit priority): the prompt leads with the change against the period before; the page shows the comparisons.
- iOS strings: new keys `ios:health.periodReport.<element>`, all ten languages (en, zh-Hant, zh-HK, ja, ko, fr, de, es, pt-BR, it), inserted **textually** with `/tmp/health2/add_keys.py` (Task 5). Never run `scripts/l10n.py add`, `fill` or `save`. `python3 scripts/l10n.py audit 2>&1 | tail -1` prints `0 error(s)` at the end of every iOS task (warnings for keys not referenced yet are fine until Task 7). Views use the key literal (`Text("ios:health.periodReport.writeNow")`); code uses `String(localized: "…", defaultValue: "<exact English>", comment: "…")` / `LocalizedStringResource(…)` whose `defaultValue` equals the catalog's English exactly. Never concatenate a sentence; never pass a ternary of two string literals to a text initializer; user data and numbers go through `Text(verbatim:)`.
- Native frameworks only, no new packages (either repo). Haptics only through `.sensoryFeedback` (no sounds). Dynamic Type: text styles, layouts switch at `dynamicTypeSize.isAccessibilitySize` (stack, one per row). Reduce Motion: no animation where it would move; `ReportStory`'s rise is already off. Screen titles through `.screenTitle(ScreenTitles.join(enclosingTitle, title))` ("Health · September 2026").
- Match the surrounding code: doc comments short and plain, saying *why*; no comment noise; Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`); vitest `describe`/`it`.
- Do not dispatch subagents from inside a task.

## Shared tooling

### `/tmp/health2/dual_edit.py` (only if a file this plan edits has gained foreign edits)

Create it the first time it is needed (`mkdir -p /tmp/health2`). Every anchor in this plan is written against the committed file; when the working file also has the user's edits, use this instead of hand edits so the commit is HEAD + our edits only.

```python
#!/usr/bin/env python3
"""Edits a file that also holds someone else's uncommitted work, and commits only our part.

    dual_edit.py check EDITS.py          every edit applies to the working file and to HEAD's (nothing written)
    dual_edit.py apply EDITS.py          applies the edits to the working file (an edit already in is skipped)
    dual_edit.py patch EDITS.py OUT      writes OUT: HEAD's file -> HEAD's file with the edits, for commit-mine.sh --patch

EDITS.py defines PATH (repo-relative) and EDITS, a list of (old, new) exact-text pairs applied in order; each `old`
must occur once in the file as committed and once in the working file. Run from the repo root.
"""
import difflib
import os
import runpy
import subprocess
import sys
import tempfile

mode, edits_path = sys.argv[1], sys.argv[2]
spec = runpy.run_path(edits_path)
path, edits = spec["PATH"], spec["EDITS"]
work = open(path, encoding="utf-8").read()
head = subprocess.run(["git", "show", "HEAD:" + path], capture_output=True, text=True, check=True).stdout


def strict(text, label):
    for old, new in edits:
        n = text.count(old)
        if n != 1:
            sys.exit("%s: %s: `old` found %d times (want 1): %r" % (label, path, n, old[:100]))
        text = text.replace(old, new, 1)
    return text


def lenient(text):
    for old, new in edits:
        n = text.count(old)
        if n == 0:
            continue  # already applied
        if n > 1:
            sys.exit("working file: %s: `old` found %d times: %r" % (path, n, old[:100]))
        text = text.replace(old, new, 1)
    return text


if mode == "check":
    strict(head, "HEAD")
    strict(work, "working file")
    print("OK", path, len(edits), "edit(s) apply to HEAD and to the working file")
elif mode == "apply":
    new = lenient(work)
    open(path, "w", encoding="utf-8").write(new)
    print("applied" if new != work else "nothing to apply", path)
elif mode == "patch":
    out = sys.argv[3]
    mine = strict(head, "HEAD")
    with open(out, "w", encoding="utf-8") as f:
        f.writelines(difflib.unified_diff(
            head.splitlines(keepends=True), mine.splitlines(keepends=True), "a/" + path, "b/" + path))
    idx = tempfile.mktemp(prefix="dual-idx.")
    env = dict(os.environ, GIT_INDEX_FILE=idx)
    subprocess.run(["git", "read-tree", "HEAD"], env=env, check=True)
    subprocess.run(["git", "apply", "--cached", "--check", out], env=env, check=True)
    os.remove(idx)
    print("PATCH-OK", out)
else:
    sys.exit("mode is check, apply or patch")
```

Workflow: write `EDITS.py` with the task's (old, new) pairs → `check` (prints `OK`) → `apply` → build/test → `patch EDITS.py X.patch` (prints `PATCH-OK`) → `commit-mine.sh … --patch X.patch` → `git diff -- <file>` afterwards shows only the user's edits.

### `/tmp/health2/add_keys.py` — written in Task 5.

## Review Focus

- Turning "Write daily notes" off while a report is being written (or pressing Clear archive then): the report must not appear or be kept, and nothing must say it is pending. Test: `HealthHomeReportsTests.revokingConsentDropsTheReportBeingWritten` (Task 4).
- A month whose kept notes include an emoji-heavy or long headline (or an old cached note with a long insight): the request must stay inside the desktop's zod limits — measured in UTF-16 units, as JavaScript counts — instead of being refused with 400 on every open and staying pending forever. Tests: `PeriodReportInputTests.longNotesAreCutToWhatTheComputerTakes` (Task 3), `health-period.test.ts › rejects an N-day window, too many notes or habits, and an oversized note` (Task 1).
- The model writing "steps up" when they fell, or a water comparison when no water was logged: the page must never show a wrong arrow or an invented number. Tests: `health-period.test.ts › works out each direction from the numbers sent, not from the model` and `› drops a comparison the numbers do not back, and a second one for a metric` (Task 1).
- Health opened from a widget while it also returns to the foreground (two opens at once): still at most two model calls. Test: `PeriodReportsTests.twoOpensAtOnceStillAskTwice` (Task 4).
- New Year's Day (1 January 2027 is in ISO week 2026-W53; December, Q4 and 2026 all end that morning): the due list is December, Q4, 2026, then week 52, with the right file names. Test: `PeriodReportScheduleTests.newYearsDay` (Task 4).

---

## File Structure

**Desktop (`/Users/yanceyleo/Code/exodus/exodus`)**
- Modify `packages/shared/src/types/health.ts` — append the period-report schemas, `periodAverage`, `periodDirection`, `parsePeriodReport`.
- Create `tests/unit/shared/types/health-period-fixtures.ts` — `PERIOD_REQUEST`, `PERIOD_REPORT` (the iOS wire tests hold the same JSON).
- Create `tests/unit/shared/types/health-period.test.ts` — schemas and lenient parsing.
- Modify `src/main/lib/server/routes/health.ts` — `HEALTH_PERIOD_REPORT_SYSTEM`, `periodMemoryQuestion`, the `/period-report` handler (the router is already mounted at `/api/v1/health` behind the app-wide auth, lock and origin gates).
- Create `tests/unit/main/lib/server/routes/health-period-report.test.ts` — the route.

**iOS HealthFeature — new**
- `Report/PeriodReport.swift` — `PeriodReport` (`Kind`, `Span`, `Insight`, `Comparison`), `PeriodReportReply`, `story`.
- `Report/PeriodReportInput.swift` — `PeriodReportRequest`, `PeriodReportInput` (request from records + archive, `clip`).
- `Report/PeriodReportStore.swift` — `PeriodReportStore`, `HealthArchive.reports`.
- `Report/PeriodReportSchedule.swift` — last finished periods, due ones, `perOpen`.
- `Report/PeriodReports.swift` — the `@Observable` coordinator.
- `Trends/PeriodReportText.swift` — words, metric names, colours, spoken text.
- `Trends/PeriodReportView.swift` — `PeriodReportRoute`, the page, `PeriodReportRow`.
- `Trends/ComparisonsCard.swift` — the comparisons.
- `Trends/PeriodReportCard.swift` — the calendar card, `ReportReadyLine`.

**iOS — modified**
- `Report/HealthServices.swift` — `PeriodReportService`, `LivePeriodReportService`.
- `Report/HealthHomeModel.swift` — `reports`, `periodReports:` init parameter, `writeDueReports()`, consent/clear hooks.
- `HealthRootView.swift` — live service, opens write due reports, the confirmation's new English.
- `UI/ReportStory.swift` — `NudgeCard` internal.
- `UI/HealthHomeView.swift` — the week card + report line, the `PeriodReportRoute` destination.
- `Trends/TrendsView.swift` — the report card under the header.
- `Trends/WeekCard.swift` — no own background.
- `Debug/HealthPreviewSource.swift` — `PreviewPeriodReportService`, `PeriodReportStore.writePreview`.
- `Sources/App/HealthGallery.swift` — `report-home`, `report-page`, `report-card`, `report-pending`.
- `Resources/App/Localizable.xcstrings` — 20 new keys + 1 replaced entry (patch).
- Tests (`Tests/HealthFeatureTests/`): new `PeriodReportWireTests`, `PeriodReportStoreTests`, `PeriodReportInputTests`, `PeriodReportScheduleTests`, `StubPeriodReports`, `PeriodReportsTests`, `HealthHomeReportsTests`, `PeriodReportTextTests`, `PeriodReportPageTests`, `PeriodReportCardTests`.
- Docs: `docs/health-device-checklist.md`, `README.md`.

---

### Task 1: Desktop — period-report schemas and lenient parsing

**Files:**
- Modify: `packages/shared/src/types/health.ts` (append at the end)
- Create: `tests/unit/shared/types/health-period-fixtures.ts`
- Test: `tests/unit/shared/types/health-period.test.ts`

**Interfaces:**
- Consumes: `count`, `isObject`, `healthCategorySchema`, `healthStatSchema` (already in `health.ts`).
- Produces (exported from `@exodus/shared/types/health`): `periodKindSchema`, `reportPeriodSchema`, `periodAggregatesSchema`, `habitKindSchema`, `periodReportRequestSchema`, `periodMetricSchema`, `periodInsightSchema`, `periodComparisonSchema`, `periodReportSchema`; types `PeriodReportRequest`, `PeriodAggregates`, `PeriodMetric`, `PeriodReport`, `PeriodInsight`, `PeriodComparison`; `periodAverage(a: PeriodAggregates | null | undefined, metric: PeriodMetric): number | null`; `periodDirection(current: number, previous: number): 'up' | 'down' | 'flat'`; `parsePeriodReport(value: unknown, request: PeriodReportRequest): PeriodReport | null`. Fixtures `PERIOD_REQUEST`, `PERIOD_REPORT`.

- [ ] **Step 1: Check the files are clean and write the fixtures**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
git diff --stat -- packages/shared/src/types/health.ts src/main/lib/server/routes/health.ts   # must print nothing
```

Create `tests/unit/shared/types/health-period-fixtures.ts`:

```ts
// The period report's wire examples (exodus-ios trends, phase 2). exodus-ios's
// PeriodReportWireTests holds the same JSON, so the two sides agree on it.
export const PERIOD_REQUEST = {
  period: { kind: 'month', start: '2026-09-01', end: '2026-09-30' },
  current: {
    elapsedDays: 30,
    daysWithData: 28,
    sleepMin: { average: 432, min: 350, max: 510, days: 28 },
    steps: { average: 7040, min: 2100, max: 13200, days: 28 },
    exerciseMin: { average: 24, min: 0, max: 75, days: 28 },
    hrvMs: { average: 44, min: 31, max: 58, days: 27 },
    restingHr: { average: 59, min: 55, max: 64, days: 27 },
    waterCups: { days: 0 },
    stepGoalRate: 0.32,
    sleepTargetRate: 0.6
  },
  previous: {
    elapsedDays: 31,
    daysWithData: 31,
    sleepMin: { average: 407, min: 330, max: 480, days: 31 },
    steps: { average: 8000, min: 3100, max: 15000, days: 31 },
    exerciseMin: { average: 24, min: 0, max: 60, days: 31 },
    hrvMs: { average: 43, min: 30, max: 55, days: 31 },
    restingHr: { average: 61, min: 57, max: 66, days: 31 },
    waterCups: { days: 0 },
    stepGoalRate: 0.45,
    sleepTargetRate: 0.42
  },
  notes: [
    {
      day: '2026-09-15',
      headline: 'A little under-slept, so take it easy.',
      insights: [
        {
          category: 'sleep',
          title:
            'You slept 5 h 52 min last night, about half an hour less than usual.'
        }
      ]
    }
  ],
  habits: [],
  locale: 'en'
}

// A report as the model writes it (no `period` — the desktop adds the request's).
export const PERIOD_REPORT = {
  headline: 'More sleep, fewer steps than in August.',
  headlineHighlight: 'More sleep',
  headlineCategory: 'sleep',
  insights: [
    {
      category: 'sleep',
      title:
        'You slept 7 h 12 min a night on average, 25 minutes more than in August.',
      highlights: ['7 h 12 min', '25 minutes more'],
      stat: { value: '7:12', unit: 'hr', caption: 'August 6:47' }
    },
    {
      category: 'activity',
      title:
        'Daily steps fell 12 % to 7,040; you reached your goal on 9 of 28 days.',
      highlights: ['fell 12 %', '9 of 28 days'],
      stat: { value: '7,040', unit: 'steps', caption: 'August 8,000' }
    },
    {
      category: 'recovery',
      title: 'Resting heart rate eased to 59 bpm from 61, and HRV held at 44 ms.',
      highlights: ['59 bpm']
    }
  ],
  comparisons: [
    { metric: 'sleep', current: '7 h 12 min', previous: '6 h 47 min', direction: 'up' },
    { metric: 'steps', current: '7,040', previous: '8,000', direction: 'down' },
    { metric: 'hrv', current: '44 ms', previous: '43 ms', direction: 'flat' },
    { metric: 'restingHr', current: '59 bpm', previous: '61 bpm', direction: 'down' }
  ],
  nudge: 'Take a short walk after lunch on workdays.'
}
```

- [ ] **Step 2: Write the failing test**

Create `tests/unit/shared/types/health-period.test.ts`:

```ts
import {
  parsePeriodReport,
  periodDirection,
  periodReportRequestSchema,
  periodReportSchema
} from '@exodus/shared/types/health'
import { describe, expect, it } from 'vitest'

import { PERIOD_REPORT, PERIOD_REQUEST } from './health-period-fixtures'

const REQUEST = periodReportRequestSchema.parse(PERIOD_REQUEST)

describe('periodReportRequestSchema', () => {
  it('accepts the fixture the phone also encodes', () => {
    expect(periodReportRequestSchema.parse(PERIOD_REQUEST)).toEqual(
      PERIOD_REQUEST
    )
  })

  it('takes no period before, as null or left out', () => {
    const { previous: _p, ...withoutPrevious } = PERIOD_REQUEST
    expect(
      periodReportRequestSchema.safeParse({ ...PERIOD_REQUEST, previous: null })
        .success
    ).toBe(true)
    expect(periodReportRequestSchema.safeParse(withoutPrevious).success).toBe(
      true
    )
  })

  it('rejects fields it does not know, at any depth (no raw samples sneak in)', () => {
    const bad = [
      { ...PERIOD_REQUEST, samples: [] },
      { ...PERIOD_REQUEST, current: { ...PERIOD_REQUEST.current, raw: [1] } },
      {
        ...PERIOD_REQUEST,
        notes: [{ ...PERIOD_REQUEST.notes[0], snapshot: {} }]
      }
    ]
    for (const body of bad)
      expect(periodReportRequestSchema.safeParse(body).success).toBe(false)
  })

  it('rejects an N-day window, too many notes or habits, and an oversized note', () => {
    const note = PERIOD_REQUEST.notes[0]
    const habit = {
      kind: 'steps',
      target: 8000,
      daysHit: 5,
      streak: 3,
      dayOfTwentyOne: 9
    }
    const bad = [
      { ...PERIOD_REQUEST, period: { ...PERIOD_REQUEST.period, kind: 'days' } },
      { ...PERIOD_REQUEST, notes: Array.from({ length: 367 }, () => note) },
      { ...PERIOD_REQUEST, habits: [habit, habit, habit, habit] },
      { ...PERIOD_REQUEST, notes: [{ ...note, headline: 'x'.repeat(121) }] },
      {
        ...PERIOD_REQUEST,
        notes: [
          { ...note, insights: [{ category: 'sleep', title: 'x'.repeat(201) }] }
        ]
      }
    ]
    for (const body of bad)
      expect(periodReportRequestSchema.safeParse(body).success).toBe(false)
    expect(
      periodReportRequestSchema.safeParse({ ...PERIOD_REQUEST, habits: [habit] })
        .success
    ).toBe(true)
  })
})

describe('periodDirection', () => {
  it('reads under 3 % either way as flat, like the phone', () => {
    expect(periodDirection(432, 407)).toBe('up')
    expect(periodDirection(7040, 8000)).toBe('down')
    expect(periodDirection(44, 43)).toBe('flat')
    expect(periodDirection(97.1, 100)).toBe('flat')
    expect(periodDirection(96.9, 100)).toBe('down')
  })

  it('compares against zero by sign', () => {
    expect(periodDirection(5, 0)).toBe('up')
    expect(periodDirection(0, 0)).toBe('flat')
  })
})

describe('parsePeriodReport', () => {
  it('reads the model report and takes the period from the request', () => {
    const report = parsePeriodReport(
      {
        ...PERIOD_REPORT,
        period: { kind: 'year', start: '1999-01-01', end: '1999-12-31' }
      },
      REQUEST
    )
    expect(report?.period).toEqual(PERIOD_REQUEST.period)
    expect(report?.insights).toEqual(PERIOD_REPORT.insights)
    expect(report?.comparisons).toEqual(PERIOD_REPORT.comparisons)
    expect(report?.headlineHighlight).toBe('More sleep')
    expect(report?.nudge).toBe(PERIOD_REPORT.nudge)
    expect(periodReportSchema.safeParse(report).success).toBe(true)
  })

  it('drops an insight it cannot draw and a highlight not in its sentence', () => {
    const report = parsePeriodReport(
      {
        ...PERIOD_REPORT,
        insights: [
          { ...PERIOD_REPORT.insights[0], highlights: ['7 小時'] },
          { ...PERIOD_REPORT.insights[1], category: 'mood' },
          { title: 42 }
        ]
      },
      REQUEST
    )
    expect(report?.insights).toEqual([
      { ...PERIOD_REPORT.insights[0], highlights: [] }
    ])
  })

  it('is its headline alone when no insight survives', () => {
    const report = parsePeriodReport(
      {
        ...PERIOD_REPORT,
        insights: [{ category: 'mood', title: 'x', highlights: [] }]
      },
      REQUEST
    )
    expect(report?.headline).toBe(PERIOD_REPORT.headline)
    expect(report?.insights).toEqual([])
  })

  it('works out each direction from the numbers sent, not from the model', () => {
    const report = parsePeriodReport(
      {
        ...PERIOD_REPORT,
        comparisons: PERIOD_REPORT.comparisons.map((c) => ({
          ...c,
          direction: 'up'
        }))
      },
      REQUEST
    )
    expect(report?.comparisons.map((c) => c.direction)).toEqual([
      'up',
      'down',
      'flat',
      'down'
    ])
  })

  it('drops a comparison the numbers do not back, and a second one for a metric', () => {
    const report = parsePeriodReport(
      {
        ...PERIOD_REPORT,
        comparisons: [
          ...PERIOD_REPORT.comparisons,
          { metric: 'water', current: '6 cups', previous: '5 cups', direction: 'up' },
          { metric: 'weight', current: '70 kg', previous: '71 kg', direction: 'down' },
          { ...PERIOD_REPORT.comparisons[0], current: '9 h' }
        ]
      },
      REQUEST
    )
    expect(report?.comparisons.map((c) => c.metric)).toEqual([
      'sleep',
      'steps',
      'hrv',
      'restingHr'
    ])
    expect(report?.comparisons[0].current).toBe('7 h 12 min')
  })

  it('has no comparisons without a period before', () => {
    const report = parsePeriodReport(PERIOD_REPORT, {
      ...REQUEST,
      previous: null
    })
    expect(report?.comparisons).toEqual([])
    expect(report?.insights).toHaveLength(3)
  })

  it('drops a headline phrase not in the headline and a nudge too long', () => {
    const report = parsePeriodReport(
      { ...PERIOD_REPORT, headlineHighlight: 'Less sleep', nudge: 'x'.repeat(141) },
      REQUEST
    )
    expect(report?.headline).toBe(PERIOD_REPORT.headline)
    expect(report?.headlineHighlight).toBeUndefined()
    expect(report?.headlineCategory).toBeUndefined()
    expect(report?.nudge).toBeUndefined()
  })

  it('fails without a usable headline', () => {
    expect(parsePeriodReport({ ...PERIOD_REPORT, headline: '' }, REQUEST)).toBeNull()
    expect(
      parsePeriodReport({ ...PERIOD_REPORT, headline: 'x'.repeat(81) }, REQUEST)
    ).toBeNull()
    expect(parsePeriodReport({ insights: PERIOD_REPORT.insights }, REQUEST)).toBeNull()
    expect(parsePeriodReport('not json', REQUEST)).toBeNull()
  })
})
```

- [ ] **Step 3: Run it to see it fail**

Run: `bunx vitest run tests/unit/shared/types/health-period.test.ts`
Expected: FAIL — `parsePeriodReport` (and the other imports) are not exported.

- [ ] **Step 4: Append the schemas and the parser to `packages/shared/src/types/health.ts`**

At the very end of the file add:

```ts

// ── Period reports (exodus-ios trends, phase 2) ─────────────────────────────
// A finished week, month, quarter or year: the phone sends that period's
// aggregates (and the period before's), the daily notes it kept, and the
// habits it tracks; the desktop answers with the report and keeps nothing.
// exodus-ios mirrors both in Sources/HealthFeature/Report/PeriodReport.swift
// and PeriodReportInput.swift.

const wireDay = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
const dayCount = count.max(366)

export const periodKindSchema = z.enum(['week', 'month', 'quarter', 'year'])

// `end` is the period's last day, inclusive.
export const reportPeriodSchema = z
  .object({ kind: periodKindSchema, start: wireDay, end: wireDay })
  .strict()

// One number over the period; the phone leaves out what it has not got.
const metricSummarySchema = z
  .object({
    average: z.number().nullish(),
    min: z.number().nullish(),
    max: z.number().nullish(),
    days: dayCount
  })
  .strict()

export const periodAggregatesSchema = z
  .object({
    elapsedDays: dayCount,
    daysWithData: dayCount,
    sleepMin: metricSummarySchema,
    steps: metricSummarySchema,
    exerciseMin: metricSummarySchema,
    hrvMs: metricSummarySchema,
    restingHr: metricSummarySchema,
    waterCups: metricSummarySchema,
    stepGoalRate: z.number().min(0).max(1).nullish(),
    sleepTargetRate: z.number().min(0).max(1).nullish()
  })
  .strict()

export const habitKindSchema = z.enum([
  'steps',
  'sleep',
  'bedtime',
  'exercise',
  'water'
])

export const periodReportRequestSchema = z
  .object({
    period: reportPeriodSchema,
    current: periodAggregatesSchema,
    previous: periodAggregatesSchema.nullish(),
    notes: z
      .array(
        z
          .object({
            day: wireDay,
            headline: z.string().min(1).max(120),
            insights: z
              .array(
                z
                  .object({
                    category: z.string().min(1).max(20),
                    title: z.string().min(1).max(200)
                  })
                  .strict()
              )
              .max(4)
          })
          .strict()
      )
      .max(366),
    // A bedtime target is minutes after midnight.
    habits: z
      .array(
        z
          .object({
            kind: habitKindSchema,
            target: z.number().nonnegative(),
            daysHit: dayCount,
            streak: dayCount,
            dayOfTwentyOne: z.number().int().min(1).max(21)
          })
          .strict()
      )
      .max(3),
    locale: z.string().min(2).max(16)
  })
  .strict()

export const periodMetricSchema = z.enum([
  'sleep',
  'steps',
  'exercise',
  'hrv',
  'restingHr',
  'water'
])

export const periodInsightSchema = z
  .object({
    category: healthCategorySchema,
    title: z.string().min(1).max(160),
    // Exact substrings of `title`; the phone colours them.
    highlights: z.array(z.string().min(1).max(40)).max(3),
    stat: healthStatSchema.optional()
  })
  .strict()

export const periodComparisonSchema = z
  .object({
    metric: periodMetricSchema,
    current: z.string().min(1).max(24),
    previous: z.string().min(1).max(24).nullable(),
    direction: z.enum(['up', 'down', 'flat'])
  })
  .strict()

export const periodReportSchema = z
  .object({
    period: reportPeriodSchema,
    headline: z.string().min(1).max(80),
    headlineHighlight: z.string().min(1).max(80).optional(),
    headlineCategory: healthCategorySchema.optional(),
    // Empty when none survived: the report is then its headline.
    insights: z.array(periodInsightSchema).max(5),
    comparisons: z.array(periodComparisonSchema).max(6),
    nudge: z.string().min(1).max(140).optional()
  })
  .strict()

export type PeriodReportRequest = z.infer<typeof periodReportRequestSchema>
export type PeriodAggregates = z.infer<typeof periodAggregatesSchema>
export type PeriodMetric = z.infer<typeof periodMetricSchema>
export type PeriodReport = z.infer<typeof periodReportSchema>
export type PeriodInsight = z.infer<typeof periodInsightSchema>
export type PeriodComparison = z.infer<typeof periodComparisonSchema>

const AGGREGATE_OF: Record<
  PeriodMetric,
  'sleepMin' | 'steps' | 'exerciseMin' | 'hrvMs' | 'restingHr' | 'waterCups'
> = {
  sleep: 'sleepMin',
  steps: 'steps',
  exercise: 'exerciseMin',
  hrv: 'hrvMs',
  restingHr: 'restingHr',
  water: 'waterCups'
}

/** A metric's average over a period; null when it was not recorded. */
export function periodAverage(
  a: PeriodAggregates | null | undefined,
  metric: PeriodMetric
): number | null {
  const v = a?.[AGGREGATE_OF[metric]]?.average
  return typeof v === 'number' && Number.isFinite(v) ? v : null
}

/** Which way a number moved, as the phone's TrendMath reads it: under 3 % either way is flat. */
export function periodDirection(
  current: number,
  previous: number
): 'up' | 'down' | 'flat' {
  if (previous === 0)
    return current === 0 ? 'flat' : current > 0 ? 'up' : 'down'
  const relative = (current - previous) / Math.abs(previous)
  if (Math.abs(relative) < 0.03) return 'flat'
  return relative > 0 ? 'up' : 'down'
}

function normalisePeriodInsight(raw: unknown): PeriodInsight | null {
  if (!isObject(raw) || typeof raw.title !== 'string') return null
  const title = raw.title
  const highlights = (Array.isArray(raw.highlights) ? raw.highlights : [])
    .filter(
      (h): h is string =>
        typeof h === 'string' &&
        h.length > 0 &&
        h.length <= 40 &&
        title.includes(h)
    )
    .slice(0, 3)
  const stat = healthStatSchema.safeParse(raw.stat)
  const insight = periodInsightSchema.safeParse({
    category: raw.category,
    title,
    highlights,
    ...(stat.success ? { stat: stat.data } : {})
  })
  return insight.success ? insight.data : null
}

/**
 * A comparison the request backs: its metric has an average this period and the period before, and its direction
 * is worked out from those averages — the model's own is never trusted.
 */
function normaliseComparison(
  raw: unknown,
  request: PeriodReportRequest
): PeriodComparison | null {
  if (!isObject(raw)) return null
  const metric = periodMetricSchema.safeParse(raw.metric)
  if (!metric.success) return null
  const current = periodAverage(request.current, metric.data)
  const before = periodAverage(request.previous, metric.data)
  if (current === null || before === null) return null
  const parsed = periodComparisonSchema.safeParse({
    metric: metric.data,
    current: raw.current,
    previous: raw.previous ?? null,
    direction: periodDirection(current, before)
  })
  return parsed.success ? parsed.data : null
}

/**
 * Reads a model's period report against the request it answers. What can't be trusted is dropped on its own — an
 * insight it can't draw, a highlight not in its sentence, a comparison the numbers don't back, a headline phrase or
 * nudge out of shape — and a report whose insights all fall away is still its headline. Null only without a usable
 * headline. The period is always the request's.
 */
export function parsePeriodReport(
  value: unknown,
  request: PeriodReportRequest
): PeriodReport | null {
  if (!isObject(value) || typeof value.headline !== 'string') return null
  const headline = value.headline.trim()
  const insights = (Array.isArray(value.insights) ? value.insights : [])
    .map(normalisePeriodInsight)
    .filter((i): i is PeriodInsight => i !== null)
    .slice(0, 5)
  const seen = new Set<PeriodMetric>()
  const comparisons: PeriodComparison[] = []
  for (const raw of Array.isArray(value.comparisons) ? value.comparisons : []) {
    const c = normaliseComparison(raw, request)
    if (!c || seen.has(c.metric)) continue
    seen.add(c.metric)
    comparisons.push(c)
  }
  const { headlineHighlight, headlineCategory, nudge } = value
  const highlightOk =
    typeof headlineHighlight === 'string' &&
    headlineHighlight.length > 0 &&
    headline.includes(headlineHighlight) &&
    healthCategorySchema.safeParse(headlineCategory).success
  const nudgeOk =
    typeof nudge === 'string' && nudge.length > 0 && nudge.length <= 140
  const parsed = periodReportSchema.safeParse({
    period: request.period,
    headline,
    ...(highlightOk ? { headlineHighlight, headlineCategory } : {}),
    insights,
    comparisons: comparisons.slice(0, 6),
    ...(nudgeOk ? { nudge } : {})
  })
  return parsed.success ? parsed.data : null
}
```

- [ ] **Step 5: Run the tests**

Run: `bunx vitest run tests/unit/shared/types/health-period.test.ts tests/unit/shared/types/health.test.ts`
Expected: all pass (the daily note's tests unchanged).

- [ ] **Step 6: Lint, format, typecheck, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
F="packages/shared/src/types/health.ts tests/unit/shared/types/health-period-fixtures.ts tests/unit/shared/types/health-period.test.ts"
bunx oxlint $F && bunx oxfmt $F
bunx vitest run tests/unit/shared/types/health-period.test.ts
bun run typecheck:shared && bun run typecheck:node
git diff --stat                        # only these three of ours besides the user's own paths
.superpowers/sdd/commit-mine.sh "feat(health): period-report schemas — a period's numbers, the one before, its notes — and a lenient reader that works out each direction from the numbers sent" $F
git show --stat HEAD                   # exactly the three files
```

---

### Task 2: Desktop — the stateless route `POST /api/v1/health/period-report`

**Files:**
- Modify: `src/main/lib/server/routes/health.ts`
- Test: `tests/unit/main/lib/server/routes/health-period-report.test.ts`

**Interfaces:**
- Consumes: `periodReportRequestSchema`, `parsePeriodReport`, `periodAverage`, `type PeriodReportRequest` (Task 1); `callLlm`, `loadRelevantMemories`, `parseJsonFromResponse`, `getModelFromProvider`, `validateSchema`, `logger`, `AIError`, `ErrorCode` (already imported in the file).
- Produces: `POST /api/v1/health/period-report` → 200 `PeriodReport` JSON, 400 on an invalid request, 500 `AI_GENERATION_FAILED` after two answers without a headline; exports `HEALTH_PERIOD_REPORT_SYSTEM`, `periodMemoryQuestion(r: PeriodReportRequest): string`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/main/lib/server/routes/health-period-report.test.ts`:

```ts
import { isAppError } from '@exodus/shared/errors/app-error'
import { Hono } from 'hono'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import {
  PERIOD_REPORT,
  PERIOD_REQUEST
} from '../../../../shared/types/health-period-fixtures'

vi.mock('electron', () => ({ app: { getPath: () => '/tmp' } }))
const logger = vi.hoisted(() => ({
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
  debug: vi.fn()
}))
vi.mock('@main/lib/logger', () => ({ logger }))

const manager = vi.hoisted(() => ({
  callLlm: vi.fn(),
  loadRelevantMemories: vi.fn(),
  parseJsonFromResponse: (t: string) => {
    try {
      return JSON.parse(t)
    } catch {
      return null
    }
  }
}))
vi.mock('@main/lib/ai/memory/manager', () => manager)

const modelUtil = vi.hoisted(() => ({
  getModelFromProvider: vi.fn(() => ({ model: { id: 'm' }, apiKey: 'k' }))
}))
vi.mock('@main/lib/ai/utils/model-util', () => modelUtil)

const memoryQueries = vi.hoisted(() => ({ createMemory: vi.fn() }))
vi.mock('@main/lib/db/memory-queries', () => memoryQueries)

let settings: Record<string, unknown> = {
  id: 's',
  memory: { useInChat: true }
}

async function buildApp() {
  const { default: healthRouter } =
    await import('@main/lib/server/routes/health')
  const app = new Hono<{ Variables: { settings: unknown } }>()
  app.use('*', async (c, next) => {
    c.set('settings', settings)
    await next()
  })
  app.route('/api/v1/health', healthRouter)
  app.onError((err, c) => {
    if (isAppError(err)) return c.json(err.toJSON(), err.statusCode as never)
    return c.json({ message: err.message }, 500)
  })
  return app
}

const post = async (body: unknown) =>
  (await buildApp()).request('/api/v1/health/period-report', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body)
  })

beforeEach(() => {
  vi.clearAllMocks()
  settings = { id: 's', memory: { useInChat: true } }
  manager.loadRelevantMemories.mockResolvedValue([
    {
      id: 'm1',
      section: 'profile',
      key: 'half-marathon',
      summary: 'Training for a half marathon',
      details: []
    }
  ])
  manager.callLlm.mockResolvedValue(JSON.stringify(PERIOD_REPORT))
})

describe('POST /api/v1/health/period-report', () => {
  it('returns the report for the period asked, with the relevant memories passed in', async () => {
    const res = await post(PERIOD_REQUEST)
    expect(res.status).toBe(200)
    const body = await res.json()
    expect(body.period).toEqual(PERIOD_REQUEST.period)
    expect(body.headline).toBe(PERIOD_REPORT.headline)
    expect(body.insights).toEqual(PERIOD_REPORT.insights)
    expect(
      body.comparisons.map((c: { direction: string }) => c.direction)
    ).toEqual(['up', 'down', 'flat', 'down'])
    expect(manager.loadRelevantMemories).toHaveBeenCalledWith(
      expect.stringContaining('Health report for a month'),
      { id: 'm' },
      'k',
      'health:month:2026-09-01',
      'health:month:2026-09-01'
    )
    const userText = manager.callLlm.mock.calls[0][3] as string
    expect(userText).toContain('half-marathon')
    expect(userText).toContain('"daysWithData":28')
    expect(userText).toContain('A little under-slept')
  })

  it('does not read memories when memory is off for chats', async () => {
    settings = { id: 's', memory: { useInChat: false } }
    const res = await post(PERIOD_REQUEST)
    expect(res.status).toBe(200)
    expect(manager.loadRelevantMemories).not.toHaveBeenCalled()
  })

  it('rejects a request with fields it does not know, before any model call', async () => {
    const res = await post({ ...PERIOD_REQUEST, samples: [] })
    expect(res.status).toBe(400)
    expect(manager.callLlm).not.toHaveBeenCalled()
  })

  it('rejects an N-day window', async () => {
    const res = await post({
      ...PERIOD_REQUEST,
      period: { ...PERIOD_REQUEST.period, kind: 'days' }
    })
    expect(res.status).toBe(400)
  })

  it('retries once on output that is not JSON, then succeeds', async () => {
    manager.callLlm.mockResolvedValueOnce('Sure! Your month went well.')
    const res = await post(PERIOD_REQUEST)
    expect(res.status).toBe(200)
    expect(manager.callLlm).toHaveBeenCalledTimes(2)
  })

  it('retries when no insight survives, then keeps the headline alone', async () => {
    manager.callLlm.mockResolvedValue(
      JSON.stringify({
        ...PERIOD_REPORT,
        insights: [{ category: 'mood', title: 'x', highlights: [] }]
      })
    )
    const res = await post(PERIOD_REQUEST)
    expect(res.status).toBe(200)
    const body = await res.json()
    expect(body.headline).toBe(PERIOD_REPORT.headline)
    expect(body.insights).toEqual([])
    expect(manager.callLlm).toHaveBeenCalledTimes(2)
  })

  it('keeps a first answer whose directions are wrong, putting them right', async () => {
    manager.callLlm.mockResolvedValue(
      JSON.stringify({
        ...PERIOD_REPORT,
        comparisons: PERIOD_REPORT.comparisons.map((c) => ({
          ...c,
          direction: 'up'
        }))
      })
    )
    const res = await post(PERIOD_REQUEST)
    expect(
      (await res.json()).comparisons.map(
        (c: { direction: string }) => c.direction
      )
    ).toEqual(['up', 'down', 'flat', 'down'])
    expect(manager.callLlm).toHaveBeenCalledTimes(1)
  })

  it('fails with AI_GENERATION_FAILED after two answers without a headline', async () => {
    manager.callLlm.mockResolvedValue('{"headline": ""}')
    const res = await post(PERIOD_REQUEST)
    expect(res.status).toBe(500)
    expect((await res.json()).error.code).toBe('AI_GENERATION_FAILED')
    expect(manager.callLlm).toHaveBeenCalledTimes(2)
  })

  it('asks for the direction against the period before, with one full example', async () => {
    await post(PERIOD_REQUEST)
    const system = manager.callLlm.mock.calls[0][2] as string
    for (const phrase of [
      '"comparisons"',
      '"previous"',
      'under 3 %',
      'verbatim',
      'daysWithData',
      'at most 60 characters'
    ])
      expect(system).toContain(phrase)
  })

  it('writes nothing and logs no health values', async () => {
    await post(PERIOD_REQUEST)
    expect(memoryQueries.createMemory).not.toHaveBeenCalled()
    const logged = JSON.stringify([
      ...logger.info.mock.calls,
      ...logger.warn.mock.calls
    ])
    for (const value of ['7040', '432', 'under-slept', 'More sleep'])
      expect(logged).not.toContain(value)
  })
})
```

- [ ] **Step 2: Run it to see it fail**

Run: `bunx vitest run tests/unit/main/lib/server/routes/health-period-report.test.ts`
Expected: FAIL — 404 for `/period-report` (status 404, not 200/400).

- [ ] **Step 3: Add the route to `src/main/lib/server/routes/health.ts`**

Replace the import block

```ts
import {
  healthSnapshotSchema,
  parseHealthSummary,
  type HealthSnapshot
} from '@exodus/shared/types/health'
```

with

```ts
import {
  healthSnapshotSchema,
  parseHealthSummary,
  parsePeriodReport,
  periodAverage,
  periodReportRequestSchema,
  type HealthSnapshot,
  type PeriodReportRequest
} from '@exodus/shared/types/health'
```

Replace the file's header comment lines

```ts
// exodus-ios's Health workspace: one report a day, written from the phone's
// aggregated snapshot. Stateless — nothing is stored, and the logs carry
// timings, never the numbers.
```

with

```ts
// exodus-ios's Health workspace: one report a day, written from the phone's
// aggregated snapshot, and one for each finished week, month, quarter and
// year, written from that period's aggregates. Stateless — nothing is stored,
// and the logs carry timings, never the numbers.
```

Replace

```ts
function userText(s: HealthSnapshot, memories: MemoryRow[]): string {
  const known = memories.length
    ? memories.map((m) => `- [${m.section}] ${m.key} — ${m.summary}`).join('\n')
    : '(none)'
  return `Snapshot:\n${JSON.stringify(s)}\n\nKnown memories:\n${known}`
}
```

with

```ts
function knownMemories(memories: MemoryRow[]): string {
  return memories.length
    ? memories.map((m) => `- [${m.section}] ${m.key} — ${m.summary}`).join('\n')
    : '(none)'
}

function userText(s: HealthSnapshot, memories: MemoryRow[]): string {
  return `Snapshot:\n${JSON.stringify(s)}\n\nKnown memories:\n${knownMemories(memories)}`
}

export const HEALTH_PERIOD_REPORT_SYSTEM = `You write a short, warm health report about one finished period — a week, a month, a quarter or a year — for one person, from the numbers you are given. The phone shows it like the daily note: a headline, a few insight cards, how each number moved, and one small idea; it colours the phrases you mark.
What you get:
- "period": its kind and its first and last day.
- "current": the period in numbers. Each of sleepMin (minutes a night), steps (a day), exerciseMin (minutes a day), hrvMs (milliseconds), restingHr (beats per minute) and waterCups (cups a day) has its average, lowest and highest, and on how many days it was recorded ("days"; 0 means not recorded). "elapsedDays" is the period's length, "daysWithData" how many days had any number, "stepGoalRate" and "sleepTargetRate" the share of days (0 to 1) at the step goal and at 7 hours of sleep.
- "previous": the same for the period just before, or absent when there is nothing to compare.
- "notes": the daily notes written in the period, oldest first (a headline, and for a week or a month its insight sentences); may be empty.
- "habits": habits the person is building; may be empty.
- "Known memories": what the person has told the assistant; use them for context only, never repeat them.
Rules:
- Write in the language named by "locale" (a BCP-47 tag).
- What matters most is the direction against the person's own past: compare "current" with "previous" wherever both have the number, and say which way it went and by how much; under 3 % either way is "about the same". Without "previous", describe the period on its own.
- Use only these numbers, rounded the way people say them (hours and minutes for sleep, whole steps). Never invent one.
- When "daysWithData" is less than "elapsedDays", say how many days had data.
- Never diagnose, never name a condition, never give medical advice beyond everyday habits (sleep, walking, water, rest).
- "headline": one short sentence about the period's direction, at most 60 characters.
- "headlineHighlight": the key phrase of the headline, copied verbatim from it (character for character); "headlineCategory" is the category it is about (sleep, activity, recovery or body).
- "insights": 1 to 5, most important first, only about numbers that were recorded. Each has:
  - "category": sleep, activity, recovery or body;
  - "title": one sentence, at most 160 characters, built around the change;
  - "highlights": 0 to 3 short phrases (at most 40 characters each) copied verbatim from that same "title";
  - "stat" (optional): {"value": at most 12 characters, "unit": at most 16, "caption": a few words of context such as the value before, at most 40}.
- "comparisons": one per number recorded in both periods. "metric" is sleep, steps, exercise, hrv, restingHr or water; "current" and "previous" are the two averages as the person reads them (at most 24 characters each); "direction" is up, down or flat.
- "nudge": one everyday habit for the next period, one sentence, at most 140 characters. No medical advice.
Example (for a different person and period; write your own from the numbers):
{"headline":"More sleep, fewer steps than in August.","headlineHighlight":"More sleep","headlineCategory":"sleep","insights":[{"category":"sleep","title":"You slept 7 h 12 min a night on average, 25 minutes more than in August.","highlights":["7 h 12 min","25 minutes more"],"stat":{"value":"7:12","unit":"hr","caption":"August 6:47"}},{"category":"activity","title":"Daily steps fell 12 % to 7,040; you reached your goal on 9 of 28 days.","highlights":["fell 12 %","9 of 28 days"],"stat":{"value":"7,040","unit":"steps","caption":"August 8,000"}}],"comparisons":[{"metric":"sleep","current":"7 h 12 min","previous":"6 h 47 min","direction":"up"},{"metric":"steps","current":"7,040","previous":"8,000","direction":"down"}],"nudge":"Take a short walk after lunch on workdays."}
Respond ONLY with JSON in exactly that shape.`

/** What the memory read-filter is asked about: the period in one line. */
export function periodMemoryQuestion(r: PeriodReportRequest): string {
  const parts: string[] = []
  const sleep = periodAverage(r.current, 'sleep')
  const steps = periodAverage(r.current, 'steps')
  const hrv = periodAverage(r.current, 'hrv')
  if (sleep !== null) parts.push(`sleep ${Math.round(sleep)} min a night`)
  if (steps !== null) parts.push(`steps ${Math.round(steps)} a day`)
  if (hrv !== null) parts.push(`HRV ${Math.round(hrv)} ms`)
  return `Health report for a ${r.period.kind}. ${parts.join('; ')}`
}

function periodUserText(r: PeriodReportRequest, memories: MemoryRow[]): string {
  return `Period:\n${JSON.stringify(r)}\n\nKnown memories:\n${knownMemories(memories)}`
}
```

Then, after the closing `})` of `health.post('/summary', …)` and before `export default health`, add:

```ts

health.post('/period-report', async (c) => {
  const request = validateSchema(
    periodReportRequestSchema,
    await c.req.json(),
    'Invalid period report request'
  )
  const setting = c.get('settings')
  const { model, apiKey } = getModelFromProvider(setting)
  const started = Date.now()
  const session = `health:${request.period.kind}:${request.period.start}`
  const memories =
    setting.memory?.useInChat !== false
      ? await loadRelevantMemories(
          periodMemoryQuestion(request),
          model,
          apiKey,
          session,
          session
        )
      : []
  const prompt = periodUserText(request, memories)

  for (let attempt = 1; attempt <= 2; attempt++) {
    const text = await callLlm(
      model,
      apiKey,
      HEALTH_PERIOD_REPORT_SYSTEM,
      prompt
    )
    const parsed = parsePeriodReport(parseJsonFromResponse(text), request)
    // A report without insights is asked for again; on the last attempt its
    // headline still beats no report at all.
    if (parsed && (parsed.insights.length > 0 || attempt === 2)) {
      logger.info('health', 'Period report written', {
        ms: Date.now() - started,
        attempt,
        kind: request.period.kind,
        insights: parsed.insights.length,
        comparisons: parsed.comparisons.length
      })
      return c.json(parsed)
    }
  }
  logger.warn('health', 'Period report output invalid twice', {
    ms: Date.now() - started,
    kind: request.period.kind
  })
  throw new AIError(
    ErrorCode.AI_GENERATION_FAILED,
    'The health period report could not be written.'
  )
})
```

- [ ] **Step 4: Run the tests**

Run: `bunx vitest run tests/unit/main/lib/server/routes/health-period-report.test.ts tests/unit/main/lib/server/routes/health.test.ts`
Expected: all pass (the daily note's route tests unchanged).

- [ ] **Step 5: Lint, format, typecheck, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
F="src/main/lib/server/routes/health.ts tests/unit/main/lib/server/routes/health-period-report.test.ts"
bunx oxlint $F && bunx oxfmt $F
bunx vitest run tests/unit/main/lib/server/routes/health-period-report.test.ts tests/unit/main/lib/server/routes/health.test.ts
bun run typecheck:node
.superpowers/sdd/commit-mine.sh "feat(health): POST /api/v1/health/period-report — a finished week, month, quarter or year written from its numbers and the one before, stateless like the daily note" $F
git show --stat HEAD                   # exactly the two files
```

---

### Task 3: iOS — `PeriodReport`, the request, the store and the service

**Files:**
- Create: `Sources/HealthFeature/Report/PeriodReport.swift`
- Create: `Sources/HealthFeature/Report/PeriodReportInput.swift`
- Create: `Sources/HealthFeature/Report/PeriodReportStore.swift`
- Modify: `Sources/HealthFeature/Report/HealthServices.swift` (append)
- Test: `Tests/HealthFeatureTests/PeriodReportWireTests.swift`, `PeriodReportStoreTests.swift`, `PeriodReportInputTests.swift`

**Interfaces:**
- Consumes: `Period`, `Period.Kind`, `Period.days(calendar:)`, `Period.previous(calendar:)`, `Aggregates` (memberwise init), `MetricSummary(average:min:max:days:)`, `TrendMath.aggregate(_:in:today:calendar:)`, `DayRecord`, `HealthArchive` (`read(day:)`, `write(_:)`, `clear()`, `directory`), `ArchivedDay`, `WireDate`, `HealthWire.encoder()`, `HealthSummary`, `APIClient.post(_:body:timeout:)`.
- Produces:
  - `public struct PeriodReport: Codable, Equatable, Sendable` with `Kind` (`week, month, quarter, year`; `init?(_: Period.Kind)`), `Span` (`kind, start, end`; `init(kind:start:end:)`, `init?(_ period: Period, calendar: Calendar)`), `Insight` (`category, title, highlights, stat`), `Comparison` (`metric, current, previous, direction`; `Direction` `up, down, flat`), fields `period, headline, headlineHighlight, headlineCategory, insights, comparisons, nudge, generatedAt, current: Aggregates, previous: Aggregates?`; `init(_ reply: PeriodReportReply, period: Span, generatedAt: Date, current: Aggregates, previous: Aggregates?)`; `var story: HealthSummary`.
  - `public struct PeriodReportReply: Decodable, Equatable, Sendable` (`headline, headlineHighlight, headlineCategory, insights, comparisons, nudge`; init with defaults).
  - `public struct PeriodReportRequest: Encodable, Equatable, Sendable` (`period, current, previous, notes: [Note], habits: [Habit], locale`; `Note(day:headline:insights:)`, `NoteInsight(category:title:)`, `Habit`).
  - `enum PeriodReportInput { static func request(period:records:archive:calendar:locale:today:) -> PeriodReportRequest?; static func clip(_:_:) -> String }`.
  - `public struct PeriodReportStore: Sendable { directory; fileURL(id:) -> URL?; write(_:id:) throws; read(id:) -> PeriodReport? }`; `HealthArchive.reports: PeriodReportStore`.
  - `public protocol PeriodReportService: Sendable { func report(for: PeriodReportRequest) async throws -> PeriodReportReply }`, `LivePeriodReportService(apiClient:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HealthFeatureTests/PeriodReportWireTests.swift`:

```swift
// Tests/HealthFeatureTests/PeriodReportWireTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

/// The period report on the wire, held to the desktop's fixtures (`tests/unit/shared/types/health-period-fixtures.ts`
/// in the desktop repo: `PERIOD_REQUEST`, and `PERIOD_REPORT` with the period the route adds).
struct PeriodReportWireTests {
    static let cal = TestClock.calendar

    static func m(_ a: Double?, _ lo: Double?, _ hi: Double?, _ d: Int) -> MetricSummary {
        MetricSummary(average: a, min: lo, max: hi, days: d)
    }

    static let request = PeriodReportRequest(
        period: .init(kind: .month, start: "2026-09-01", end: "2026-09-30"),
        current: Aggregates(
            elapsedDays: 30, daysWithData: 28, sleepMin: m(432, 350, 510, 28), steps: m(7040, 2100, 13200, 28),
            exerciseMin: m(24, 0, 75, 28), hrvMs: m(44, 31, 58, 27), restingHr: m(59, 55, 64, 27),
            waterCups: m(nil, nil, nil, 0), stepGoalRate: 0.32, sleepTargetRate: 0.6),
        previous: Aggregates(
            elapsedDays: 31, daysWithData: 31, sleepMin: m(407, 330, 480, 31), steps: m(8000, 3100, 15000, 31),
            exerciseMin: m(24, 0, 60, 31), hrvMs: m(43, 30, 55, 31), restingHr: m(61, 57, 66, 31),
            waterCups: m(nil, nil, nil, 0), stepGoalRate: 0.45, sleepTargetRate: 0.42),
        notes: [
            .init(
                day: "2026-09-15", headline: "A little under-slept, so take it easy.",
                insights: [
                    .init(
                        category: "sleep",
                        title: "You slept 5 h 52 min last night, about half an hour less than usual.")
                ])
        ],
        habits: [], locale: "en")

    static let desktopRequest = #"""
        {"period":{"kind":"month","start":"2026-09-01","end":"2026-09-30"},
         "current":{"elapsedDays":30,"daysWithData":28,"sleepMin":{"average":432,"min":350,"max":510,"days":28},
           "steps":{"average":7040,"min":2100,"max":13200,"days":28},"exerciseMin":{"average":24,"min":0,"max":75,"days":28},
           "hrvMs":{"average":44,"min":31,"max":58,"days":27},"restingHr":{"average":59,"min":55,"max":64,"days":27},
           "waterCups":{"days":0},"stepGoalRate":0.32,"sleepTargetRate":0.6},
         "previous":{"elapsedDays":31,"daysWithData":31,"sleepMin":{"average":407,"min":330,"max":480,"days":31},
           "steps":{"average":8000,"min":3100,"max":15000,"days":31},"exerciseMin":{"average":24,"min":0,"max":60,"days":31},
           "hrvMs":{"average":43,"min":30,"max":55,"days":31},"restingHr":{"average":61,"min":57,"max":66,"days":31},
           "waterCups":{"days":0},"stepGoalRate":0.45,"sleepTargetRate":0.42},
         "notes":[{"day":"2026-09-15","headline":"A little under-slept, so take it easy.",
           "insights":[{"category":"sleep","title":"You slept 5 h 52 min last night, about half an hour less than usual."}]}],
         "habits":[],"locale":"en"}
        """#

    static let desktopReply = #"""
        {"period":{"kind":"month","start":"2026-09-01","end":"2026-09-30"},
         "headline":"More sleep, fewer steps than in August.","headlineHighlight":"More sleep","headlineCategory":"sleep",
         "insights":[
           {"category":"sleep","title":"You slept 7 h 12 min a night on average, 25 minutes more than in August.",
            "highlights":["7 h 12 min","25 minutes more"],"stat":{"value":"7:12","unit":"hr","caption":"August 6:47"}},
           {"category":"activity","title":"Daily steps fell 12 % to 7,040; you reached your goal on 9 of 28 days.",
            "highlights":["fell 12 %","9 of 28 days"],"stat":{"value":"7,040","unit":"steps","caption":"August 8,000"}},
           {"category":"recovery","title":"Resting heart rate eased to 59 bpm from 61, and HRV held at 44 ms.",
            "highlights":["59 bpm"]}],
         "comparisons":[{"metric":"sleep","current":"7 h 12 min","previous":"6 h 47 min","direction":"up"},
           {"metric":"steps","current":"7,040","previous":"8,000","direction":"down"},
           {"metric":"hrv","current":"44 ms","previous":"43 ms","direction":"flat"},
           {"metric":"restingHr","current":"59 bpm","previous":"61 bpm","direction":"down"}],
         "nudge":"Take a short walk after lunch on workdays."}
        """#

    static func reply() throws -> PeriodReportReply {
        try JSONDecoder().decode(PeriodReportReply.self, from: Data(desktopReply.utf8))
    }

    @Test func aRequestEncodesAsTheDesktopReadsIt() throws {
        let mine = try JSONSerialization.jsonObject(with: HealthWire.encoder().encode(Self.request)) as? NSDictionary
        let theirs = try JSONSerialization.jsonObject(with: Data(Self.desktopRequest.utf8)) as? NSDictionary
        #expect(mine != nil)
        #expect(mine == theirs)
    }

    @Test func aReplyReadsAsTheDesktopWritesIt() throws {
        let reply = try Self.reply()
        #expect(reply.headline == "More sleep, fewer steps than in August.")
        #expect(reply.headlineHighlight == "More sleep")
        #expect(reply.headlineCategory == "sleep")
        #expect(reply.insights.count == 3)
        #expect(reply.insights[0].highlights == ["7 h 12 min", "25 minutes more"])
        #expect(reply.insights[2].stat == nil)
        #expect(reply.comparisons.map(\.direction) == [.up, .down, .flat, .down])
        #expect(reply.nudge == "Take a short walk after lunch on workdays.")
    }

    @Test func missingListsAreEmptyAndAnUnknownDirectionIsLevel() throws {
        let json = #"{"headline":"h","comparisons":[{"metric":"sleep","current":"7h","direction":"sideways"}]}"#
        let reply = try JSONDecoder().decode(PeriodReportReply.self, from: Data(json.utf8))
        #expect(reply.insights.isEmpty)
        #expect(reply.comparisons == [.init(metric: "sleep", current: "7h", previous: nil, direction: .flat)])
    }

    @Test func aSpanNamesThePeriodsFirstAndLastDay() {
        let cal = Self.cal
        let september = Period.containing(TestClock.date(2026, 9, 15), .month, calendar: cal)
        #expect(PeriodReport.Span(september, calendar: cal) == .init(kind: .month, start: "2026-09-01", end: "2026-09-30"))
        let week53 = Period.containing(TestClock.date(2027, 1, 1), .week, calendar: cal)
        #expect(PeriodReport.Span(week53, calendar: cal) == .init(kind: .week, start: "2026-12-28", end: "2027-01-03"))
        #expect(PeriodReport.Span(Period.containing(TestClock.now, .days(7), calendar: cal), calendar: cal) == nil)
    }

    @Test func aKeptReportRoundTrips() throws {
        let report = PeriodReport(
            try Self.reply(), period: Self.request.period, generatedAt: TestClock.now, current: Self.request.current,
            previous: Self.request.previous)
        let data = try HealthWire.encoder().encode(report)
        #expect(try JSONDecoder().decode(PeriodReport.self, from: data) == report)
    }

    @Test func theStoryIsTheDailyNotesShape() throws {
        let reply = try Self.reply()
        let story = PeriodReport(
            reply, period: Self.request.period, generatedAt: TestClock.now, current: Self.request.current,
            previous: nil
        ).story
        #expect(story.headline == reply.headline)
        #expect(story.headlineCategory == "sleep")
        #expect(story.insights?.map(\.text) == reply.insights.map(\.title))
        #expect(story.nudge == reply.nudge)
        #expect(ReportText.stories(story).count == 3)
    }
}
```

Create `Tests/HealthFeatureTests/PeriodReportStoreTests.swift`:

```swift
// Tests/HealthFeatureTests/PeriodReportStoreTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct PeriodReportStoreTests {
    let archive = HealthArchive(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    var store: PeriodReportStore { archive.reports }

    static func report(headline: String = "h") -> PeriodReport {
        let cal = TestClock.calendar
        let september = Period.containing(TestClock.date(2026, 9, 15), .month, calendar: cal)
        return PeriodReport(
            PeriodReportReply(headline: headline, insights: [.init(category: "sleep", title: "t")]),
            period: PeriodReport.Span(september, calendar: cal)!, generatedAt: TestClock.now,
            current: TrendMath.aggregate([], in: september, today: TestClock.now, calendar: cal), previous: nil)
    }

    @Test func aReportIsKeptUnderItsPeriodInTheArchive() throws {
        let report = Self.report()
        try store.write(report, id: "2026-09")
        let path = archive.directory.appending(path: "reports/2026-09.json").path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(store.read(id: "2026-09") == report)
        #expect(store.read(id: "2026-08") == nil)
    }

    @Test func writingAgainReplacesIt() throws {
        try store.write(Self.report(headline: "first"), id: "2026-09")
        try store.write(Self.report(headline: "second"), id: "2026-09")
        #expect(store.read(id: "2026-09")?.headline == "second")
    }

    @Test func aCorruptFileIsNoReport() throws {
        try store.write(Self.report(), id: "2026-09")
        try Data("{".utf8).write(to: #require(store.fileURL(id: "2026-09")))
        #expect(store.read(id: "2026-09") == nil)
    }

    @Test func onlyReportNamesHaveFiles() {
        for id in ["2026-W40", "2026-09", "2026-Q3", "2026"] { #expect(store.fileURL(id: id) != nil) }
        for id in ["../2026", "2026-Q5", "2026-9", "2026-W4", "x", ""] { #expect(store.fileURL(id: id) == nil) }
        #expect(throws: CocoaError.self) { try store.write(Self.report(), id: "../x") }
    }

    @Test func neitherTheFileNorItsFoldersAreBackedUp() throws {
        try store.write(Self.report(), id: "2026-09")
        let file = try #require(store.fileURL(id: "2026-09"))
        for url in [file, store.directory, archive.directory] {
            #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        }
    }

    @Test func clearingTheArchiveDeletesTheReports() throws {
        try store.write(Self.report(), id: "2026-09")
        try archive.clear()
        #expect(store.read(id: "2026-09") == nil)
    }
}
```

Create `Tests/HealthFeatureTests/PeriodReportInputTests.swift`:

```swift
// Tests/HealthFeatureTests/PeriodReportInputTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct PeriodReportInputTests {
    let cal = TestClock.calendar
    let archive = HealthArchive(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    var september: Period { Period.containing(TestClock.date(2026, 9, 15), .month, calendar: cal) }
    var q3: Period { Period.containing(TestClock.date(2026, 9, 15), .quarter, calendar: cal) }

    func record(_ m: Int, _ d: Int) -> DayRecord { DayRecord(day: TestClock.date(2026, m, d), steps: 9000, mood: .active) }
    var august: [DayRecord] { (1...31).map { record(8, $0) } }
    var septemberDays: [DayRecord] { (1...30).map { record(9, $0) } }

    func keepNote(_ day: String, headline: String = "Short night.", text: String = "You slept 5 h 52 min.") throws {
        let snapshot = HealthSnapshot(
            date: day, localTime: "08:30", locale: "en", sleep: nil, activity: nil, recovery: nil, body: nil,
            odyState: .tired)
        let summary = HealthSummary(
            headline: headline, summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
            memorySuggestion: nil, insights: [.init(category: "sleep", text: text, highlights: [])])
        try archive.write(ArchivedDay(snapshot: snapshot, summary: summary, generatedAt: TestClock.now))
    }

    func request(_ period: Period, _ records: [DayRecord]) -> PeriodReportRequest? {
        PeriodReportInput.request(
            period: period, records: records, archive: archive, calendar: cal, locale: "en", today: TestClock.today)
    }

    @Test func aMonthCarriesItsNumbersTheMonthBeforeAndItsNotes() throws {
        try keepNote("2026-09-15")
        try keepNote("2026-08-20")  // the month before's note stays out
        let r = try #require(request(september, august + septemberDays))
        #expect(r.period == .init(kind: .month, start: "2026-09-01", end: "2026-09-30"))
        #expect(r.current.daysWithData == 30)
        #expect(r.current.steps.average == 9000)
        #expect(r.previous?.daysWithData == 31)
        #expect(r.notes == [.init(day: "2026-09-15", headline: "Short night.", insights: [.init(category: "sleep", title: "You slept 5 h 52 min.")])])
        #expect(r.habits.isEmpty)
        #expect(r.locale == "en")
    }

    @Test func aQuarterSendsHeadlinesOnly() throws {
        try keepNote("2026-09-15")
        let r = try #require(request(q3, septemberDays))
        #expect(r.notes.map(\.headline) == ["Short night."])
        #expect(r.notes[0].insights.isEmpty)
    }

    @Test func aPeriodWithNoDataIsNoRequest() {
        #expect(request(september, []) == nil)
        #expect(request(september, august) == nil)
    }

    @Test func withNothingBeforeThereIsNoPreviousPeriod() throws {
        #expect(try #require(request(september, septemberDays)).previous == nil)
    }

    @Test func longNotesAreCutToWhatTheComputerTakes() throws {
        try keepNote("2026-09-15", headline: String(repeating: "睡", count: 130), text: String(repeating: "😴", count: 105))
        let note = try #require(request(september, septemberDays)?.notes.first)
        #expect(note.headline.utf16.count == 120)
        #expect(note.insights[0].title.utf16.count == 200)
        #expect(note.insights[0].title.count == 100)
        #expect(PeriodReportInput.clip("  x  ", 5) == "x")
    }

    @Test func anEmptyHeadlineIsNoNote() throws {
        try keepNote("2026-09-15", headline: "   ")
        #expect(try #require(request(september, septemberDays)).notes.isEmpty)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git diff --stat -- Sources/HealthFeature Tests/HealthFeatureTests   # must print nothing
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd -only-testing:HealthFeatureTests/PeriodReportWireTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'PeriodReportRequest' in scope` (and the other new names), `TEST FAILED`.

- [ ] **Step 3: Write `Sources/HealthFeature/Report/PeriodReport.swift`**

```swift
// Sources/HealthFeature/Report/PeriodReport.swift
import Foundation
import Models

/// A finished week, month, quarter or year told like the daily note (spec §2.4): written by the computer from the
/// period's numbers and the notes kept in it, then kept on this phone (`archive/reports/2026-09.json`). It keeps the
/// numbers it was written from, as a kept note keeps its snapshot, so a question about it carries them.
public struct PeriodReport: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case week, month, quarter, year

        /// Nil for an N-day window, which has no report.
        init?(_ kind: Period.Kind) {
            switch kind {
            case .week: self = .week
            case .month: self = .month
            case .quarter: self = .quarter
            case .year: self = .year
            case .days: return nil
            }
        }
    }

    /// The period on the wire: its kind, first day and last day ("2026-09-01", "2026-09-30").
    public struct Span: Codable, Equatable, Sendable {
        public var kind: Kind
        public var start: String
        public var end: String

        public init(kind: Kind, start: String, end: String) {
            self.kind = kind
            self.start = start
            self.end = end
        }

        init?(_ period: Period, calendar: Calendar) {
            guard let kind = Kind(period.kind) else { return nil }
            let wire = WireDate(timeZone: calendar.timeZone)
            let last = calendar.date(byAdding: .day, value: -1, to: period.end)!
            self.init(kind: kind, start: wire.day(period.start), end: wire.day(last))
        }
    }

    /// One sentence about one category — the daily note's insight, with the sentence called `title`.
    public struct Insight: Codable, Equatable, Sendable {
        public var category: String
        public var title: String
        /// Exact substrings of `title`, coloured in the category's colour.
        public var highlights: [String]
        public var stat: HealthSummary.Stat?

        public init(category: String, title: String, highlights: [String] = [], stat: HealthSummary.Stat? = nil) {
            self.category = category
            self.title = title
            self.highlights = highlights
            self.stat = stat
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            category = try c.decode(String.self, forKey: .category)
            title = try c.decode(String.self, forKey: .title)
            highlights = try c.decodeIfPresent([String].self, forKey: .highlights) ?? []
            stat = try c.decodeIfPresent(HealthSummary.Stat.self, forKey: .stat)
        }
    }

    /// One number against the period before, as the model wrote it for the reader; the direction is the desktop's,
    /// worked out from the numbers sent.
    public struct Comparison: Codable, Equatable, Sendable {
        public enum Direction: String, Codable, Sendable {
            case up, down, flat
        }

        public var metric: String
        public var current: String
        public var previous: String?
        public var direction: Direction

        public init(metric: String, current: String, previous: String?, direction: Direction) {
            self.metric = metric
            self.current = current
            self.previous = previous
            self.direction = direction
        }

        /// A direction this app doesn't know reads as level, rather than costing the report.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            metric = try c.decode(String.self, forKey: .metric)
            current = try c.decode(String.self, forKey: .current)
            previous = try c.decodeIfPresent(String.self, forKey: .previous)
            direction = (try? c.decode(Direction.self, forKey: .direction)) ?? .flat
        }
    }

    public var period: Span
    public var headline: String
    /// The headline's key phrase, an exact substring of it, coloured as `headlineCategory`.
    public var headlineHighlight: String?
    public var headlineCategory: String?
    public var insights: [Insight]
    public var comparisons: [Comparison]
    public var nudge: String?
    /// When this phone kept it: the home's "report ready" line looks at the last two days.
    public var generatedAt: Date
    /// The numbers it was written from.
    public var current: Aggregates
    public var previous: Aggregates?

    public init(_ reply: PeriodReportReply, period: Span, generatedAt: Date, current: Aggregates, previous: Aggregates?) {
        self.period = period
        self.headline = reply.headline
        self.headlineHighlight = reply.headlineHighlight
        self.headlineCategory = reply.headlineCategory
        self.insights = reply.insights
        self.comparisons = reply.comparisons
        self.nudge = reply.nudge
        self.generatedAt = generatedAt
        self.current = current
        self.previous = previous
    }

    /// The report in the daily note's shape, so it is drawn with the same insight stories.
    var story: HealthSummary {
        HealthSummary(
            headline: headline, summary: headline,
            categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil), memorySuggestion: nil,
            headlineHighlight: headlineHighlight, headlineCategory: headlineCategory,
            insights: insights.map { .init(category: $0.category, text: $0.title, highlights: $0.highlights, stat: $0.stat) },
            nudge: nudge)
    }
}

/// What the computer answers (`POST /api/v1/health/period-report`): the report without what this phone adds. The
/// period it echoes is not read — the phone knows which period it asked about.
public struct PeriodReportReply: Decodable, Equatable, Sendable {
    public var headline: String
    public var headlineHighlight: String?
    public var headlineCategory: String?
    public var insights: [PeriodReport.Insight]
    public var comparisons: [PeriodReport.Comparison]
    public var nudge: String?

    public init(
        headline: String, headlineHighlight: String? = nil, headlineCategory: String? = nil,
        insights: [PeriodReport.Insight] = [], comparisons: [PeriodReport.Comparison] = [], nudge: String? = nil
    ) {
        self.headline = headline
        self.headlineHighlight = headlineHighlight
        self.headlineCategory = headlineCategory
        self.insights = insights
        self.comparisons = comparisons
        self.nudge = nudge
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headline = try c.decode(String.self, forKey: .headline)
        headlineHighlight = try c.decodeIfPresent(String.self, forKey: .headlineHighlight)
        headlineCategory = try c.decodeIfPresent(String.self, forKey: .headlineCategory)
        insights = try c.decodeIfPresent([PeriodReport.Insight].self, forKey: .insights) ?? []
        comparisons = try c.decodeIfPresent([PeriodReport.Comparison].self, forKey: .comparisons) ?? []
        nudge = try c.decodeIfPresent(String.self, forKey: .nudge)
    }

    private enum CodingKeys: String, CodingKey {
        case headline, headlineHighlight, headlineCategory, insights, comparisons, nudge
    }
}
```

- [ ] **Step 4: Write `Sources/HealthFeature/Report/PeriodReportInput.swift`**

```swift
// Sources/HealthFeature/Report/PeriodReportInput.swift
import Foundation
import Models

/// What the phone sends for a finished period (spec §4): its numbers and the period before's, the notes kept in it,
/// the habits (phase 3; none yet) and the language. The desktop's zod schema rejects anything else.
public struct PeriodReportRequest: Encodable, Equatable, Sendable {
    public struct Note: Encodable, Equatable, Sendable {
        public var day: String
        public var headline: String
        public var insights: [NoteInsight]
    }

    public struct NoteInsight: Encodable, Equatable, Sendable {
        public var category: String
        public var title: String
    }

    /// A 21-day habit's progress; phase 3 fills these in. A bedtime target is minutes after midnight.
    public struct Habit: Encodable, Equatable, Sendable {
        public var kind: String
        public var target: Double
        public var daysHit: Int
        public var streak: Int
        public var dayOfTwentyOne: Int
    }

    public var period: PeriodReport.Span
    public var current: Aggregates
    /// Left out (not null) when the period before has no data: the desktop takes either.
    public var previous: Aggregates?
    public var notes: [Note]
    public var habits: [Habit]
    public var locale: String
}

/// Builds a period's request from its day records and the archive. Pure, and fine off the main actor: a year reads
/// up to 366 small files.
enum PeriodReportInput {
    /// The desktop's limits, in UTF-16 units as JavaScript counts them.
    static let headlineLimit = 120
    static let titleLimit = 200
    static let categoryLimit = 20

    /// The request for a finished period, or nil when it has no data at all (nothing to write about, no call).
    /// `records` holds the period's days and the period before's. A week's or a month's notes carry their insight
    /// sentences; a quarter's or a year's only their headlines, so a year stays a small request.
    static func request(
        period: Period, records: [DayRecord], archive: HealthArchive, calendar: Calendar, locale: String, today: Date
    ) -> PeriodReportRequest? {
        guard let span = PeriodReport.Span(period, calendar: calendar) else { return nil }
        let current = TrendMath.aggregate(records, in: period, today: today, calendar: calendar)
        guard current.daysWithData > 0 else { return nil }
        let before = TrendMath.aggregate(
            records, in: period.previous(calendar: calendar), today: today, calendar: calendar)
        let detailed = span.kind == .week || span.kind == .month
        let wire = WireDate(timeZone: calendar.timeZone)
        let notes: [PeriodReportRequest.Note] = period.days(calendar: calendar).compactMap { day in
            let key = wire.day(day)
            guard let kept = archive.read(day: key) else { return nil }
            let headline = clip(kept.summary.headline, headlineLimit)
            guard !headline.isEmpty else { return nil }
            let insights: [PeriodReportRequest.NoteInsight] =
                detailed
                ? (kept.summary.insights ?? []).prefix(4).compactMap { i in
                    let title = clip(i.text, titleLimit)
                    let category = clip(i.category, categoryLimit)
                    return title.isEmpty || category.isEmpty ? nil : .init(category: category, title: title)
                }
                : []
            return .init(day: key, headline: headline, insights: insights)
        }
        return PeriodReportRequest(
            period: span, current: current, previous: before.daysWithData > 0 ? before : nil, notes: notes,
            habits: [], locale: locale)
    }

    /// Trimmed and cut to `limit` UTF-16 units on a character boundary, so an old long note or an emoji-heavy one can't
    /// make the computer refuse the whole request.
    static func clip(_ text: String, _ limit: Int) -> String {
        var out = ""
        var units = 0
        for ch in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            units += ch.utf16.count
            guard units <= limit else { break }
            out.append(ch)
        }
        return out
    }
}
```

- [ ] **Step 5: Write `Sources/HealthFeature/Report/PeriodReportStore.swift`**

```swift
// Sources/HealthFeature/Report/PeriodReportStore.swift
import Foundation
import Models

/// The period reports kept on this phone, one file per period (`archive/reports/2026-W40.json`, `2026-09.json`,
/// `2026-Q3.json`, `2026.json`), inside the archive so Clear archive deletes them with the notes. Same protection as
/// the notes: complete file protection, never backed up. A corrupt file is no report.
public struct PeriodReportStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// Only a report name has a file — never a path.
    func fileURL(id: String) -> URL? {
        guard id.wholeMatch(of: /\d{4}(?:-W\d{2}|-\d{2}|-Q[1-4])?/) != nil else { return nil }
        return directory.appending(path: "\(id).json")
    }

    public func write(_ report: PeriodReport, id: String) throws {
        guard let url = fileURL(id: id) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.excludeFromBackup(directory.deletingLastPathComponent())
        try Self.excludeFromBackup(directory)
        try HealthWire.encoder().encode(report).write(to: url, options: [.atomic, .completeFileProtection])
        try Self.excludeFromBackup(url)
    }

    public func read(id: String) -> PeriodReport? {
        guard let url = fileURL(id: id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PeriodReport.self, from: data)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

extension HealthArchive {
    /// The period reports, in `archive/reports/`.
    public var reports: PeriodReportStore {
        PeriodReportStore(directory: directory.appending(path: "reports", directoryHint: .isDirectory))
    }
}
```

- [ ] **Step 6: Append the service to `Sources/HealthFeature/Report/HealthServices.swift`**

At the end of the file add:

```swift

/// Writes a finished period's report. The real one asks the computer (`POST /api/v1/health/period-report`).
public protocol PeriodReportService: Sendable {
    func report(for request: PeriodReportRequest) async throws -> PeriodReportReply
}

public struct LivePeriodReportService: PeriodReportService {
    let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public func report(for request: PeriodReportRequest) async throws -> PeriodReportReply {
        // A memory read and a longer prompt than the day's note: give it longer still.
        try await apiClient.post("/api/v1/health/period-report", body: request, timeout: 180)
    }
}
```

- [ ] **Step 7: Run the tests**

```bash
tuist generate --no-open
for T in PeriodReportWireTests PeriodReportStoreTests PeriodReportInputTests; do
  xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd -only-testing:HealthFeatureTests/$T 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
done
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: `Test run with 6 tests passed`, `… 6 tests passed`, `… 6 tests passed`; `0 error(s)`.

- [ ] **Step 8: Commit**

```bash
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): a period report's shape, the request a period makes from its numbers and kept notes, and the reports kept on the phone beside the notes" \
  Sources/HealthFeature/Report/PeriodReport.swift Sources/HealthFeature/Report/PeriodReportInput.swift \
  Sources/HealthFeature/Report/PeriodReportStore.swift Sources/HealthFeature/Report/HealthServices.swift \
  Tests/HealthFeatureTests/PeriodReportWireTests.swift Tests/HealthFeatureTests/PeriodReportStoreTests.swift \
  Tests/HealthFeatureTests/PeriodReportInputTests.swift
git show --stat HEAD           # exactly these seven files
```

---
### Task 4: iOS — the schedule and `PeriodReports`, wired into the home model and Health's opens

**Files:**
- Create: `Sources/HealthFeature/Report/PeriodReportSchedule.swift`
- Create: `Sources/HealthFeature/Report/PeriodReports.swift`
- Modify: `Sources/HealthFeature/Report/HealthHomeModel.swift`
- Modify: `Sources/HealthFeature/HealthRootView.swift`
- Test: `Tests/HealthFeatureTests/PeriodReportScheduleTests.swift`, `StubPeriodReports.swift`, `PeriodReportsTests.swift`, `HealthHomeReportsTests.swift`

**Interfaces:**
- Consumes: Task 3's `PeriodReport`, `PeriodReportReply`, `PeriodReportRequest`, `PeriodReportInput.request(...)`, `PeriodReportStore`, `HealthArchive.reports`, `PeriodReportService`, `LivePeriodReportService`; phase 1's `Period.containing/previous/reportID`, `DayRecordStore.records(from:through:)`, `SnapshotBuilder`, `HealthHomeModel.reportState(for:)`; test helpers `FakeHealthSource`, `TestClock`, `StubSummaries`, `StubMemory`, `HealthHomeModelTests.summary`.
- Produces:
  - `enum PeriodReportSchedule { static let perOpen = 2; static func lastFinished(today: Date, calendar: Calendar) -> [Period]; static func due(today: Date, calendar: Calendar, isKept: (String) -> Bool) -> [Period] }`
  - `@MainActor @Observable final class PeriodReports` — `enum State: Equatable { case missing, pending, writing, ready(PeriodReport) }`, `enum Failure: Equatable { case offline, needsModel, failed }`, `enum Outcome: Equatable { case written, empty, failed }`; `init(store:service:records:archive:calendar:locale:now:hasConsent:)`; `let calendar: Calendar`; `func report(id: String) -> PeriodReport?`; `func state(for: Period) -> State`; `func failure(for: Period) -> Failure?`; `func isWriting(_: Period) -> Bool`; `func fresh() -> (period: Period, report: PeriodReport)?`; `func writeDue() async`; `@discardableResult func write(_: Period) async -> Outcome`; `func stop()`; `func forget()`; `static let freshFor: TimeInterval`.
  - `HealthHomeModel`: `let reports: PeriodReports`; init parameter `periodReports: (any PeriodReportService)? = nil` (after `preferences:`); `func writeDueReports() async`.
  - `HealthRootView` writes due reports on each open.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HealthFeatureTests/StubPeriodReports.swift`:

```swift
// Tests/HealthFeatureTests/StubPeriodReports.swift
import Foundation

@testable import HealthFeature

/// The computer, for period reports: records what it was asked, can fail, and can hold an answer until released.
actor StubPeriodReports: PeriodReportService {
    var asked: [PeriodReportRequest] = []
    var error: Error?
    var gated = false
    private var held: [CheckedContinuation<Void, Never>] = []

    /// The first day of each period asked about, in order.
    var starts: [String] { asked.map(\.period.start) }

    func fail(_ error: Error?) { self.error = error }
    func hold() { gated = true }

    func release() {
        gated = false
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }

    func report(for request: PeriodReportRequest) async throws -> PeriodReportReply {
        asked.append(request)
        if gated { await withCheckedContinuation { held.append($0) } }
        if let error { throw error }
        return PeriodReportReply(
            headline: "Report \(request.period.start)", insights: [.init(category: "sleep", title: "t")])
    }
}
```

Create `Tests/HealthFeatureTests/PeriodReportScheduleTests.swift`:

```swift
// Tests/HealthFeatureTests/PeriodReportScheduleTests.swift
import Foundation
import Testing

@testable import HealthFeature

struct PeriodReportScheduleTests {
    let cal = TestClock.calendar

    func ids(_ periods: [Period]) -> [String] { periods.compactMap { $0.reportID(calendar: cal) } }

    @Test func onTheFirstOfAMonthTheMonthComesFirst() {
        // Thursday 1 October 2026: September and Q3 ended this morning, week 39 on Monday.
        #expect(ids(PeriodReportSchedule.lastFinished(today: TestClock.now, calendar: cal)) == ["2026-09", "2026-Q3", "2026-W39", "2025"])
    }

    @Test func onAMondayLastWeekComesFirst() {
        #expect(ids(PeriodReportSchedule.lastFinished(today: TestClock.date(2026, 10, 5, 9), calendar: cal)) == ["2026-W40", "2026-09", "2026-Q3", "2025"])
    }

    @Test func newYearsDay() {
        // Friday 1 January 2027 is in 2026-W53; December, Q4 and 2026 all ended this morning, the shorter first.
        #expect(ids(PeriodReportSchedule.lastFinished(today: TestClock.date(2027, 1, 1, 9), calendar: cal)) == ["2026-12", "2026-Q4", "2026", "2026-W52"])
    }

    @Test func aKeptReportIsNotDue() {
        let due = PeriodReportSchedule.due(today: TestClock.now, calendar: cal) { $0 == "2026-09" || $0 == "2025" }
        #expect(ids(due) == ["2026-Q3", "2026-W39"])
    }
}
```

Create `Tests/HealthFeatureTests/PeriodReportsTests.swift`:

```swift
// Tests/HealthFeatureTests/PeriodReportsTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

@MainActor
struct PeriodReportsTests {
    let cal = TestClock.calendar
    let source = FakeHealthSource()
    let service = StubPeriodReports()
    let archive = HealthArchive(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))

    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: TestClock.today)! }
    var september: Period { Period.containing(TestClock.date(2026, 9, 15), .month, calendar: cal) }
    var q3: Period { Period.containing(TestClock.date(2026, 9, 15), .quarter, calendar: cal) }
    var week39: Period { Period.containing(TestClock.date(2026, 9, 23), .week, calendar: cal) }
    var year2025: Period { Period.containing(TestClock.date(2025, 6, 1), .year, calendar: cal) }

    func reports(consent: Bool = true, now: @escaping @Sendable () -> Date = { TestClock.now }) -> PeriodReports {
        let records = DayRecordStore(builder: SnapshotBuilder(source: source, calendar: cal), calendar: cal, now: now)
        return PeriodReports(
            store: archive.reports, service: service, records: records, archive: archive, calendar: cal, locale: "en",
            now: now, hasConsent: { consent })
    }

    /// 9,000 steps a day, going back `days` days from today.
    func steps(days: Int = 500) async {
        let values = (0..<days).map { DayValue(day: day(-$0), value: 9000) }
        await source.set { $0.sums[.steps] = values }
    }

    func keep(_ period: Period, headline: String = "kept", at date: Date) throws {
        let report = PeriodReport(
            PeriodReportReply(headline: headline), period: PeriodReport.Span(period, calendar: cal)!, generatedAt: date,
            current: TrendMath.aggregate([], in: period, today: TestClock.now, calendar: cal), previous: nil)
        try archive.reports.write(report, id: period.reportID(calendar: cal)!)
    }

    @Test func dueReportsAreWrittenNewestFirstTwoAnOpen() async {
        await steps()
        let r = reports()
        await r.writeDue()
        #expect(await service.starts == ["2026-09-01", "2026-07-01"])
        #expect(r.state(for: week39) == .pending)
        await r.writeDue()
        #expect(await service.starts == ["2026-09-01", "2026-07-01", "2026-09-21", "2025-01-01"])
        await r.writeDue()
        #expect(await service.asked.count == 4)
        #expect(archive.reports.read(id: "2026-W39")?.headline == "Report 2026-09-21")
        guard case .ready(let report) = r.state(for: september) else { Issue.record("no September report"); return }
        #expect(report.generatedAt == TestClock.now)
        #expect(report.current.daysWithData == 30)
    }

    @Test func aFailureEndsTheOpenAndTheRestWait() async {
        await steps()
        await service.fail(URLError(.cannotConnectToHost))
        let r = reports()
        await r.writeDue()
        #expect(await service.asked.count == 1)
        #expect(r.state(for: september) == .pending)
        #expect(r.state(for: q3) == .pending)
        #expect(r.failure(for: september) == .offline)
        await service.fail(nil)
        await r.writeDue()
        #expect(await service.starts == ["2026-09-01", "2026-09-01", "2026-07-01"])
        #expect(r.failure(for: september) == nil)
    }

    @Test func withoutConsentNothingIsAskedOrWaits() async {
        await steps()
        let r = reports(consent: false)
        await r.writeDue()
        #expect(await service.asked.isEmpty)
        #expect(r.state(for: september) == .missing)
        #expect(await r.write(september) == .failed)
    }

    @Test func aKeptReportIsNeverWrittenAgainByItself() async throws {
        await steps()
        try keep(september, at: day(-1))
        let r = reports()
        await r.writeDue()
        #expect(await service.starts == ["2026-07-01", "2026-09-21"])
        #expect(archive.reports.read(id: "2026-09")?.headline == "kept")
    }

    @Test func aPeriodWithNoDataCostsNoCall() async {
        await steps(days: 70)
        let r = reports()
        await r.writeDue()
        await r.writeDue()
        await r.writeDue()
        #expect(await service.starts == ["2026-09-01", "2026-07-01", "2026-09-21"])
        #expect(r.state(for: year2025) == .missing)
    }

    @Test func writingAgainReplacesTheKeptReport() async throws {
        await steps()
        try keep(september, at: day(-3))
        let r = reports()
        #expect(await r.write(september) == .written)
        #expect(archive.reports.read(id: "2026-09")?.headline == "Report 2026-09-01")
        guard case .ready(let report) = r.state(for: september) else { Issue.record("no report"); return }
        #expect(report.headline == "Report 2026-09-01")
    }

    @Test func aFailedRewriteKeepsTheReport() async throws {
        await steps()
        try keep(september, at: day(-3))
        await service.fail(URLError(.timedOut))
        let r = reports()
        #expect(await r.write(september) == .failed)
        guard case .ready(let report) = r.state(for: september) else { Issue.record("report lost"); return }
        #expect(report.headline == "kept")
        #expect(r.failure(for: september) == .failed)
    }

    @Test func twoOpensAtOnceStillAskTwice() async {
        await steps()
        let r = reports()
        async let a: Void = r.writeDue()
        async let b: Void = r.writeDue()
        _ = await (a, b)
        #expect(await service.asked.count == 2)
    }

    @Test func theReadyLineShowsTheNewestReportForTwoDays() async throws {
        try keep(september, at: TestClock.now.addingTimeInterval(-3600))
        try keep(week39, at: TestClock.now.addingTimeInterval(-60))
        #expect(reports().fresh()?.period == week39)
        let later = TestClock.now.addingTimeInterval(49 * 3600)
        #expect(reports(now: { later }).fresh() == nil)
        #expect(reports(now: { TestClock.now.addingTimeInterval(47 * 3600) }).fresh()?.period == week39)
    }
}
```

Create `Tests/HealthFeatureTests/HealthHomeReportsTests.swift`:

```swift
// Tests/HealthFeatureTests/HealthHomeReportsTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

/// The period reports as Health's opens drive them through the home model.
@MainActor
struct HealthHomeReportsTests {
    let cal = TestClock.calendar
    let source = FakeHealthSource()
    let summaries = StubSummaries(.success(HealthHomeModelTests.summary))
    let service = StubPeriodReports()
    let prefs = HealthPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let cache = ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    var september: Period { Period.containing(TestClock.date(2026, 9, 15), .month, calendar: cal) }

    func model(consent: Bool = true) async -> HealthHomeModel {
        prefs.summaryConsent = consent
        prefs.hasOnboarded = true
        let values = (0..<500).map { DayValue(day: cal.date(byAdding: .day, value: -$0, to: TestClock.today)!, value: 9000) }
        await source.set { $0.sums[.steps] = values }
        return HealthHomeModel(
            source: source, summaries: summaries, memory: StubMemory(), cache: cache, preferences: prefs,
            periodReports: service, calendar: cal, now: { TestClock.now }, locale: "en")
    }

    @Test func anOpenWritesTheDueReportsAfterTheNote() async {
        let m = await model()
        await m.load()
        await m.writeDueReports()
        #expect(await summaries.calls == 1)
        #expect(await service.starts == ["2026-09-01", "2026-07-01"])
        #expect(m.reports.state(for: september) != .missing)
    }

    @Test func withoutHealthAccessNoReportIsWritten() async {
        let m = await model()
        await source.set { $0.requested = false }
        await m.load()
        await m.writeDueReports()
        #expect(await service.asked.isEmpty)
    }

    @Test func grantingConsentWritesTheDueReports() async {
        let m = await model(consent: false)
        await m.grantConsent()
        #expect(await service.asked.count == 2)
    }

    @Test func clearingTheArchiveForgetsTheReports() async {
        let m = await model()
        await m.load()
        await m.writeDueReports()
        guard case .ready = m.reports.state(for: september) else { Issue.record("no report"); return }
        #expect(m.clearArchive())
        #expect(m.reports.state(for: september) == .missing)
        #expect(cache.archive.reports.read(id: "2026-09") == nil)
    }

    @Test func revokingConsentDropsTheReportBeingWritten() async {
        let m = await model()
        await m.load()
        await service.hold()
        let open = Task { await m.writeDueReports() }
        while await service.asked.isEmpty { await Task.yield() }
        m.revokeConsent()
        await service.release()
        await open.value
        #expect(cache.archive.reports.read(id: "2026-09") == nil)
        #expect(m.reports.state(for: september) == .missing)
        #expect(await service.asked.count == 1)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd -only-testing:HealthFeatureTests/PeriodReportScheduleTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'PeriodReportSchedule' in scope` (and `PeriodReports`, `periodReports:`), `TEST FAILED`.

- [ ] **Step 3: Write `Sources/HealthFeature/Report/PeriodReportSchedule.swift`**

```swift
// Sources/HealthFeature/Report/PeriodReportSchedule.swift
import Foundation

/// Which period reports are due (spec §5): the last finished week, month, quarter and year that have no kept report.
/// Only the last of each — never a backlog.
enum PeriodReportSchedule {
    /// Model calls one Health open may make.
    static let perOpen = 2

    /// The last finished week, month, quarter and year, newest first: by when they ended, and of two that ended
    /// together the shorter first (on 1 October: September, then Q3).
    static func lastFinished(today: Date, calendar: Calendar) -> [Period] {
        let kinds: [Period.Kind] = [.week, .month, .quarter, .year]
        return kinds.enumerated()
            .map { (rank: $0.offset, period: Period.containing(today, $0.element, calendar: calendar).previous(calendar: calendar)) }
            .sorted { $0.period.end != $1.period.end ? $0.period.end > $1.period.end : $0.rank < $1.rank }
            .map(\.period)
    }

    /// Of those, the ones with no kept report: a kept one is never written again by itself.
    static func due(today: Date, calendar: Calendar, isKept: (String) -> Bool) -> [Period] {
        lastFinished(today: today, calendar: calendar).filter { period in
            period.reportID(calendar: calendar).map { !isKept($0) } ?? false
        }
    }
}
```

- [ ] **Step 4: Write `Sources/HealthFeature/Report/PeriodReports.swift`**

```swift
// Sources/HealthFeature/Report/PeriodReports.swift
import Foundation
import Observation

/// The period reports (spec §5): which are kept, which are being written, and which wait for the computer. Each
/// Health open writes the last finished week, month, quarter and year that have no report, newest first and at most
/// two, only with the daily-note consent; the first failure ends the open and the rest wait for the next one. A kept
/// report is never written again by itself — only from its page.
@MainActor
@Observable
final class PeriodReports {
    enum State: Equatable {
        case missing, pending, writing
        case ready(PeriodReport)
    }

    /// Why the last try for a period failed, for its page.
    enum Failure: Equatable { case offline, needsModel, failed }

    /// How one write went: a report, nothing to write about (no data, so no call), or no report.
    enum Outcome: Equatable { case written, empty, failed }

    /// The home's line shows a report this long after it was written.
    static let freshFor: TimeInterval = 2 * 24 * 3600

    /// Reports written this session, by id; kept ones are read from disk through `report(id:)`.
    private(set) var written: [String: PeriodReport] = [:]
    /// Due on this open and not written yet. In memory only: the next open works it out again.
    private(set) var pending: Set<String> = []
    private(set) var writing: Set<String> = []
    private(set) var failures: [String: Failure] = [:]
    @ObservationIgnored let calendar: Calendar

    /// What was read from disk, misses too, so a view can ask on every update.
    @ObservationIgnored private var read: [String: PeriodReport?] = [:]
    @ObservationIgnored private let store: PeriodReportStore
    @ObservationIgnored private let service: (any PeriodReportService)?
    @ObservationIgnored private let records: DayRecordStore
    @ObservationIgnored private let archive: HealthArchive
    @ObservationIgnored private let locale: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let hasConsent: @MainActor () -> Bool
    @ObservationIgnored private var running: Task<Void, Never>?
    /// Bumped by `stop()`: a write that started before it is not kept.
    @ObservationIgnored private var generation = 0

    init(
        store: PeriodReportStore, service: (any PeriodReportService)?, records: DayRecordStore, archive: HealthArchive,
        calendar: Calendar, locale: String, now: @escaping @Sendable () -> Date,
        hasConsent: @escaping @MainActor () -> Bool
    ) {
        self.store = store
        self.service = service
        self.records = records
        self.archive = archive
        self.calendar = calendar
        self.locale = locale
        self.now = now
        self.hasConsent = hasConsent
    }

    private var today: Date { calendar.startOfDay(for: now()) }

    /// The report kept for a period id, if any; a file that can't be read is none.
    func report(id: String) -> PeriodReport? {
        if let report = written[id] { return report }
        if let cached = read[id] { return cached }
        let report = store.read(id: id)
        read[id] = .some(report)
        return report
    }

    /// A kept report shows even while it is written again.
    func state(for period: Period) -> State {
        guard let id = period.reportID(calendar: calendar) else { return .missing }
        if let report = report(id: id) { return .ready(report) }
        if writing.contains(id) { return .writing }
        if pending.contains(id) { return .pending }
        return .missing
    }

    func failure(for period: Period) -> Failure? { period.reportID(calendar: calendar).flatMap { failures[$0] } }

    func isWriting(_ period: Period) -> Bool { period.reportID(calendar: calendar).map(writing.contains) ?? false }

    /// The newest report kept in the last two days among the last finished periods: the home's line (spec §3.1).
    func fresh() -> (period: Period, report: PeriodReport)? {
        let now = now()
        return PeriodReportSchedule.lastFinished(today: today, calendar: calendar)
            .compactMap { p in p.reportID(calendar: calendar).flatMap(report(id:)).map { (period: p, report: $0) } }
            .filter { $0.report.generatedAt <= now && now.timeIntervalSince($0.report.generatedAt) < Self.freshFor }
            .max { $0.report.generatedAt < $1.report.generatedAt }
    }

    /// Writes what is due. One run at a time: an open while one runs waits for it instead of asking again.
    func writeDue() async {
        if let running { return await running.value }
        let task = Task { await runDue() }
        running = task
        await task.value
        if running == task { running = nil }
    }

    private func runDue() async {
        guard service != nil, hasConsent() else { return }
        let due = PeriodReportSchedule.due(today: today, calendar: calendar) { report(id: $0) != nil }
        pending.formUnion(due.compactMap { $0.reportID(calendar: calendar) })
        var calls = 0
        for period in due where calls < PeriodReportSchedule.perOpen {
            switch await write(period) {
            case .written: calls += 1
            case .empty: continue
            case .failed: return
            }
        }
    }

    /// Writes one period's report now: an open's due period, the page's Write again, the card's Write now. An
    /// earlier report stays on screen and on disk until the new one is in.
    @discardableResult
    func write(_ period: Period) async -> Outcome {
        guard let service, hasConsent(), let id = period.reportID(calendar: calendar),
            let span = PeriodReport.Span(period, calendar: calendar), !writing.contains(id)
        else { return .failed }
        let mine = generation
        writing.insert(id)
        defer { writing.remove(id) }
        do {
            let before = period.previous(calendar: calendar)
            let lastDay = calendar.date(byAdding: .day, value: -1, to: period.end)!
            let days = Array(try await records.records(from: before.start, through: lastDay).values)
            let (archive, calendar, locale, today) = (archive, calendar, locale, today)
            let request = await Task.detached(priority: .utility) {
                PeriodReportInput.request(
                    period: period, records: days, archive: archive, calendar: calendar, locale: locale, today: today)
            }.value
            guard let request else {
                pending.remove(id)
                return .empty
            }
            let reply = try await service.report(for: request)
            // Consent taken back (or the archive cleared) while it was written: it is not kept.
            guard generation == mine, hasConsent() else { return .failed }
            let report = PeriodReport(
                reply, period: span, generatedAt: now(), current: request.current, previous: request.previous)
            try store.write(report, id: id)
            written[id] = report
            pending.remove(id)
            failures[id] = nil
            return .written
        } catch {
            guard generation == mine else { return .failed }
            failures[id] = Self.failure(for: error)
            // A kept report stays as it is; a due one never written waits for the next open.
            if report(id: id) == nil, PeriodReportSchedule.lastFinished(today: today, calendar: calendar).contains(period) {
                pending.insert(id)
            }
            return .failed
        }
    }

    /// Consent taken back: nothing is written or waits any more. Kept reports stay readable, like kept notes.
    func stop() {
        generation += 1
        running?.cancel()
        running = nil
        pending = []
        failures = [:]
    }

    /// The archive was cleared, reports with it.
    func forget() {
        stop()
        written = [:]
        read = [:]
    }

    static func failure(for error: Error) -> Failure {
        switch HealthHomeModel.reportState(for: error) {
        case .offline: .offline
        case .needsModel: .needsModel
        default: .failed
        }
    }
}
```

- [ ] **Step 5: Wire it into `Sources/HealthFeature/Report/HealthHomeModel.swift`** (check `git diff --stat -- Sources/HealthFeature/Report/HealthHomeModel.swift Sources/HealthFeature/HealthRootView.swift` is empty first)

Replace

```swift
    @ObservationIgnored let calendar: Calendar

    @ObservationIgnored private let source: any HealthDataSource
```

with

```swift
    @ObservationIgnored let calendar: Calendar
    /// The period reports, on the same day records and archive as the calendar.
    @ObservationIgnored let reports: PeriodReports

    @ObservationIgnored private let source: any HealthDataSource
```

Replace

```swift
        cache: ReportCache, preferences: HealthPreferences, calendar: Calendar = .current,
```

with

```swift
        cache: ReportCache, preferences: HealthPreferences, periodReports: (any PeriodReportService)? = nil,
        calendar: Calendar = .current,
```

Replace

```swift
        self.dayRecords = DayRecordStore(builder: builder, calendar: calendar, now: now)
```

with

```swift
        let dayRecords = DayRecordStore(builder: builder, calendar: calendar, now: now)
        self.dayRecords = dayRecords
        self.reports = PeriodReports(
            store: cache.archive.reports, service: periodReports, records: dayRecords, archive: cache.archive,
            calendar: calendar, locale: locale, now: now, hasConsent: { preferences.summaryConsent })
```

Replace

```swift
    public func grantConsent() async {
        preferences.summaryConsent = true
        hasConsent = true
        await load()
    }
```

with

```swift
    public func grantConsent() async {
        preferences.summaryConsent = true
        hasConsent = true
        await load()
        await writeDueReports()
    }

    /// The period reports due (spec §5), after the day's note so the computer is asked one thing at a time. Only once
    /// Apple Health has been asked: before that there are no numbers to write about.
    func writeDueReports() async {
        guard day?.snapshot.odyState != .permission else { return }
        await reports.writeDue()
    }
```

Replace

```swift
        try? cache.clear()
        suggestion = nil
        report = .needsConsent
```

with

```swift
        try? cache.clear()
        reports.stop()
        suggestion = nil
        report = .needsConsent
```

Replace

```swift
        guard (try? archive.clear()) != nil else { return false }
```

with

```swift
        guard (try? archive.clear()) != nil else { return false }
        reports.forget()
```

Also update `clearArchive`'s doc comment first line from `/// Deletes every kept note on this phone (the menu's Clear archive), then files today's again: today's note stays` to `/// Deletes every kept note and report on this phone (the menu's Clear archive), then files today's note again: it stays` — keep the rest of the comment.

- [ ] **Step 6: Health's opens write the due reports (`Sources/HealthFeature/HealthRootView.swift`)**

Replace

```swift
                memory: LiveMemoryWriter(apiClient: apiClient), cache: .standard(), preferences: HealthPreferences(),
                locale: Bundle.main.preferredLocalizations.first ?? "en"))
```

with

```swift
                memory: LiveMemoryWriter(apiClient: apiClient), cache: .standard(), preferences: HealthPreferences(),
                periodReports: LivePeriodReportService(apiClient: apiClient),
                locale: Bundle.main.preferredLocalizations.first ?? "en"))
```

Replace

```swift
        .task { await model.load() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.load() } } }
```

with

```swift
        .task { await open() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await open() } } }
```

and add, just before `/// The glance once the report has settled.`:

```swift
    /// An open of Health: the day and its note, then the period reports that are due.
    private func open() async {
        await model.load()
        await model.writeDueReports()
    }

```

- [ ] **Step 7: Run the tests**

```bash
tuist generate --no-open
for T in PeriodReportScheduleTests PeriodReportsTests HealthHomeReportsTests HealthHomeModelTests WidgetGlanceTests; do
  xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd -only-testing:HealthFeatureTests/$T 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
done
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: 4, 9 and 5 tests pass in the new suites; `HealthHomeModelTests` and `WidgetGlanceTests` still pass; `** BUILD SUCCEEDED **` (the gallery's `HealthHomeModel(...)` call still compiles: the new parameter has a default); `0 error(s)`.

- [ ] **Step 8: Commit**

```bash
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): each Health open writes the last finished week, month, quarter and year still without a report — newest first, two an open, only with consent — and the rest wait" \
  Sources/HealthFeature/Report/PeriodReportSchedule.swift Sources/HealthFeature/Report/PeriodReports.swift \
  Sources/HealthFeature/Report/HealthHomeModel.swift Sources/HealthFeature/HealthRootView.swift \
  Tests/HealthFeatureTests/StubPeriodReports.swift Tests/HealthFeatureTests/PeriodReportScheduleTests.swift \
  Tests/HealthFeatureTests/PeriodReportsTests.swift Tests/HealthFeatureTests/HealthHomeReportsTests.swift
git show --stat HEAD           # exactly these eight files
```

---

### Task 5: iOS — the strings in ten languages, and `PeriodReportText`

`Resources/App/Localizable.xcstrings` carries the user's uncommitted edits. The keys are inserted *textually* (each in its sorted place, in Xcode's formatting), and the one changed entry is replaced in place, in the working catalog and, identically, in a copy of the committed one; the commit is the difference between the committed catalog and that copy, so only these entries enter it.

**Files:**
- Modify: `Resources/App/Localizable.xcstrings` (20 new keys, 1 replaced entry; patch)
- Create: `Sources/HealthFeature/Trends/PeriodReportText.swift`
- Modify: `Sources/HealthFeature/HealthRootView.swift` (the confirmation's `defaultValue`)
- Test: `Tests/HealthFeatureTests/PeriodReportTextTests.swift`

**Interfaces:**
- Consumes: `PeriodReport.Kind`, `PeriodReport.Comparison` (Task 3), `PeriodReports.Failure` (Task 4), `TrendScope`, `HealthCategory`, `ReportInk.green`, `Color.adaptive`.
- Produces: `enum PeriodReportText` — `struct Metric { title: LocalizedStringResource; symbol: String; category: HealthCategory }`; `kind(_:) -> LocalizedStringResource`; `scope(_:) -> TrendScope`; `ready(_ title: String) -> String`; `written(_ date: Date, calendar: Calendar) -> String`; `daysWithData(_ n: Int, of total: Int) -> String`; `was(_ value: String) -> String`; `metric(_ wire: String) -> Metric?`; `isBetter(metric:direction:) -> Bool?`; `arrow(_:) -> String`; `color(metric:direction:) -> AnyShapeStyle`; `spoken(_:title:) -> String`; `failure(_:) -> LocalizedStringResource`. And these keys (exact English; every `defaultValue:` must match):

| Key | English |
|---|---|
| `ios:health.periodReport.kind.week` | Weekly report |
| `ios:health.periodReport.kind.month` | Monthly report |
| `ios:health.periodReport.kind.quarter` | Quarterly report |
| `ios:health.periodReport.kind.year` | Yearly report |
| `ios:health.periodReport.ready` | %@ report ready |
| `ios:health.periodReport.pending` | Will be written when your computer is reachable. |
| `ios:health.periodReport.writing` | Ody is writing this report… |
| `ios:health.periodReport.none` | No report for this period. |
| `ios:health.periodReport.writeNow` | Write now |
| `ios:health.periodReport.writeAgain` | Write again |
| `ios:health.periodReport.written` | Written %@ |
| `ios:health.periodReport.offline` | Your computer isn't reachable, so the report couldn't be written. Try again when it is. |
| `ios:health.periodReport.failed` | The report couldn't be written. Try again later. |
| `ios:health.periodReport.daysWithData` | %lld of %lld days had data |
| `ios:health.periodReport.was` | was %@ |
| `ios:health.periodReport.up` | Up |
| `ios:health.periodReport.down` | Down |
| `ios:health.periodReport.openHint` | Opens the report. |
| `ios:health.periodReport.ask.changed` | What changed most in this period? |
| `ios:health.periodReport.ask.next` | What should I focus on next? |
| `ios:health.archive.confirmMessage` (replaced) | This deletes every daily note and report kept on this iPhone. Today's note and your health data stay. |

Reused as they are: `ios:health.calendar.change.flat` (About the same), `ios:health.calendar.vs.*`, `ios:health.report.needsModel`, `ios:health.category.sleep`, `ios:health.day.steps`, `ios:health.day.exercise`, `ios:health.recovery.hrv`, `ios:health.recovery.restingHr`, `ios:health.body.water`.

- [ ] **Step 1: Write the failing test**

Create `Tests/HealthFeatureTests/PeriodReportTextTests.swift`:

```swift
// Tests/HealthFeatureTests/PeriodReportTextTests.swift
import Foundation
import Testing

@testable import HealthFeature

/// The English the catalog's keys fall back to.
struct PeriodReportTextTests {
    @Test func theHomeLineNamesThePeriod() {
        #expect(PeriodReportText.ready("September 2026") == "September 2026 report ready")
    }

    @Test func sparseDataAndWhatItWas() {
        #expect(PeriodReportText.daysWithData(21, of: 30) == "21 of 30 days had data")
        #expect(PeriodReportText.was("6h 47m") == "was 6h 47m")
    }

    @Test func eachKindHasItsEyebrowAndScope() {
        #expect(PeriodReport.Kind.allCases.map { String(localized: PeriodReportText.kind($0)) } == ["Weekly report", "Monthly report", "Quarterly report", "Yearly report"])
        #expect(PeriodReport.Kind.allCases.map(PeriodReportText.scope) == [.week, .month, .quarter, .year])
    }

    @Test func downIsBetterOnlyForTheRestingHeartRate() {
        #expect(PeriodReportText.isBetter(metric: "restingHr", direction: .down) == true)
        #expect(PeriodReportText.isBetter(metric: "restingHr", direction: .up) == false)
        #expect(PeriodReportText.isBetter(metric: "sleep", direction: .up) == true)
        #expect(PeriodReportText.isBetter(metric: "steps", direction: .down) == false)
        #expect(PeriodReportText.isBetter(metric: "hrv", direction: .flat) == nil)
    }

    @Test func onlyKnownMetricsAreNamed() {
        #expect(PeriodReportText.metric("restingHr")?.symbol == "heart.fill")
        #expect(PeriodReportText.metric("water")?.category == .body)
        #expect(PeriodReportText.metric("sleep")?.category == .sleep)
        #expect(PeriodReportText.metric("weight") == nil)
    }

    @Test func voiceOverReadsAComparison() throws {
        let down = PeriodReport.Comparison(metric: "restingHr", current: "59 bpm", previous: "61 bpm", direction: .down)
        #expect(PeriodReportText.spoken(down, title: try #require(PeriodReportText.metric("restingHr")).title) == "Resting heart rate, 59 bpm, Down, was 61 bpm")
        let flat = PeriodReport.Comparison(metric: "hrv", current: "44 ms", previous: nil, direction: .flat)
        #expect(PeriodReportText.spoken(flat, title: try #require(PeriodReportText.metric("hrv")).title) == "Heart rate variability, 44 ms, About the same")
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
git diff --stat                                  # note the catalog's foreign edits before you start
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd -only-testing:HealthFeatureTests/PeriodReportTextTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'PeriodReportText' in scope`, `TEST FAILED`.

- [ ] **Step 3: Write the key script**

Create `/tmp/health2/add_keys.py` (`mkdir -p /tmp/health2` first):

```python
# Inserts the period-report keys into the String Catalog named on the command line, each in its sorted place and in
# Xcode's own formatting, and replaces the Clear-archive confirmation's entry in place, without rewriting any other
# line (so the user's uncommitted edits stay as they are).
# Usage, from the repo root: python3 /tmp/health2/add_keys.py CATALOG
import json
import sys

LANGS = ["de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "zh-HK", "zh-Hant"]

# (key, comment, {language: text})
KEYS = [
    ("ios:health.periodReport.kind.week", "Eyebrow over a weekly health report's headline, and on its card in the calendar.",
     {"en": "Weekly report", "de": "Wochenbericht", "es": "Informe semanal", "fr": "Bilan de la semaine", "it": "Resoconto settimanale", "ja": "週間レポート", "ko": "주간 리포트", "pt-BR": "Relatório semanal", "zh-HK": "每週報告", "zh-Hant": "每週報告"}),
    ("ios:health.periodReport.kind.month", "Eyebrow over a monthly health report's headline, and on its card in the calendar.",
     {"en": "Monthly report", "de": "Monatsbericht", "es": "Informe mensual", "fr": "Bilan du mois", "it": "Resoconto mensile", "ja": "月間レポート", "ko": "월간 리포트", "pt-BR": "Relatório mensal", "zh-HK": "每月報告", "zh-Hant": "每月報告"}),
    ("ios:health.periodReport.kind.quarter", "Eyebrow over a quarterly (three-month) health report's headline, and on its card in the calendar.",
     {"en": "Quarterly report", "de": "Quartalsbericht", "es": "Informe trimestral", "fr": "Bilan du trimestre", "it": "Resoconto trimestrale", "ja": "四半期レポート", "ko": "분기 리포트", "pt-BR": "Relatório trimestral", "zh-HK": "季度報告", "zh-Hant": "季度報告"}),
    ("ios:health.periodReport.kind.year", "Eyebrow over a yearly health report's headline, and on its card in the calendar.",
     {"en": "Yearly report", "de": "Jahresbericht", "es": "Informe anual", "fr": "Bilan de l’année", "it": "Resoconto annuale", "ja": "年間レポート", "ko": "연간 리포트", "pt-BR": "Relatório anual", "zh-HK": "年度報告", "zh-Hant": "年度報告"}),
    ("ios:health.periodReport.ready", "Health home, under This week: a period report was just written. %@ is the period, e.g. September 2026 or Week 39.",
     {"en": "%@ report ready", "de": "Bericht fertig: %@", "es": "Informe listo: %@", "fr": "Bilan prêt : %@", "it": "Resoconto pronto: %@", "ja": "%@のレポートができました", "ko": "%@ 리포트가 준비됐어요", "pt-BR": "Relatório pronto: %@", "zh-HK": "%@報告寫好咗", "zh-Hant": "%@報告已完成"}),
    ("ios:health.periodReport.pending", "Calendar and report page: a finished period's report has not been written yet because the computer could not be reached.",
     {"en": "Will be written when your computer is reachable.", "de": "Wird geschrieben, sobald dein Computer erreichbar ist.", "es": "Se escribirá cuando tu ordenador esté disponible.", "fr": "Sera rédigé dès que ton ordinateur sera joignable.", "it": "Verrà scritto quando il tuo computer sarà raggiungibile.", "ja": "コンピュータに接続できたら作成します。", "ko": "컴퓨터에 연결되면 작성할게요.", "pt-BR": "Será escrito quando seu computador estiver acessível.", "zh-HK": "等你部電腦連得到就會寫。", "zh-Hant": "等你的電腦可以連線時就會撰寫。"}),
    ("ios:health.periodReport.writing", "Calendar and report page: the period report is being written. Ody is the app's mascot; keep the name.",
     {"en": "Ody is writing this report…", "de": "Ody schreibt diesen Bericht …", "es": "Ody está escribiendo este informe…", "fr": "Ody rédige ce bilan…", "it": "Ody sta scrivendo questo resoconto…", "ja": "Odyがこのレポートを書いています…", "ko": "Ody가 이 리포트를 쓰고 있어요…", "pt-BR": "Ody está escrevendo este relatório…", "zh-HK": "Ody 寫緊呢份報告…", "zh-Hant": "Ody 正在撰寫這份報告…"}),
    ("ios:health.periodReport.none", "Report page: there is no report for this period.",
     {"en": "No report for this period.", "de": "Für diesen Zeitraum gibt es keinen Bericht.", "es": "No hay informe de este periodo.", "fr": "Aucun bilan pour cette période.", "it": "Nessun resoconto per questo periodo.", "ja": "この期間のレポートはありません。", "ko": "이 기간의 리포트가 없어요.", "pt-BR": "Nenhum relatório para este período.", "zh-HK": "呢段期間冇報告。", "zh-Hant": "這段期間沒有報告。"}),
    ("ios:health.periodReport.writeNow", "Button: write a period's health report now.",
     {"en": "Write now", "de": "Jetzt schreiben", "es": "Escribir ahora", "fr": "Rédiger maintenant", "it": "Scrivi ora", "ja": "今すぐ作成", "ko": "지금 작성", "pt-BR": "Escrever agora", "zh-HK": "即刻寫", "zh-Hant": "立即撰寫"}),
    ("ios:health.periodReport.writeAgain", "Report page toolbar button: write this period's report again.",
     {"en": "Write again", "de": "Neu schreiben", "es": "Volver a escribir", "fr": "Rédiger à nouveau", "it": "Riscrivi", "ja": "書き直す", "ko": "다시 작성", "pt-BR": "Escrever de novo", "zh-HK": "重新寫", "zh-Hant": "重新撰寫"}),
    ("ios:health.periodReport.written", "Report page footer: when the report was written. %@ is a short date, e.g. Oct 1.",
     {"en": "Written %@", "de": "Geschrieben am %@", "es": "Escrito el %@", "fr": "Rédigé le %@", "it": "Scritto il %@", "ja": "%@に作成", "ko": "%@ 작성", "pt-BR": "Escrito em %@", "zh-HK": "%@寫好", "zh-Hant": "撰寫於 %@"}),
    ("ios:health.periodReport.offline", "Report page: writing the report failed because the computer could not be reached.",
     {"en": "Your computer isn't reachable, so the report couldn't be written. Try again when it is.", "de": "Dein Computer ist nicht erreichbar, daher konnte der Bericht nicht geschrieben werden. Versuch es erneut, sobald er erreichbar ist.", "es": "Tu ordenador no está disponible, así que no se pudo escribir el informe. Inténtalo de nuevo cuando lo esté.", "fr": "Ton ordinateur n’est pas joignable, le bilan n’a donc pas pu être rédigé. Réessaie quand il le sera.", "it": "Il tuo computer non è raggiungibile, quindi il resoconto non è stato scritto. Riprova quando lo sarà.", "ja": "コンピュータに接続できないため、レポートを作成できませんでした。接続できるようになったらもう一度お試しください。", "ko": "컴퓨터에 연결할 수 없어 리포트를 작성하지 못했어요. 연결되면 다시 시도해 주세요.", "pt-BR": "Seu computador não está acessível, então o relatório não pôde ser escrito. Tente de novo quando estiver.", "zh-HK": "連唔到你部電腦，所以寫唔到報告。連得到嘅時候再試吓。", "zh-Hant": "無法連線到你的電腦，所以無法撰寫報告。可以連線時再試一次。"}),
    ("ios:health.periodReport.failed", "Report page: writing the report failed for another reason.",
     {"en": "The report couldn't be written. Try again later.", "de": "Der Bericht konnte nicht geschrieben werden. Versuch es später noch einmal.", "es": "No se pudo escribir el informe. Inténtalo más tarde.", "fr": "Le bilan n’a pas pu être rédigé. Réessaie plus tard.", "it": "Non è stato possibile scrivere il resoconto. Riprova più tardi.", "ja": "レポートを作成できませんでした。しばらくしてからもう一度お試しください。", "ko": "리포트를 작성하지 못했어요. 나중에 다시 시도해 주세요.", "pt-BR": "Não foi possível escrever o relatório. Tente de novo mais tarde.", "zh-HK": "寫唔到報告，遲啲再試吓。", "zh-Hant": "無法撰寫報告，請稍後再試。"}),
    ("ios:health.periodReport.daysWithData", "Report page footer when some days had no health data. The first %lld is the days with data, the second the days in the period.",
     {"en": "%lld of %lld days had data", "de": "An %lld von %lld Tagen gab es Daten", "es": "%lld de %lld días con datos", "fr": "%lld jours sur %lld avec des données", "it": "%lld giorni su %lld con dati", "ja": "%2$lld日中%1$lld日にデータがありました", "ko": "%2$lld일 중 %1$lld일에 데이터가 있었어요", "pt-BR": "%lld de %lld dias com dados", "zh-HK": "%2$lld 日之中有 %1$lld 日有資料", "zh-Hant": "%2$lld 天中有 %1$lld 天有資料"}),
    ("ios:health.periodReport.was", "Report page comparison: the value in the period before. %@ is that value, e.g. 6 h 47 min.",
     {"en": "was %@", "de": "vorher %@", "es": "antes %@", "fr": "avant %@", "it": "prima %@", "ja": "前は%@", "ko": "이전 %@", "pt-BR": "antes %@", "zh-HK": "之前 %@", "zh-Hant": "之前 %@"}),
    ("ios:health.periodReport.up", "VoiceOver, report page comparison: the number went up against the period before.",
     {"en": "Up", "de": "Gestiegen", "es": "Sube", "fr": "En hausse", "it": "In aumento", "ja": "増加", "ko": "증가", "pt-BR": "Subiu", "zh-HK": "上升", "zh-Hant": "上升"}),
    ("ios:health.periodReport.down", "VoiceOver, report page comparison: the number went down against the period before.",
     {"en": "Down", "de": "Gesunken", "es": "Baja", "fr": "En baisse", "it": "In calo", "ja": "減少", "ko": "감소", "pt-BR": "Caiu", "zh-HK": "下降", "zh-Hant": "下降"}),
    ("ios:health.periodReport.openHint", "VoiceOver hint on a period report's card or line: tapping opens the report.",
     {"en": "Opens the report.", "de": "Öffnet den Bericht.", "es": "Abre el informe.", "fr": "Ouvre le bilan.", "it": "Apre il resoconto.", "ja": "レポートを開きます。", "ko": "리포트를 엽니다.", "pt-BR": "Abre o relatório.", "zh-HK": "打開報告。", "zh-Hant": "開啟報告。"}),
    ("ios:health.periodReport.ask.changed", "Report page suggestion chip: ask what changed most in the period.",
     {"en": "What changed most in this period?", "de": "Was hat sich in diesem Zeitraum am meisten verändert?", "es": "¿Qué cambió más en este periodo?", "fr": "Qu’est-ce qui a le plus changé sur cette période ?", "it": "Cosa è cambiato di più in questo periodo?", "ja": "この期間で一番変わったことは？", "ko": "이 기간에 가장 많이 달라진 건 뭐야?", "pt-BR": "O que mais mudou neste período?", "zh-HK": "呢段期間變得最多嘅係咩？", "zh-Hant": "這段期間變化最大的是什麼？"}),
    ("ios:health.periodReport.ask.next", "Report page suggestion chip: ask what to focus on next.",
     {"en": "What should I focus on next?", "de": "Worauf sollte ich mich als Nächstes konzentrieren?", "es": "¿En qué debería centrarme ahora?", "fr": "Sur quoi me concentrer ensuite ?", "it": "Su cosa dovrei concentrarmi adesso?", "ja": "次は何に気をつければいい？", "ko": "다음엔 뭐에 집중하면 좋을까?", "pt-BR": "No que devo focar agora?", "zh-HK": "下一步應該專注喺邊方面？", "zh-Hant": "接下來該專注在什麼？"}),
]

# Existing entries replaced whole, in place.
REPLACE = [
    ("ios:health.archive.confirmMessage", "Confirmation message before deleting every kept daily note and period report.",
     {"en": "This deletes every daily note and report kept on this iPhone. Today's note and your health data stay.",
      "de": "Damit werden alle auf diesem iPhone gespeicherten Tagesnotizen und Berichte gelöscht. Die heutige Notiz und deine Gesundheitsdaten bleiben erhalten.",
      "es": "Se eliminarán todas las notas diarias y los informes guardados en este iPhone. La nota de hoy y tus datos de salud se conservan.",
      "fr": "Toutes les notes quotidiennes et tous les bilans conservés sur cet iPhone seront supprimés. La note du jour et tes données de santé restent.",
      "it": "Verranno eliminati tutte le note giornaliere e i resoconti conservati su questo iPhone. La nota di oggi e i tuoi dati sulla salute restano.",
      "ja": "このiPhoneに保存されている毎日のメモとレポートがすべて削除されます。今日のメモとヘルスケアのデータはそのまま残ります。",
      "ko": "이 iPhone에 보관된 모든 일일 노트와 리포트가 삭제돼요. 오늘의 노트와 건강 데이터는 그대로 남아요.",
      "pt-BR": "Isso apaga todas as notas diárias e relatórios guardados neste iPhone. A nota de hoje e seus dados de saúde continuam.",
      "zh-HK": "咁會刪除呢部 iPhone 上面保存嘅所有每日小記同報告。今日嘅小記同你嘅健康資料會保留。",
      "zh-Hant": "這會刪除這部 iPhone 上保存的所有每日小記和報告。今天的小記和你的健康資料都會保留。"}),
]


def block(key, comment, values):
    entry = {
        "comment": comment,
        "extractionState": "manual",
        "localizations": {lang: {"stringUnit": {"state": "translated", "value": text}} for lang, text in values.items()},
    }
    body = json.dumps(entry, indent=2, separators=(",", " : "), ensure_ascii=False, sort_keys=True)
    return "    " + json.dumps(key, ensure_ascii=False) + " : " + body.replace("\n", "\n    ")


path = sys.argv[1]
text = open(path, encoding="utf-8").read()
for key, comment, values in KEYS:
    assert set(values) == set(LANGS), (key, sorted(set(LANGS) ^ set(values)))
    keys = list(json.loads(text)["strings"])
    assert key not in keys, key + " is already in " + path
    # Before the first key, in file order, that sorts after this one: the catalog is sorted.
    after = next(k for k in keys if k > key)
    marker = "\n    " + json.dumps(after, ensure_ascii=False) + " : {\n"
    assert text.count(marker) == 1, after
    text = text.replace(marker, "\n" + block(key, comment, values) + "," + marker, 1)
for key, comment, values in REPLACE:
    assert set(values) == set(LANGS), key
    marker = "\n    " + json.dumps(key, ensure_ascii=False) + " : {\n"
    assert text.count(marker) == 1, key
    start = text.index(marker) + 1
    # The entry's own closing brace is the first line indented by exactly four spaces after its opening line.
    end = text.index("\n    }", start) + len("\n    }")
    text = text[:start] + block(key, comment, values) + text[end:]
json.loads(text)  # still a catalog
open(path, "w", encoding="utf-8").write(text)
print("added", len(KEYS), "keys and replaced", len(REPLACE), "in", path)
```

- [ ] **Step 4: Apply it to the working catalog and to a copy of the committed one, and verify**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git show HEAD:Resources/App/Localizable.xcstrings > /tmp/health2/head.xcstrings
cp /tmp/health2/head.xcstrings /tmp/health2/mine.xcstrings
python3 /tmp/health2/add_keys.py /tmp/health2/mine.xcstrings
python3 /tmp/health2/add_keys.py Resources/App/Localizable.xcstrings
python3 - <<'PY'
import json
work = json.load(open('Resources/App/Localizable.xcstrings', encoding='utf-8'))['strings']
mine = json.load(open('/tmp/health2/mine.xcstrings', encoding='utf-8'))['strings']
head = json.load(open('/tmp/health2/head.xcstrings', encoding='utf-8'))['strings']
new = sorted(set(mine) - set(head))
assert len(new) == 20, len(new)
changed = sorted(k for k in head if head[k] != mine[k])
assert changed == ['ios:health.archive.confirmMessage'], changed
for k in new + changed:
    assert work.get(k) == mine[k], k
    assert set(mine[k]['localizations']) == {'en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pt-BR', 'zh-Hant', 'zh-HK'}, k
print('OK', len(new), 'new,', len(changed), 'replaced')
PY
```
Expected: `added 20 keys and replaced 1 …` twice, then `OK 20 new, 1 replaced`.

- [ ] **Step 5: Write `Sources/HealthFeature/Trends/PeriodReportText.swift`**

```swift
// Sources/HealthFeature/Trends/PeriodReportText.swift
import Foundation
import SwiftUI

/// The period reports' words, in the user's language, and how a comparison reads and is coloured.
enum PeriodReportText {
    /// A comparison's metric as the day sheet names it, with its glyph and whose colour the glyph takes.
    struct Metric {
        let title: LocalizedStringResource
        let symbol: String
        let category: HealthCategory
    }

    /// The report's eyebrow: "Monthly report".
    static func kind(_ kind: PeriodReport.Kind) -> LocalizedStringResource {
        switch kind {
        case .week: LocalizedStringResource("ios:health.periodReport.kind.week", defaultValue: "Weekly report", comment: "Eyebrow over a weekly health report's headline, and on its card in the calendar.")
        case .month: LocalizedStringResource("ios:health.periodReport.kind.month", defaultValue: "Monthly report", comment: "Eyebrow over a monthly health report's headline, and on its card in the calendar.")
        case .quarter: LocalizedStringResource("ios:health.periodReport.kind.quarter", defaultValue: "Quarterly report", comment: "Eyebrow over a quarterly (three-month) health report's headline, and on its card in the calendar.")
        case .year: LocalizedStringResource("ios:health.periodReport.kind.year", defaultValue: "Yearly report", comment: "Eyebrow over a yearly health report's headline, and on its card in the calendar.")
        }
    }

    /// The calendar view a kind of report belongs to (for "vs last month").
    static func scope(_ kind: PeriodReport.Kind) -> TrendScope {
        switch kind {
        case .week: .week
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
    }

    /// "September 2026 report ready".
    static func ready(_ title: String) -> String {
        String(
            localized: "ios:health.periodReport.ready", defaultValue: "\(title) report ready",
            comment: "Health home, under This week: a period report was just written. %@ is the period, e.g. September 2026 or Week 39.")
    }

    /// "Written Oct 1".
    static func written(_ date: Date, calendar: Calendar) -> String {
        let when = date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())
        return String(
            localized: "ios:health.periodReport.written", defaultValue: "Written \(when)",
            comment: "Report page footer: when the report was written. %@ is a short date, e.g. Oct 1.")
    }

    /// "21 of 30 days had data".
    static func daysWithData(_ n: Int, of total: Int) -> String {
        String(
            localized: "ios:health.periodReport.daysWithData", defaultValue: "\(n) of \(total) days had data",
            comment: "Report page footer when some days had no health data. The first %lld is the days with data, the second the days in the period.")
    }

    /// "was 6 h 47 min".
    static func was(_ value: String) -> String {
        String(
            localized: "ios:health.periodReport.was", defaultValue: "was \(value)",
            comment: "Report page comparison: the value in the period before. %@ is that value, e.g. 6 h 47 min.")
    }

    /// The metrics the desktop compares; another name is left out.
    static func metric(_ wire: String) -> Metric? {
        switch wire {
        case "sleep":
            Metric(title: LocalizedStringResource("ios:health.category.sleep", defaultValue: "Sleep", comment: "Sleep category title."), symbol: "moon.zzz.fill", category: .sleep)
        case "steps":
            Metric(title: LocalizedStringResource("ios:health.day.steps", defaultValue: "Steps", comment: "Day sheet row: the day's step count."), symbol: "figure.walk", category: .activity)
        case "exercise":
            Metric(title: LocalizedStringResource("ios:health.day.exercise", defaultValue: "Exercise", comment: "Day sheet row: minutes of exercise."), symbol: "flame.fill", category: .activity)
        case "hrv":
            Metric(title: LocalizedStringResource("ios:health.recovery.hrv", defaultValue: "Heart rate variability", comment: "Day sheet row: HRV."), symbol: "waveform.path.ecg", category: .recovery)
        case "restingHr":
            Metric(title: LocalizedStringResource("ios:health.recovery.restingHr", defaultValue: "Resting heart rate", comment: "Day sheet row: resting heart rate."), symbol: "heart.fill", category: .recovery)
        case "water":
            Metric(title: LocalizedStringResource("ios:health.body.water", defaultValue: "Water", comment: "Day sheet row: cups of water."), symbol: "drop.fill", category: .body)
        default: nil
        }
    }

    /// Whether a move is for the better: up for most numbers, down for the resting heart rate; level is neither.
    static func isBetter(metric: String, direction: PeriodReport.Comparison.Direction) -> Bool? {
        switch direction {
        case .flat: nil
        case .up: metric != "restingHr"
        case .down: metric == "restingHr"
        }
    }

    static func arrow(_ direction: PeriodReport.Comparison.Direction) -> String {
        switch direction {
        case .up: "↑"  // l10n:ignore: arrow
        case .down: "↓"  // l10n:ignore: arrow
        case .flat: "→"  // l10n:ignore: arrow
        }
    }

    /// Better in the note's green, worse in the calendar's warm orange, level in secondary ink.
    static func color(metric: String, direction: PeriodReport.Comparison.Direction) -> AnyShapeStyle {
        switch isBetter(metric: metric, direction: direction) {
        case true?: AnyShapeStyle(ReportInk.green)
        case false?: AnyShapeStyle(Color.adaptive(0xB4470C, dark: 0xFFA27A))
        case nil: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    /// What VoiceOver reads for a comparison: "Resting heart rate, 59 bpm, Down, was 61 bpm".
    static func spoken(_ c: PeriodReport.Comparison, title: LocalizedStringResource) -> String {
        let moved: String =
            switch c.direction {
            case .up: String(localized: "ios:health.periodReport.up", defaultValue: "Up", comment: "VoiceOver, report page comparison: the number went up against the period before.")
            case .down: String(localized: "ios:health.periodReport.down", defaultValue: "Down", comment: "VoiceOver, report page comparison: the number went down against the period before.")
            case .flat: String(localized: "ios:health.calendar.change.flat", defaultValue: "About the same", comment: "VoiceOver: a number changed less than 3% against the previous period.")
            }
        return ([String(localized: title), c.current, moved] + [c.previous.map(was)].compactMap { $0 })
            .joined(separator: ", ")
    }

    static func failure(_ failure: PeriodReports.Failure) -> LocalizedStringResource {
        switch failure {
        case .offline:
            LocalizedStringResource("ios:health.periodReport.offline", defaultValue: "Your computer isn't reachable, so the report couldn't be written. Try again when it is.", comment: "Report page: writing the report failed because the computer could not be reached.")
        case .needsModel:
            LocalizedStringResource("ios:health.report.needsModel", defaultValue: "Set up an AI provider on your computer and Ody will write your notes.", comment: "Health: no AI provider is set up on the computer.")
        case .failed:
            LocalizedStringResource("ios:health.periodReport.failed", defaultValue: "The report couldn't be written. Try again later.", comment: "Report page: writing the report failed for another reason.")
        }
    }
}
```

- [ ] **Step 6: The confirmation's new English (`Sources/HealthFeature/HealthRootView.swift`)**

Replace

```swift
        defaultValue: "This deletes every daily note kept on this iPhone. Today's note and your health data stay.",
        comment: "Confirmation message before deleting every kept daily note.")
```

with

```swift
        defaultValue: "This deletes every daily note and report kept on this iPhone. Today's note and your health data stay.",
        comment: "Confirmation message before deleting every kept daily note and period report.")
```

- [ ] **Step 7: Run the test and the audit**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd -only-testing:HealthFeatureTests/PeriodReportTextTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: `Test run with 6 tests passed`; `0 error(s)` (keys only views use show as "not referenced" warnings until Tasks 6–7).

- [ ] **Step 8: Build the catalog patch and commit**

```bash
python3 - <<'PY'
import difflib
head = open('/tmp/health2/head.xcstrings', encoding='utf-8').read().splitlines(keepends=True)
mine = open('/tmp/health2/mine.xcstrings', encoding='utf-8').read().splitlines(keepends=True)
with open('/tmp/health2/catalog.patch', 'w', encoding='utf-8') as f:
    f.writelines(difflib.unified_diff(head, mine, 'a/Resources/App/Localizable.xcstrings', 'b/Resources/App/Localizable.xcstrings'))
PY
GIT_INDEX_FILE=/tmp/health2/check.idx git read-tree HEAD
GIT_INDEX_FILE=/tmp/health2/check.idx git apply --cached --check /tmp/health2/catalog.patch && echo PATCH-OK
rm -f /tmp/health2/check.idx
.superpowers/sdd/commit-mine.sh "feat(health): period-report strings in ten languages — the kinds, ready, pending, written, the comparisons — and Clear archive now says it deletes the reports too" \
  --patch /tmp/health2/catalog.patch \
  Sources/HealthFeature/Trends/PeriodReportText.swift Tests/HealthFeatureTests/PeriodReportTextTests.swift \
  Sources/HealthFeature/HealthRootView.swift
git show --stat HEAD           # these four files
git diff --stat                # the catalog still shows the user's own edits, nothing of ours
```

---
### Task 6: iOS — the report page

**Files:**
- Create: `Sources/HealthFeature/Trends/PeriodReportView.swift`
- Create: `Sources/HealthFeature/Trends/ComparisonsCard.swift`
- Modify: `Sources/HealthFeature/UI/ReportStory.swift` (`NudgeCard` internal)
- Modify: `Sources/HealthFeature/UI/HealthHomeView.swift` (the destination)
- Test: `Tests/HealthFeatureTests/PeriodReportPageTests.swift`

**Interfaces:**
- Consumes: `PeriodReports` (`state(for:)`, `failure(for:)`, `isWriting(_:)`, `write(_:)`), `HealthHomeModel.reports/.calendar/.hasConsent` (Task 4); `PeriodReportText` (Task 5); `PeriodReport.story` (Task 3); `ReportStory(_:eyebrow:)`, `ReportInk`, `NudgeCard`, `AskComposer(suggestions:attachment:onSend:)`, `HealthSurface`, `TrendText.title`, `TrendScope.versusLabel`, `CategoryStyle.of(_:).accent`, `OdySceneView`, `OdyScene`, `OdyPalette.marigold`, `ScreenTitles.join`, `.screenTitle`.
- Produces: `public struct PeriodReportRoute: Hashable, Sendable { public let period: Period; public init(period:) }`; `struct PeriodReportView: View` (`init(period:home:onAsk:)`, `static func story(_: PeriodReport) -> HealthSummary`, `static func attachment(_: PeriodReport) -> String?`); `struct PeriodReportRow: View` (`scene: OdyScene`, `text: Text`); `struct ComparisonsCard: View` (`comparisons`, `scope`; `static func rows(_:) -> [(PeriodReport.Comparison, PeriodReportText.Metric)]`); `HealthHomeView` routes `PeriodReportRoute` to the page.

- [ ] **Step 1: Write the failing test**

Create `Tests/HealthFeatureTests/PeriodReportPageTests.swift`:

```swift
// Tests/HealthFeatureTests/PeriodReportPageTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

@MainActor
struct PeriodReportPageTests {
    static func report() -> PeriodReport {
        PeriodReport(
            PeriodReportReply(
                headline: "More sleep.", headlineHighlight: "More sleep", headlineCategory: "sleep",
                insights: [
                    .init(category: "sleep", title: "You slept 7 h 12 min.", highlights: ["7 h 12 min"]),
                    .init(category: "mood", title: "Calm month."),
                ],
                comparisons: [
                    .init(metric: "sleep", current: "7 h 12 min", previous: "6 h 47 min", direction: .up),
                    .init(metric: "weight", current: "70 kg", previous: "71 kg", direction: .down),
                ],
                nudge: "Walk after lunch."),
            period: PeriodReportWireTests.request.period, generatedAt: TestClock.now,
            current: PeriodReportWireTests.request.current, previous: PeriodReportWireTests.request.previous)
    }

    @Test func theStoryKeepsTheIdeaForAfterTheComparisons() {
        let story = PeriodReportView.story(Self.report())
        #expect(story.nudge == nil)
        #expect(story.headlineHighlight == "More sleep")
        #expect(ReportText.stories(story).map { $0.1.text } == ["You slept 7 h 12 min."])
    }

    @Test func comparisonsThisAppCannotNameAreLeftOut() {
        #expect(ComparisonsCard.rows(Self.report().comparisons).map { $0.0.metric } == ["sleep"])
    }

    @Test func aQuestionCarriesThePeriodItsNumbersAndWhatTheReportSaid() throws {
        let json = try #require(PeriodReportView.attachment(Self.report()))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect((object["period"] as? [String: Any])?["kind"] as? String == "month")
        #expect((object["current"] as? [String: Any])?["daysWithData"] as? Int == 28)
        #expect((object["previous"] as? [String: Any])?["daysWithData"] as? Int == 31)
        #expect(object["headline"] as? String == "More sleep.")
        #expect(object["insights"] as? [String] == ["You slept 7 h 12 min.", "Calm month."])
        // Chat's card reads a block with a category as a week block; this one is not.
        #expect(object["category"] == nil)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
git diff --stat -- Sources/HealthFeature/UI/ReportStory.swift Sources/HealthFeature/UI/HealthHomeView.swift   # must print nothing
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd -only-testing:HealthFeatureTests/PeriodReportPageTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'PeriodReportView' in scope`, `TEST FAILED`.

- [ ] **Step 3: Make the idea's card reusable (`Sources/HealthFeature/UI/ReportStory.swift`)**

Replace

```swift
/// The closing idea, on a mint card.
private struct NudgeCard: View {
```

with

```swift
/// The closing idea, on a mint card; a period report's page shows it after its comparisons.
struct NudgeCard: View {
```

- [ ] **Step 4: Write `Sources/HealthFeature/Trends/ComparisonsCard.swift`**

```swift
// Sources/HealthFeature/Trends/ComparisonsCard.swift
import SwiftUI

/// How each number moved against the period before, as the report put it: the metric's glyph and name, the arrow in
/// the colour of better or worse (down is better for the resting heart rate), the number now and what it was. One
/// under another at accessibility sizes; nothing at all when there is nothing to compare.
struct ComparisonsCard: View {
    let comparisons: [PeriodReport.Comparison]
    let scope: TrendScope
    @Environment(\.dynamicTypeSize) private var typeSize
    /// One column for every glyph, as the day sheet's rows.
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 26

    /// The comparisons this app can name, in the report's order.
    static func rows(_ comparisons: [PeriodReport.Comparison]) -> [(PeriodReport.Comparison, PeriodReportText.Metric)] {
        comparisons.compactMap { c in PeriodReportText.metric(c.metric).map { (c, $0) } }
    }

    var body: some View {
        let rows = Self.rows(comparisons)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(scope.versusLabel)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                    Divider()
                    row(item.0, item.1)
                }
            }
            .padding(.horizontal, 14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
        }
    }

    private func row(_ c: PeriodReport.Comparison, _ metric: PeriodReportText.Metric) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout =
            stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            Label {
                Text(metric.title)
            } icon: {
                Image(systemName: metric.symbol)
                    .font(.body.weight(.medium))
                    .imageScale(.small)
                    .foregroundStyle(CategoryStyle.of(metric.category).accent)
                    .frame(width: glyphWidth)
            }
            if !stacked { Spacer(minLength: 8) }
            VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: PeriodReportText.arrow(c.direction))
                        .font(.body.weight(.bold))
                        .foregroundStyle(PeriodReportText.color(metric: c.metric, direction: c.direction))
                    Text(verbatim: c.current).font(.body.weight(.semibold)).monospacedDigit()
                }
                if let previous = c.previous {
                    Text(verbatim: PeriodReportText.was(previous)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: PeriodReportText.spoken(c, title: metric.title)))
    }
}
```

- [ ] **Step 5: Write `Sources/HealthFeature/Trends/PeriodReportView.swift`**

```swift
// Sources/HealthFeature/Trends/PeriodReportView.swift
import Models
import OdyKit
import SwiftUI

/// Where a period report opens.
public struct PeriodReportRoute: Hashable, Sendable {
    public let period: Period

    public init(period: Period) { self.period = period }
}

/// A period's report (spec §3.4), told like the daily note: the kind of report as the eyebrow over the coloured
/// headline, the insight cards, how each number moved against the period before, then the small idea. Write again
/// rewrites it (the earlier one stays until the new one is in); the ask box sends the period's numbers with the
/// question.
struct PeriodReportView: View {
    let period: Period
    let home: HealthHomeModel
    let onAsk: (String) -> Void
    /// Bumped when Write again (or Write now) brought a report: the success tap.
    @State private var rewritten = 0
    /// The workspace's ("Health"): a screenshot of this page is "Health · September 2026".
    @Environment(\.screenTitle) private var enclosingTitle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reports: PeriodReports { home.reports }
    private var title: String { TrendText.title(period, calendar: home.calendar) }

    var body: some View {
        let state = reports.state(for: period)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch state {
                case .ready(let report):
                    page(report)
                case .writing:
                    card { PeriodReportRow(scene: .writing, text: Text("ios:health.periodReport.writing")) }
                case .pending:
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            PeriodReportRow(scene: .offline, text: Text("ios:health.periodReport.pending"))
                            writeNow
                        }
                    }
                case .missing:
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ios:health.periodReport.none").font(.subheadline).foregroundStyle(.secondary)
                            writeNow
                        }
                    }
                }
                if let failure = reports.failure(for: period) {
                    Text(PeriodReportText.failure(failure))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(reduceMotion ? nil : .smooth, value: state)
        }
        .background(HealthSurface.page)
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .screenTitle(ScreenTitles.join(enclosingTitle, title))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if reports.isWriting(period) {
                    ProgressView()
                } else if case .ready = state, home.hasConsent {
                    Button(action: write) {
                        Label {
                            Text("ios:health.periodReport.writeAgain")
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if case .ready(let report) = state {
                AskComposer(
                    suggestions: [
                        LocalizedStringResource("ios:health.periodReport.ask.changed", defaultValue: "What changed most in this period?", comment: "Report page suggestion chip: ask what changed most in the period."),
                        LocalizedStringResource("ios:health.periodReport.ask.next", defaultValue: "What should I focus on next?", comment: "Report page suggestion chip: ask what to focus on next."),
                    ],
                    attachment: { Self.attachment(report) }, onSend: onAsk)
            }
        }
        .sensoryFeedback(.success, trigger: rewritten)
    }

    /// The stories, the comparisons, the idea, then when it was written (and how many days it had).
    @ViewBuilder
    private func page(_ report: PeriodReport) -> some View {
        let eyebrow = Text(PeriodReportText.kind(report.period.kind))
        if let story = ReportStory(Self.story(report), eyebrow: eyebrow) {
            story
        } else {
            // Its insights all fell away: the report is its headline.
            VStack(alignment: .leading, spacing: 6) {
                eyebrow.font(.footnote.weight(.bold)).foregroundStyle(ReportInk.green)
                Text(verbatim: report.headline)
                    .font(.title2.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        ComparisonsCard(comparisons: report.comparisons, scope: PeriodReportText.scope(report.period.kind))
        if let nudge = report.nudge, !nudge.isEmpty { NudgeCard(text: nudge) }
        VStack(alignment: .leading, spacing: 4) {
            if report.current.daysWithData < report.current.elapsedDays {
                Text(verbatim: PeriodReportText.daysWithData(report.current.daysWithData, of: report.current.elapsedDays))
            }
            Text(verbatim: PeriodReportText.written(report.generatedAt, calendar: home.calendar))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var writeNow: some View {
        if home.hasConsent {
            Button(action: write) { Text("ios:health.periodReport.writeNow") }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(OdyPalette.marigold)
        }
    }

    private func write() {
        Task { if await reports.write(period) == .written { rewritten += 1 } }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }

    /// The report as the daily note's stories, without its idea: here that comes after the comparisons.
    static func story(_ report: PeriodReport) -> HealthSummary {
        var story = report.story
        story.nudge = nil
        return story
    }

    /// What a question about the report carries: the period, its numbers and the period before's, and what the report
    /// said. Chat's card shows it as "Health" (it is not a day).
    static func attachment(_ report: PeriodReport) -> String? {
        let ask = Ask(
            period: report.period, current: report.current, previous: report.previous, headline: report.headline,
            insights: report.insights.map(\.title))
        guard let data = try? HealthWire.encoder().encode(ask) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private struct Ask: Encodable {
        let period: PeriodReport.Span
        let current: Aggregates
        let previous: Aggregates?
        let headline: String
        let insights: [String]
    }
}

/// Ody beside a line: a report being written, or waiting for the computer.
struct PeriodReportRow: View {
    let scene: OdyScene
    let text: Text
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            OdySceneView(scene)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 14))
                .accessibilityHidden(true)
            text.font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 6: Route to it from the Health stack (`Sources/HealthFeature/UI/HealthHomeView.swift`)**

Replace

```swift
        .navigationDestination(for: TrendsRoute.self) { route in
            TrendsView(route: route, home: model, onAsk: onAsk)
        }
```

with

```swift
        .navigationDestination(for: TrendsRoute.self) { route in
            TrendsView(route: route, home: model, onAsk: onAsk)
        }
        // From the calendar's report card and the home's "report ready" line.
        .navigationDestination(for: PeriodReportRoute.self) { route in
            PeriodReportView(period: route.period, home: model, onAsk: onAsk)
        }
```

- [ ] **Step 7: Run the tests and build**

```bash
tuist generate --no-open
for T in PeriodReportPageTests ReportStoryTests; do
  xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd -only-testing:HealthFeatureTests/$T 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
done
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: `Test run with 3 tests passed`; `ReportStoryTests` still pass; `** BUILD SUCCEEDED **`; `0 error(s)`.

- [ ] **Step 8: Commit**

```bash
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): the period report's page — the daily note's stories under 'Monthly report', how each number moved against the period before, the idea, Write again, and a question carries the period's numbers" \
  Sources/HealthFeature/Trends/PeriodReportView.swift Sources/HealthFeature/Trends/ComparisonsCard.swift \
  Sources/HealthFeature/UI/ReportStory.swift Sources/HealthFeature/UI/HealthHomeView.swift \
  Tests/HealthFeatureTests/PeriodReportPageTests.swift
git show --stat HEAD           # exactly these five files
```

---

### Task 7: iOS — the calendar's report card and the home's "report ready" line

**Files:**
- Create: `Sources/HealthFeature/Trends/PeriodReportCard.swift`
- Modify: `Sources/HealthFeature/Trends/TrendsView.swift`
- Modify: `Sources/HealthFeature/Trends/WeekCard.swift`
- Modify: `Sources/HealthFeature/UI/HealthHomeView.swift`
- Test: `Tests/HealthFeatureTests/PeriodReportCardTests.swift`

**Interfaces:**
- Consumes: `PeriodReports.State`, `PeriodReports.fresh()`, `write(_:)` (Task 4); `PeriodReportText.kind/ready` (Task 5); `PeriodReportRoute`, `PeriodReportRow` (Task 6); `TrendsModel.period/.current`, `TrendText.title`, `ReportInk`, `HealthSurface`, `OdyPalette`.
- Produces: `struct PeriodReportCard: View` (`state`, `period`, `hasData`, `canWrite`, `onWrite`; `static func shows(_:hasData:) -> Bool`); `struct ReportReadyLine: View` (`period`, `calendar`); `TrendsView` shows the card under the header; the home's week card carries the line.

- [ ] **Step 1: Write the failing test**

Create `Tests/HealthFeatureTests/PeriodReportCardTests.swift`:

```swift
// Tests/HealthFeatureTests/PeriodReportCardTests.swift
import Testing

@testable import HealthFeature

@MainActor
struct PeriodReportCardTests {
    @Test func theCalendarShowsAReportAWriteAndAWaitThatHasData() {
        #expect(PeriodReportCard.shows(.ready(PeriodReportPageTests.report()), hasData: false))
        #expect(PeriodReportCard.shows(.writing, hasData: true))
        #expect(PeriodReportCard.shows(.pending, hasData: true))
        #expect(!PeriodReportCard.shows(.pending, hasData: false))
        #expect(!PeriodReportCard.shows(.missing, hasData: true))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
git diff --stat -- Sources/HealthFeature/Trends/TrendsView.swift Sources/HealthFeature/Trends/WeekCard.swift Sources/HealthFeature/UI/HealthHomeView.swift   # must print nothing
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd -only-testing:HealthFeatureTests/PeriodReportCardTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: `error: cannot find 'PeriodReportCard' in scope`, `TEST FAILED`.

- [ ] **Step 3: Write `Sources/HealthFeature/Trends/PeriodReportCard.swift`**

```swift
// Sources/HealthFeature/Trends/PeriodReportCard.swift
import OdyKit
import SwiftUI

/// The shown period's report on the calendar (spec §3.2), between the three numbers and the days: its headline,
/// opening the report; while it is written, Ody writing; for a finished period that has numbers but still waits for
/// the computer, when it will be written, and Write now.
struct PeriodReportCard: View {
    let state: PeriodReports.State
    let period: Period
    /// The period has numbers: one with nothing recorded has nothing to wait for.
    let hasData: Bool
    let canWrite: Bool
    let onWrite: () -> Void

    static func shows(_ state: PeriodReports.State, hasData: Bool) -> Bool {
        switch state {
        case .ready, .writing: true
        case .pending: hasData
        case .missing: false
        }
    }

    var body: some View {
        if Self.shows(state, hasData: hasData) {
            switch state {
            case .ready(let report):
                NavigationLink(value: PeriodReportRoute(period: period)) { headline(report) }
                    .buttonStyle(.plain)
            case .writing:
                card { PeriodReportRow(scene: .writing, text: Text("ios:health.periodReport.writing")) }
            default:
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        PeriodReportRow(scene: .offline, text: Text("ios:health.periodReport.pending"))
                        if canWrite {
                            Button(action: onWrite) { Text("ios:health.periodReport.writeNow") }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .tint(OdyPalette.marigold)
                        }
                    }
                }
            }
        }
    }

    private func headline(_ report: PeriodReport) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(PeriodReportText.kind(report.period.kind))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(ReportInk.green)
                Text(verbatim: report.headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("ios:health.periodReport.openHint"))
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }
}

/// The home's line under This week when a report was written in the last two days (spec §3.1).
struct ReportReadyLine: View {
    let period: Period
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill").foregroundStyle(ReportInk.green).accessibilityHidden(true)
            Text(verbatim: PeriodReportText.ready(TrendText.title(period, calendar: calendar)))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("ios:health.periodReport.openHint"))
    }
}
```

- [ ] **Step 4: The card on the calendar (`Sources/HealthFeature/Trends/TrendsView.swift`)**

Replace

```swift
    @State private var forward = true
    let onAsk: (String) -> Void
```

with

```swift
    @State private var forward = true
    /// Bumped when Write now brought a report: the success tap.
    @State private var reportsWritten = 0
    private let home: HealthHomeModel
    let onAsk: (String) -> Void
```

Replace

```swift
        _trends = State(initialValue: home.trends(route))
```

with

```swift
        _trends = State(initialValue: home.trends(route))
        self.home = home
```

Replace

```swift
                TrendStatsHeader(scope: trends.scope, current: trends.current, previous: trends.previous)
                    .redacted(reason: trends.current == nil ? .placeholder : [])
```

with

```swift
                TrendStatsHeader(scope: trends.scope, current: trends.current, previous: trends.previous)
                    .redacted(reason: trends.current == nil ? .placeholder : [])
                PeriodReportCard(
                    state: home.reports.state(for: trends.period), period: trends.period,
                    hasData: (trends.current?.daysWithData ?? 0) > 0, canWrite: home.hasConsent, onWrite: writeReport)
```

Replace

```swift
        .sensoryFeedback(.selection, trigger: trends.period)
```

with

```swift
        .sensoryFeedback(.selection, trigger: trends.period)
        .sensoryFeedback(.success, trigger: reportsWritten)
```

Replace

```swift
    private func open(_ day: Date) { presented = PresentedDay(day: day) }
```

with

```swift
    private func open(_ day: Date) { presented = PresentedDay(day: day) }

    /// The card's Write now, for the period on screen when it was tapped.
    private func writeReport() {
        let period = trends.period
        Task { if await home.reports.write(period) == .written { reportsWritten += 1 } }
    }
```

Also extend the type's doc comment: after `against the period before; the days as style-C cells, or for a quarter or a year a bar per month.` keep the text and add the sentence `Under the numbers, the period's report (or when it will be written).` at the end of that comment's second line group (keep it one comment block).

- [ ] **Step 5: The home's card draws the week and the report line (`WeekCard.swift`, `HealthHomeView.swift`)**

In `Sources/HealthFeature/Trends/WeekCard.swift` replace

```swift
/// This week on the home (spec §3.1): seven style-C days, Monday first, and average sleep and daily steps against
/// last week. The whole card opens the calendar on this week.
```

with

```swift
/// This week on the home (spec §3.1): seven style-C days, Monday first, and average sleep and daily steps against
/// last week. It opens the calendar on this week; the home draws the card around it, with a fresh report's line under
/// it when there is one.
```

and delete the line

```swift
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
```

(the one between `.padding(14)` and `.contentShape(.rect(cornerRadius: 18))`).

In `Sources/HealthFeature/UI/HealthHomeView.swift` replace

```swift
                if let week = model.week, model.day?.snapshot.odyState != .permission {
                    NavigationLink(value: TrendsRoute(scope: .week, anchor: week.period.start)) {
                        WeekCard(week: week, calendar: model.calendar)
                    }
                    .buttonStyle(.plain)
                }
```

with

```swift
                if let week = model.week, model.day?.snapshot.odyState != .permission {
                    // One card: the week opens the calendar; a report written in the last two days, under it, opens
                    // that report.
                    VStack(spacing: 0) {
                        NavigationLink(value: TrendsRoute(scope: .week, anchor: week.period.start)) {
                            WeekCard(week: week, calendar: model.calendar)
                        }
                        .buttonStyle(.plain)
                        if let fresh = model.reports.fresh() {
                            Divider().padding(.horizontal, 14)
                            NavigationLink(value: PeriodReportRoute(period: fresh.period)) {
                                ReportReadyLine(period: fresh.period, calendar: model.calendar)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(HealthSurface.card, in: .rect(cornerRadius: 18))
                }
```

- [ ] **Step 6: Run the tests, build, audit**

```bash
tuist generate --no-open
for T in PeriodReportCardTests WeekCardTests TrendsModelTests; do
  xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd -only-testing:HealthFeatureTests/$T 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
done
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
python3 scripts/l10n.py audit 2>&1 | grep "not referenced" | grep -c "ios:health.periodReport" || true   # 0
```
Expected: `Test run with 1 test passed` and the two phase-1 suites still pass; `** BUILD SUCCEEDED **`; `0 error(s)`; the grep prints `0` (every new key is used).

- [ ] **Step 7: Commit**

```bash
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): the calendar shows the period's report under its numbers, or that it will be written when the computer is reachable; the home says a report is ready for two days" \
  Sources/HealthFeature/Trends/PeriodReportCard.swift Sources/HealthFeature/Trends/TrendsView.swift \
  Sources/HealthFeature/Trends/WeekCard.swift Sources/HealthFeature/UI/HealthHomeView.swift \
  Tests/HealthFeatureTests/PeriodReportCardTests.swift
git show --stat HEAD           # exactly these five files
```

---

### Task 8: iOS — gallery states, screenshots, device checklist, README

**Files:**
- Modify: `Sources/HealthFeature/Debug/HealthPreviewSource.swift`
- Modify: `Sources/App/HealthGallery.swift`
- Modify: `docs/health-device-checklist.md`
- Modify: `README.md` (the `HealthFeature` bullet)

**Interfaces:**
- Consumes: everything above; `HealthHomeModel(source:summaries:memory:cache:preferences:periodReports:locale:)`, `PeriodReportRoute`, `TrendsRoute`, `Period.containing`, `ReportCache.archive.reports`.
- Produces (DEBUG): `PreviewPeriodReportService(offline:)` with `static let sample: PeriodReportReply`; `PeriodReportStore.writePreview(period:generatedAt:calendar:)`; `-HealthGallery report-home | report-page | report-card | report-pending`.

- [ ] **Step 1: Preview data (`Sources/HealthFeature/Debug/HealthPreviewSource.swift`)**

Check `git diff --stat -- Sources/HealthFeature/Debug/HealthPreviewSource.swift Sources/App/HealthGallery.swift docs/health-device-checklist.md README.md` prints nothing. At the end of the file, before the closing `#endif`, add:

```swift

/// The computer for period reports in the gallery: a month a little better slept and a little less walked than the
/// one before (the numbers `writePreview` keeps), or unreachable.
public struct PreviewPeriodReportService: PeriodReportService {
    let offline: Bool

    public init(offline: Bool = false) { self.offline = offline }

    public static let sample = PeriodReportReply(
        headline: "More sleep, fewer steps than the month before.", headlineHighlight: "More sleep",
        headlineCategory: "sleep",
        insights: [
            .init(
                category: "sleep", title: "You slept 7 h 12 min a night on average, 25 minutes more than the month before.",
                highlights: ["7 h 12 min", "25 minutes more"], stat: .init(value: "7:12", unit: "hr", caption: "before 6:47")),
            .init(
                category: "activity", title: "Daily steps fell 12 % to 7,040; you reached your goal on 9 of 21 days.",
                highlights: ["fell 12 %", "9 of 21 days"], stat: .init(value: "7,040", unit: "steps", caption: "before 8,000")),
            .init(
                category: "recovery", title: "Resting heart rate eased to 59 bpm from 61, and HRV held at 44 ms.",
                highlights: ["59 bpm"]),
        ],
        comparisons: [
            .init(metric: "sleep", current: "7 h 12 min", previous: "6 h 47 min", direction: .up),
            .init(metric: "steps", current: "7,040", previous: "8,000", direction: .down),
            .init(metric: "hrv", current: "44 ms", previous: "43 ms", direction: .flat),
            .init(metric: "restingHr", current: "59 bpm", previous: "61 bpm", direction: .down),
        ],
        nudge: "Take a short walk after lunch on workdays.")

    public func report(for request: PeriodReportRequest) async throws -> PeriodReportReply {
        if offline { throw URLError(.cannotConnectToHost) }
        return Self.sample
    }
}

extension PeriodReportStore {
    /// The gallery's kept report for `period`: the sample, written from 21 days with data.
    public func writePreview(period: Period, generatedAt: Date, calendar: Calendar = .current) throws {
        guard let span = PeriodReport.Span(period, calendar: calendar), let id = period.reportID(calendar: calendar)
        else { return }
        func m(_ a: Double, _ lo: Double, _ hi: Double, _ d: Int) -> MetricSummary {
            MetricSummary(average: a, min: lo, max: hi, days: d)
        }
        let none = MetricSummary(average: nil, min: nil, max: nil, days: 0)
        let current = Aggregates(
            elapsedDays: period.days(calendar: calendar).count, daysWithData: 21, sleepMin: m(432, 350, 510, 21),
            steps: m(7040, 2100, 13200, 21), exerciseMin: m(24, 0, 75, 21), hrvMs: m(44, 31, 58, 21),
            restingHr: m(59, 55, 64, 21), waterCups: none, stepGoalRate: 0.43, sleepTargetRate: 0.6)
        let previous = Aggregates(
            elapsedDays: 31, daysWithData: 31, sleepMin: m(407, 330, 480, 31), steps: m(8000, 3100, 15000, 31),
            exerciseMin: m(24, 0, 60, 31), hrvMs: m(43, 30, 55, 31), restingHr: m(61, 57, 66, 31), waterCups: none,
            stepGoalRate: 0.45, sleepTargetRate: 0.42)
        try write(
            PeriodReport(
                PreviewPeriodReportService.sample, period: span, generatedAt: generatedAt, current: current,
                previous: previous),
            id: id)
    }
}
```

- [ ] **Step 2: The gallery states (`Sources/App/HealthGallery.swift`, replaced whole — it has no foreign edits)**

```swift
#if DEBUG
import HealthFeature
import Models
import SwiftUI

/// DEBUG-only visual check of Health: `-HealthGallery <state>` opens the workspace on preview data with the report in
/// `<state>` (`ready` default, `writing`, `offline`, `needsModel`, `failed`, `consent`, `onboarding`), or opens the
/// calendar over it, on last month: `calendar-week`, `calendar-month`, `calendar-quarter`, `calendar-year`, and
/// `day-note` / `day-empty` (the month with the sheet of its 16th up, which has a kept note, or of its 12th, which has
/// none). Period reports: `report-home` (last month's report written just now, so the "report ready" line shows under
/// This week), `report-page` (that report: stories, comparisons, the idea, 21 days with data), `report-card` (the
/// calendar on last month with its report card) and `report-pending` (the calendar on last month with the computer
/// unreachable: "Will be written…"). Add `-HealthGalleryAnchor center|bottom` to open the home scrolled down.
enum HealthGalleryLaunch {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-HealthGallery") }

    static var state: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-HealthGallery"), i + 1 < args.count, !args[i + 1].hasPrefix("-") else {
            return "ready"
        }
        return args[i + 1]
    }

    static var anchor: UnitPoint? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-HealthGalleryAnchor"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "center": return .center
        case "bottom": return .bottom
        default: return nil
        }
    }
}

struct HealthGalleryView: View {
    /// Made once: the model mirrors the preferences when it is created, so they are set first.
    @State private var model = Self.makeModel()
    @State private var path = Self.path()

    var body: some View {
        NavigationStack(path: $path) { HealthRootView.gallery(model: model) }
            .defaultScrollAnchor(HealthGalleryLaunch.anchor)
    }

    /// The calendar opens on last month, which preview data fills with coloured days: its 15th and the days around.
    private static func reference(_ offset: Int = 0) -> Date {
        let cal = Calendar.current
        let thisMonth = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        let mid = cal.date(byAdding: .month, value: -1, to: thisMonth).flatMap { cal.date(byAdding: .day, value: 14, to: $0) } ?? Date()
        return cal.date(byAdding: .day, value: offset, to: mid) ?? mid
    }

    /// Last month: finished, so it has (or waits for) a report.
    private static var lastMonth: Period { Period.containing(reference(), .month, calendar: .current) }

    private static func path() -> NavigationPath {
        let anchor = reference()
        var path = NavigationPath()
        switch HealthGalleryLaunch.state {
        case "calendar-week": path.append(TrendsRoute(scope: .week, anchor: anchor))
        case "calendar-month", "report-card", "report-pending": path.append(TrendsRoute(scope: .month, anchor: anchor))
        case "calendar-quarter": path.append(TrendsRoute(scope: .quarter, anchor: anchor))
        case "calendar-year": path.append(TrendsRoute(scope: .year, anchor: anchor))
        case "day-note": path.append(TrendsRoute(scope: .month, anchor: anchor, presentedDay: reference(1)))
        case "day-empty": path.append(TrendsRoute(scope: .month, anchor: anchor, presentedDay: reference(-3)))
        case "report-page": path.append(PeriodReportRoute(period: lastMonth))
        default: break
        }
        return path
    }

    private static func makeModel() -> HealthHomeModel {
        let suite = "health-gallery"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = HealthPreferences(defaults: defaults)
        prefs.hasOnboarded = HealthGalleryLaunch.state != "onboarding"
        prefs.summaryConsent = HealthGalleryLaunch.state != "consent"
        let report: HealthHomeModel.Report =
            switch HealthGalleryLaunch.state {
            case "writing": .writing
            case "offline": .offline
            case "needsModel": .needsModel
            case "failed": .failed
            default: .ready(PreviewSummaryService.sample)
            }
        let cache = ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        // Yesterday and the day-note state's day have a kept note; the other days have none.
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            try? cache.archive.writePreview(day: yesterday)
        }
        try? cache.archive.writePreview(day: reference(1))
        switch HealthGalleryLaunch.state {
        case "report-home", "report-page", "report-card":
            try? cache.archive.reports.writePreview(period: lastMonth, generatedAt: Date())
        default: break
        }
        // Only the pending state asks for reports (and finds the computer unreachable); the others show what is kept.
        let periodReports: (any PeriodReportService)? =
            HealthGalleryLaunch.state == "report-pending" ? PreviewPeriodReportService(offline: true) : nil
        return HealthHomeModel(
            source: HealthPreviewSource(), summaries: PreviewSummaryService(report: report),
            memory: PreviewMemoryWriter(), cache: cache, preferences: prefs, periodReports: periodReports,
            locale: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
#endif
```

- [ ] **Step 3: Build, install, and take the screenshots**

Write `/tmp/health2/shots.sh`:

```bash
#!/bin/bash
# Light, dark and AX screenshots of the period-report gallery states. Run from the repo root.
set -euo pipefail
SIM=992425B7-F06B-4CE5-9288-95C71C2F1D44
APP=app.yancey.exodus.exodus-ios
OUT=.superpowers/health2
mkdir -p "$OUT"
shoot() {
  local name=$1; shift
  xcrun simctl terminate "$SIM" "$APP" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$APP" "$@" >/dev/null
  sleep 5
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null
}
STATES="report-page report-card report-pending"
for mode in light dark; do
  xcrun simctl ui "$SIM" appearance "$mode"
  for s in $STATES; do shoot "$mode-$s" -HealthGallery "$s"; done
  shoot "$mode-report-home" -HealthGallery report-home -HealthGalleryAnchor center
  shoot "$mode-calendar-month" -HealthGallery calendar-month
done
xcrun simctl ui "$SIM" appearance light
xcrun simctl ui "$SIM" content_size accessibility-extra-extra-extra-large
for s in $STATES; do shoot "ax-$s" -HealthGallery "$s"; done
shoot ax-report-home -HealthGallery report-home -HealthGalleryAnchor center
xcrun simctl ui "$SIM" content_size large
echo done
```

```bash
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcrun simctl boot 992425B7-F06B-4CE5-9288-95C71C2F1D44 2>/dev/null || true
xcrun simctl install 992425B7-F06B-4CE5-9288-95C71C2F1D44 /tmp/health2-dd/Build/Products/Debug-iphonesimulator/Exodus.app
bash /tmp/health2/shots.sh
```

Expected: `** BUILD SUCCEEDED **`, `done`. Read every PNG in `.superpowers/health2/` and check against spec §3:
- `report-page`: title "<last month> <year>" inline; green eyebrow "Monthly report"; the headline with "More sleep" in the sleep gradient; three insight cards with their numbers; a "vs last month" card — Sleep ↑ green "7 h 12 min / was 6 h 47 min", Steps ↓ orange, Heart rate variability → grey, Resting heart rate ↓ **green**; the mint idea card after it; "21 of N days had data" and "Written <today>"; the ask box with the two suggestions; Write again (↻) in the toolbar.
- `report-card`: the calendar's header, then a card "Monthly report" + the headline + chevron, then the month grid.
- `report-pending`: the header, then Ody (offline) with "Will be written when your computer is reachable." and Write now.
- `report-home`: under the hero and note, the This week card with a divider and "<last month> <year> report ready" with the green page glyph and chevron, all one card.
- `calendar-month` unchanged from phase 1 apart from nothing new (no report kept, no service → no card).
- Dark: green and orange arrows readable on the card; AX: comparison rows stack (name over value), the report card's headline wraps, the home line wraps.
Fix mismatches before committing (re-run the script after a fix).

- [ ] **Step 4: Extend the device checklist**

Append to `docs/health-device-checklist.md`:

```markdown

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
```

- [ ] **Step 5: Update the README's HealthFeature bullet**

In `README.md`, replace

```markdown
  `day-note`, `day-empty`) opens it on preview data. Design: [spec](docs/superpowers/specs/2026-10-01-health-workspace-design.md),
```

with

```markdown
  `day-note`, `day-empty`) opens it on preview data. Each finished week, month, quarter and year gets a report on the
  next Health open (`PeriodReports`; `POST /api/v1/health/period-report`, kept in `archive/reports`), shown on the
  calendar, on the home and on its own page (`-HealthGallery report-page`, `report-card`, `report-pending`,
  `report-home`). Design: [spec](docs/superpowers/specs/2026-10-01-health-workspace-design.md),
```

- [ ] **Step 6: Final checks and commit**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/health2-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): period-report gallery states — the page, the calendar card, waiting for the computer, the home's line — device checklist and README" \
  Sources/HealthFeature/Debug/HealthPreviewSource.swift Sources/App/HealthGallery.swift \
  docs/health-device-checklist.md README.md
git show --stat HEAD
```
Expected: every HealthFeature test passes; `0 error(s)`; the commit lists exactly the four files. In the desktop repo, run once more: `bunx vitest run tests/unit/shared/types/health-period.test.ts tests/unit/main/lib/server/routes/health-period-report.test.ts tests/unit/main/lib/server/routes/health.test.ts tests/unit/shared/types/health.test.ts` — all pass.

---

## Self-Review

**Spec coverage (phase 2):**
- §2.4 `PeriodReport` stored at `archive/reports/2026-W40.json` / `2026-09.json` / `2026-Q3.json` / `2026.json` (ISO weeks via `Period.reportID`), content headline, highlight, insights (category, title, verbatim highlights, stat), comparisons (metric, current, previous, direction), nudge, generatedAt, period → Task 3 (+ Decisions 1–3).
- §3.1 "report ready" line on This week, for reports written in the last 2 days → Task 4 (`fresh()`), Task 7.
- §3.2 report card under the header; "Will be written when your computer is reachable" when pending → Task 7 (+ Write now, Decision 9).
- §3.4 report page: insight-story layout, coloured headline, insight cards, comparisons, nudge, "Ask about this report" → Task 6; manual refresh (§5) → Task 6 toolbar.
- §3.6 light/dark, Dynamic Type, VoiceOver, ten languages, Reduce Motion → Tasks 5–8.
- §4 route: LAN auth/lock/origin gates (app-wide on `/api/*`, the router is already mounted), stores nothing, logs no bodies, strict zod request with exactly `{period, current, previous, notes, habits, locale}`, memories only with memory on for chats, `PeriodReport` response, lenient parse (strip invalid insights, degrade to headline-only), retry once → Tasks 1–2.
- §5 schedule: on each Health appear, due periods newest first, at most 2 per open, only with consent and a reachable computer with a model; failure → pending in memory, retry next open; never auto-regenerate; manual refresh → Task 4 (+ Decisions 7–10).
- §6 offline/no model → pending, local features unaffected; no consent → no reports; sparse data → the prompt says how many days had data and the page shows "N of M days had data"; corrupt file → no report → Tasks 2, 3, 4, 6.
- §7 desktop vitest (schemas, lenient parsing, no persistence) → Tasks 1–2; iOS due-period scheduling and the 2-per-open cap → Task 4; gallery states for the report page and card, screenshots light/dark/AX, checklist → Task 8.

**Placeholder scan:** every code step has complete code; every command has its expected output.

**Type consistency:** `PeriodReport(_:period:generatedAt:current:previous:)`, `PeriodReport.Span(_:calendar:)` / `init(kind:start:end:)`, `PeriodReport.Kind(_: Period.Kind)`, `PeriodReport.Comparison.Direction` `.up/.down/.flat`, `PeriodReportReply(headline:headlineHighlight:headlineCategory:insights:comparisons:nudge:)`, `PeriodReportRequest(period:current:previous:notes:habits:locale:)`, `PeriodReportInput.request(period:records:archive:calendar:locale:today:)`, `PeriodReportInput.clip(_:_:)`, `PeriodReportStore.write(_:id:)` / `read(id:)` / `fileURL(id:)`, `HealthArchive.reports`, `PeriodReportService.report(for:)`, `PeriodReportSchedule.lastFinished(today:calendar:)` / `due(today:calendar:isKept:)` / `perOpen`, `PeriodReports(store:service:records:archive:calendar:locale:now:hasConsent:)` with `State.missing/.pending/.writing/.ready`, `Failure.offline/.needsModel/.failed`, `Outcome.written/.empty/.failed`, `report(id:)`, `state(for:)`, `failure(for:)`, `isWriting(_:)`, `fresh()`, `writeDue()`, `write(_:)`, `stop()`, `forget()`; `HealthHomeModel(… preferences:periodReports:calendar:now:locale:)`, `.reports`, `writeDueReports()`; `PeriodReportText.kind/scope/ready/written/daysWithData/was/metric/isBetter/arrow/color/spoken/failure`; `PeriodReportRoute(period:)`, `PeriodReportView(period:home:onAsk:)`, `.story(_:)`, `.attachment(_:)`, `PeriodReportRow(scene:text:)`, `ComparisonsCard(comparisons:scope:)`, `.rows(_:)`, `PeriodReportCard(state:period:hasData:canWrite:onWrite:)`, `.shows(_:hasData:)`, `ReportReadyLine(period:calendar:)`; desktop `parsePeriodReport(value, request)`, `periodDirection`, `periodAverage`, `periodReportRequestSchema`, `periodReportSchema`, `HEALTH_PERIOD_REPORT_SYSTEM`, `periodMemoryQuestion` — used with these names in every task.

**Review Focus:** each of the five lines has its test in the owning task (Tasks 1, 3, 4).
