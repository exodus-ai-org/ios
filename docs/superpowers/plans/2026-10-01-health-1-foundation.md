# Health 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything under the Health UI: the desktop's `POST /api/v1/health/summary`, the shared wire types, the iOS modules, the HealthKit data layer, the snapshot/rules engine, the health block that travels into Chat, and the observable model the home screen will bind to.

**Architecture:** The phone reads HealthKit through a `HealthDataSource` protocol (a fake in tests), turns samples into a `HealthSnapshot` with pure, tested rules, and asks the desktop — a stateless route that reads relevant memories and calls the active model once — for a structured report. `HealthHomeModel` orchestrates cache, consent, errors and memory suggestions. No UI beyond a placeholder in this plan.

**Tech Stack:** Swift 6 / SwiftUI / HealthKit / Swift Testing / Tuist 4.208 (iOS 27); TypeScript / Hono / zod / vitest (desktop).

**Spec:** `docs/superpowers/specs/2026-10-01-health-workspace-design.md` (sections 2, 3, 4, 7)

**Series:** this is plan 1 of 3. Plan 2 `2026-10-01-health-2-odykit.md` (Ody character + scenes), plan 3 `2026-10-01-health-3-ui.md` (screens, interactions, Chat handoff, gallery, strings).

## Global Constraints

- Every iOS target deploys to iOS 27.0; Swift 6 language mode; native frameworks only (no new packages).
- Two repos: `exodus-ios` (this one) and `../exodus` (desktop). Both are on branch `maintenance` with unrelated uncommitted work — **stage only the files a task names** (`git add <paths>`; never `git add -A`/`.`), and commit with the paths after `--`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- Health data never leaves the phone except as the aggregated snapshot in §4 of the spec; the desktop writes nothing to its database for it and logs no health values.
- Wire JSON keys are exactly those in the spec §4 (camelCase); nullable fields may be omitted or `null`.
- Memory sections are `profile | topic | person`; Health suggestions use `profile`.
- The default step goal is 8,000 (HealthKit has no step goal; activity-summary only gives move/exercise/stand goals — this corrects spec §3's "activity-summary goal" for steps).
- New user-facing iOS strings use keys `ios:health.<screen>.<element>` and are added with `scripts/l10n.py add`.
- iOS tests: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme <Scheme> -destination "platform=iOS Simulator,name=iPhone 17"`; check for a `Test run with N tests` line (a wrong `-only-testing:` name still prints SUCCEEDED). Run `tuist generate --no-open` after adding files or targets.
- Desktop tests: from `../exodus`, `bunx vitest run <path>`.

## Review Focus

- A night with Apple Watch **and** iPhone sleep samples overlapping → minutes counted once (from the staged source), not doubled.
- A user with fewer than 7 days of history → baselines `nil`, recovery `nil`, `tired` decided by the 6.5 h floor alone, no crash on empty arrays.
- Desktop unreachable / no model configured / model returns prose instead of JSON → home shows offline / needs-model / failed, never a spinner forever.
- A message typed in Chat that merely *contains* "```exodus-health" later in the text → not mistaken for a health block (only a leading block counts).
- Sleep that crosses midnight and a phone in a different time zone than the samples → bedtime/wake rendered in the phone's current calendar time zone, window 18:00→12:00 local.

---

## File Structure

**Desktop (`../exodus`)**
- Create `packages/shared/src/types/health.ts` — zod schemas + types for snapshot and summary.
- Modify `packages/shared/package.json` — export `./types/health`.
- Modify `src/main/lib/ai/memory/manager.ts` — export `callLlm`, `parseJsonFromResponse`.
- Create `src/main/lib/server/routes/health.ts` — the route.
- Modify `src/main/lib/server/app.ts` — mount it.
- Create `tests/unit/shared/types/health-fixtures.ts`, `tests/unit/shared/types/health.test.ts`, `tests/unit/main/lib/server/routes/health.test.ts`.

**iOS**
- Modify `Project.swift` — `OdyKit`, `HealthFeature` (+ test targets), App deps, HealthKit entitlement, usage strings.
- Modify `Resources/App/InfoPlist.xcstrings` — two usage descriptions.
- Create `Sources/OdyKit/OdyKit.swift` — module placeholder (filled by plan 2).
- Create `Sources/Models/HealthWire.swift` — `HealthSnapshot`, `HealthSummary`, enums.
- Create `Sources/Models/HealthContext.swift` — compose/split of the block sent to Chat.
- Create `Sources/HealthFeature/Data/HealthSamples.swift` — raw sample value types + `HealthDataSource`.
- Create `Sources/HealthFeature/Data/SleepAnalyzer.swift` — night window, source dedupe, stages.
- Create `Sources/HealthFeature/Data/HealthRules.swift` — baselines, recovery level, Ody moods.
- Create `Sources/HealthFeature/Data/SnapshotBuilder.swift` — assembles a `HealthDay`.
- Create `Sources/HealthFeature/Data/HealthKitSource.swift` — the real HealthKit implementation.
- Create `Sources/HealthFeature/Report/HealthServices.swift` — summary + memory services (live = `APIClient`).
- Create `Sources/HealthFeature/Report/ReportStore.swift` — cache, regeneration policy, dismissed suggestions, consent.
- Create `Sources/HealthFeature/Report/HealthHomeModel.swift` — the observable orchestrator.
- Create `Sources/HealthFeature/HealthRootView.swift` — placeholder root (replaced in plan 3).
- Modify `Sources/App/AppWorkspace.swift`, `Sources/App/AppShell.swift` — `.health` workspace.
- Tests: `Tests/ModelsTests/HealthWireTests.swift`, `Tests/ModelsTests/HealthContextTests.swift`, `Tests/HealthFeatureTests/{FakeHealthSource,SleepAnalyzerTests,HealthRulesTests,SnapshotBuilderTests,ReportStoreTests,HealthHomeModelTests}.swift`, `Tests/OdyKitTests/OdyKitSmokeTests.swift`.

---

### Task 1: Desktop — shared health schemas

**Files:**
- Create: `../exodus/packages/shared/src/types/health.ts`
- Modify: `../exodus/packages/shared/package.json` (exports map)
- Test: `../exodus/tests/unit/shared/types/health.test.ts`, fixtures `../exodus/tests/unit/shared/types/health-fixtures.ts`

**Interfaces:**
- Produces: `healthSnapshotSchema`, `healthSummarySchema`, `odyStateSchema`, types `HealthSnapshot`, `HealthSummary` from `@exodus/shared/types/health`.

- [ ] **Step 1: Write the failing test**

```ts
// tests/unit/shared/types/health-fixtures.ts
// The spec's §4 examples; exodus-ios's HealthWireTests holds the same JSON,
// so the two sides agree on the wire.
export const SNAPSHOT = {
  date: '2026-10-01',
  localTime: '15:00',
  locale: 'zh-Hant',
  sleep: { asleepMin: 372, baselineMin: 425, deepMin: 52, coreMin: 209, remMin: 81, awakeMin: 30, bedtime: '23:48', wake: '06:00' },
  activity: { steps: 5840, stepGoal: 8000, activeKcal: 310, kcalGoal: 500, exerciseMin: 12, standHours: 6, workouts: [] },
  recovery: { level: 'low', hrvMs: 38, hrvBaselineMs: 44, restingHr: 61, restingHrBaseline: 58, respRate: 14.2 },
  body: { waterCups: 3, weightKg: null, weightTrend30d: null, mood: null },
  odyState: 'tired'
}

export const SUMMARY = {
  headline: '有點沒睡飽',
  summary: '昨晚只睡了 **6 小時 12 分**。',
  categories: { sleep: '深睡偏少。', activity: '還差 2,160 步。', recovery: 'HRV 偏低。', body: null },
  memorySuggestion: { section: 'profile', key: 'weekday-sleep', summary: '工作日平均只睡 6 小時左右' }
}
```

```ts
// tests/unit/shared/types/health.test.ts
import {
  healthSnapshotSchema,
  healthSummarySchema
} from '@exodus/shared/types/health'
import { describe, expect, it } from 'vitest'

import { SNAPSHOT, SUMMARY } from './health-fixtures'

describe('healthSnapshotSchema', () => {
  it('accepts the spec example', () => {
    expect(healthSnapshotSchema.parse(SNAPSHOT)).toEqual(SNAPSHOT)
  })

  it('accepts a category that is null or absent', () => {
    const { body: _b, ...withoutBody } = SNAPSHOT
    expect(healthSnapshotSchema.safeParse({ ...SNAPSHOT, sleep: null }).success).toBe(true)
    expect(healthSnapshotSchema.safeParse(withoutBody).success).toBe(true)
  })

  it('rejects fields it does not know (no raw samples sneak in)', () => {
    const r = healthSnapshotSchema.safeParse({ ...SNAPSHOT, samples: [{ v: 1 }] })
    expect(r.success).toBe(false)
  })

  it('rejects a bad date and an unknown Ody state', () => {
    expect(healthSnapshotSchema.safeParse({ ...SNAPSHOT, date: '1/10/2026' }).success).toBe(false)
    expect(healthSnapshotSchema.safeParse({ ...SNAPSHOT, odyState: 'sad' }).success).toBe(false)
  })
})

describe('healthSummarySchema', () => {
  it('accepts the spec example and a null suggestion', () => {
    expect(healthSummarySchema.parse(SUMMARY)).toEqual(SUMMARY)
    expect(healthSummarySchema.safeParse({ ...SUMMARY, memorySuggestion: null }).success).toBe(true)
  })

  it('only suggests profile memories with a kebab-case key', () => {
    const bad = { ...SUMMARY, memorySuggestion: { section: 'topic', key: 'x', summary: 'y' } }
    expect(healthSummarySchema.safeParse(bad).success).toBe(false)
    const badKey = { ...SUMMARY, memorySuggestion: { ...SUMMARY.memorySuggestion, key: 'Weekday Sleep' } }
    expect(healthSummarySchema.safeParse(badKey).success).toBe(false)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run (in `../exodus`): `bunx vitest run tests/unit/shared/types/health.test.ts`
Expected: FAIL — cannot resolve `@exodus/shared/types/health`.

- [ ] **Step 3: Write the schemas**

```ts
// packages/shared/src/types/health.ts
// The phone's daily health snapshot (aggregates only — never raw samples) and
// the report the desktop writes from it. exodus-ios mirrors both in
// Sources/Models/HealthWire.swift.
import { z } from 'zod'

const hhmm = z.string().regex(/^\d{2}:\d{2}$/)
const count = z.number().int().nonnegative()

export const odyStateSchema = z.enum([
  'permission',
  'noData',
  'tired',
  'recovering',
  'active',
  'rested',
  'calm',
  'happy'
])

export const moodLabelSchema = z.enum([
  'veryUnpleasant',
  'unpleasant',
  'slightlyUnpleasant',
  'neutral',
  'slightlyPleasant',
  'pleasant',
  'veryPleasant'
])

export const healthSnapshotSchema = z
  .object({
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    localTime: hhmm,
    locale: z.string().min(2).max(16),
    sleep: z
      .object({
        asleepMin: count,
        baselineMin: count.nullish(),
        deepMin: count,
        coreMin: count,
        remMin: count,
        awakeMin: count,
        bedtime: hhmm,
        wake: hhmm
      })
      .strict()
      .nullish(),
    activity: z
      .object({
        steps: count,
        stepGoal: count,
        activeKcal: count,
        kcalGoal: count.nullish(),
        exerciseMin: count,
        standHours: count,
        workouts: z
          .array(
            z
              .object({ type: z.string().max(40), minutes: count, kcal: count.nullish() })
              .strict()
          )
          .max(20)
      })
      .strict()
      .nullish(),
    recovery: z
      .object({
        level: z.enum(['good', 'fair', 'low']).nullish(),
        hrvMs: z.number().nonnegative().nullish(),
        hrvBaselineMs: z.number().nonnegative().nullish(),
        restingHr: z.number().nonnegative().nullish(),
        restingHrBaseline: z.number().nonnegative().nullish(),
        respRate: z.number().nonnegative().nullish()
      })
      .strict()
      .nullish(),
    body: z
      .object({
        waterCups: count,
        weightKg: z.number().nonnegative().nullish(),
        weightTrend30d: z.number().nullish(),
        mood: moodLabelSchema.nullish()
      })
      .strict()
      .nullish(),
    odyState: odyStateSchema
  })
  .strict()

const line = z.string().min(1).max(200).nullable()

export const healthSummarySchema = z.object({
  headline: z.string().min(1).max(40),
  summary: z.string().min(1).max(1200),
  categories: z.object({ sleep: line, activity: line, recovery: line, body: line }),
  memorySuggestion: z
    .object({
      section: z.literal('profile'),
      key: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/).max(48),
      summary: z.string().min(1).max(120)
    })
    .nullable()
})

export type HealthSnapshot = z.infer<typeof healthSnapshotSchema>
export type HealthSummary = z.infer<typeof healthSummarySchema>
```

Add to the `exports` map in `packages/shared/package.json`, next to `"./types/chat"`:

```json
    "./types/health": "./src/types/health.ts",
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bunx vitest run tests/unit/shared/types/health.test.ts`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
cd ../exodus
git add packages/shared/src/types/health.ts packages/shared/package.json tests/unit/shared/types/health.test.ts tests/unit/shared/types/health-fixtures.ts
git commit -m "feat(health): shared schemas for the phone's daily snapshot and report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- packages/shared/src/types/health.ts packages/shared/package.json tests/unit/shared/types/health.test.ts tests/unit/shared/types/health-fixtures.ts
```

Note: `packages/shared/package.json` already has unrelated uncommitted edits. Before committing, run `git diff packages/shared/package.json`; if it shows more than the one added line, commit with `git add -p packages/shared/package.json` (stage only the `./types/health` hunk) and drop the path from the `--` list.

---

### Task 2: Desktop — `POST /api/v1/health/summary`

