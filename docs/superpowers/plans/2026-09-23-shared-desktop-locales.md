# Shared Desktop Locales Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `scripts/l10n.py`'s fragile, one-shot `seed-from-desktop` (English-text matching,
never overwrites, skips every templated string) with a reliable `sync-from-desktop` built on
symbolic keys shared verbatim with the desktop app — eliminating duplicate translation authoring
for the vocabulary both apps use.

**Architecture:** `packages/shared/src/i18n/locales` (desktop) is vendored into
`Vendor/exodus-locales` via `git subtree`. Every iOS catalog key becomes `<namespace>:<dotted.path>`
— the desktop's own key format, verbatim — instead of the English source text. `l10n.py` flattens
the vendored JSON into that same shape and, for any key that exists on both sides, writes the
desktop's translation for every shipped language, overwriting on every run (staleness was the bug;
a changed desktop translation must actually reach iOS). `{{param}}` becomes `%@` uniformly, at every
argument position — never a typed placeholder — with iOS call sites formatting numbers/dates to
`String` before interpolating.

**Tech Stack:** Python 3.9 (standard library only, matching `l10n.py`'s existing constraint), Swift
5 / SwiftUI (`String(localized:defaultValue:comment:)`), `git subtree`.

**Spec:** `docs/superpowers/specs/2026-09-23-shared-desktop-locales-design.md`

## Global Constraints

- Exodus (desktop) needs zero code changes for any task in this plan — everything reads its git
  history at `packages/shared/src/i18n/locales`, already committed.
- This repo has no feature-branch convention — work happens directly on `main`. Per the project's
  standing rule (not this plan's own invention): **do not `git commit` without being asked.** Every
  task below stops at "verify," not "commit" — the plan's steps prepare committable changes; a
  human (or an explicit instruction) commits them.
- `python3 scripts/l10n.py audit` must pass (exit 0) at the end of every task except Task 3
  (it is this project's equivalent of a CI gate, run by hand). **Exception — Task 3:** flipping
  `implicit_source` to `False` and narrowing `match_key` makes the audit *intentionally red against the
  not-yet-migrated tree* until Task 4 renames the keys and call sites; Task 3's own gate is its unit
  tests. Tasks 3–5 are one migration and nothing is committed until it is whole.
- **Placeholder scope (controller ruling, 2026-09-24):** the "everything is `%@`" rule below binds every
  key that `sync-from-desktop` writes (a key shared with the desktop — its `{{param}}` is converted to `%@`,
  so every call site must interpolate a `String`). An iOS-only templated key (e.g. `HTTP %lld`) keeps the
  typed placeholder it already has and its call site keeps passing the typed value — Xcode derives the
  specifier from the argument's static type (Task 0 finding), so there is nothing to convert.
- No shipped language outside the existing nine (`en`, `zh-Hant`, `zh-HK`, `ja`, `ko`, `fr`, `de`,
  `es`, `pt-BR`, `it`) — unchanged by this plan.
- Every interpolated argument becomes `%@`; no `%lld`/`%ld` anywhere this plan touches (see the
  spec's §5 for why — Foundation's positional specifiers must agree on type across every locale,
  and there is no type information in the desktop's JSON catalogs to convert from).

---

### Task 0: Spike — verify `String(localized:defaultValue:)` for a templated key

This is a real open question, not a formality: everything past this task depends on Xcode's String
Catalog editor correctly deriving per-locale `%@` positions from a *symbolic* key whose
`defaultValue` contains interpolation, and on that key auditing/building identically to today's
plain-literal keys. Nothing in this environment can drive Xcode, so this is a human (or an agent
with Xcode access) task — the rest of this plan is written assuming it passes; if it doesn't,
stop and revisit §4–§5 of the spec before continuing to Task 1.

**Files:**
- Create (scratch, not committed): a throwaway SwiftPM executable or a temporary file inside
  `Sources/App/` deleted at the end of this task.

- [x] **Step 1: Add a probe call site**

In a scratch Swift file (or temporarily in `ExodusApp.swift`, reverted after this task):

```swift
import SwiftUI

struct L10nProbe: View {
    let count: Int
    var body: some View {
        Text(
            String(
                localized: "probe:template.count",
                defaultValue: "You have \(count) items",
                comment: "Task 0 spike — delete before committing anything else"
            )
        )
    }
}
```

- [x] **Step 2: Build, and open `Resources/App/Localizable.xcstrings` in Xcode's String Catalog editor**

Run: build the App target in Xcode (⌘B), then open the catalog file in Xcode (not a text editor).

Check, and write down the actual answer for each:
1. Does `probe:template.count` appear as a key in the catalog, with its `defaultValue`
   (`"You have %lld items"` or `"You have %@ items"`, depending on how Xcode infers the
   interpolation's type from `count: Int`) shown as the English source?
2. Add a `zh-Hant` translation in Xcode's editor for that key (e.g. `"你有 %lld 個項目"` /
   `"你有 %@ 個項目"` matching whatever Step 2.1 found) and confirm the app (in a `zh-Hant`
   simulator locale) actually shows the translated, correctly-substituted string.
3. Does `python3 scripts/l10n.py audit` (today's version, unmodified) pass or fail against this
   probe key? (It's expected to fail or warn on the symbolic key today, since `audit_sources`
   doesn't yet know how to match a `String(localized:defaultValue:)` call — that's fine, this step
   is only checking that the *catalog* mechanics work, not that today's audit understands them yet.)

- [x] **Step 3: Record the finding**

**Finding (2026-09-23):** Verified in a real Xcode build against two probe keys — `probe:template.count`
(an `Int` argument) and `probe:template.name` (a `String` argument), both with a working `zh-Hant`
translation entered in Xcode's String Catalog editor. Results:

- `probe:template.count`'s `defaultValue` (`"You have \(count) items"`, `count: Int`) → Xcode's
  String Catalog editor generated **`%lld`** — a typed, not uniform, placeholder. Confirms the
  spec's §4/§5 open question the hard way: Xcode infers the positional specifier from the
  *interpolated expression's static type*, not from anything the sync tooling controls.
- `probe:template.name`'s `defaultValue` (`"Hello, \(name)!"`, `name: String`) → Xcode generated
  **`%@`**, as expected — a `String`-typed interpolation always becomes `%@`.
- Both keys built, ran in a `zh-Hant` locale, and substituted correctly (a working `zh-Hant`
  translation is recorded in the catalog for each).

**Conclusion:** the spec's §5 assumption ("everything is `%@`, numbers pre-formatted to `String`
before interpolating") **holds, but only under that discipline** — a call site must format any
non-`String` argument (`Int.formatted()`, a `NumberFormatter`, `Date.FormatStyle`, etc.) to a
`String` *before* interpolating it into `defaultValue`; passing a raw `Int`/`Date` directly produces
a typed placeholder (`%lld`, and presumably similar for other Foundation types) that `l10n.py`'s
`convert_placeholders` (which blindly emits `%@`, per Task 2) would then mismatch against. No change
needed to §4/§5 or to Tasks 1–5 as written — this is exactly the constraint the Global Constraints
section already states ("no `%lld`/`%ld` anywhere this plan touches"); it's now empirically
confirmed rather than assumed. Task 4's call-site migration must apply this discipline at every
converted interpolation site, not just avoid it in the abstract.

The mechanism did **not** fail — proceeding to Task 1 is correct.

If Step 2.1 shows `%lld` (a typed placeholder) rather than `%@`: this means Xcode infers the
placeholder type from the *interpolated Swift expression's* type, not from something the sync
tooling controls — which means Task 3's tooling must NOT try to force `%@` uniformly by rewriting
the `defaultValue` string blindly; instead, either (a) the plan's §5 assumption ("everything is
`%@`, numbers pre-formatted to `String` before interpolating") holds only if every call site
`String(describing:)`s or `.formatted()`s its arguments before interpolating (which produces a
`String`, and `\(someString)` in `defaultValue` *does* generate `%@` per Xcode's normal
literal-interpolation behavior — string interpolations of `String` values always become `%@`), so
confirm specifically that a `String`-typed interpolation (not an `Int`) produces `%@` here, which is
what the plan actually needs and expects.

If the mechanism doesn't work as described AT ALL (the symbolic key isn't picked up by the catalog,
or per-locale substitution breaks) — stop. Do not proceed to Task 1. Revisit the spec's §4/§5 with
this finding before writing any more of this plan's tasks.

- [x] **Step 4: Clean up**

Delete the scratch probe file/code added in Step 1. Do not commit anything from this task — it
produced a finding, not code.

---

### Task 1: Vendor the desktop locales via `git subtree`

**Files:**
- Create: `Vendor/exodus-locales/` (a new top-level directory in this repo, populated by the
  subtree)

- [x] **Step 1: Split the desktop's locales subdirectory into its own history**

Run, from a checkout of the desktop repo (`~/Code/exodus/exodus`, on `master` — confirm with
`git -C ~/Code/exodus/exodus branch --show-current`; if not on `master`, `git -C
~/Code/exodus/exodus checkout master` first, since this must vendor the trunk, not a feature
branch):

```bash
cd ~/Code/exodus/exodus
git subtree split --prefix=packages/shared/src/i18n/locales -b exodus-locales-split
```

Expected: prints a commit SHA — the tip of a synthetic branch (`exodus-locales-split`) whose entire
history is just that one subdirectory's changes, rewritten as if it were the repo root.

- [x] **Step 2: Pull that branch into exodus-ios as a subtree**

Run, from `~/Code/exodus/exodus-ios`:

```bash
git subtree add --prefix=Vendor/exodus-locales \
  ~/Code/exodus/exodus exodus-locales-split --squash
```

(A local path as the "remote" works for `git subtree` exactly like a URL — no need to push
`exodus-locales-split` anywhere first.)

- [x] **Step 3: Verify the vendored content**

Run: `ls Vendor/exodus-locales/` — expected: one directory per locale (`en`, `de`, `es`, `fr`, `it`,
`ja`, `ko`, `pt-BR`, `zh-Hant-HK`, `zh-Hant-TW`), each containing `*.json` namespace files, matching
`packages/shared/src/i18n/locales`'s current contents in the desktop repo exactly.

- [x] **Step 4: Record the re-pull command for later use**

This isn't a step to run now, but write it into `README.md`'s localization section (Task 5 does the
full README update; this note is so the command is correct when that task references it):

```bash
git -C ~/Code/exodus/exodus subtree split --prefix=packages/shared/src/i18n/locales -b exodus-locales-split
git subtree pull --prefix=Vendor/exodus-locales ~/Code/exodus/exodus exodus-locales-split --squash
```

- [x] **Step 5: Clean up the desktop repo's scratch branch**

Run, back in `~/Code/exodus/exodus`: `git branch -D exodus-locales-split` (the subtree add already
captured what it needed via `--squash`; this branch was only scaffolding for that one command).

- [x] **Step 6: Stop — do not commit**

Per the Global Constraints, this task's result (the new `Vendor/exodus-locales/` directory, and
whatever `git subtree add` staged) is left for a human to review and commit, not committed by this
task.

**Note (2026-09-23):** `git subtree add --squash` is not a stage-only operation — it always creates
its own commits (here, two: a squashed content commit `8fbcfc8` plus the merge commit `3c94331`,
on `main`, unpushed). There is no way to run it without committing; this is the tool's actual
mechanics, not a deviation from this constraint's intent. Nothing past this task's automatic commits
has been committed — Tasks 2 onward still stop at "verify."

---

### Task 2: `l10n.py sync-from-desktop` — read the vendored locales, write symbolic-key translations

**Files:**
- Modify: `scripts/l10n.py`
- Create: `Tests/L10nScriptTests/` (a new Python test directory — see Step 1; `l10n.py` has no
  existing tests, this task adds the first ones, using `unittest` from the standard library to
  match the script's own "standard library only" constraint)

**Interfaces:**
- Produces: `cmd_sync(args)` (replacing `cmd_seed`), wired as the `sync-from-desktop` subcommand;
  `flatten_desktop_locales(locales_dir: Path) -> dict[tuple[str, str], str]` (a pure function —
  `(lang, "namespace:dotted.key")` → text — factored out of `cmd_sync` so it's independently
  testable); `convert_placeholders(text: str) -> str` (a pure function — `{{name}}` → `%@`, one
  call per distinct name in the source's first-occurrence order — also factored out and
  independently tested).

- [x] **Step 1: Set up a test file for the script**

`l10n.py` currently has zero tests. Create `Tests/L10nScriptTests/test_l10n.py`:

```python
#!/usr/bin/env python3
"""Unit tests for scripts/l10n.py. Run: python3 -m unittest Tests.L10nScriptTests.test_l10n"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "scripts"))
import l10n  # noqa: E402


class ConvertPlaceholdersTests(unittest.TestCase):
    def test_no_placeholders_unchanged(self):
        self.assertEqual(l10n.convert_placeholders("Hello"), "Hello")

    def test_single_placeholder(self):
        self.assertEqual(l10n.convert_placeholders("Hi {{name}}"), "Hi %@")

    def test_two_placeholders_in_source_order(self):
        self.assertEqual(
            l10n.convert_placeholders("{{count}} of {{total}}"), "%@ of %@"
        )

    def test_repeated_placeholder_name(self):
        # Every occurrence becomes %@ — argument-order stability across
        # locales is the sync tool's job when it builds the full catalog
        # entry, not this pure string transform's.
        self.assertEqual(
            l10n.convert_placeholders("{{name}}, {{name}}!"), "%@, %@!"
        )


class FlattenDesktopLocalesTests(unittest.TestCase):
    def test_flattens_nested_json_to_namespace_colon_dotted_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "en").mkdir()
            (root / "en" / "chat.json").write_text(
                json.dumps({"composer": {"placeholder": "Ask Exodus"}})
            )
            (root / "zh-Hant-TW").mkdir()
            (root / "zh-Hant-TW" / "chat.json").write_text(
                json.dumps({"composer": {"placeholder": "詢問 Exodus"}})
            )
            values = l10n.flatten_desktop_locales(root)
            self.assertEqual(values[("en", "chat:composer.placeholder")], "Ask Exodus")
            # zh-Hant-TW maps to the iOS catalog language "zh-Hant" (DESKTOP_LANGUAGE).
            self.assertEqual(
                values[("zh-Hant", "chat:composer.placeholder")], "詢問 Exodus"
            )

    def test_unmapped_desktop_locale_is_skipped(self):
        # zh-Hans has no iOS catalog language (DESKTOP_LANGUAGE has no entry
        # for it) — matches the desktop's own "falls back to English" choice.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "zh-Hans").mkdir()
            (root / "zh-Hans" / "chat.json").write_text(json.dumps({"a": "x"}))
            values = l10n.flatten_desktop_locales(root)
            self.assertEqual(
                [k for k in values if k[0] not in l10n.SHIPPED], []
            )


if __name__ == "__main__":
    unittest.main()
```

- [x] **Step 2: Run it, confirm it fails**

Run: `python3 -m unittest Tests.L10nScriptTests.test_l10n -v` (from the repo root)
Expected: FAIL — `l10n` module has no `convert_placeholders`/`flatten_desktop_locales` attribute.

- [x] **Step 3: Add `convert_placeholders` and `flatten_desktop_locales` to `l10n.py`**

Insert near the existing `PLACEHOLDER_RE`/`placeholders()` helpers (around line 74 in today's
file):

```python
INTERP_RE = re.compile(r"\{\{(\w+)\}\}")


def convert_placeholders(text):
    """Every `{{name}}` becomes `%@` — see the design spec's §5 for why never a typed specifier."""
    return INTERP_RE.sub("%@", text)


def flatten_desktop_locales(locales_dir):
    """(iOS catalog language, "namespace:dotted.key") -> text, for every desktop locale this
    project ships (DESKTOP_LANGUAGE's keys); anything else (e.g. zh-Hans) is skipped, matching the
    desktop's own zh-Hans-falls-back-to-English choice."""
    values = {}
    for locale_dir in sorted(p for p in Path(locales_dir).iterdir() if p.is_dir()):
        lang = DESKTOP_LANGUAGE.get(locale_dir.name)
        if lang is None:
            continue
        for f in sorted(locale_dir.glob("*.json")):
            for key, text in flatten(json.loads(f.read_text(encoding="utf-8"))):
                values[(lang, "%s:%s" % (f.stem, key))] = text
    return values
```

(`flatten()` already exists in `l10n.py`, unchanged — it's the nested-JSON-to-dotted-path
generator `cmd_seed` already uses.) Add `from pathlib import Path` if not already imported at the
top of the file (it is — `l10n.py`'s existing `ROOT = Path(__file__)...` line confirms this).

- [x] **Step 4: Run the tests again, confirm they pass**

Run: `python3 -m unittest Tests.L10nScriptTests.test_l10n -v`
Expected: PASS (5 tests)

- [x] **Step 5: Write the failing test for `cmd_sync`'s overwrite behavior**

```python
class CmdSyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.locales = self.root / "locales"
        for lang, text in [
            ("en", "Ask Exodus"), ("zh-Hant-TW", "詢問 Exodus"), ("zh-Hant-HK", "詢問 Exodus"),
            ("ja", "Exodusに聞く"), ("ko", "Exodus에게 물어보기"), ("fr", "Demander à Exodus"),
            ("de", "Exodus fragen"), ("es", "Preguntar a Exodus"),
            ("pt-BR", "Perguntar ao Exodus"), ("it", "Chiedi a Exodus"),
        ]:
            d = self.locales / lang
            d.mkdir(parents=True)
            (d / "chat.json").write_text(json.dumps({"composer": {"placeholder": text}}))

        self.catalog_path = self.root / "Localizable.xcstrings"
        self.catalog_path.write_text(json.dumps({
            "sourceLanguage": "en",
            "strings": {
                "chat:composer.placeholder": {
                    "extractionState": "manual",
                    "localizations": {
                        "en": {"stringUnit": {"state": "translated", "value": "Ask Exodus"}},
                        # A deliberately stale zh-Hant translation — cmd_sync must overwrite this.
                        "zh-Hant": {"stringUnit": {"state": "translated", "value": "STALE"}},
                    },
                },
                "ios.onlyKey": {
                    "extractionState": "manual",
                    "localizations": {
                        "en": {"stringUnit": {"state": "translated", "value": "iOS only"}},
                    },
                },
            },
        }))

    def test_shared_key_is_overwritten_from_every_shipped_language(self):
        args = argparse.Namespace(locales_dir=str(self.locales), file=str(self.catalog_path))
        l10n.cmd_sync(args)
        catalog = json.loads(self.catalog_path.read_text())
        zh_hant = catalog["strings"]["chat:composer.placeholder"]["localizations"]["zh-Hant"]
        self.assertEqual(zh_hant["stringUnit"]["value"], "詢問 Exodus")

    def test_ios_only_key_is_untouched(self):
        args = argparse.Namespace(locales_dir=str(self.locales), file=str(self.catalog_path))
        l10n.cmd_sync(args)
        catalog = json.loads(self.catalog_path.read_text())
        self.assertNotIn("zh-Hant", catalog["strings"]["ios.onlyKey"]["localizations"])
```

Add `import argparse` to the test file's imports.

- [x] **Step 6: Run it, confirm it fails**

Run: `python3 -m unittest Tests.L10nScriptTests.test_l10n -v`
Expected: FAIL — `cmd_sync` doesn't exist yet.

- [x] **Step 7: Implement `cmd_sync`, replacing `cmd_seed`**

```python
def cmd_sync(args):
    path = resolve(args.file)
    catalog = load(path)
    values = flatten_desktop_locales(args.locales_dir)
    targets = [l for l in SHIPPED if l != SOURCE_LANGUAGE]
    synced, skipped = 0, []
    for key, entry in sorted(catalog["strings"].items()):
        if entry.get("shouldTranslate") is False:
            continue
        found = [values.get((lang, key)) for lang in [SOURCE_LANGUAGE] + targets]
        if not all(found):
            skipped.append(key)
            continue
        locs = entry.setdefault("localizations", {})
        for lang, text in zip([SOURCE_LANGUAGE] + targets, found):
            locs[lang] = {
                "stringUnit": {"state": "translated", "value": convert_placeholders(text)}
            }
        synced += 1
        print("synced %r from the desktop" % key)
    save(path, catalog)
    print("%d synced; %d not on the desktop (independently translated):" % (synced, len(skipped)))
    for key in skipped:
        print("  " + key)
    return 0
```

Delete `cmd_seed` — nothing else calls it once Step 8 rewires the CLI.

- [x] **Step 8: Rewire the CLI subcommand**

Replace the `seed = sub.add_parser("seed-from-desktop")` block in `main()` with:

```python
    sync = sub.add_parser("sync-from-desktop")
    sync.add_argument("locales_dir", nargs="?", default=str(ROOT / "Vendor/exodus-locales"))
    sync.add_argument("--file")
    sync.set_defaults(run=cmd_sync)
```

(The default path means `python3 scripts/l10n.py sync-from-desktop` with no argument works once
Task 1's vendored copy exists — matching the spec's §3 "simpler than today's invocation.")

- [x] **Step 9: Run the tests again, confirm they pass**

Run: `python3 -m unittest Tests.L10nScriptTests.test_l10n -v`
Expected: PASS (7 tests)

- [x] **Step 10: Stop — do not commit** (per the Global Constraints)

---

### Task 3: `audit_catalog`/`audit_sources` for symbolic keys

**Files:**
- Modify: `scripts/l10n.py`
- Modify: `Tests/L10nScriptTests/test_l10n.py`

**Interfaces:**
- Consumes: `flatten_desktop_locales`, `convert_placeholders` from Task 2.
- Produces: `audit_catalog(LOCALIZABLE, implicit_source=False, ...)` (was `True`); `match_key`
  simplified to an exact-string match against the symbolic key literal (no more
  interpolation-placeholder regex built from *displayed* English text).

- [x] **Step 1: Write the failing tests**

`audit_catalog` does `path.relative_to(ROOT)` and `audit_sources` reads `ROOT/"Sources"/**/*.swift`
plus `ROOT/"Project.swift"` (which must exist), so a test must point `l10n.ROOT`, `l10n.LOCALIZABLE`
and `l10n.INFOPLIST` at a throwaway repo. Add this helper and these tests to `test_l10n.py`
(add `import contextlib`, `import io` to its imports):

```python
@contextlib.contextmanager
def fake_repo(strings, swift=""):
    """A throwaway repo root with catalogs, Sources/View.swift and Project.swift, and l10n's module
    globals pointed at it (restored on exit)."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "Sources").mkdir()
        (root / "Sources" / "View.swift").write_text(swift, encoding="utf-8")
        (root / "Project.swift").write_text("", encoding="utf-8")
        localizable, infoplist = root / "Localizable.xcstrings", root / "InfoPlist.xcstrings"
        localizable.write_text(json.dumps({"sourceLanguage": "en", "strings": strings}), encoding="utf-8")
        infoplist.write_text(json.dumps({"sourceLanguage": "en", "strings": {}}), encoding="utf-8")
        saved = (l10n.ROOT, l10n.LOCALIZABLE, l10n.INFOPLIST)
        l10n.ROOT, l10n.LOCALIZABLE, l10n.INFOPLIST = root, localizable, infoplist
        try:
            yield root
        finally:
            l10n.ROOT, l10n.LOCALIZABLE, l10n.INFOPLIST = saved


def run_audit():
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = l10n.cmd_audit(argparse.Namespace(exclude=[], source_only=True))
    return code, out.getvalue()


def translated(value):
    return {"stringUnit": {"state": "translated", "value": value}}


class AuditImplicitSourceTests(unittest.TestCase):
    def test_symbolic_key_needs_its_own_en_value(self):
        # With implicit_source=False the key is no longer read as the English text —
        # an entry with no `en` localization is an error.
        with fake_repo({"chat:composer.placeholder": {"extractionState": "manual"}}):
            errors = l10n.audit_catalog(l10n.LOCALIZABLE, implicit_source=False, source_only=True)
            self.assertTrue(any("has no en value" in e for e in errors))


class CmdAuditDefaultTests(unittest.TestCase):
    """These pin cmd_audit's own call site, which is what Step 3 changes."""

    def test_a_key_with_no_en_value_fails_the_audit(self):
        # Under the old implicit_source=True default this entry passed (the key WAS the English
        # text); it must now fail, or the default was not flipped.
        with fake_repo({"Search": {"extractionState": "manual"}}, swift='Text("Search")\n'):
            code, out = run_audit()
            self.assertEqual(code, 1)
            self.assertIn("has no en value", out)

    def test_a_complete_symbolic_catalog_and_matching_call_site_passes(self):
        strings = {"chat:composer.placeholder": {"extractionState": "manual",
                   "localizations": {"en": translated("Ask Exodus")}}}
        with fake_repo(strings, swift='Text("chat:composer.placeholder")\n'):
            code, out = run_audit()
            self.assertEqual(code, 0, out)

    def test_a_swift_literal_missing_from_the_catalog_fails(self):
        strings = {"chat:composer.placeholder": {"extractionState": "manual",
                   "localizations": {"en": translated("Ask Exodus")}}}
        with fake_repo(strings, swift='Text("chat:nope")\n'):
            code, out = run_audit()
            self.assertEqual(code, 1)
            self.assertIn("is not in Localizable.xcstrings", out)
```

- [x] **Step 2: Run them, confirm the right one fails**

Run: `python3 -m unittest Tests.L10nScriptTests.test_l10n -v`
Expected: `AuditImplicitSourceTests` passes already (`audit_catalog` accepted the flag before this task);
`CmdAuditDefaultTests.test_a_key_with_no_en_value_fails_the_audit` FAILS (exit code 0, not 1 — the call
site still passes `True`). That failure is the RED test for Step 3. The other two `cmd_audit` tests
should pass both before and after (they pin that the audit is not simply always-red).

- [x] **Step 3: Change `cmd_audit`'s call site**

```python
# In cmd_audit, replace:
errors = audit_catalog(LOCALIZABLE, True, args.source_only) + audit_catalog(INFOPLIST, False, args.source_only)
# with:
errors = audit_catalog(LOCALIZABLE, False, args.source_only) + audit_catalog(INFOPLIST, False, args.source_only)
```

- [x] **Step 4: (folded into Step 1 — the `cmd_audit`-level tests above are the pin)**

- [x] **Step 5: Run it, confirm it passes**

Run: `python3 -m unittest Tests.L10nScriptTests.test_l10n -v`
Expected: PASS

- [x] **Step 6: Simplify `match_key` for exact symbolic-key matching**

`audit_sources` currently builds a regex from the *displayed* literal's pieces (via `literal_pieces`
+ `match_key`'s `pattern.fullmatch(key)`) because keys ≡ English text meant a call site's literal
argument WAS the key, interpolations and all. With symbolic keys, a `String(localized:
"chat:composer.placeholder", ...)` call's first argument is a **plain string literal with no
interpolation of its own** — the symbolic key never contains `\(...)`. This means `match_key` can
become a direct set-membership check instead of a regex match:

```python
def match_key(pieces, keys):
    # A symbolic key is never itself interpolated — pieces is a single-element
    # list when the call is `String(localized: "some.key", ...)`. A literal
    # with an actual `\(...)` interpolation (only still valid for a plain,
    # non-symbolic Text("...") call, which this project no longer uses for
    # anything with an interpolation per the migration in Task 4) has no
    # match here and is reported, which is correct — it means a call site
    # wasn't migrated to the defaultValue form.
    if len(pieces) == 1:
        return pieces[0] if pieces[0] in keys else None
    return None
```

This is a real behavior narrowing worth a test:

```python
class MatchKeySymbolicTests(unittest.TestCase):
    def test_a_plain_symbolic_key_matches(self):
        self.assertEqual(l10n.match_key(["chat:composer.placeholder"], {"chat:composer.placeholder"}), "chat:composer.placeholder")

    def test_an_interpolated_literal_no_longer_matches_by_pattern(self):
        # Old behavior: an English literal with an interpolation matched a
        # key via a placeholder regex. New behavior: any interpolated
        # literal call site is an audit error, since it should have moved
        # to `String(localized:defaultValue:)` instead.
        self.assertIsNone(l10n.match_key(["Hi ", "!"], {"chat:greeting"}))

    def test_an_unknown_key_does_not_match(self):
        self.assertIsNone(l10n.match_key(["chat:nope"], {"chat:composer.placeholder"}))
```

- [x] **Step 7: Run the full test file, confirm everything passes**

Run: `python3 -m unittest Tests.L10nScriptTests.test_l10n -v`
Expected: PASS (all tests from Tasks 2 and 3)

- [x] **Step 8: Stop — do not commit**

---

### Task 4: Migrate existing call sites to symbolic keys

The mechanical part: every existing `Text("English")`/`Button("English")`/`.navigationTitle("English")`
/etc. call site becomes either a plain `Text("namespace:key")`-style call (SwiftUI's literal
argument IS the key when there's no interpolation — this still auto-localizes, only the *key text*
changed, from English to symbolic) or, for anything with an interpolation,
`String(localized: "namespace:key", defaultValue: "…", comment: "…")`.

**Files:**
- Modify: every `.swift` file under `Sources/` that contains a localizable string literal (the
  audit, run with today's un-migrated catalog, is the authoritative list — see Step 1).
- Modify: `Resources/App/Localizable.xcstrings` (keys renamed, an explicit `en` value added to every entry).
  `InfoPlist.xcstrings` is NOT touched — its keys are Info.plist key names (`NSCameraUsageDescription`, …),
  not display text, and its audit already reads an explicit `en`.
- Measured baseline (2026-09-24, read-only): of the 70 existing keys, 10 have exactly one desktop counterpart
  whose English text is equal (placeholders normalised), 8 have several, 52 have none. So most of this task
  is naming iOS-only keys, not adopting desktop ones.

- [x] **Step 1: Generate the exact list of keys to rename**

Run: `python3 scripts/l10n.py audit --source-only 2>&1 | grep 'warning: '` — every warning line
names a catalog key not referenced by any Swift literal *after* a prior rename attempt; run this
audit BEFORE any renaming as a sanity check that today's baseline is clean (it should report 0
unreferenced keys, since nothing has been renamed yet). Then, separately, dump every existing key:

```bash
python3 -c "
import json
c = json.load(open('Resources/App/Localizable.xcstrings'))
for k in sorted(c['strings']):
    print(k)
" > /tmp/ios-keys-before-rename.txt
wc -l /tmp/ios-keys-before-rename.txt
```

Expected: ~70 lines, matching the count found in this plan's own exploration.

- [x] **Step 2: For each key, determine its desktop match via the flattening helper**

The old key IS its own English text, so the lookup goes English text → desktop key(s). Only desktop keys
that exist in every shipped language are candidates; placeholders are normalised to `%@` on both sides
so `Paired with %@` can meet `Paired with {{name}}`; ties are ordered by `DESKTOP_NAMESPACES`.

```bash
python3 - <<'EOF' > /tmp/ios-key-rename-map.tsv
import json, re, sys
sys.path.insert(0, 'scripts')
import l10n

values = l10n.flatten_desktop_locales('Vendor/exodus-locales')
by_text = {}
for (lang, key), text in values.items():
    if lang == l10n.SOURCE_LANGUAGE and all((l, key) in values for l in l10n.SHIPPED):
        by_text.setdefault(l10n.convert_placeholders(text), []).append(key)

def ns_rank(key):
    ns = key.split(':')[0]
    return (l10n.DESKTOP_NAMESPACES.index(ns) if ns in l10n.DESKTOP_NAMESPACES else 99, key)

catalog = json.load(open('Resources/App/Localizable.xcstrings'))
for key in sorted(catalog['strings']):
    candidates = sorted(by_text.get(re.sub(l10n.PLACEHOLDER, '%@', key), []), key=ns_rank)
    if len(candidates) == 1:
        print('%s\t->\t%s' % (key, candidates[0]))
    elif candidates:
        print('%s\t->\t(ambiguous: %s)' % (key, ' | '.join(candidates)))
    else:
        print('%s\t->\t(no desktop match — needs a manual symbolic name)' % key)
EOF
```

Expected shape of the result: about 10 rows with a real `namespace:key`, about 8 `(ambiguous: …)`, and about
52 `(no desktop match …)` — if the counts are wildly different, stop and investigate before renaming anything.

- [x] **Step 3: Review the map**

Run: `column -t -s $'\t' /tmp/ios-key-rename-map.tsv | less` — most rows should show a real
`namespace:key` on the right; a handful (the camera permission text, the drawer's
"Close sidebar" accessibility label, anything else genuinely iOS-only) show the "no desktop match"
placeholder. For those, choose a symbolic key `ios:<lowercase module>.<screen>.<element>` (e.g.
`ios:settings.camera.permissionHint`, `ios:sidebar.closeButton.label`) — there is no script for this half,
since it's naming judgment, not a derivable fact. The `ios:` prefix is mandatory: desktop keys always start
with one of its namespaces, so an `ios:` key can never be matched by `sync-from-desktop` against a desktop
key of the same short name.

For every `(ambiguous: a | b | …)` row, open the Swift call site and pick the desktop key whose *meaning*
fits (the same English word can be a button in one namespace and a heading in another); when nothing
decides it, prefer the first candidate (`common:` before `chat:` before `settings:`). Replace the whole
`(…)` cell with the one chosen key. Every row must end up with a real key — Step 4's script refuses
otherwise.

- [x] **Step 4: Rename catalog keys**

For every row in the reviewed map, the catalog key changes but its EXISTING translated values (for
languages already filled in) must move with it — write a small one-off script rather than doing
this by hand across ~70 entries:

```python
#!/usr/bin/env python3
# scripts/_rename_catalog_keys.py — a one-off migration helper for Task 4.
# Not part of the shipped tool; delete after this task is done.
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import l10n

mapping = {}
with open(sys.argv[2], encoding="utf-8") as f:
    for line in f:
        old, sep, new = line.rstrip("\n").partition("\t->\t")
        if not sep or not new or new.startswith("("):
            sys.exit("unresolved row %r: give every row a real symbolic key first" % line.strip())
        mapping[old] = new

path = Path(sys.argv[1])
catalog = l10n.load(path)
unmapped = set(catalog["strings"]) - set(mapping)
if unmapped:
    sys.exit("keys with no row in the map: %s" % sorted(unmapped))
renamed = {}
for old_key, entry in catalog["strings"].items():
    new_key = mapping[old_key]
    if new_key in renamed:
        sys.exit("two keys map to %r" % new_key)
    # The old key WAS the English source text; the new key is not, so keep the text as an explicit `en`.
    entry.setdefault("localizations", {}).setdefault(
        l10n.SOURCE_LANGUAGE, {"stringUnit": {"state": "translated", "value": old_key}}
    )
    renamed[new_key] = entry
catalog["strings"] = renamed
l10n.save(path, catalog)
print("renamed %d keys" % len(renamed))
```

(`l10n.save` writes the tool's own format, so the catalog's earlier Xcode-only reformatting diff disappears
as a side effect — expected.)

Run: `python3 scripts/_rename_catalog_keys.py Resources/App/Localizable.xcstrings /tmp/ios-key-rename-map.tsv`

For rows kept as a manually-chosen symbolic name (Step 3), edit the `.tsv` file first to replace
the `(no desktop match...)` placeholder with the actual chosen key before running this script, so
every row has a real `new` value.

- [x] **Step 5: Update every Swift call site**

For each renamed key, find its call sites:

```bash
git grep -F '"<old English text>"' -- Sources/
```

For a non-interpolated literal (`Text("Search")` → `Text("chat:search.button")`), just replace the
string. For anything the audit's `CALL_RE` matches with an interpolation piece (check
`literal_pieces` would have split it — i.e., the original had a `\(...)` inside), convert to the
explicit two-argument form:

```swift
// before
Text("Hello, \(name)!")
// after
Text(String(localized: "chat:greeting.hello", defaultValue: "Hello, \(name)!", comment: "…"))
```

**Adopted desktop keys with a placeholder** (the sync writes `%@` for them — see Global Constraints): every
interpolated argument in that call's `defaultValue` must already be a `String` expression — `String(n)`,
`n.formatted()`, `date.formatted(...)` — never a raw `Int`/`Double`/`Date`, or Xcode derives `%lld`/`%f` at the
call site and the runtime specifier no longer matches the catalog's `%@`. iOS-only templated keys are not
touched by this rule (Global Constraints, "Placeholder scope").

Also `git grep` `Tests/` for the old English text of each renamed key: a test asserting on displayed text must
follow the key change (report any you change).

A `comment` is required on every converted call (matches the project's existing rule for ambiguous
strings — "Chat" the workspace vs. "Chat" the fallback title — extend that same care to every
converted key here, not just the ones that were already ambiguous).

- [x] **Step 6: Delete the one-off rename script**

Run: `rm scripts/_rename_catalog_keys.py` — it isn't part of the shipped tool and shouldn't stay in
the tree past this task.

- [x] **Step 7: Run the audit**

Run: `python3 scripts/l10n.py audit` — and, since Swift files changed, syntax-check every one you touched:
`xcrun swiftc -parse <file>` (and try one `xcodebuild` build of the app scheme for the Simulator; if it cannot
run for an environment reason — signing, no destination, minutes-long — do not fight it, report why).
Expected: audit PASS, exit 0 (every entry now carries an explicit `en` from Step 4; shared keys still hold the
old iOS translations until Task 5 overwrites them). If it reports a Swift literal not found in the catalog, a call site was
missed in Step 5 — find it (`git grep -F '"<the missed English text>"' -- Sources/`) and fix it.
If it reports a catalog key with no Swift reference, either Step 4's rename map had a stale/unused
entry (remove it from the catalog) or a call site still needs migrating.

- [x] **Step 8: Stop — do not commit**

---

### Task 5: Run the real sync, update the README

**Files:**
- Modify: `Resources/App/Localizable.xcstrings` (populated with real desktop translations)
- Modify: `README.md`

- [x] **Step 1: Run the real sync**

Run: `python3 scripts/l10n.py sync-from-desktop`
Expected: prints one `synced %r from the desktop` line per shared key, then a summary; the
"skipped" list should now only contain genuinely iOS-only keys (the ones Task 4 gave manual
symbolic names) — if a key you expected to sync shows up as skipped, its symbolic key doesn't
exactly match the desktop's; check the desktop's actual catalog for the precise `namespace:key`
rather than guessing.

- [x] **Step 2: Verify with the audit**

Run: `python3 scripts/l10n.py audit`
Expected: PASS.

- [x] **Step 3: Update `README.md`'s Localization section**

Replace the `seed-from-desktop` line and its description with:

```markdown
python3 scripts/l10n.py sync-from-desktop   # Vendor/exodus-locales by default
```

and replace the paragraph describing `seed-from-desktop`'s text-matching behavior with a
description of the symbolic-key mechanism (keys are `<namespace>:<dotted.path>`, shared verbatim
with the desktop app's own `t()` keys; `sync-from-desktop` overwrites every shared key's
translation from the vendored copy on every run — a stale translation is a bug, not a feature, so
re-run it whenever the vendored copy is refreshed). Add Task 1 Step 4's two-command re-pull
sequence as the documented way to refresh `Vendor/exodus-locales`.

Also update the "Keys are the English source text" paragraph (§10 of the spec supersedes it) to
describe the new convention: a non-interpolated string's literal argument is now the symbolic key
(`Text("chat:search.button")`), and an interpolated one uses
`String(localized:defaultValue:comment:)` — both still audited by `scripts/l10n.py audit`, which
now checks by exact key rather than by literal-text pattern.

- [x] **Step 4: Stop — do not commit**

This plan's tasks are all complete at this point (subject to Task 0's spike having actually passed,
without which none of Tasks 1–5 should have been executed). Per the Global Constraints, everything
from Task 1 onward is left staged/modified in the working tree for a human to review and commit.

## Self-Review Notes

**Spec coverage:** §3 (git subtree delivery, no desktop changes) — Task 1, confirmed no desktop
repo file is ever modified. §4 (symbolic keys, Task 0's verification requirement) — Task 0 is
exactly that spike, gating everything after it. §5 (uniform `%@`) — `convert_placeholders`, Task 2.
§6 (extend `l10n.py`, don't replace; `implicit_source=False`; simplified `match_key`) — Tasks 2–3.
§7 (v1 manual, CI fast-follow not required) — this plan has no CI task, matching the spec's explicit
deferral. §9's `sync-from-desktop`-always-overwrites risk is directly what Task 2's
`test_shared_key_is_overwritten_from_every_shipped_language` pins.

**Placeholder scan:** Task 4's "choose a symbolic key" step (Step 3) is real judgment work with no
script to fully automate — flagged explicitly as such rather than disguised as a mechanical step,
with a stated naming convention so it's still a concrete instruction, not a "TBD."

**Type consistency:** N/A in the Python-plan sense (no cross-task function signatures beyond
`flatten_desktop_locales`/`convert_placeholders`, both defined once in Task 2 and consumed
identically in Task 3's `match_key` discussion and Task 5's `sync-from-desktop` run) — checked;
consistent.

---

### Task 6: harden the sync/audit (findings of the final review, 2026-09-24)

The final whole-change review (opus) found no wrong string or raw key, but two Important tooling bugs and several
minors. All fixes below are in `scripts/l10n.py`, `Tests/L10nScriptTests/test_l10n.py`, the catalog, two Swift call
sites, and README; nothing is committed.

- [ ] **I1. `convert_placeholders` must escape a literal `%` as `%%`** *before* it replaces `{{x}}` with `%@`. The
  desktop has `"{{percent}}% rain"` (chat.json) and `"(50-95%). Default: 75%."` (settings.json); today `%@% rain`
  renders as `40 rain` (Foundation swallows the `% r`), and the audit's `PLACEHOLDER_RE` does not see it. Tests:
  `"{{percent}}% rain"` → `"%@%% rain"`, `"50%"` → `"50%%"`, no double-escaping of an already `%%`, a text with no
  `%` unchanged; and `audit`'s `placeholders()` treats `%%` as literal (it already strips `%%` — pin it).
- [ ] **I2. `cmd_sync` must not skip a shared key silently.** A catalog key that is NOT `ios:`-prefixed but is missing
  from the vendored desktop tree — in any shipped language — is an ERROR: print it in a separate list
  ("shared key not found on the desktop (renamed or removed?)") and return exit code 1 (keep updating every key that
  can be updated first, and still save). `ios:` keys that the desktop lacks stay quietly "independently translated".
  Tests: a shared key absent in one language; a shared key absent entirely; an `ios:` key absent (exit 0).
- [ ] **M3. Two adopted keys come from unrelated desktop features** and the sync overwrites `en` too, so a desktop
  rewording of that feature would change iOS text: `settings:fullTextSearch.connection.label` (Settings' server
  connection section, `SettingsView.swift`) and `settings:tools.imageGeneration.model.placeholder` (the model picker
  placeholder, `SettingsView.swift`). Rename both to `ios:` keys (`ios:settings.connection.sectionTitle`,
  `ios:settings.providers.selectModel`), keep each entry's current 10-language values and comment, update the two call
  sites. (Do not change any other adopted key.)
- [ ] **M4. Audit the `defaultValue:` rule the README states.** For every `String(localized:` call site the audit sees:
  it must carry a `defaultValue:` argument (error otherwise), and when the `defaultValue:` literal's text
  (interpolations `\( … )` normalised to `%@`, and normalised the same way for the catalog `en`, `%lld`/`%d`/… → `%@`)
  differs from the catalog's `en` for that key, report an error naming both. Fix any real mismatch this exposes (do not
  weaken the check to make it pass — if it finds a genuine mismatch, correct the Swift default or the catalog and say so).
- [ ] **M5.** `Sources/SettingsFeature/PairingViewModel.swift` (~line 39): make the Swift `comment:` say what the catalog
  comment says ("Exodus is the app's name." included) — comment text only.
- [ ] **M6. Stale text in `l10n.py`:** the module docstring line about `add` ("KEY (the English source text)") must
  describe symbolic keys and `--en-value`; delete the now-unused `DESKTOP_NAMESPACES`; rewrite the `match_key` comment
  so it is short and true.
- [ ] **M7. Desktop `<Trans>` markup and plural keys cannot be shared as-is.** `sync-from-desktop` must treat a shared key
  whose desktop text contains i18next `<N>…</N>` / `<strong>`-style markup, or whose desktop key has a CLDR plural
  suffix (`_one`, `_other`, `_zero`, `_two`, `_few`, `_many`) as an error in the same separate list as I2 ("not shareable
  as-is: markup/plural"), and README's Localization section gets one sentence saying so.
- [ ] **M8. Test gaps:** `cmd_sync` converts `{{x}}` → `%@`; skips `shouldTranslate: false` entries; the `cmd_sync` tests
  no longer print to stdout (capture with `contextlib.redirect_stdout`).
- Done when: `python3 -m unittest Tests.L10nScriptTests.test_l10n` passes; `python3 scripts/l10n.py audit` exit 0;
  `python3 scripts/l10n.py sync-from-desktop --file <copy of the catalog in the scratchpad>` exits 0 on the real vendored
  tree and changes nothing except… nothing (all 15 shared keys are already identical — after M3 that is 15);
  `swiftc -parse` on the two Swift files; one `xcodebuild` build of the App scheme succeeds; README diff limited to the
  Localization section (+ the owner's port line).
