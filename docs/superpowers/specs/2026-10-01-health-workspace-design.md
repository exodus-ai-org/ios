# Health workspace — design

Date: 2026-10-01 · Status: approved in brainstorming, awaiting spec review
Repos: `exodus-ios` (most of the work) and `exodus` (one desktop route)
Prototypes: `.superpowers/brainstorm/83696-1790821334/content/` (`home-layout.html`, `ody-states-v2.html`, `interactions-v2.html`)

## 1. Goal

A third workspace, **Health**, next to Chat and Philharmonic in the drawer. It reads Apple Health on the phone and greets the user with a warm daily report: a living Ody scene, a short model-written summary, and four category cards. It is a product of its own, not a Chat feature and not a desktop agent tool. Questions typed into it hand off to the existing Chat with the health data attached.

It is also the first place the app gets **livelier**: Ody becomes a code-driven character (breathes, blinks, follows your finger, squashes when poked) and every state has an illustration.

### What the user said vs. what we assumed

| Decided by the user | Assumed / recommended and accepted |
|---|---|
| Health is an independent sub-app beside Chat / Philharmonic | Drawer row placed between Chat and Philharmonic |
| Uses "our AI provider", via a desktop **stateless** endpoint (no key on the phone) | Single endpoint `POST /api/v1/health/summary`, structured JSON, no streaming |
| Home = daily report: beautiful visualization + warm summary (layout A) | Category cards use layout C's coloured scene style; C's big scenes become detail headers |
| Asking a question (bottom composer) goes to Chat with prompt + health data | Plain-text health block, like `QuotedText` |
| Memory: read automatically, write only on confirmation | Suggestion card; "Remember" posts to existing `/api/v1/memory` |
| All four categories in v1: sleep, activity, heart & recovery, body & mood | — |
| Cool interactions; no Rive (nobody can author it) | Native SwiftUI + Metal; no Lottie in v1 |

### Non-goals (v1)

- Background delivery / notifications, widgets, Apple Watch app.
- Clinical records, medications, cycle tracking.
- Desktop rendering of the health block as a card (it shows as a plain quote-like block for now).
- Any medical judgement.

## 2. Architecture

```
iPhone                                                    Desktop (exodus)
┌──────────────────────── HealthFeature ───────────────┐  ┌──────────────────────────┐
│ HealthDataSource (protocol) ── HealthKitSource        │  │ routes/health.ts         │
│        │ fake in tests                                │  │  POST /summary           │
│ SnapshotBuilder → HealthSnapshot + OdyState (rules)   │──┼─▶ memory read-filter      │
│        │                                              │  │  callLlm (active model)  │
│ SummaryClient ─ cache (Application Support, no backup)│◀─┼─ JSON report, no DB write│
│ HomeView / Detail views / MemorySuggestionCard        │  └──────────────────────────┘
│ Composer ─▶ AppShell: switch to .chat, new chat,      │        POST /api/v1/memory (existing)
│             send HealthContext.compose(snapshot, q)   │        POST /api/v1/chat   (existing)
└──────────────────────────┬────────────────────────────┘
                           │ uses
                     OdyKit (OdyShape, OdyView, OdyScene, DaySky, Confetti, HeartbeatWave.metal)
```

New iOS targets (Tuist `moduleTarget`): `HealthFeature` (depends on Models, NetworkingKit, MarkdownKit, OdyKit) and `OdyKit` (no dependencies), each with a test target. `AppWorkspace` gains `.health` (`heart.text.square`), available.

Project changes: HealthKit entitlement (`com.apple.developer.healthkit`), `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` (water only), `NSMotionUsageDescription` is **not** needed (device-motion attitude does not prompt).

## 3. Data and rules (phone)

Windows: *today* = local midnight → now; *last night* = 18:00 yesterday → 12:00 today. Baseline = trailing 30 days excluding today; a baseline needs ≥ 7 days of data, otherwise it is `nil`.

| Category | HealthKit types | Snapshot fields |
|---|---|---|
| Sleep | `sleepAnalysis` | `asleepMin`, `baselineMin`, `deepMin`, `coreMin`, `remMin`, `awakeMin`, `bedtime`, `wake`, `stages[]` (for the hero track and detail) |
| Activity | `stepCount`, `activeEnergyBurned`, `appleExerciseTime`, `appleStandHour`, `HKWorkout`, `HKActivitySummary` (goals) | `steps`, `stepGoal`, `activeKcal`, `kcalGoal`, `exerciseMin`, `standHours`, `workouts[]` (type, minutes, kcal) |
| Heart & recovery | `restingHeartRate`, `heartRateVariabilitySDNN`, `respiratoryRate` | `restingHr`, `restingHrBaseline`, `hrvMs`, `hrvBaselineMs`, `respRate`, `level` |
| Body & mood | `bodyMass`, `dietaryWater`, `HKStateOfMind` | `waterCups` (250 ml each), `weightKg`, `weightTrend30d`, `mood` (latest valence label) |