**Files:**
- Modify: `../exodus/src/main/lib/ai/memory/manager.ts:92` and `:109` (add `export`)
- Create: `../exodus/src/main/lib/server/routes/health.ts`
- Modify: `../exodus/src/main/lib/server/app.ts` (import + `v1.route('/health', healthRouter)` after `/memory`)
- Test: `../exodus/tests/unit/main/lib/server/routes/health.test.ts`

**Interfaces:**
- Consumes: `healthSnapshotSchema`, `healthSummarySchema` (Task 1); `getModelFromProvider(setting)`; `loadRelevantMemories(question, model, apiKey, sessionId, runId)`.
- Produces: HTTP `POST /api/v1/health/summary` → 200 `HealthSummary` JSON; 400 `VALIDATION_FAILED`; config errors from `getModelFromProvider`; 500 `AI_GENERATION_FAILED`.

- [ ] **Step 1: Write the failing test**

```ts
// tests/unit/main/lib/server/routes/health.test.ts
import { isAppError } from '@exodus/shared/errors/app-error'
import { Hono } from 'hono'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { SNAPSHOT, SUMMARY } from '../../../../shared/types/health-fixtures'

vi.mock('electron', () => ({ app: { getPath: () => '/tmp' } }))
const logger = vi.hoisted(() => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }))
vi.mock('@main/lib/logger', () => ({ logger }))

const manager = vi.hoisted(() => ({
  callLlm: vi.fn(),
  loadRelevantMemories: vi.fn(),
  parseJsonFromResponse: (t: string) => {
    try { return JSON.parse(t) } catch { return null }
  }
}))
vi.mock('@main/lib/ai/memory/manager', () => manager)

const modelUtil = vi.hoisted(() => ({
  getModelFromProvider: vi.fn(() => ({ model: { id: 'm' }, apiKey: 'k' }))
}))
vi.mock('@main/lib/ai/utils/model-util', () => modelUtil)

const memoryQueries = vi.hoisted(() => ({ createMemory: vi.fn() }))
vi.mock('@main/lib/db/memory-queries', () => memoryQueries)

let settings: Record<string, unknown> = { id: 's', memory: { useInChat: true } }

async function buildApp() {
  const { default: healthRouter } = await import('@main/lib/server/routes/health')
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
  (await buildApp()).request('/api/v1/health/summary', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body)
  })

beforeEach(() => {
  vi.clearAllMocks()
  settings = { id: 's', memory: { useInChat: true } }
  manager.loadRelevantMemories.mockResolvedValue([
    { id: 'm1', section: 'profile', key: 'half-marathon', summary: 'Training for a half marathon', details: [] }
  ])
  manager.callLlm.mockResolvedValue(JSON.stringify(SUMMARY))
})

describe('POST /api/v1/health/summary', () => {
  it('returns the model report and passes the relevant memories in', async () => {
    const res = await post(SNAPSHOT)
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual(SUMMARY)
    expect(manager.loadRelevantMemories).toHaveBeenCalledWith(
      expect.stringContaining('Daily health report'),
      { id: 'm' },
      'k',
      'health:2026-10-01',
      'health:2026-10-01'
    )
    const userText = manager.callLlm.mock.calls[0][3] as string
    expect(userText).toContain('half-marathon')
    expect(userText).toContain('"steps":5840')
  })

  it('does not read memories when memory is off for chats', async () => {
    settings = { id: 's', memory: { useInChat: false } }
    await post(SNAPSHOT)
    expect(manager.loadRelevantMemories).not.toHaveBeenCalled()
  })

  it('accepts null categories', async () => {
    const res = await post({ ...SNAPSHOT, sleep: null, activity: null, recovery: null, body: null, odyState: 'noData' })
    expect(res.status).toBe(200)
  })

  it('rejects a snapshot with raw samples', async () => {
    const res = await post({ ...SNAPSHOT, samples: [] })
    expect(res.status).toBe(400)
    expect(manager.callLlm).not.toHaveBeenCalled()
  })

  it('retries once on output that is not the schema, then succeeds', async () => {
    manager.callLlm.mockResolvedValueOnce('Sure! Here is your report: you slept well.')
    const res = await post(SNAPSHOT)
    expect(res.status).toBe(200)
    expect(manager.callLlm).toHaveBeenCalledTimes(2)
  })

  it('fails with AI_GENERATION_FAILED after two bad outputs', async () => {
    manager.callLlm.mockResolvedValue('{"headline": ""}')
    const res = await post(SNAPSHOT)
    expect(res.status).toBe(500)
    expect((await res.json()).code).toBe('AI_GENERATION_FAILED')
    expect(manager.callLlm).toHaveBeenCalledTimes(2)
  })

  it('writes nothing and logs no health values', async () => {
    await post(SNAPSHOT)
    expect(memoryQueries.createMemory).not.toHaveBeenCalled()
    const logged = JSON.stringify([...logger.info.mock.calls, ...logger.warn.mock.calls])
    for (const value of ['5840', '372', '61', '38']) expect(logged).not.toContain(value)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bunx vitest run tests/unit/main/lib/server/routes/health.test.ts`
Expected: FAIL — cannot find module `@main/lib/server/routes/health`.

- [ ] **Step 3: Export the two helpers**

In `src/main/lib/ai/memory/manager.ts` change `function parseJsonFromResponse(` to `export function parseJsonFromResponse(` and `async function callLlm(` to `export async function callLlm(`. Nothing else changes.

- [ ] **Step 4: Write the route**

```ts
// src/main/lib/server/routes/health.ts
// exodus-ios's Health workspace: one report a day, written from the phone's
// aggregated snapshot. Stateless — nothing is stored, and the logs carry
// timings, never the numbers.
import { ErrorCode } from '@exodus/shared/constants/error-codes'
import { AIError } from '@exodus/shared/errors/app-error'
import {
  healthSnapshotSchema,
  healthSummarySchema,
  type HealthSnapshot
} from '@exodus/shared/types/health'
import { Hono } from 'hono'

import {
  callLlm,
  loadRelevantMemories,
  parseJsonFromResponse
} from '../../ai/memory/manager'
import { getModelFromProvider } from '../../ai/utils/model-util'
import type { MemoryRow } from '../../db/memory-queries'
import { logger } from '../../logger'
import { Variables } from '../types'
import { validateSchema } from '../utils'

export const HEALTH_SUMMARY_SYSTEM = `You write a short, warm daily health note for one person from the numbers you are given.
Rules:
- Write in the language named by "locale" (a BCP-47 tag).
- Use only the numbers in the snapshot and quote them exactly. A category that is null has no data: say nothing about it and set its line to null.
- Never diagnose, never name a condition, never give medical advice beyond everyday habits (sleep, walking, water, rest).
- "headline": at most 12 words, no trailing punctuation.
- "summary": 2 to 4 sentences of Markdown; bold (**...**) the one or two numbers that matter most.
- "categories": one short sentence per category, or null.
- "memorySuggestion": only when the snapshot and the known memories show a lasting pattern worth remembering long-term — never a one-day event, never something the memories already say. Shape: {"section":"profile","key":"kebab-case-key","summary":"one sentence"}. Otherwise null.
Respond ONLY with JSON: {"headline":"...","summary":"...","categories":{"sleep":...,"activity":...,"recovery":...,"body":...},"memorySuggestion":...}`

/** What the memory read-filter is asked about: the day in one line. */
export function memoryQuestion(s: HealthSnapshot): string {
  const parts: string[] = []
  if (s.sleep) parts.push(`sleep ${s.sleep.asleepMin} min`)
  if (s.activity) parts.push(`steps ${s.activity.steps}/${s.activity.stepGoal}`)
  if (s.recovery?.level) parts.push(`recovery ${s.recovery.level}`)
  if (s.body) parts.push(`water ${s.body.waterCups} cups`)
  return `Daily health report. ${parts.join('; ')}`
}

function userText(s: HealthSnapshot, memories: MemoryRow[]): string {
  const known = memories.length
    ? memories.map((m) => `- [${m.section}] ${m.key} — ${m.summary}`).join('\n')
    : '(none)'
  return `Snapshot:\n${JSON.stringify(s)}\n\nKnown memories:\n${known}`
}

const health = new Hono<{ Variables: Variables }>()

health.post('/summary', async (c) => {
  const snapshot = validateSchema(
    healthSnapshotSchema,
    await c.req.json(),
    'Invalid health snapshot'
  )
  const setting = c.get('settings')
  const { model, apiKey } = getModelFromProvider(setting)
  const started = Date.now()
  const session = `health:${snapshot.date}`
  const memories =
    setting.memory?.useInChat !== false
      ? await loadRelevantMemories(memoryQuestion(snapshot), model, apiKey, session, session)
      : []
  const prompt = userText(snapshot, memories)

  for (let attempt = 1; attempt <= 2; attempt++) {
    const text = await callLlm(model, apiKey, HEALTH_SUMMARY_SYSTEM, prompt)
    const parsed = healthSummarySchema.safeParse(parseJsonFromResponse(text))
    if (parsed.success) {
      logger.info('health', 'Summary written', { ms: Date.now() - started, attempt })
      return c.json(parsed.data)
    }
  }
  logger.warn('health', 'Summary output invalid twice', { ms: Date.now() - started })
  throw new AIError(ErrorCode.AI_GENERATION_FAILED, 'The health summary could not be written.')
})

export default health
```

In `src/main/lib/server/app.ts`, add `import healthRouter from './routes/health'` beside the other route imports and `v1.route('/health', healthRouter)` right after `v1.route('/memory', memoryRouter)`.

If TypeScript reports `setting.memory` missing on the settings type, mirror `chat.ts:244` exactly (`const memoryConfig = setting.memory` is already used there with the same `Variables`), so it will type-check the same way.

- [ ] **Step 5: Run tests and typecheck**

Run: `bunx vitest run tests/unit/main/lib/server/routes/health.test.ts tests/unit/main/lib/server/routes/memory-undo.test.ts`
Expected: PASS (7 + existing).
Run: `bunx tsc --noEmit -p tsconfig.node.json`
Expected: no new errors in `health.ts`, `manager.ts`, `app.ts`.

- [ ] **Step 6: Commit**

```bash
git add src/main/lib/server/routes/health.ts src/main/lib/server/app.ts src/main/lib/ai/memory/manager.ts tests/unit/main/lib/server/routes/health.test.ts
git commit -m "feat(health): stateless daily-report route for exodus-ios

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- src/main/lib/server/routes/health.ts src/main/lib/server/app.ts src/main/lib/ai/memory/manager.ts tests/unit/main/lib/server/routes/health.test.ts
```

---

### Task 3: iOS — modules, entitlement, usage strings, `.health` workspace

**Files:**
- Modify: `Project.swift`
- Modify: `Resources/App/InfoPlist.xcstrings`
- Create: `Sources/OdyKit/OdyKit.swift`, `Sources/HealthFeature/HealthRootView.swift`
- Create: `Tests/OdyKitTests/OdyKitSmokeTests.swift`, `Tests/HealthFeatureTests/HealthRootSmokeTests.swift`
- Modify: `Sources/App/AppWorkspace.swift`, `Sources/App/AppShell.swift:112-128`

**Interfaces:**
- Produces: modules `OdyKit` (public enum `OdyKit` with `static let version = 1`), `HealthFeature` (public `HealthRootView(apiClient: APIClient)`), `AppWorkspace.health`.

- [ ] **Step 1: Write the failing smoke tests**

```swift
// Tests/OdyKitTests/OdyKitSmokeTests.swift
import Testing

@testable import OdyKit

struct OdyKitSmokeTests {
    @Test func moduleLinks() { #expect(OdyKit.version == 1) }
}
```

```swift
// Tests/HealthFeatureTests/HealthRootSmokeTests.swift
import Testing

@testable import HealthFeature

struct HealthRootSmokeTests {
    @Test func moduleLinks() { #expect(HealthFeatureInfo.name == "Health") }
}
```

- [ ] **Step 2: Add the targets to `Project.swift`**

After `moduleTarget(name: "PhilharmonicFeature", ...)` add:

```swift
        moduleTarget(name: "OdyKit"),
        .target(
            name: "OdyKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).OdyKitTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/OdyKitTests"],
            dependencies: [.target(name: "OdyKit")]
        ),
        moduleTarget(
            name: "HealthFeature",
            dependencies: [
                .target(name: "Models"), .target(name: "NetworkingKit"), .target(name: "MarkdownKit"),
                .target(name: "OdyKit")
            ]
        ),
        .target(
            name: "HealthFeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).HealthFeatureTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/HealthFeatureTests"],
            dependencies: [
                .target(name: "HealthFeature"), .target(name: "NetworkingKit"), .target(name: "Models")
            ]
        ),
```

In the `App` target: add `.target(name: "HealthFeature")` and `.target(name: "OdyKit")` to `dependencies`; add to the `infoPlist` dictionary

```swift
                    "NSHealthShareUsageDescription":
                        "Exodus reads your sleep, activity, heart and body data to write your daily health report.",
                    "NSHealthUpdateUsageDescription":
                        "Exodus saves the water you log to Apple Health."
```

and add, as a sibling of `infoPlist:`,

```swift
            entitlements: .dictionary([
                "com.apple.developer.healthkit": .boolean(true),
                "com.apple.developer.healthkit.access": .array([])
            ]),
```

- [ ] **Step 3: Write the module sources**

```swift
// Sources/OdyKit/OdyKit.swift
/// Ody, the Exodus mascot, as a living SwiftUI character and the scenes it appears in. Plan 2 fills this module;
/// the body curve and palette come from the desktop's `brand/art.mjs`.
public enum OdyKit {
    static let version = 1
}
```

```swift
// Sources/HealthFeature/HealthRootView.swift
import NetworkingKit
import SwiftUI

enum HealthFeatureInfo {
    static let name = "Health"
}

/// The Health workspace. A placeholder until the home screen lands (plan 3).
public struct HealthRootView: View {
    let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public var body: some View {
        ContentUnavailableView("ios:app.workspace.health", systemImage: "heart.text.square")
    }
}
```

