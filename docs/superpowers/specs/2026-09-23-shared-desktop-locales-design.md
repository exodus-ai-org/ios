# exodus-ios: shared desktop locales — design

Status: design approved by the user in conversation (2026-09-23); spec written, not yet reviewed

## 1. Context and goal

Today, exodus (desktop) and exodus-ios each own their translations independently. The one bridge
is `scripts/l10n.py seed-from-desktop LOCALES_DIR`: given a local checkout of the desktop repo, it
copies the desktop's translation of any iOS catalog key whose **English text is byte-for-byte equal**
to one of the desktop's own English strings (`cmd_seed` in `scripts/l10n.py`). This is a real,
working mechanism — 2026-09-19's i18n pass used it to seed most of the 70 keys the app ships today
— but it has two problems this design is for:

1. **Fragile matching.** A wording tweak on either side (even fixing a typo) silently breaks the
   match — the key falls into the "skipped, needs manual translation" bucket with no error, and an
   already-seeded key keeps its stale translation forever (`locs.setdefault(...)` never overwrites).
2. **Templated strings don't sync at all.** `cmd_seed` explicitly skips any desktop string whose
   text contains `{{` — i18next's interpolation syntax — so every parameterized string (a count, a
   name, a date) is 100% manually translated on iOS today, with no path to ever share the desktop's
   wording.

The result is real duplicate authoring for the strings that exist on both sides, and it's the
standing bottleneck on iOS's own i18n progress: someone has to notice a desktop string changed,
re-run the script, and manually re-translate anything the fragile match missed.

**Goal:** eliminate the duplicate authoring for shared vocabulary, keep the sync reliable
(a wording change on the desktop should either update the iOS translation or announce itself
loudly, never silently drift), and bring templated strings in scope. Not a redesign of exodus's own
i18n (already solid — `bun run i18n:check`, `catalog-audit.ts`) or of iOS's App Shell / anything
this spec doesn't name.

## 2. Non-goals

- Any change to exodus (desktop). Everything here reads exodus's git history; nothing in exodus's
  own code or CI needs to change for this to work.
- A new hosting/publishing pipeline (no S3, no package registry, no third repo). See §3.
- Automating iOS-only strings ("Allow Exodus to use the camera…", the drawer's accessibility
  labels) — they have no desktop counterpart and stay independently authored, exactly as today.
- An in-app language switcher, RTL, or adding `zh-Hans` as a real (non-fallback) locale — all
  already explicit non-goals of the 2026-09-19 i18n design and unaffected by this one.
- CI enforcement of freshness (a PR fails if the vendored copy is stale). Proposed as a fast-follow
  in §7, not required to ship v1.

## 3. Delivery: `git subtree`, not a new repo

`packages/shared/src/i18n/locales` (exodus) is vendored into exodus-ios via `git subtree`, e.g.:

```
git subtree add --prefix Vendor/exodus-locales \
  git@github.com:exodus-ai-org/exodus.git master \
  --squash -- packages/shared/src/i18n/locales
```

(the exact subtree invocation for a *subdirectory* of the source repo needs `git subtree split`
first to produce a synthetic branch containing only that path's history, then `subtree add` from
that branch — the plan's first task works out the precise command and commits the result, since
`git subtree` on a subdirectory is fussier than a whole-repo subtree and is worth getting right
once rather than re-deriving it each pull).

Re-pulled on demand (`git subtree pull ...`) whenever a developer wants fresh strings — no network
dependency at sync-script run time beyond what `git subtree pull` itself needs, no new
infrastructure, and **exodus needs zero code changes**: this only ever reads exodus's existing git
history at the one path it already treats as the real source.

Alternatives considered: a new dedicated `exodus-locales` repo (decouples the pair, but adds a third
repo and a second sync direction — exodus would need to push *into* it — for no benefit given
there are exactly two consumers); exodus's CI publishing the locale JSON as a release asset /
static URL (adds a publish step and a version-pinning question — *which* published version does a
given iOS commit target — that subtree's git history already answers for free).

## 4. Key format: adopt exodus's own, verbatim

iOS's ~70 existing keys are the English source text (`"Search"`, `"Cancel"`) — idiomatic Apple
String Catalog style, and what lets `Text("Search")` localize with no extra call. This design
replaces that with exodus's own `<namespace>:<dotted.path>` convention exactly
(`chat:composer.placeholder`, `menu:newChat`) — the same key format already used throughout
exodus's own `t()` calls (CLAUDE.md: "dot-nested, component-scoped"). A human reading either
codebase for the same string sees the same key.

This is the one call in this design that costs the most: every existing iOS call site
(`Text("Search")`, `.navigationTitle("Chat")`, …) moves from a literal to a symbolic key. It buys
exact, stable matching — a wording change on the desktop updates the iOS translation automatically
instead of silently breaking a text-equality check — and is what makes §6's templated-string
support possible at all (there is no reliable way to match a `{{param}}`-bearing English sentence
against a `%@`-bearing Swift interpolation by *text*; by *key* it's exact).

**Needs verifying before the plan commits to it (Task 0):** the exact mechanics of
`String(localized:defaultValue:comment:)` — the initializer that takes a symbolic key separate
from the displayed text — for a string *with* interpolated arguments, specifically: does Xcode's
String Catalog editor correctly derive the per-locale `%@` positions from the `defaultValue`
argument's interpolations, and does a key defined this way audit and build identically to one
declared as a plain `Text("literal")`? This needs a real Xcode project, which nothing in this
environment can drive — a five-minute spike in a scratch project, not a design risk, but the plan's
first task, before any real migration work.

## 5. Placeholders: everything is `%@`

`{{name}}` → `%@`, never `%lld`/`%ld` for a numeric param. Two reasons: Foundation's positional
specifiers must agree on *type* across every locale's translation of a key, and there is no
type information in exodus's own JSON catalogs to convert from (a `{{count}}` is just a JS value
i18next stringifies) — inferring it would mean parsing every call site's TypeScript, out of
proportion to what this buys. Instead, every interpolated argument becomes a `String` at the
call site, same discipline exodus's own `useFormat()` already enforces ("never build a sentence by
splicing a hand-formatted date/number into raw English word order"): a count is formatted via
`Int.formatted()` or the locale's own `NumberFormatter`, a date via `Date.FormatStyle`, *then*
interpolated. This is a convention the plan documents and the audit script (§6) can check for
(a raw `Int`/`Date` argument to a symbolic-key `String(localized:)` call is a lint-able mistake,
not just a style preference).

Argument *order* is derived once from the desktop's own English source (first-occurrence order of
`{{name}}` in the `en` catalog) and is fixed per key across every locale — a translation is free to
reorder where `%1$@`/`%2$@` *appear* in its own sentence (positional specifiers exist for exactly
this), but the desktop's param names always map to the same argument index.