- **Sleep source dedupe:** when several sources overlap, keep the source with the most staged (core/deep/REM) minutes for the night.
- **Step goal:** activity-summary goal when present, else 8,000.
- **Recovery level** (relative to own baseline, never medical): `low` if HRV ≤ −12 % or resting HR ≥ +7 %; `good` if HRV ≥ −5 % and resting HR ≤ +3 %; else `fair`; `nil` without baselines.
- **Empty category** → the whole category is `nil` in the snapshot.

**Hero Ody state** — first match wins:

1. not authorised → `permission`
2. all four categories `nil` → `noData`
3. sleep < 6.5 h or < 85 % of baseline → `tired`
4. recovery `low` → `recovering`
5. step goal reached → `active`
6. sleep ≥ baseline and recovery `good` → `rested`
7. pleasant mood logged today → `calm`
8. otherwise → `happy`

Each category card picks its own small Ody from its own data (`noData` when `nil`). System states: `writing` (report loading), `offline` (desktop unreachable).

**Authorisation and consent.** First entry shows an onboarding page (Ody holding the heart): step 1 the HealthKit request (read types above + write `dietaryWater`); step 2 an explicit toggle "Send today's summary to the AI provider configured on your computer to write the report" (App Review 5.1.2 / 5.1.3). Without consent Health still shows data and illustrations, just no report text. Because read denial is invisible, every "no data" explanation also says it may be a permission and links to Settings. Reads happen in the foreground only.

## 4. Desktop endpoint

`src/main/lib/server/routes/health.ts`, mounted `v1.route('/health', healthRouter)`, behind the existing pairing auth. Schemas in `packages/shared` (zod); iOS mirrors them as Codable.

**Request** — aggregates only, never raw samples:

```jsonc
{
  "date": "2026-10-01", "localTime": "15:00", "locale": "zh-Hans",
  "sleep":    { "asleepMin": 372, "baselineMin": 425, "deepMin": 52, "remMin": 81, "bedtime": "23:48", "wake": "06:00" },
  "activity": { "steps": 5840, "stepGoal": 8000, "activeKcal": 310, "exerciseMin": 12, "standHours": 6, "workouts": [] },
  "recovery": { "level": "low", "hrvMs": 38, "hrvBaselineMs": 44, "restingHr": 61, "restingHrBaseline": 58 },
  "body":     { "waterCups": 3, "weightKg": null, "weightTrend30d": null, "mood": null },
  "odyState": "tired"
}
```

**Flow**