- [ ] **Step 4: Add the workspace**

`Sources/App/AppWorkspace.swift`: the doc comment becomes `/// The top-level areas of the app. Philharmonic is listed but not available yet.` (unchanged), then:

```swift
enum AppWorkspace: CaseIterable, Identifiable {
    case chat
    case health
    case philharmonic
```

add to `title`:

```swift
        case .health:
            LocalizedStringResource(
                "ios:app.workspace.health", comment: "Name of the Health workspace in the sidebar.")
```

to `systemImage`: `case .health: "heart.text.square"`; and `var isAvailable: Bool { self != .philharmonic }`.

`Sources/App/AppShell.swift`: add `import HealthFeature`, and in `detail`'s switch:

```swift
        case .health:
            HealthRootView(apiClient: apiClient)
```

Update the `.sensoryFeedback(.selection, trigger: workspace)` comment's last sentence to: `today .chat and .health are selectable (AppWorkspace.isAvailable).`

- [ ] **Step 5: Strings**

```bash
python3 scripts/l10n.py add "ios:app.workspace.health" --comment "Name of the Health workspace in the sidebar." --en-value "Health"
python3 scripts/l10n.py add NSHealthShareUsageDescription --file Resources/App/InfoPlist.xcstrings --en-value "Exodus reads your sleep, activity, heart and body data to write your daily health report."
python3 scripts/l10n.py add NSHealthUpdateUsageDescription --file Resources/App/InfoPlist.xcstrings --en-value "Exodus saves the water you log to Apple Health."
```

Then write `/private/tmp/…/health-l10n-1.json` (any scratch path) with the nine translations of each of the three keys (`zh-Hant`, `zh-HK`, `ja`, `ko`, `fr`, `de`, `es`, `pt-BR`, `it`) — "Health" is `健康`/`健康`/`ヘルスケア`/`건강`/`Santé`/`Health`/`Salud`/`Saúde`/`Salute` — and run `python3 scripts/l10n.py fill <that file>` and `python3 scripts/l10n.py fill <that file> --file Resources/App/InfoPlist.xcstrings` for the two plist keys. Run `python3 scripts/l10n.py audit`; expected exit 0.

- [ ] **Step 6: Generate, build, run the smoke tests**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme OdyKit -destination "platform=iOS Simulator,name=iPhone 17"
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "platform=iOS Simulator,name=iPhone 17"
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "generic/platform=iOS Simulator"
```

Expected: each test run prints `Test run with 1 test … passed`; the App build succeeds (the entitlement is accepted under automatic signing for the simulator).

- [ ] **Step 7: Commit**

```bash
git add Project.swift Resources/App/InfoPlist.xcstrings Resources/App/Localizable.xcstrings Sources/OdyKit Sources/HealthFeature Tests/OdyKitTests Tests/HealthFeatureTests Sources/App/AppWorkspace.swift Sources/App/AppShell.swift
git commit -m "feat(health): Health workspace, OdyKit and HealthFeature modules, HealthKit entitlement

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Project.swift Resources/App/InfoPlist.xcstrings Resources/App/Localizable.xcstrings Sources/OdyKit Sources/HealthFeature Tests/OdyKitTests Tests/HealthFeatureTests Sources/App/AppWorkspace.swift Sources/App/AppShell.swift
```

Note: `Resources/App/Localizable.xcstrings` and `Sources/App/AppShell.swift` are not touched by other uncommitted work except `Localizable.xcstrings`, which has unrelated edits. Check `git diff --stat Resources/App/Localizable.xcstrings` before committing; if it contains other keys, stage only the new keys' hunks with `git add -p` and leave the rest.

---

### Task 4: iOS — wire types

**Files:**
- Create: `Sources/Models/HealthWire.swift`
- Test: `Tests/ModelsTests/HealthWireTests.swift`

**Interfaces:**
- Produces (module `Models`, all `public`, `Codable, Equatable, Sendable`):
  - `enum OdyMood: String, CaseIterable { permission, noData, tired, recovering, active, rested, calm, happy }`
  - `enum RecoveryLevel: String { good, fair, low }`
  - `enum MoodLabel: String { veryUnpleasant, unpleasant, slightlyUnpleasant, neutral, slightlyPleasant, pleasant, veryPleasant }` with `var isPleasant: Bool`
  - `struct HealthSnapshot { date, localTime, locale: String; sleep: Sleep?; activity: Activity?; recovery: Recovery?; body: Body?; odyState: OdyMood }` with nested `Sleep { asleepMin: Int; baselineMin: Int?; deepMin, coreMin, remMin, awakeMin: Int; bedtime, wake: String }`, `Activity { steps, stepGoal, activeKcal: Int; kcalGoal: Int?; exerciseMin, standHours: Int; workouts: [Workout] }`, `Workout { type: String; minutes: Int; kcal: Int? }`, `Recovery { level: RecoveryLevel?; hrvMs, hrvBaselineMs, restingHr, restingHrBaseline, respRate: Double? }`, `Body { waterCups: Int; weightKg, weightTrend30d: Double?; mood: MoodLabel? }`
  - `struct HealthSummary { headline, summary: String; categories: Categories; memorySuggestion: MemorySuggestion? }`, `Categories { sleep, activity, recovery, body: String? }`, `MemorySuggestion { section, key, summary: String }`
  - `enum HealthWire { static func encoder() -> JSONEncoder }` (sorted keys)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ModelsTests/HealthWireTests.swift
import Foundation
import Testing

@testable import Models

/// The same JSON as the desktop's tests/unit/shared/types/health.test.ts: both sides agree on the wire.
struct HealthWireTests {
    static let snapshotJSON = """
        {"date":"2026-10-01","localTime":"15:00","locale":"zh-Hant",
         "sleep":{"asleepMin":372,"baselineMin":425,"deepMin":52,"coreMin":209,"remMin":81,"awakeMin":30,"bedtime":"23:48","wake":"06:00"},
         "activity":{"steps":5840,"stepGoal":8000,"activeKcal":310,"kcalGoal":500,"exerciseMin":12,"standHours":6,"workouts":[]},
         "recovery":{"level":"low","hrvMs":38,"hrvBaselineMs":44,"restingHr":61,"restingHrBaseline":58,"respRate":14.2},
         "body":{"waterCups":3,"weightKg":null,"weightTrend30d":null,"mood":null},
         "odyState":"tired"}
        """
    static let summaryJSON = """
        {"headline":"有點沒睡飽","summary":"昨晚只睡了 **6 小時 12 分**。",
         "categories":{"sleep":"深睡偏少。","activity":"還差 2,160 步。","recovery":"HRV 偏低。","body":null},
         "memorySuggestion":{"section":"profile","key":"weekday-sleep","summary":"工作日平均只睡 6 小時左右"}}
        """

    @Test func decodesTheSpecSnapshot() throws {
        let s = try JSONDecoder().decode(HealthSnapshot.self, from: Data(Self.snapshotJSON.utf8))
        #expect(s.sleep?.asleepMin == 372)
        #expect(s.recovery?.level == .low)
        #expect(s.body?.weightKg == nil)
        #expect(s.odyState == .tired)
    }

    @Test func roundTripsAndOmitsNothingItNeeds() throws {
        let s = try JSONDecoder().decode(HealthSnapshot.self, from: Data(Self.snapshotJSON.utf8))
        let data = try HealthWire.encoder().encode(s)
        let again = try JSONDecoder().decode(HealthSnapshot.self, from: data)
        #expect(again == s)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"odyState\":\"tired\""))
        #expect(!text.contains("weightKg"))  // nil is omitted, which the desktop's .nullish() accepts
    }

    @Test func decodesTheSpecSummary() throws {
        let r = try JSONDecoder().decode(HealthSummary.self, from: Data(Self.summaryJSON.utf8))
        #expect(r.categories.body == nil)
        #expect(r.memorySuggestion?.key == "weekday-sleep")
    }

    @Test func aSummaryWithoutSuggestionDecodes() throws {
        let json = Self.summaryJSON.replacingOccurrences(
            of: #""memorySuggestion":{"section":"profile","key":"weekday-sleep","summary":"工作日平均只睡 6 小時左右"}"#,
            with: #""memorySuggestion":null"#)
        let r = try JSONDecoder().decode(HealthSummary.self, from: Data(json.utf8))
        #expect(r.memorySuggestion == nil)
    }

    @Test func pleasantMoods() {
        #expect(MoodLabel.slightlyPleasant.isPleasant)
        #expect(!MoodLabel.neutral.isPleasant)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `tuist generate --no-open && xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:ModelsTests/HealthWireTests`
Expected: build failure — `HealthSnapshot` not found.

- [ ] **Step 3: Write the types**

```swift
// Sources/Models/HealthWire.swift
import Foundation

/// The Health workspace's wire types: the day's aggregated snapshot the phone sends to `/api/v1/health/summary` and
/// the report that comes back. The desktop's `packages/shared/src/types/health.ts`, held to the same JSON.

/// Which Ody the day calls for. The first two are about the app, the rest about the body.
public enum OdyMood: String, Codable, CaseIterable, Sendable {
    case permission, noData, tired, recovering, active, rested, calm, happy
}

/// Recovery relative to the user's own 30-day baseline — never a medical judgement.
public enum RecoveryLevel: String, Codable, Sendable {
    case good, fair, low
}

/// HealthKit's State of Mind valence, as a label.
public enum MoodLabel: String, Codable, Sendable {
    case veryUnpleasant, unpleasant, slightlyUnpleasant, neutral, slightlyPleasant, pleasant, veryPleasant

    public var isPleasant: Bool { self == .slightlyPleasant || self == .pleasant || self == .veryPleasant }
}

public struct HealthSnapshot: Codable, Equatable, Sendable {
    public var date: String
    public var localTime: String
    public var locale: String
    public var sleep: Sleep?
    public var activity: Activity?
    public var recovery: Recovery?
    public var body: Body?
    public var odyState: OdyMood

    public init(
        date: String, localTime: String, locale: String, sleep: Sleep?, activity: Activity?, recovery: Recovery?,
        body: Body?, odyState: OdyMood
    ) {
        self.date = date
        self.localTime = localTime
        self.locale = locale
        self.sleep = sleep
        self.activity = activity
        self.recovery = recovery
        self.body = body
        self.odyState = odyState
    }

    public struct Sleep: Codable, Equatable, Sendable {
        public var asleepMin: Int
        public var baselineMin: Int?
        public var deepMin: Int
        public var coreMin: Int
        public var remMin: Int
        public var awakeMin: Int
        public var bedtime: String
        public var wake: String

        public init(
            asleepMin: Int, baselineMin: Int?, deepMin: Int, coreMin: Int, remMin: Int, awakeMin: Int,
            bedtime: String, wake: String
        ) {
            self.asleepMin = asleepMin
            self.baselineMin = baselineMin
            self.deepMin = deepMin
            self.coreMin = coreMin
            self.remMin = remMin
            self.awakeMin = awakeMin
            self.bedtime = bedtime
            self.wake = wake
        }
    }

    public struct Activity: Codable, Equatable, Sendable {
        public var steps: Int
        public var stepGoal: Int
        public var activeKcal: Int
        public var kcalGoal: Int?
        public var exerciseMin: Int
        public var standHours: Int
        public var workouts: [Workout]

        public init(
            steps: Int, stepGoal: Int, activeKcal: Int, kcalGoal: Int?, exerciseMin: Int, standHours: Int,
            workouts: [Workout]
        ) {
            self.steps = steps
            self.stepGoal = stepGoal
            self.activeKcal = activeKcal
            self.kcalGoal = kcalGoal
            self.exerciseMin = exerciseMin
            self.standHours = standHours
            self.workouts = workouts
        }

        public var reachedGoal: Bool { steps >= stepGoal }
    }

    public struct Workout: Codable, Equatable, Sendable {
        public var type: String
        public var minutes: Int
        public var kcal: Int?

        public init(type: String, minutes: Int, kcal: Int?) {
            self.type = type
            self.minutes = minutes
            self.kcal = kcal
        }
    }

    public struct Recovery: Codable, Equatable, Sendable {
        public var level: RecoveryLevel?
        public var hrvMs: Double?
        public var hrvBaselineMs: Double?
        public var restingHr: Double?
        public var restingHrBaseline: Double?
        public var respRate: Double?

        public init(
            level: RecoveryLevel?, hrvMs: Double?, hrvBaselineMs: Double?, restingHr: Double?,
            restingHrBaseline: Double?, respRate: Double?
        ) {
            self.level = level
            self.hrvMs = hrvMs
            self.hrvBaselineMs = hrvBaselineMs
            self.restingHr = restingHr
            self.restingHrBaseline = restingHrBaseline
            self.respRate = respRate
        }
    }

    public struct Body: Codable, Equatable, Sendable {
        public var waterCups: Int
        public var weightKg: Double?
        public var weightTrend30d: Double?
        public var mood: MoodLabel?

        public init(waterCups: Int, weightKg: Double?, weightTrend30d: Double?, mood: MoodLabel?) {
            self.waterCups = waterCups
            self.weightKg = weightKg
            self.weightTrend30d = weightTrend30d
            self.mood = mood
        }
    }
}

public struct HealthSummary: Codable, Equatable, Sendable {
    public var headline: String
    public var summary: String
    public var categories: Categories
    public var memorySuggestion: MemorySuggestion?

    public init(headline: String, summary: String, categories: Categories, memorySuggestion: MemorySuggestion?) {
        self.headline = headline
        self.summary = summary
        self.categories = categories
        self.memorySuggestion = memorySuggestion
    }

    public struct Categories: Codable, Equatable, Sendable {
        public var sleep: String?
        public var activity: String?
        public var recovery: String?
        public var body: String?

        public init(sleep: String?, activity: String?, recovery: String?, body: String?) {
            self.sleep = sleep
            self.activity = activity
            self.recovery = recovery
            self.body = body
        }
    }