## 6. Tooling: extend `scripts/l10n.py`, don't replace it

`seed-from-desktop` (English-text matching) is replaced by `sync-from-desktop`, reading the vendored
subtree at a fixed, known path (`Vendor/exodus-locales`, no `--locales-dir` argument needed once
vendored — simpler than today's invocation) and:

1. Flattens every `packages/shared/src/i18n/locales/<locale>/<namespace>.json` into
   `<namespace>:<dotted.path>` → text, exactly mirroring how exodus's own `t()` resolves a key.
2. For a key that exists in **both** catalogs: the desktop is authoritative. Converts `{{param}}`
   → `%@` per §5 and writes/overwrites the iOS catalog entry for every shipped language (this *does*
   overwrite, unlike today's `seed-from-desktop` — staleness is the bug being fixed, so a changed
   desktop translation must actually update iOS, not be silently skipped because a value is
   already there).
3. A key that exists only in iOS's own catalog is untouched — independently translated, exactly
   today's behavior for iOS-only strings (the camera permission text, drawer accessibility labels).
4. A key that exists only in the desktop's catalog and *not* yet in iOS's is not created — iOS opts
   in to a shared string by using its symbolic key at a call site first (same flow as `cmd_add`
   today), the same way a new desktop string doesn't appear on iOS until something reads it there.

`audit_catalog`'s `implicit_source=True` call (today's assumption that the *key itself* is the
English source, since key ≡ English text) becomes `implicit_source=False` for `Localizable.xcstrings`
— every entry now carries a real `en` `stringUnit`, populated either by `sync-from-desktop` (shared
keys) or by hand (iOS-only keys, via `cmd_add`'s existing `--en-value`). `audit_sources`' matching
(`match_key`, today matching literal English text against the catalog's keys) simplifies to an exact
string match against the symbolic key that a call site's first `String(localized:)` argument names
— no more building an interpolation-placeholder regex from the *displayed* text.

## 7. What ships now vs. later

**v1** (this design's scope): `sync-from-desktop`, the key-format migration for existing strings,
the audit changes, run by hand — a developer pulls the subtree, runs the sync script, commits the
result, same rhythm as today's manual `seed-from-desktop` but reliable instead of fragile, and now
covering templated strings.

**Fast-follow, not v1:** a CI job that re-runs `sync-from-desktop` against the currently-vendored
subtree and fails the PR if `Localizable.xcstrings` would change — closes the loop so nobody can
merge iOS code against a stale translation, at the cost of needing the subtree kept reasonably
current (a stale subtree just means CI checks against an old desktop snapshot, not a false
failure). Left for later since v1 alone already removes the duplicate-authoring problem the desktop
side cares about; the enforcement layer is a nice-to-have on top, not the blocker.

## 8. Testing and verification

- `l10n.py`'s own tests (if any exist today — the plan's first task checks) extended for
  `sync-from-desktop`: a fixture desktop locales tree in, the expected catalog mutations out;
  overwrite-on-change behavior; a templated key's `%@` conversion and argument-order stability
  across locales; a key present only on one side is left alone.
- `python3 scripts/l10n.py audit` goes green against the migrated catalog and the migrated call
  sites — this is the existing audit, now running with `implicit_source=False`.
- The Task 0 spike (§4) is verified and its findings folded into the plan before the real
  migration task is written — if `String(localized:defaultValue:)` doesn't behave as expected for
  templated keys, this section (and possibly §5's placeholder scheme) needs revisiting before
  the plan proceeds past that one task.

## 9. Risks and known limits

- **Task 0's outcome is a real open question**, not a formality — see §4. Everything downstream of
  templated-string support depends on it.
- `git subtree` on a subdirectory (not a whole repo) is the fussier form of an already-fussy
  command; getting the initial split right is worth deliberate care, not a quick guess.
- Migrating ~70 existing call sites from literal to symbolic keys is mechanical but real work,
  and worth a careful pass rather than a blind find-and-replace (a few keys carry a `comment` for
  disambiguation today — e.g. "Chat" the workspace vs. "Chat" the fallback title — that context
  must survive the migration).
- `sync-from-desktop` now overwriting on every run (§6.2) means a hand-edited iOS translation for a
  *shared* key would be silently clobbered on the next sync — if that's ever wanted (an iOS-specific
  wording tweak on an otherwise-shared string), the key should be renamed to something iOS-only,
  or the sync tool needs an explicit override list, neither of which this design has a strong
  opinion on yet: cross that bridge if it comes up, rather than build for it speculatively.