1. If memory is enabled for chat, `loadRelevantMemories(question, …)` with a question built from "daily health report" + a one-line snapshot digest; session id `health:<date>`.
2. One `callLlm` with the active provider/model/key. System prompt: warm, brief, in `locale` (one of the app's ten languages); only the given numbers, quoted exactly; no diagnosis; a memory suggestion only for a **lasting pattern**, never a one-day event, never a duplicate of an existing memory.
3. Validate with the schema; on failure retry once; then `AIError(AI_GENERATION_FAILED)` (HTTP 500).
4. No database writes (token usage is not recorded: the desktop derives usage from assistant messages and Health writes none); logs carry duration and outcome only, never health values.

**Response**

```jsonc
{
  "headline": "有点没睡饱",
  "summary": "昨晚只睡了 **6 小时 12 分**……",          // markdown, rendered by MarkdownKit
  "categories": { "sleep": "…", "activity": "…", "recovery": "…", "body": null },
  "memorySuggestion": { "section": "profile", "key": "weekday-sleep", "summary": "工作日平均只睡 6 小时左右" } // or null
}
```

| Failure | UI |
|---|---|
| No provider / key configured (`CONFIG_*` / `SETTING_NOT_FOUND`) | `noData` Ody, "Set up a model on your computer" |
| Desktop unreachable | `offline` Ody; cards still show |
| `AI_GENERATION_FAILED` (500) | "The report couldn't be written" — pull to retry |

**Cache.** Today's report + the snapshot it was written from are cached in Application Support with `isExcludedFromBackup`. Regenerated on the first open of a day, on pull-to-refresh, and when the hero Ody state differs from the cached one.

## 5. Interface and interaction

**Home** (prototype `interactions-v2.html`)

- Hero scene: `DaySky` + Ody. Horizontal drag scrubs from 22:00 yesterday to now (one screen width ≈ 10 h; drag right = back in time); 1:1 tracking, momentum projection on release, rubber-band past both ends; "Back to now" chip springs home (damping 1.0, response 0.3). While scrubbing the title shows time + sleep stage, Ody lies on the pillow and sinks deeper in deep sleep; a stage track with a playhead runs along the hero's bottom.
- Poke Ody: squash and spring back (0.45 / 0.4); a tired Ody yawns. Eyes follow the finger.
- Report: while loading, the `writing` Ody; on arrival sentences fade in and numbers count up.
- Four coloured category cards with their own small Ody.
- Memory suggestion card: "Remember" folds the card and flies it along an arc into Ody's bindle (bindle bounces); "No thanks" slides it away. Dismissed keys are remembered locally and not suggested again.
- Pull to refresh: Ody stretches with progressive resistance; past the threshold, release re-reads data and rewrites the report.
- Activity goal reached: confetti of little bindles and stars, **once per day**.

**Detail pages** — opened with `.navigationTransition(.zoom)` from the card; the card's scene becomes the header. Charts with Swift Charts.

| Page | Content |
|---|---|
| Sleep | Night-sky header; star-band hypnogram, finger scrub highlights a stage and its time (`.selection` at stage edges); 7/30-day duration bars with baseline; bedtime consistency |
| Activity | Walking Ody header; today's steps by hour; 7-day completion vs goal; workouts |
| Recovery | Metal heartbeat wave pulsing at the real resting HR; HRV and resting HR 30-day lines with baseline band; respiratory rate |
| Body & mood | Interactive glass: tap logs a cup (writes `dietaryWater`), surface sloshes with device attitude (Core Motion); weight 30-day line; mood timeline |

**Ask → Chat.** Composer on home and every detail page, with three suggested questions. A chip "Include today's health data ✕" sits above the field (removable). Sending switches to the Chat workspace, opens a new chat and sends `HealthContext.compose(snapshot, question)`: home attaches today's snapshot; a detail page attaches that category's last 7 days. The iOS transcript draws the block as a collapsible health card above the user bubble (`HealthContext.split`, mirroring `QuotedText`).

**Haptics** (`.sensoryFeedback`, no sounds)

| Moment | Feedback |
|---|---|
| Poke Ody | `.impact(flexibility: .soft)` |
| Pull crosses threshold | `.impact(weight: .light)` |
| Refresh done, Remember, goal reached, 8th cup | `.success` |
| Scrub crosses a sleep-stage edge, Back to now | `.selection` |
| Log a cup | `.impact(weight: .light)` |

**Accessibility & polish.** Reduce Motion: no breathing/blinking, confetti/flight/slosh become cross-fades, scrubbing keeps working without momentum. Dynamic Type, dark mode (night palette hero, desaturated cards). VoiceOver treats Ody as decorative and reads the state ("Status: under-slept"); the hero is an adjustable element stepping by hour. New strings live under `ios:health.*` in `Localizable.xcstrings` for all ten locales.

## 6. Illustration system — OdyKit

Everything is drawn in SwiftUI code (one source, animatable, dark-mode aware); `ImageRenderer` produces stills when needed.

- `OdyShape` — body curve and palette ported from desktop `brand/art.mjs` (header comment: keep in sync).
- `OdyView` — parameters: expression (`happy`, `grin`, `sleepy`, `content`, `curious`, `down`, `away`, `yawn`), eye openness, look direction, squash, tilt. Idle breathing + random blink via `TimelineView` (off under Reduce Motion); poke spring built in.
- `OdyScene` — the ten states (`rested`, `tired`, `active`, `recovering`, `hydrating`, `calm`, `noData`, `writing`, `permission`, `offline`) = `OdyView` + prop shapes (pillow, bindle, blanket, mug, glass, pencil, keyhole heart, sprout). Reference art: `ody-states-v2.html`.
- `DaySky` — hourly gradient keyframes, stars, sun/moon arcs.
- `Confetti` — Canvas + TimelineView particles (bindles, stars).
- `HeartbeatWave.metal` — the recovery wave.
- No Lottie in v1.

Only Health uses OdyKit in v1; its public API lets pairing, empty states and Chat adopt Ody later.

## 7. Testing

**iOS (Swift Testing), HealthKit behind a fake `HealthDataSource`:** snapshot windows, sleep source dedupe, baselines (< 7 days → `nil`), recovery thresholds at their edges, hero/card Ody-state priority, `HealthContext` compose/split vectors, summary decoding (incl. `null` categories and suggestion), dismissed-suggestion store, cache expiry and `isExcludedFromBackup`.

**Desktop (vitest):** request validation, `null` categories, memory disabled → no memory read, invalid model output → one retry → `AI_GENERATION_FAILED`, no DB writes, logs free of health values.

**Shared vectors:** like `QuotedText`, the same example snapshot and summary JSON appear verbatim in both repos' tests (iOS `HealthWireTests`, desktop `health-schema.test.ts`).

**Visual:** `HealthGallery` (like `SettingsGallery` / `MarkdownGallery`) lays out every scene and state with fake data, reachable by launch argument for simulator screenshots. DEBUG builds get a "Write sample health data" action to seed the simulator's Health app.

**On device (handed to the user as a checklist):** haptics, glass tilt, scrub feel, zoom transitions, Reduce Motion.