    /// Posted as-is to `/api/v1/memory` when the user taps Remember.
    public struct MemorySuggestion: Codable, Equatable, Sendable {
        public var section: String
        public var key: String
        public var summary: String

        public init(section: String, key: String, summary: String) {
            self.section = section
            self.key = key
            self.summary = summary
        }
    }
}

public enum HealthWire {
    /// Sorted keys, so a snapshot always reads the same (cache comparisons, the block sent to Chat).
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: the Step 2 command. Expected: `Test run with 5 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/HealthWire.swift Tests/ModelsTests/HealthWireTests.swift
git commit -m "feat(health): wire types for the daily snapshot and report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/Models/HealthWire.swift Tests/ModelsTests/HealthWireTests.swift
```

---

### Task 5: iOS — the health block sent to Chat

**Files:**
- Create: `Sources/Models/HealthContext.swift`
- Test: `Tests/ModelsTests/HealthContextTests.swift`

**Interfaces:**
- Consumes: `HealthWire.encoder()` (Task 4).
- Produces: `public enum HealthContext { static let infoString = "exodus-health"; static func block(json: String) -> String; static func compose(json: String, question: String) -> String; static func compose<T: Encodable>(_ value: T, question: String) throws -> String; static func split(_ text: String) -> (json: String?, body: String) }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ModelsTests/HealthContextTests.swift
import Testing

@testable import Models

struct HealthContextTests {
    @Test func composeIsAFencedBlockThenTheQuestion() {
        let text = HealthContext.compose(json: #"{"steps":1}"#, question: "  Why am I tired?\n")
        #expect(text == "```exodus-health\n{\"steps\":1}\n```\n\nWhy am I tired?")
    }

    @Test func splitReturnsTheBlockAndTheQuestion() {
        let parts = HealthContext.split("```exodus-health\n{\"a\":1}\n```\n\nHow did I sleep?")
        #expect(parts.json == #"{"a":1}"#)
        #expect(parts.body == "How did I sleep?")
    }

    @Test func roundTripsMultiLineJSON() {
        let json = "{\n  \"a\" : 1\n}"
        let parts = HealthContext.split(HealthContext.compose(json: json, question: "q"))
        #expect(parts.json == json)
        #expect(parts.body == "q")
    }

    @Test func onlyALeadingBlockCounts() {
        let text = "Look at this:\n```exodus-health\n{}\n```"
        let parts = HealthContext.split(text)
        #expect(parts.json == nil)
        #expect(parts.body == text)
    }

    @Test func anUnclosedBlockIsJustText() {
        let text = "```exodus-health\n{\"a\":1}"
        #expect(HealthContext.split(text).json == nil)
    }

    @Test func aBlockWithNoQuestionHasAnEmptyBody() {
        let parts = HealthContext.split("```exodus-health\n{}\n```")
        #expect(parts.json == "{}")
        #expect(parts.body.isEmpty)
    }

    @Test func encodesAValueWithSortedKeys() throws {
        struct V: Encodable { let b = 2, a = 1 }
        let text = try HealthContext.compose(V(), question: "q")
        #expect(text.hasPrefix("```exodus-health\n{\"a\":1,\"b\":2}\n```"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme Models -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:ModelsTests/HealthContextTests`
Expected: build failure — `HealthContext` not found.

- [ ] **Step 3: Write it**

```swift
// Sources/Models/HealthContext.swift
import Foundation

/// The Health workspace's "ask about this": a question typed there travels to Chat with the day's numbers as a
/// leading fenced block — ```` ```exodus-health ````, the JSON, ```` ``` ````, a blank line, the question. Plain text, like
/// `QuotedText`, so the computer and every provider read it as what it is; the transcript reads it back with `split`
/// to draw the numbers as a card. Only a block that opens the message counts.
public enum HealthContext {
    public static let infoString = "exodus-health"
    private static var opening: String { "```" + infoString + "\n" }  // l10n:ignore: markdown syntax
    private static let closing = "\n```"  // l10n:ignore: markdown syntax

    public static func block(json: String) -> String { opening + json + closing }

    public static func compose(json: String, question: String) -> String {
        block(json: json) + "\n\n" + question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func compose<T: Encodable>(_ value: T, question: String) throws -> String {
        let data = try HealthWire.encoder().encode(value)
        return compose(json: String(decoding: data, as: UTF8.self), question: question)
    }

    public static func split(_ text: String) -> (json: String?, body: String) {
        guard text.hasPrefix(opening) else { return (nil, text) }
        let rest = text.dropFirst(opening.count)
        // The block ends at the first line that is exactly the closing fence.
        guard let end = rest.range(of: closing + "\n") ?? (rest.hasSuffix(closing) ? rest.range(of: closing, options: .backwards) : nil)
        else { return (nil, text) }
        let json = String(rest[..<end.lowerBound])
        let body = rest[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (json, body)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: Step 2's command. Expected: `Test run with 7 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/HealthContext.swift Tests/ModelsTests/HealthContextTests.swift
git commit -m "feat(health): the health block a question carries into Chat

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/Models/HealthContext.swift Tests/ModelsTests/HealthContextTests.swift
```

---

### Task 6: iOS — samples, data source protocol, sleep analyzer

**Files:**
- Create: `Sources/HealthFeature/Data/HealthSamples.swift`, `Sources/HealthFeature/Data/SleepAnalyzer.swift`
- Create: `Tests/HealthFeatureTests/FakeHealthSource.swift`, `Tests/HealthFeatureTests/SleepAnalyzerTests.swift`

**Interfaces:**
- Produces:
  - `public enum SleepStage: String, Sendable { case awake, core, deep, rem, unspecified; var isAsleep: Bool }`
  - `public struct SleepSample: Sendable, Equatable { start, end: Date; stage: SleepStage; source: String }`
  - `public struct DayValue: Sendable, Equatable { day: Date; value: Double }` (day = start of day)
  - `public struct WorkoutSample: Sendable, Equatable { start: Date; minutes: Int; kcal: Int?; type: String }`
  - `public struct MoodSample: Sendable, Equatable { date: Date; label: MoodLabel }`
  - `public struct ActivityGoals: Sendable, Equatable { moveKcal: Int?; exerciseMin: Int?; standHours: Int? }`
  - `public enum SumMetric: Sendable { steps, activeKcal, exerciseMin, waterMl }`, `public enum AverageMetric: Sendable { restingHr, hrv, respRate, weightKg }`
  - `public protocol HealthDataSource: Sendable` (methods below)
  - `public struct SleepNight: Sendable, Equatable { asleepMin, deepMin, coreMin, remMin, awakeMin: Int; bedtime, wake: Date; stages: [SleepSample] }`
  - `public enum SleepAnalyzer { static func window(endingOn day: Date, calendar: Calendar) -> DateInterval; static func night(from samples: [SleepSample], endingOn day: Date, calendar: Calendar) -> SleepNight? }`
  - Test helper `FakeHealthSource` (actor) conforming to `HealthDataSource`.

- [ ] **Step 1: Write the protocol and sample types (no logic yet)**

```swift
// Sources/HealthFeature/Data/HealthSamples.swift
import Foundation
import Models

/// HealthKit's sleep values, reduced to what the report uses. `inBed` samples are dropped at the source.
public enum SleepStage: String, Sendable {
    case awake, core, deep, rem, unspecified

    public var isAsleep: Bool { self != .awake }
}

public struct SleepSample: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage
    /// The recording device's bundle identifier (Watch and iPhone both write sleep).
    public var source: String

    public init(start: Date, end: Date, stage: SleepStage, source: String) {
        self.start = start
        self.end = end
        self.stage = stage
        self.source = source
    }
}

/// One calendar day's value; `day` is that day's start.
public struct DayValue: Sendable, Equatable {
    public var day: Date
    public var value: Double

    public init(day: Date, value: Double) {
        self.day = day
        self.value = value
    }
}

public struct WorkoutSample: Sendable, Equatable {
    public var start: Date
    public var minutes: Int
    public var kcal: Int?
    /// A short English name of the activity type ("running", "yoga"), as the model reads it.
    public var type: String

    public init(start: Date, minutes: Int, kcal: Int?, type: String) {
        self.start = start
        self.minutes = minutes
        self.kcal = kcal
        self.type = type
    }
}

public struct MoodSample: Sendable, Equatable {
    public var date: Date
    public var label: MoodLabel

    public init(date: Date, label: MoodLabel) {
        self.date = date
        self.label = label
    }
}

/// The Activity rings' goals for a day; HealthKit has no step goal.
public struct ActivityGoals: Sendable, Equatable {
    public var moveKcal: Int?
    public var exerciseMin: Int?
    public var standHours: Int?

    public init(moveKcal: Int?, exerciseMin: Int?, standHours: Int?) {
        self.moveKcal = moveKcal
        self.exerciseMin = exerciseMin
        self.standHours = standHours
    }
}

public enum SumMetric: Sendable { case steps, activeKcal, exerciseMin, waterMl }
public enum AverageMetric: Sendable { case restingHr, hrv, respRate, weightKg }

/// What the Health workspace reads and writes. The real one is `HealthKitSource`; tests give their own.
public protocol HealthDataSource: Sendable {
    var isAvailable: Bool { get }
    /// Whether the system sheet has been shown already. Read denial is invisible to apps, so this is all we can know.
    func hasRequestedAuthorization() async -> Bool
    func requestAuthorization() async throws
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample]
    /// Per-day sums over `[start, end)`, one entry per day that has data.
    func dailySums(_ metric: SumMetric, from start: Date, to end: Date) async throws -> [DayValue]
    /// Per-hour sums of one day (24 entries max, `day` holds the hour's start).
    func hourlySums(_ metric: SumMetric, on day: Date) async throws -> [DayValue]
    /// Per-day averages over `[start, end)`, one entry per day that has data.
    func dailyAverages(_ metric: AverageMetric, from start: Date, to end: Date) async throws -> [DayValue]
    func standHours(on day: Date) async throws -> Int
    func activityGoals(on day: Date) async throws -> ActivityGoals?
    func workouts(from start: Date, to end: Date) async throws -> [WorkoutSample]
    func moods(from start: Date, to end: Date) async throws -> [MoodSample]
    func logWater(milliliters: Double, at date: Date) async throws
}
```

- [ ] **Step 2: Write the fake (test target)**

```swift
// Tests/HealthFeatureTests/FakeHealthSource.swift
import Foundation
import Models

@testable import HealthFeature

/// A HealthKit stand-in: tests fill in what the store holds.
actor FakeHealthSource: HealthDataSource {
    nonisolated let isAvailable = true
    var requested = true
    var sleep: [SleepSample] = []
    var sums: [SumMetric: [DayValue]] = [:]
    var hourly: [SumMetric: [DayValue]] = [:]
    var averages: [AverageMetric: [DayValue]] = [:]
    var stand = 0
    var goals: ActivityGoals?
    var workoutList: [WorkoutSample] = []
    var moodList: [MoodSample] = []
    var loggedWater: [Double] = []
    var failure: Error?

    func set(_ change: (isolated FakeHealthSource) -> Void) { change(self) }

    func hasRequestedAuthorization() async -> Bool { requested }
    func requestAuthorization() async throws { requested = true }

    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        if let failure { throw failure }
        return sleep.filter { $0.end > start && $0.start < end }
    }

    func dailySums(_ metric: SumMetric, from start: Date, to end: Date) async throws -> [DayValue] {
        (sums[metric] ?? []).filter { $0.day >= start && $0.day < end }
    }

    func hourlySums(_ metric: SumMetric, on day: Date) async throws -> [DayValue] { hourly[metric] ?? [] }

    func dailyAverages(_ metric: AverageMetric, from start: Date, to end: Date) async throws -> [DayValue] {
        (averages[metric] ?? []).filter { $0.day >= start && $0.day < end }
    }

    func standHours(on day: Date) async throws -> Int { stand }
    func activityGoals(on day: Date) async throws -> ActivityGoals? { goals }

    func workouts(from start: Date, to end: Date) async throws -> [WorkoutSample] {
        workoutList.filter { $0.start >= start && $0.start < end }
    }

    func moods(from start: Date, to end: Date) async throws -> [MoodSample] {
        moodList.filter { $0.date >= start && $0.date < end }
    }

    func logWater(milliliters: Double, at date: Date) async throws { loggedWater.append(milliliters) }
}

/// Fixed calendar and clock for every Health test: Taipei, 2026-10-01 15:00.
enum TestClock {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static let now = date(2026, 10, 1, 15, 0)
    static var today: Date { calendar.startOfDay(for: now) }
}
```

- [ ] **Step 3: Write the failing sleep tests**

```swift
// Tests/HealthFeatureTests/SleepAnalyzerTests.swift
import Foundation
import Testing

@testable import HealthFeature

struct SleepAnalyzerTests {
    private let cal = TestClock.calendar
    private func t(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { TestClock.date(2026, d < 15 ? 10 : 9, d, h, m) }
    private func s(_ a: Date, _ b: Date, _ stage: SleepStage, _ source: String = "watch") -> SleepSample {
        SleepSample(start: a, end: b, stage: stage, source: source)
    }

    @Test func windowIsSixPmYesterdayToNoonToday() {
        let w = SleepAnalyzer.window(endingOn: TestClock.today, calendar: cal)
        #expect(w.start == t(30, 18))
        #expect(w.end == t(1, 12))
    }

    @Test func sumsStagesAndFindsBedtimeAndWake() throws {
        let samples = [
            s(t(30, 23, 48), t(1, 0, 30), .core),
            s(t(1, 0, 30), t(1, 1, 18), .deep),
            s(t(1, 1, 18), t(1, 1, 30), .awake),
            s(t(1, 1, 30), t(1, 2, 30), .rem),
            s(t(1, 2, 30), t(1, 6, 0), .core),
        ]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.deepMin == 48)
        #expect(night.remMin == 60)
        #expect(night.coreMin == 42 + 210)
        #expect(night.awakeMin == 12)
        #expect(night.asleepMin == 48 + 60 + 252)
        #expect(night.bedtime == t(30, 23, 48))
        #expect(night.wake == t(1, 6, 0))
        #expect(night.stages.count == 5)
    }

    @Test func overlappingSourcesAreCountedOnceFromTheStagedOne() throws {
        let samples = [
            s(t(30, 23, 0), t(1, 7, 0), .unspecified, "iphone"),  // 8 h, no stages
            s(t(30, 23, 30), t(1, 3, 0), .core, "watch"),
            s(t(1, 3, 0), t(1, 4, 0), .deep, "watch"),
            s(t(1, 4, 0), t(1, 6, 30), .rem, "watch"),
        ]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.asleepMin == 210 + 60 + 150)
        #expect(night.stages.allSatisfy { $0.source == "watch" })
    }

    @Test func withoutStagedDataTheLongestUnspecifiedSourceWins() throws {
        let samples = [
            s(t(30, 23, 0), t(1, 6, 0), .unspecified, "iphone"),
            s(t(1, 1, 0), t(1, 2, 0), .unspecified, "other"),
        ]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.asleepMin == 420)
    }

    @Test func samplesAreClippedToTheWindow() throws {
        let samples = [s(t(30, 17, 0), t(30, 19, 0), .core), s(t(1, 11, 0), t(1, 13, 0), .core)]
        let night = try #require(SleepAnalyzer.night(from: samples, endingOn: TestClock.today, calendar: cal))
        #expect(night.asleepMin == 60 + 60)
    }

    @Test func noSleepIsNil() {
        #expect(SleepAnalyzer.night(from: [], endingOn: TestClock.today, calendar: cal) == nil)
        let awakeOnly = [s(t(1, 2, 0), t(1, 3, 0), .awake)]
        #expect(SleepAnalyzer.night(from: awakeOnly, endingOn: TestClock.today, calendar: cal) == nil)
    }
}
```

- [ ] **Step 4: Run to verify they fail**

Run: `tuist generate --no-open && xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:HealthFeatureTests/SleepAnalyzerTests`
Expected: build failure — `SleepAnalyzer` not found.

- [ ] **Step 5: Write the analyzer**

```swift
// Sources/HealthFeature/Data/SleepAnalyzer.swift
import Foundation

/// One night of sleep: the minutes in each stage, and when it began and ended.
public struct SleepNight: Sendable, Equatable {
    public var asleepMin: Int
    public var deepMin: Int
    public var coreMin: Int
    public var remMin: Int
    public var awakeMin: Int
    public var bedtime: Date
    public var wake: Date
    /// The chosen source's samples, clipped to the window and in order (the hero's track and the hypnogram).
    public var stages: [SleepSample]
}

/// Turns sleep samples into the night that ended on a day. "Last night" runs from 18:00 the day before to 12:00 on
/// the day. When a Watch and an iPhone both recorded the night, only one source is read — the one with the most staged
/// minutes (core, deep, REM), else the one with the most sleep — so overlapping minutes are not counted twice.
public enum SleepAnalyzer {
    public static func window(endingOn day: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let from = calendar.date(byAdding: .hour, value: -6, to: start)!
        let to = calendar.date(byAdding: .hour, value: 12, to: start)!
        return DateInterval(start: from, end: to)
    }

    public static func night(from samples: [SleepSample], endingOn day: Date, calendar: Calendar) -> SleepNight? {
        let window = window(endingOn: day, calendar: calendar)
        let clipped: [SleepSample] = samples.compactMap { sample in
            let start = max(sample.start, window.start)
            let end = min(sample.end, window.end)
            guard end > start else { return nil }
            return SleepSample(start: start, end: end, stage: sample.stage, source: sample.source)
        }
        let bySource = Dictionary(grouping: clipped, by: \.source)
        func minutes(_ list: [SleepSample], _ include: (SleepStage) -> Bool) -> Int {
            Int(list.filter { include($0.stage) }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
        }
        let staged: (SleepStage) -> Bool = { $0 == .core || $0 == .deep || $0 == .rem }
        guard
            let chosen = bySource.values.max(by: { a, b in
                let (sa, sb) = (minutes(a, staged), minutes(b, staged))
                return sa != sb ? sa < sb : minutes(a, \.isAsleep) < minutes(b, \.isAsleep)
            })
        else { return nil }
        let asleep = chosen.filter(\.stage.isAsleep)
        guard let bedtime = asleep.map(\.start).min(), let wake = asleep.map(\.end).max() else { return nil }
        return SleepNight(
            asleepMin: minutes(chosen, \.isAsleep),
            deepMin: minutes(chosen) { $0 == .deep },
            coreMin: minutes(chosen) { $0 == .core || $0 == .unspecified },
            remMin: minutes(chosen) { $0 == .rem },
            awakeMin: minutes(chosen) { $0 == .awake },
            bedtime: bedtime,
            wake: wake,
            stages: chosen.sorted { $0.start < $1.start })
    }
}
```

Note: `coreMin` folds `unspecified` in (an iPhone-only night has no stages; it reads as "core" so the four numbers still add up to `asleepMin`). Update `sumsStagesAndFindsBedtimeAndWake` expectations only if you change that rule.

- [ ] **Step 6: Run to verify they pass**

Run: Step 4's command. Expected: `Test run with 6 tests … passed`.

- [ ] **Step 7: Commit**

```bash
git add Sources/HealthFeature/Data Tests/HealthFeatureTests/FakeHealthSource.swift Tests/HealthFeatureTests/SleepAnalyzerTests.swift
git commit -m "feat(health): data source protocol and the sleep analyzer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/HealthFeature/Data Tests/HealthFeatureTests/FakeHealthSource.swift Tests/HealthFeatureTests/SleepAnalyzerTests.swift
```

---

### Task 7: iOS — rules: baselines, recovery, Ody moods

**Files:**
- Create: `Sources/HealthFeature/Data/HealthRules.swift`
- Test: `Tests/HealthFeatureTests/HealthRulesTests.swift`

**Interfaces:**
- Consumes: `HealthSnapshot`, `OdyMood`, `RecoveryLevel` (Task 4).
- Produces:
  - `enum HealthRules { static let minimumBaselineDays = 7; static let tiredFloorMin = 390; static func baseline(_ values: [Double]) -> Double?; static func recovery(hrv: Double?, hrvBaseline: Double?, restingHr: Double?, restingHrBaseline: Double?) -> RecoveryLevel?; static func isTired(_ sleep: HealthSnapshot.Sleep) -> Bool; static func hero(_ s: HealthSnapshot, authorized: Bool) -> OdyMood; static func card(_ category: HealthCategory, in s: HealthSnapshot) -> OdyMood }`
  - `public enum HealthCategory: String, CaseIterable, Sendable { case sleep, activity, recovery, body }`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/HealthFeatureTests/HealthRulesTests.swift
import Models
import Testing

@testable import HealthFeature

struct HealthRulesTests {
    static func snapshot(
        sleep: HealthSnapshot.Sleep? = nil, activity: HealthSnapshot.Activity? = nil,
        recovery: HealthSnapshot.Recovery? = nil, body: HealthSnapshot.Body? = nil
    ) -> HealthSnapshot {
        HealthSnapshot(
            date: "2026-10-01", localTime: "15:00", locale: "en", sleep: sleep, activity: activity,
            recovery: recovery, body: body, odyState: .happy)
    }
    static func sleep(_ min: Int, base: Int? = nil) -> HealthSnapshot.Sleep {
        .init(asleepMin: min, baselineMin: base, deepMin: 0, coreMin: min, remMin: 0, awakeMin: 0, bedtime: "23:00", wake: "07:00")
    }
    static func steps(_ n: Int) -> HealthSnapshot.Activity {
        .init(steps: n, stepGoal: 8000, activeKcal: 0, kcalGoal: nil, exerciseMin: 0, standHours: 0, workouts: [])
    }
    static func recovery(_ level: RecoveryLevel?) -> HealthSnapshot.Recovery {
        .init(level: level, hrvMs: 40, hrvBaselineMs: 40, restingHr: 60, restingHrBaseline: 60, respRate: nil)
    }

    // Baselines
    @Test func baselineNeedsSevenDays() {
        #expect(HealthRules.baseline([1, 2, 3, 4, 5, 6]) == nil)
        #expect(HealthRules.baseline([]) == nil)
        #expect(HealthRules.baseline([5, 1, 3, 2, 4, 7, 6]) == 4)
        #expect(HealthRules.baseline([1, 2, 3, 4, 5, 6, 7, 8]) == 4.5)
    }

    // Recovery thresholds, at their edges
    @Test func recoveryLowAtTwelvePercentHrvDrop() {
        #expect(HealthRules.recovery(hrv: 88, hrvBaseline: 100, restingHr: 60, restingHrBaseline: 60) == .low)
        #expect(HealthRules.recovery(hrv: 89, hrvBaseline: 100, restingHr: 60, restingHrBaseline: 60) == .fair)
    }

    @Test func recoveryLowAtSevenPercentRestingRise() {
        #expect(HealthRules.recovery(hrv: 100, hrvBaseline: 100, restingHr: 107, restingHrBaseline: 100) == .low)
    }

    @Test func recoveryGoodNeedsBothWithinBounds() {
        #expect(HealthRules.recovery(hrv: 95, hrvBaseline: 100, restingHr: 103, restingHrBaseline: 100) == .good)
        #expect(HealthRules.recovery(hrv: 94, hrvBaseline: 100, restingHr: 100, restingHrBaseline: 100) == .fair)
        #expect(HealthRules.recovery(hrv: 100, hrvBaseline: 100, restingHr: 104, restingHrBaseline: 100) == .fair)
    }

    @Test func recoveryFromRestingHeartRateAlone() {
        #expect(HealthRules.recovery(hrv: nil, hrvBaseline: nil, restingHr: 108, restingHrBaseline: 100) == .low)
        #expect(HealthRules.recovery(hrv: nil, hrvBaseline: nil, restingHr: 102, restingHrBaseline: 100) == .good)
    }

    @Test func noBaselinesNoRecovery() {
        #expect(HealthRules.recovery(hrv: 40, hrvBaseline: nil, restingHr: 60, restingHrBaseline: nil) == nil)
    }

    // Hero priority
    @Test func heroPriorityOrder() {
        typealias S = HealthRulesTests
        #expect(HealthRules.hero(S.snapshot(sleep: S.sleep(480)), authorized: false) == .permission)
        #expect(HealthRules.hero(S.snapshot(), authorized: true) == .noData)
        #expect(HealthRules.hero(S.snapshot(sleep: S.sleep(389), recovery: S.recovery(.low)), authorized: true) == .tired)
        #expect(HealthRules.hero(S.snapshot(sleep: S.sleep(420, base: 500)), authorized: true) == .tired)  // < 85 %
        #expect(HealthRules.hero(S.snapshot(sleep: S.sleep(480), recovery: S.recovery(.low)), authorized: true) == .recovering)
        #expect(HealthRules.hero(S.snapshot(sleep: S.sleep(480), activity: S.steps(8000)), authorized: true) == .active)
        #expect(
            HealthRules.hero(S.snapshot(sleep: S.sleep(480, base: 450), recovery: S.recovery(.good)), authorized: true)
                == .rested)
        #expect(
            HealthRules.hero(
                S.snapshot(body: .init(waterCups: 0, weightKg: nil, weightTrend30d: nil, mood: .pleasant)),
                authorized: true) == .calm)
        #expect(HealthRules.hero(S.snapshot(activity: S.steps(100)), authorized: true) == .happy)
    }

    @Test func restedNeedsABaseline() {
        let s = Self.snapshot(sleep: Self.sleep(480, base: nil), recovery: Self.recovery(.good))
        #expect(HealthRules.hero(s, authorized: true) == .happy)
    }

    // Cards
    @Test func cardsDecideOnTheirOwnData() {
        let s = Self.snapshot(sleep: Self.sleep(300), activity: Self.steps(9000), recovery: Self.recovery(nil))
        #expect(HealthRules.card(.sleep, in: s) == .tired)
        #expect(HealthRules.card(.activity, in: s) == .active)
        #expect(HealthRules.card(.recovery, in: s) == .happy)
        #expect(HealthRules.card(.body, in: s) == .noData)
        #expect(HealthRules.card(.recovery, in: Self.snapshot(recovery: Self.recovery(.low))) == .recovering)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:HealthFeatureTests/HealthRulesTests`
Expected: build failure — `HealthRules` not found.

- [ ] **Step 3: Write the rules**

```swift
// Sources/HealthFeature/Data/HealthRules.swift
import Foundation
import Models

public enum HealthCategory: String, CaseIterable, Sendable {
    case sleep, activity, recovery, body
}

/// The judgements the Health workspace makes on its own, so the illustration and the numbers never depend on the
/// model: baselines, recovery relative to the user's own normal (never a medical judgement), and which Ody to show.
enum HealthRules {
    static let minimumBaselineDays = 7
    /// Under 6.5 h is short sleep whatever the baseline.
    static let tiredFloorMin = 390

    /// The median of the trailing days, once there are at least a week of them.
    static func baseline(_ values: [Double]) -> Double? {
        guard values.count >= minimumBaselineDays else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Low when HRV is 12 % or more under its baseline or resting heart rate 7 % or more over; good when HRV is within
    /// 5 % under and resting heart rate within 3 % over; fair otherwise. Either pair alone decides; neither, no answer.
    static func recovery(hrv: Double?, hrvBaseline: Double?, restingHr: Double?, restingHrBaseline: Double?)
        -> RecoveryLevel?
    {
        func delta(_ value: Double?, _ base: Double?) -> Double? {
            guard let value, let base, base > 0 else { return nil }
            return (value - base) / base
        }
        let hrvDelta = delta(hrv, hrvBaseline)
        let rhrDelta = delta(restingHr, restingHrBaseline)
        guard hrvDelta != nil || rhrDelta != nil else { return nil }
        // Rounded to basis points so 88/100 is exactly −12 %.
        let h = hrvDelta.map { ($0 * 10_000).rounded() / 10_000 }
        let r = rhrDelta.map { ($0 * 10_000).rounded() / 10_000 }
        if (h ?? 0) <= -0.12 || (r ?? 0) >= 0.07 { return .low }
        if (h ?? 0) >= -0.05 && (r ?? 0) <= 0.03 { return .good }
        return .fair
    }

    static func isTired(_ sleep: HealthSnapshot.Sleep) -> Bool {
        if sleep.asleepMin < tiredFloorMin { return true }
        if let base = sleep.baselineMin, Double(sleep.asleepMin) < Double(base) * 0.85 { return true }
        return false
    }

    /// The hero's Ody: the first that applies.
    static func hero(_ s: HealthSnapshot, authorized: Bool) -> OdyMood {
        guard authorized else { return .permission }
        if s.sleep == nil && s.activity == nil && s.recovery == nil && s.body == nil { return .noData }
        if let sleep = s.sleep, isTired(sleep) { return .tired }
        if s.recovery?.level == .low { return .recovering }
        if s.activity?.reachedGoal == true { return .active }
        if let sleep = s.sleep, let base = sleep.baselineMin, sleep.asleepMin >= base, s.recovery?.level == .good {
            return .rested
        }
        if s.body?.mood?.isPleasant == true { return .calm }
        return .happy
    }

    /// A category card's own Ody.
    static func card(_ category: HealthCategory, in s: HealthSnapshot) -> OdyMood {
        switch category {
        case .sleep:
            guard let sleep = s.sleep else { return .noData }
            return isTired(sleep) ? .tired : .rested
        case .activity:
            guard let activity = s.activity else { return .noData }
            return activity.reachedGoal ? .active : .happy
        case .recovery:
            guard let recovery = s.recovery else { return .noData }
            switch recovery.level {
            case .low: return .recovering
            case .good: return .rested
            case .fair, nil: return .happy
            }
        case .body:
            guard let body = s.body else { return .noData }
            return body.mood?.isPleasant == true ? .calm : .happy
        }
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: Step 2's command. Expected: `Test run with 10 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/HealthFeature/Data/HealthRules.swift Tests/HealthFeatureTests/HealthRulesTests.swift
git commit -m "feat(health): baselines, recovery level and which Ody to show

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/HealthFeature/Data/HealthRules.swift Tests/HealthFeatureTests/HealthRulesTests.swift
```

---

### Task 8: iOS — snapshot builder

**Files:**
- Create: `Sources/HealthFeature/Data/SnapshotBuilder.swift`
- Test: `Tests/HealthFeatureTests/SnapshotBuilderTests.swift`

**Interfaces:**
- Consumes: `HealthDataSource`, `SleepAnalyzer`, `HealthRules` (Tasks 6–7).
- Produces:
  - `public struct HealthDay: Sendable, Equatable { public var snapshot: HealthSnapshot; public var night: SleepNight? }`
  - `public struct SnapshotBuilder: Sendable { init(source: any HealthDataSource, calendar: Calendar = .current, stepGoal: Int = 8000); func build(now: Date, locale: String) async throws -> HealthDay }`
  - `SnapshotBuilder.clock(_ date: Date) -> String` ("HH:mm" in the builder's calendar), `SnapshotBuilder.day(_ date: Date) -> String` ("yyyy-MM-dd").

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/HealthFeatureTests/SnapshotBuilderTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct SnapshotBuilderTests {
    let cal = TestClock.calendar
    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: TestClock.today)! }

    /// A night of `minutes` core sleep that ends at 07:00 on the day `offset` from today.
    func night(_ offset: Int, minutes: Int, source: String = "watch") -> SleepSample {
        let wake = cal.date(byAdding: .hour, value: 7, to: day(offset))!
        return SleepSample(start: wake.addingTimeInterval(Double(-minutes * 60)), end: wake, stage: .core, source: source)
    }

    func build(_ fake: FakeHealthSource) async throws -> HealthDay {
        try await SnapshotBuilder(source: fake, calendar: cal).build(now: TestClock.now, locale: "en")
    }

    @Test func anEmptyStoreIsNoData() async throws {
        let d = try await build(FakeHealthSource())
        #expect(d.snapshot.sleep == nil && d.snapshot.activity == nil && d.snapshot.recovery == nil && d.snapshot.body == nil)
        #expect(d.snapshot.odyState == .noData)
        #expect(d.snapshot.date == "2026-10-01")
        #expect(d.snapshot.localTime == "15:00")
    }

    @Test func notYetAskedIsPermission() async throws {
        let fake = FakeHealthSource()
        await fake.set { $0.requested = false }
        #expect(try await build(fake).snapshot.odyState == .permission)
    }

    @Test func sleepWithBaselineFromThirtyPreviousNights() async throws {
        let fake = FakeHealthSource()
        let history = (1...10).map { night(-$0, minutes: 450) }
        await fake.set { $0.sleep = history + [night(0, minutes: 372)] }
        let d = try await build(fake)
        let sleep = try #require(d.snapshot.sleep)
        #expect(sleep.asleepMin == 372)
        #expect(sleep.baselineMin == 450)
        #expect(sleep.wake == "07:00")
        #expect(d.snapshot.odyState == .tired)
        #expect(d.night?.asleepMin == 372)
    }

    @Test func activityUsesTodayAndTheRingGoal() async throws {
        let fake = FakeHealthSource()
        await fake.set {
            $0.sums[.steps] = [DayValue(day: self.day(-1), value: 12000), DayValue(day: self.day(0), value: 5840)]
            $0.sums[.activeKcal] = [DayValue(day: self.day(0), value: 310.6)]
            $0.sums[.exerciseMin] = [DayValue(day: self.day(0), value: 12)]
            $0.stand = 6
            $0.goals = ActivityGoals(moveKcal: 500, exerciseMin: 30, standHours: 12)
            $0.workoutList = [WorkoutSample(start: self.day(0).addingTimeInterval(3600 * 7), minutes: 30, kcal: 200, type: "running")]
        }
        let a = try #require(try await build(fake).snapshot.activity)
        #expect(a.steps == 5840)
        #expect(a.stepGoal == 8000)
        #expect(a.activeKcal == 310)
        #expect(a.kcalGoal == 500)
        #expect(a.standHours == 6)
        #expect(a.workouts == [HealthSnapshot.Workout(type: "running", minutes: 30, kcal: 200)])
    }

    @Test func recoveryAgainstBaselines() async throws {
        let fake = FakeHealthSource()
        let past = (1...8).map { DayValue(day: self.day(-$0), value: 44) }
        let pastHr = (1...8).map { DayValue(day: self.day(-$0), value: 58) }
        await fake.set {
            $0.averages[.hrv] = past + [DayValue(day: self.day(0), value: 38)]
            $0.averages[.restingHr] = pastHr + [DayValue(day: self.day(0), value: 61)]
        }
        let r = try #require(try await build(fake).snapshot.recovery)
        #expect(r.hrvMs == 38 && r.hrvBaselineMs == 44)
        #expect(r.restingHr == 61 && r.restingHrBaseline == 58)
        #expect(r.level == .low)  // −13.6 % HRV
    }

    @Test func recoveryWithOnlyAFewDaysHasNoLevel() async throws {
        let fake = FakeHealthSource()
        await fake.set { $0.averages[.hrv] = [DayValue(day: self.day(-1), value: 40), DayValue(day: self.day(0), value: 30)] }
        let r = try #require(try await build(fake).snapshot.recovery)
        #expect(r.hrvBaselineMs == nil)
        #expect(r.level == nil)
    }

    @Test func bodyWaterWeightAndMood() async throws {
        let fake = FakeHealthSource()
        await fake.set {
            $0.sums[.waterMl] = [DayValue(day: self.day(0), value: 800)]
            $0.averages[.weightKg] = [DayValue(day: self.day(-20), value: 70.4), DayValue(day: self.day(-1), value: 69.9)]
            $0.moodList = [MoodSample(date: self.day(0).addingTimeInterval(3600 * 9), label: .pleasant)]
        }
        let b = try #require(try await build(fake).snapshot.body)
        #expect(b.waterCups == 3)
        #expect(b.weightKg == 69.9)
        #expect(abs((b.weightTrend30d ?? 0) - (-0.5)) < 0.001)
        #expect(b.mood == .pleasant)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:HealthFeatureTests/SnapshotBuilderTests`
Expected: build failure — `SnapshotBuilder` not found.

- [ ] **Step 3: Write the builder**

```swift
// Sources/HealthFeature/Data/SnapshotBuilder.swift
import Foundation
import Models

/// The day as the home screen and the report see it: the wire snapshot, plus last night's stages for the hero.
public struct HealthDay: Sendable, Equatable {
    public var snapshot: HealthSnapshot
    public var night: SleepNight?
}

/// Reads one day from a `HealthDataSource` and turns it into a `HealthDay`. Today is local midnight to `now`; each
/// baseline is the median of the 30 days before today, once there are seven of them. A category with nothing in it
/// is `nil`, so the report says nothing about it rather than "0".
public struct SnapshotBuilder: Sendable {
    let source: any HealthDataSource
    let calendar: Calendar
    let stepGoal: Int

    public init(source: any HealthDataSource, calendar: Calendar = .current, stepGoal: Int = 8000) {
        self.source = source
        self.calendar = calendar
        self.stepGoal = stepGoal
    }

    public func build(now: Date, locale: String) async throws -> HealthDay {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: today)!
        let authorized = await source.hasRequestedAuthorization()

        // Sleep: every night of the last 31, read once.
        let sleepFrom = SleepAnalyzer.window(endingOn: monthAgo, calendar: calendar).start
        let samples = try await source.sleepSamples(from: sleepFrom, to: now)
        let night = SleepAnalyzer.night(from: samples, endingOn: today, calendar: calendar)
        let pastNights = (1...30).compactMap { offset -> Double? in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return SleepAnalyzer.night(from: samples, endingOn: day, calendar: calendar).map { Double($0.asleepMin) }
        }
        let sleep = night.map { n in
            HealthSnapshot.Sleep(
                asleepMin: n.asleepMin, baselineMin: HealthRules.baseline(pastNights).map { Int($0.rounded()) },
                deepMin: n.deepMin, coreMin: n.coreMin, remMin: n.remMin, awakeMin: n.awakeMin,
                bedtime: clock(n.bedtime), wake: clock(n.wake))
        }

        // Activity: today only.
        func todaySum(_ metric: SumMetric) async throws -> Double {
            try await source.dailySums(metric, from: today, to: tomorrow).reduce(0) { $0 + $1.value }
        }
        let steps = try await todaySum(.steps)
        let kcal = try await todaySum(.activeKcal)
        let exercise = try await todaySum(.exerciseMin)
        let stand = try await source.standHours(on: today)
        let goals = try await source.activityGoals(on: today)
        let workouts = try await source.workouts(from: today, to: tomorrow)
        let hasActivity = steps > 0 || kcal > 0 || exercise > 0 || stand > 0 || !workouts.isEmpty
        let activity =
            hasActivity
            ? HealthSnapshot.Activity(
                steps: Int(steps), stepGoal: stepGoal, activeKcal: Int(kcal), kcalGoal: goals?.moveKcal,
                exerciseMin: Int(exercise), standHours: stand,
                workouts: workouts.prefix(20).map { .init(type: $0.type, minutes: $0.minutes, kcal: $0.kcal) })
            : nil

        // Recovery: today against the 30 days before.
        func todayAndBaseline(_ metric: AverageMetric) async throws -> (Double?, Double?) {
            let values = try await source.dailyAverages(metric, from: monthAgo, to: tomorrow)
            let todayValue = values.last { $0.day >= today }?.value
            return (todayValue, HealthRules.baseline(values.filter { $0.day < today }.map(\.value)))
        }
        let (hrv, hrvBase) = try await todayAndBaseline(.hrv)
        let (rhr, rhrBase) = try await todayAndBaseline(.restingHr)
        let (resp, _) = try await todayAndBaseline(.respRate)
        let recovery =
            (hrv ?? rhr ?? resp) == nil
            ? nil
            : HealthSnapshot.Recovery(
                level: HealthRules.recovery(hrv: hrv, hrvBaseline: hrvBase, restingHr: rhr, restingHrBaseline: rhrBase),
                hrvMs: hrv, hrvBaselineMs: hrvBase, restingHr: rhr, restingHrBaseline: rhrBase, respRate: resp)

        // Body & mood.
        let cups = Int(try await todaySum(.waterMl) / 250)
        let weights = try await source.dailyAverages(.weightKg, from: monthAgo, to: tomorrow)
        let trend = weights.count >= 2 ? weights.last!.value - weights.first!.value : nil
        let mood = try await source.moods(from: today, to: tomorrow).max { $0.date < $1.date }?.label
        let body =
            cups == 0 && weights.isEmpty && mood == nil
            ? nil
            : HealthSnapshot.Body(waterCups: cups, weightKg: weights.last?.value, weightTrend30d: trend, mood: mood)

        var snapshot = HealthSnapshot(
            date: Self.dayFormat(calendar).string(from: now), localTime: clock(now), locale: locale,
            sleep: sleep, activity: activity, recovery: recovery, body: body, odyState: .happy)
        snapshot.odyState = HealthRules.hero(snapshot, authorized: authorized)
        return HealthDay(snapshot: snapshot, night: night)
    }

    func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func dayFormat(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: Step 2's command. Expected: `Test run with 7 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/HealthFeature/Data/SnapshotBuilder.swift Tests/HealthFeatureTests/SnapshotBuilderTests.swift
git commit -m "feat(health): build the day's snapshot from the health store

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/HealthFeature/Data/SnapshotBuilder.swift Tests/HealthFeatureTests/SnapshotBuilderTests.swift
```

---

### Task 9: iOS — the real HealthKit source (+ DEBUG sample writer)

**Files:**
- Create: `Sources/HealthFeature/Data/HealthKitSource.swift`

**Interfaces:**
- Consumes: `HealthDataSource` (Task 6).
- Produces: `public final class HealthKitSource: HealthDataSource` (`init(store: HKHealthStore = HKHealthStore())`); DEBUG-only `func writeSampleData(now: Date) async throws` (needs write access to the sample types, requested only in DEBUG).

No unit test: HealthKit cannot run in unit tests without an entitled host and data. It is exercised by the gallery's seeded data in plan 3 and by the on-device checklist. Verify by building.

- [ ] **Step 1: Write the source**

```swift
// Sources/HealthFeature/Data/HealthKitSource.swift
import Foundation
import HealthKit
import Models

/// `HealthDataSource` over HealthKit. Reads happen in the foreground only (a locked device's store is encrypted).
public final class HealthKitSource: HealthDataSource, @unchecked Sendable {
    private let store: HKHealthStore

    public init(store: HKHealthStore = HKHealthStore()) { self.store = store }

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let readTypes: Set<HKObjectType> = [
        HKCategoryType(.sleepAnalysis), HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleExerciseTime), HKCategoryType(.appleStandHour), HKObjectType.workoutType(),
        HKObjectType.activitySummaryType(), HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.respiratoryRate), HKQuantityType(.bodyMass),
        HKQuantityType(.dietaryWater), HKObjectType.stateOfMindType(),
    ]

    static var shareTypes: Set<HKSampleType> {
        #if DEBUG
        // The gallery's "write sample data" fills the simulator's store.
        return [
            HKQuantityType(.dietaryWater), HKCategoryType(.sleepAnalysis), HKQuantityType(.stepCount),
            HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN),
        ]
        #else
        return [HKQuantityType(.dietaryWater)]
        #endif
    }

    public func hasRequestedAuthorization() async -> Bool {
        let status = try? await store.statusForAuthorizationRequest(toShare: Self.shareTypes, read: Self.readTypes)
        return status == .unnecessary
    }

    public func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    public func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: Self.range(start, end))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).compactMap { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .awake: stage = .awake
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            case .asleepUnspecified: stage = .unspecified
            default: return nil  // inBed
            }
            return SleepSample(
                start: sample.startDate, end: sample.endDate, stage: stage,
                source: sample.sourceRevision.source.bundleIdentifier)
        }
    }

    public func dailySums(_ metric: SumMetric, from start: Date, to end: Date) async throws -> [DayValue] {
        try await collection(Self.type(metric), Self.unit(metric), .cumulativeSum, from: start, to: end, step: DateComponents(day: 1))
    }

    public func hourlySums(_ metric: SumMetric, on day: Date) async throws -> [DayValue] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return try await collection(Self.type(metric), Self.unit(metric), .cumulativeSum, from: start, to: end, step: DateComponents(hour: 1))
    }

    public func dailyAverages(_ metric: AverageMetric, from start: Date, to end: Date) async throws -> [DayValue] {
        try await collection(Self.type(metric), Self.unit(metric), .discreteAverage, from: start, to: end, step: DateComponents(day: 1))
    }

    public func standHours(on day: Date) async throws -> Int {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.appleStandHour), predicate: Self.range(start, end))],
            sortDescriptors: [])
        return try await descriptor.result(for: store)
            .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
    }

    public func activityGoals(on day: Date) async throws -> ActivityGoals? {
        var components = Calendar.current.dateComponents([.year, .month, .day, .era], from: day)
        components.calendar = Calendar.current
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: HKQuery.predicate(forActivitySummariesBetweenStart: components, end: components))
        guard let summary = try await descriptor.result(for: store).first else { return nil }
        return ActivityGoals(
            moveKcal: Int(summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())),
            exerciseMin: Int(summary.exerciseTimeGoal?.doubleValue(for: .minute()) ?? 0),
            standHours: Int(summary.standHoursGoal?.doubleValue(for: .count()) ?? 0))
    }

    public func workouts(from start: Date, to end: Date) async throws -> [WorkoutSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(Self.range(start, end))], sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).map { w in
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            return WorkoutSample(
                start: w.startDate, minutes: Int(w.duration / 60), kcal: kcal.map { Int($0) },
                type: String(describing: w.workoutActivityType).lowercased())
        }
    }

    public func moods(from start: Date, to end: Date) async throws -> [MoodSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.stateOfMind(Self.range(start, end))], sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).map { MoodSample(date: $0.startDate, label: Self.label($0.valence)) }
    }

    public func logWater(milliliters: Double, at date: Date) async throws {
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryWater), quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters),
            start: date, end: date)
        try await store.save(sample)
    }

    // MARK: - Helpers

    private func collection(
        _ type: HKQuantityType, _ unit: HKUnit, _ options: HKStatisticsOptions, from start: Date, to end: Date,
        step: DateComponents
    ) async throws -> [DayValue] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: Self.range(start, end)), options: options,
            anchorDate: Calendar.current.startOfDay(for: start), intervalComponents: step)
        let collection = try await descriptor.result(for: store)
        var out: [DayValue] = []
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            let quantity = options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
            if let quantity { out.append(DayValue(day: stats.startDate, value: quantity.doubleValue(for: unit))) }
        }
        return out
    }

    private static func range(_ start: Date, _ end: Date) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    }

    private static func type(_ m: SumMetric) -> HKQuantityType {
        switch m {
        case .steps: HKQuantityType(.stepCount)
        case .activeKcal: HKQuantityType(.activeEnergyBurned)
        case .exerciseMin: HKQuantityType(.appleExerciseTime)
        case .waterMl: HKQuantityType(.dietaryWater)
        }
    }

    private static func unit(_ m: SumMetric) -> HKUnit {
        switch m {
        case .steps: .count()
        case .activeKcal: .kilocalorie()
        case .exerciseMin: .minute()
        case .waterMl: .literUnit(with: .milli)
        }
    }

    private static func type(_ m: AverageMetric) -> HKQuantityType {
        switch m {
        case .restingHr: HKQuantityType(.restingHeartRate)
        case .hrv: HKQuantityType(.heartRateVariabilitySDNN)
        case .respRate: HKQuantityType(.respiratoryRate)
        case .weightKg: HKQuantityType(.bodyMass)
        }
    }

    private static func unit(_ m: AverageMetric) -> HKUnit {
        switch m {
        case .restingHr, .respRate: .count().unitDivided(by: .minute())
        case .hrv: .secondUnit(with: .milli)
        case .weightKg: .gramUnit(with: .kilo)
        }
    }

    private static func label(_ valence: Double) -> MoodLabel {
        switch valence {
        case ..<(-0.71): .veryUnpleasant
        case ..<(-0.43): .unpleasant
        case ..<(-0.14): .slightlyUnpleasant
        case ...0.14: .neutral
        case ...0.43: .slightlyPleasant
        case ...0.71: .pleasant
        default: .veryPleasant
        }
    }
}

#if DEBUG
extension HealthKitSource {
    /// Fills the simulator's store with a believable month: nightly sleep with stages, steps, resting HR, HRV, water.
    public func writeSampleData(now: Date) async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var samples: [HKSample] = []
        for offset in 0..<30 {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let bed = cal.date(byAdding: .minute, value: -(12 + offset % 5 * 9), to: day)!  // ~23:48
            let stages: [(HKCategoryValueSleepAnalysis, Int)] = [
                (.asleepCore, 42), (.asleepDeep, 48 - offset % 3 * 6), (.asleepREM, 60), (.awake, 8),
                (.asleepCore, 150 + offset % 4 * 15), (.asleepDeep, 30), (.asleepREM, 40),
            ]
            var t = bed
            for (value, minutes) in stages {
                let end = t.addingTimeInterval(Double(minutes * 60))
                samples.append(HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: value.rawValue, start: t, end: end))
                t = end
            }
            let noon = cal.date(byAdding: .hour, value: 12, to: day)!
            func q(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ v: Double) -> HKQuantitySample {
                HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: v), start: noon, end: noon)
            }
            if offset > 0 || now > noon {
                samples.append(q(.stepCount, .count(), Double(6000 + (offset * 731) % 5000)))
            }
            samples.append(q(.restingHeartRate, .count().unitDivided(by: .minute()), Double(57 + offset % 4)))
            samples.append(q(.heartRateVariabilitySDNN, .secondUnit(with: .milli), Double(40 + offset % 7)))
        }
        try await store.save(samples)
    }
}
#endif
```

- [ ] **Step 2: Build**

Run: `tuist generate --no-open && xcodebuild build -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "generic/platform=iOS Simulator"`
Expected: BUILD SUCCEEDED. If an API name differs in the iOS 27 SDK (e.g. `HKActivitySummaryQueryDescriptor`, `.stateOfMind(_:)` predicate), look it up with `mcp__plugin_context7_context7__query-docs` for "HealthKit" and use the SDK's spelling; keep the behavior above.

- [ ] **Step 3: Commit**

```bash
git add Sources/HealthFeature/Data/HealthKitSource.swift
git commit -m "feat(health): HealthKit-backed data source

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/HealthFeature/Data/HealthKitSource.swift
```

---

### Task 10: iOS — services and local stores

**Files:**
- Create: `Sources/HealthFeature/Report/HealthServices.swift`, `Sources/HealthFeature/Report/ReportStore.swift`
- Test: `Tests/HealthFeatureTests/ReportStoreTests.swift`

**Interfaces:**
- Produces:
  - `public protocol HealthSummaryService: Sendable { func summary(for snapshot: HealthSnapshot) async throws -> HealthSummary }`, `public struct LiveHealthSummaryService: HealthSummaryService { init(apiClient: APIClient) }`
  - `public protocol MemoryWriter: Sendable { func remember(_ s: HealthSummary.MemorySuggestion) async throws }`, `public struct LiveMemoryWriter: MemoryWriter { init(apiClient: APIClient) }`
  - `public struct CachedReport: Codable, Equatable, Sendable { snapshot: HealthSnapshot; summary: HealthSummary; generatedAt: Date }`
  - `public struct ReportCache: Sendable { init(directory: URL); static func standard() -> ReportCache; func load(date: String) -> CachedReport?; func save(_ r: CachedReport) throws; var fileURL: URL }`
  - `enum ReportPolicy { static func needsRegeneration(cached: CachedReport?, current: HealthSnapshot, forced: Bool) -> Bool }`
  - `public final class HealthPreferences: @unchecked Sendable { init(defaults: UserDefaults = .standard); var summaryConsent: Bool; var hasOnboarded: Bool; func isDismissed(_ key: String) -> Bool; func dismiss(_ key: String); var lastCelebrated: String? }`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/HealthFeatureTests/ReportStoreTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct ReportStoreTests {
    static func report(date: String = "2026-10-01", state: OdyMood = .tired) -> CachedReport {
        CachedReport(
            snapshot: HealthSnapshot(
                date: date, localTime: "15:00", locale: "en", sleep: nil, activity: nil, recovery: nil, body: nil,
                odyState: state),
            summary: HealthSummary(
                headline: "h", summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
                memorySuggestion: nil),
            generatedAt: Date(timeIntervalSince1970: 0))
    }

    func tempCache() -> ReportCache {
        ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func savesAndLoadsTodaysReport() throws {
        let cache = tempCache()
        try cache.save(Self.report())
        #expect(cache.load(date: "2026-10-01") == Self.report())
        #expect(cache.load(date: "2026-10-02") == nil)
    }

    @Test func theFileIsExcludedFromBackup() throws {
        let cache = tempCache()
        try cache.save(Self.report())
        let values = try cache.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func aMissingOrCorruptFileIsNoReport() throws {
        let cache = tempCache()
        #expect(cache.load(date: "2026-10-01") == nil)
        try FileManager.default.createDirectory(at: cache.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cache.fileURL)
        #expect(cache.load(date: "2026-10-01") == nil)
    }

    @Test func regenerationPolicy() {
        let cached = Self.report()
        #expect(ReportPolicy.needsRegeneration(cached: nil, current: cached.snapshot, forced: false))
        #expect(!ReportPolicy.needsRegeneration(cached: cached, current: cached.snapshot, forced: false))
        #expect(ReportPolicy.needsRegeneration(cached: cached, current: cached.snapshot, forced: true))
        #expect(ReportPolicy.needsRegeneration(cached: cached, current: Self.report(date: "2026-10-02").snapshot, forced: false))
        #expect(ReportPolicy.needsRegeneration(cached: cached, current: Self.report(state: .active).snapshot, forced: false))
    }

    @Test func preferencesRememberConsentAndDismissals() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = HealthPreferences(defaults: defaults)
        #expect(!prefs.summaryConsent)
        prefs.summaryConsent = true
        prefs.dismiss("weekday-sleep")
        let again = HealthPreferences(defaults: defaults)
        #expect(again.summaryConsent)
        #expect(again.isDismissed("weekday-sleep"))
        #expect(!again.isDismissed("other"))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:HealthFeatureTests/ReportStoreTests`
Expected: build failure — `ReportCache` not found.

- [ ] **Step 3: Write the services**

```swift
// Sources/HealthFeature/Report/HealthServices.swift
import Foundation
import Models
import NetworkingKit

/// Writes the day's report from its snapshot. The real one asks the computer (`POST /api/v1/health/summary`).
public protocol HealthSummaryService: Sendable {
    func summary(for snapshot: HealthSnapshot) async throws -> HealthSummary
}

public struct LiveHealthSummaryService: HealthSummaryService {
    let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public func summary(for snapshot: HealthSnapshot) async throws -> HealthSummary {
        // A memory read and a model call: give it longer than a plain request.
        try await apiClient.post("/api/v1/health/summary", body: snapshot, timeout: 90)
    }
}

/// Saves a suggestion the user chose to keep, through the memory API every other client uses.
public protocol MemoryWriter: Sendable {
    func remember(_ suggestion: HealthSummary.MemorySuggestion) async throws
}

public struct LiveMemoryWriter: MemoryWriter {
    let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public func remember(_ suggestion: HealthSummary.MemorySuggestion) async throws {
        try await apiClient.post("/api/v1/memory", body: suggestion)
    }
}
```

- [ ] **Step 4: Write the stores**

```swift
// Sources/HealthFeature/Report/ReportStore.swift
import Foundation
import Models

public struct CachedReport: Codable, Equatable, Sendable {
    public var snapshot: HealthSnapshot
    public var summary: HealthSummary
    public var generatedAt: Date

    public init(snapshot: HealthSnapshot, summary: HealthSummary, generatedAt: Date) {
        self.snapshot = snapshot
        self.summary = summary
        self.generatedAt = generatedAt
    }
}

/// Today's report on disk, so reopening Health does not ask the computer again. Kept in Application Support and
/// excluded from backups: App Review does not allow health data in iCloud.
public struct ReportCache: Sendable {
    let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static func standard() -> ReportCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ReportCache(directory: base.appending(path: "Health", directoryHint: .isDirectory))
    }

    public var fileURL: URL { directory.appending(path: "report.json") }

    public func load(date: String) -> CachedReport? {
        guard let data = try? Data(contentsOf: fileURL),
            let report = try? JSONDecoder().decode(CachedReport.self, from: data), report.snapshot.date == date
        else { return nil }
        return report
    }

    public func save(_ report: CachedReport) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try HealthWire.encoder().encode(report).write(to: fileURL, options: [.atomic, .completeFileProtection])
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

/// When the report is written again: on request, on a new day, or when the day has changed enough to change Ody.
enum ReportPolicy {
    static func needsRegeneration(cached: CachedReport?, current: HealthSnapshot, forced: Bool) -> Bool {
        guard !forced, let cached else { return true }
        return cached.snapshot.date != current.date || cached.snapshot.odyState != current.odyState
    }
}

/// The small things Health remembers on this phone.
public final class HealthPreferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The user agreed to send the day's summary to their AI provider.
    public var summaryConsent: Bool {
        get { defaults.bool(forKey: "health.summaryConsent") }
        set { defaults.set(newValue, forKey: "health.summaryConsent") }
    }

    public var hasOnboarded: Bool {
        get { defaults.bool(forKey: "health.hasOnboarded") }
        set { defaults.set(newValue, forKey: "health.hasOnboarded") }
    }

    /// The day ("yyyy-MM-dd") the goal confetti last played, so it plays once a day.
    public var lastCelebrated: String? {
        get { defaults.string(forKey: "health.lastCelebrated") }
        set { defaults.set(newValue, forKey: "health.lastCelebrated") }
    }

    public func isDismissed(_ key: String) -> Bool { dismissed.contains(key) }

    public func dismiss(_ key: String) { defaults.set(Array(dismissed.union([key])), forKey: "health.dismissedSuggestions") }

    private var dismissed: Set<String> { Set(defaults.stringArray(forKey: "health.dismissedSuggestions") ?? []) }
}
```

- [ ] **Step 5: Run to verify they pass**

Run: Step 2's command. Expected: `Test run with 5 tests … passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/HealthFeature/Report/HealthServices.swift Sources/HealthFeature/Report/ReportStore.swift Tests/HealthFeatureTests/ReportStoreTests.swift
git commit -m "feat(health): report services, cache and preferences

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/HealthFeature/Report/HealthServices.swift Sources/HealthFeature/Report/ReportStore.swift Tests/HealthFeatureTests/ReportStoreTests.swift
```

---

### Task 11: iOS — `HealthHomeModel`

**Files:**
- Create: `Sources/HealthFeature/Report/HealthHomeModel.swift`
- Test: `Tests/HealthFeatureTests/HealthHomeModelTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces:
  ```swift
  @MainActor @Observable public final class HealthHomeModel {
      public enum Report: Equatable { case idle, needsConsent, writing, ready(HealthSummary), offline, needsModel, failed }
      public private(set) var day: HealthDay?
      public private(set) var report: Report
      public private(set) var suggestion: HealthSummary.MemorySuggestion?
      public private(set) var isLoading: Bool
      public private(set) var celebrates: Bool       // goal reached and not yet celebrated today
      public let preferences: HealthPreferences
      public init(source: any HealthDataSource, summaries: any HealthSummaryService, memory: any MemoryWriter,
                  cache: ReportCache, preferences: HealthPreferences, calendar: Calendar = .current,
                  now: @escaping @Sendable () -> Date = { Date() }, locale: String)
      public func load(force: Bool = false) async
      public func authorize() async
      public func grantConsent() async
      public func remember() async -> Bool
      public func dismissSuggestion()
      public func didCelebrate()
      public func logWater() async
      public static func reportState(for error: Error) -> Report
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/HealthFeatureTests/HealthHomeModelTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

actor StubSummaries: HealthSummaryService {
    var result: Result<HealthSummary, Error>
    var calls = 0
    init(_ result: Result<HealthSummary, Error>) { self.result = result }
    func set(_ r: Result<HealthSummary, Error>) { result = r }
    func summary(for snapshot: HealthSnapshot) async throws -> HealthSummary {
        calls += 1
        return try result.get()
    }
}

actor StubMemory: MemoryWriter {
    var saved: [HealthSummary.MemorySuggestion] = []
    var fails = false
    func setFails() { fails = true }
    func remember(_ s: HealthSummary.MemorySuggestion) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        saved.append(s)
    }
}

@MainActor
struct HealthHomeModelTests {
    static let suggestion = HealthSummary.MemorySuggestion(section: "profile", key: "weekday-sleep", summary: "s")
    static let summary = HealthSummary(
        headline: "h", summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
        memorySuggestion: suggestion)

    let source = FakeHealthSource()
    let summaries = StubSummaries(.success(summary))
    let memory = StubMemory()
    let prefs = HealthPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let cache = ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))

    func model() -> HealthHomeModel {
        HealthHomeModel(
            source: source, summaries: summaries, memory: memory, cache: cache, preferences: prefs,
            calendar: TestClock.calendar, now: { TestClock.now }, locale: "en")
    }

    func withData() async {
        await source.set { $0.sums[.steps] = [DayValue(day: TestClock.today, value: 9000)] }
    }

    @Test func withoutConsentThereIsDataButNoReport() async {
        await withData()
        let m = model()
        await m.load()
        #expect(m.day?.snapshot.activity?.steps == 9000)
        #expect(m.report == .needsConsent)
        #expect(await summaries.calls == 0)
    }

    @Test func withConsentTheReportIsWrittenAndCached() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        #expect(m.report == .ready(Self.summary))
        #expect(m.suggestion == Self.suggestion)
        #expect(cache.load(date: "2026-10-01")?.summary == Self.summary)

        let again = model()
        await again.load()
        #expect(again.report == .ready(Self.summary))
        #expect(await summaries.calls == 1)  // the cache answered
    }

    @Test func forceRewrites() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        await m.load(force: true)
        #expect(await summaries.calls == 2)
    }

    @Test func errorsMapToStates() {
        #expect(HealthHomeModel.reportState(for: URLError(.cannotConnectToHost)) == .offline)
        #expect(HealthHomeModel.reportState(for: HTTPError(statusCode: 400, code: "CONFIG_MISSING_PROVIDER", message: "")) == .needsModel)
        #expect(HealthHomeModel.reportState(for: HTTPError(statusCode: 404, code: "SETTING_NOT_FOUND", message: "")) == .needsModel)
        #expect(HealthHomeModel.reportState(for: HTTPError(statusCode: 500, code: "AI_GENERATION_FAILED", message: "")) == .failed)
    }

    @Test func anOfflineComputerStillShowsTheDay() async {
        await withData()
        prefs.summaryConsent = true
        await summaries.set(.failure(URLError(.cannotConnectToHost)))
        let m = model()
        await m.load()
        #expect(m.report == .offline)
        #expect(m.day != nil)
        #expect(!m.isLoading)
    }

    @Test func rememberSavesAndClearsTheSuggestion() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        #expect(await m.remember())
        #expect(await memory.saved == [Self.suggestion])
        #expect(m.suggestion == nil)
    }

    @Test func aFailedRememberKeepsTheSuggestion() async {
        await withData()
        prefs.summaryConsent = true
        await memory.setFails()
        let m = model()
        await m.load()
        #expect(await !m.remember())
        #expect(m.suggestion == Self.suggestion)
    }

    @Test func aDismissedSuggestionStaysDismissed() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        m.dismissSuggestion()
        #expect(m.suggestion == nil)
        await m.load(force: true)
        #expect(m.suggestion == nil)
    }

    @Test func celebrationPlaysOncePerDay() async {
        await withData()  // 9000 ≥ 8000
        let m = model()
        await m.load()
        #expect(m.celebrates)
        m.didCelebrate()
        await m.load()
        #expect(!m.celebrates)
    }

    @Test func loggingWaterWritesAndReloads() async {
        await withData()
        let m = model()
        await m.load()
        await m.logWater()
        #expect(await source.loggedWater == [250])
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:HealthFeatureTests/HealthHomeModelTests`
Expected: build failure — `HealthHomeModel` not found.

- [ ] **Step 3: Write the model**

```swift
// Sources/HealthFeature/Report/HealthHomeModel.swift
import Foundation
import Models
import Observation

/// The home screen's state: the day read from the health store, and the report written about it. The day always
/// shows; the report needs consent and a reachable computer with a model, and says which one is missing.
@MainActor
@Observable
public final class HealthHomeModel {
    public enum Report: Equatable {
        case idle
        case needsConsent
        case writing
        case ready(HealthSummary)
        case offline
        case needsModel
        case failed
    }

    public private(set) var day: HealthDay?
    public private(set) var report: Report = .idle
    public private(set) var suggestion: HealthSummary.MemorySuggestion?
    public private(set) var isLoading = false
    public private(set) var celebrates = false
    public let preferences: HealthPreferences

    @ObservationIgnored private let source: any HealthDataSource
    @ObservationIgnored private let summaries: any HealthSummaryService
    @ObservationIgnored private let memory: any MemoryWriter
    @ObservationIgnored private let cache: ReportCache
    @ObservationIgnored private let builder: SnapshotBuilder
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let locale: String

    public init(
        source: any HealthDataSource, summaries: any HealthSummaryService, memory: any MemoryWriter,
        cache: ReportCache, preferences: HealthPreferences, calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }, locale: String
    ) {
        self.source = source
        self.summaries = summaries
        self.memory = memory
        self.cache = cache
        self.preferences = preferences
        self.builder = SnapshotBuilder(source: source, calendar: calendar)
        self.now = now
        self.locale = locale
    }

    public func load(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        let built: HealthDay
        do {
            built = try await builder.build(now: now(), locale: locale)
        } catch {
            report = .failed
            return
        }
        day = built
        let snapshot = built.snapshot
        celebrates = snapshot.activity?.reachedGoal == true && preferences.lastCelebrated != snapshot.date

        guard snapshot.odyState != .permission, snapshot.odyState != .noData else {
            report = .idle
            suggestion = nil
            return
        }
        guard preferences.summaryConsent else {
            report = .needsConsent
            return
        }
        let cached = cache.load(date: snapshot.date)
        if !ReportPolicy.needsRegeneration(cached: cached, current: snapshot, forced: force), let cached {
            show(cached.summary)
            return
        }
        report = .writing
        do {
            let summary = try await summaries.summary(for: snapshot)
            try? cache.save(CachedReport(snapshot: snapshot, summary: summary, generatedAt: now()))
            show(summary)
        } catch {
            // A report from earlier today beats an error.
            if let cached { show(cached.summary) } else { report = Self.reportState(for: error) }
        }
    }

    public func authorize() async {
        try? await source.requestAuthorization()
        preferences.hasOnboarded = true
        await load()
    }

    public func grantConsent() async {
        preferences.summaryConsent = true
        await load()
    }

    /// Saves the suggestion as a memory. False when it could not be saved; the card stays.
    public func remember() async -> Bool {
        guard let suggestion else { return false }
        do {
            try await memory.remember(suggestion)
            preferences.dismiss(suggestion.key)
            self.suggestion = nil
            return true
        } catch {
            return false
        }
    }

    public func dismissSuggestion() {
        guard let suggestion else { return }
        preferences.dismiss(suggestion.key)
        self.suggestion = nil
    }

    public func didCelebrate() {
        preferences.lastCelebrated = day?.snapshot.date
        celebrates = false
    }

    /// One cup (250 ml) into Apple Health, then the day again.
    public func logWater() async {
        try? await source.logWater(milliliters: 250, at: now())
        await load()
    }

    public static func reportState(for error: Error) -> Report {
        if error is URLError { return .offline }
        if let http = error as? HTTPError, http.code.hasPrefix("CONFIG_") || http.code == "SETTING_NOT_FOUND" {
            return .needsModel
        }
        return .failed
    }

    private func show(_ summary: HealthSummary) {
        report = .ready(summary)
        if let s = summary.memorySuggestion, !preferences.isDismissed(s.key) {
            suggestion = s
        } else {
            suggestion = nil
        }
    }
}
```

Check how `APIClient` reports an unreachable computer: open `Sources/NetworkingKit/APIClient.swift` (`send`) and `ServerConnection.swift`. If it wraps transport failures in its own error type instead of passing `URLError` through, add that type to the `.offline` branch of `reportState(for:)` and a matching line to `errorsMapToStates`.

- [ ] **Step 4: Run to verify they pass**

Run: Step 2's command. Expected: `Test run with 10 tests … passed`.

- [ ] **Step 5: Run the whole HealthFeature and Models suites**

Run: `xcodebuild test … -scheme HealthFeature …` and `xcodebuild test … -scheme Models …`
Expected: both pass, with `Test run with` counts that include the new suites.

- [ ] **Step 6: Commit**

```bash
git add Sources/HealthFeature/Report/HealthHomeModel.swift Tests/HealthFeatureTests/HealthHomeModelTests.swift
git commit -m "feat(health): the home model — day, report, suggestions, celebration, water

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/HealthFeature/Report/HealthHomeModel.swift Tests/HealthFeatureTests/HealthHomeModelTests.swift
```
