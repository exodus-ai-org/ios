# ChatGPT-style Shell + i18n Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reshape exodus-ios like the ChatGPT iOS app (new-chat launch, a card-slide drawer with Recents, inline search, glass composer) and make every user-visible string localizable from the start, in the desktop app's ten languages.

**Architecture:** A small custom `SideDrawer` container (App target) hosts two native `NavigationStack`s, the sidebar behind and the chat as a rounded card in front. `ChatSidebarView` (ChatFeature) owns Recents, long-press delete and a hand-built inline search field backed by `ChatSearchViewModel`. Strings live in String Catalogs in the App target (English source text as keys); `scripts/l10n.py` adds keys, fills translations and audits the catalogs against the Swift sources. A first task moves every endpoint under the desktop's new `/api/v1` prefix, without which the shipped app cannot reach the current desktop server.

**Tech Stack:** Swift 6 (language mode 6), SwiftUI (iOS 27 Liquid Glass APIs), Swift Testing, Tuist 4.208.0, Python 3.9 (stdlib only) for the l10n tool.

**Spec:** `docs/superpowers/specs/2026-09-19-chatgpt-style-shell-and-i18n-design.md` (read it first; this plan argues from it). Two facts found after the spec was written override it and are folded into Task 1 and the tasks below: the desktop backend now mounts every route under `/api/v1` (`GET /api/v1/history` is 200, `GET /api/history` is 404, verified against the running server), and its i18n catalogs live at `~/Code/exodus/exodus/packages/shared/src/i18n/locales` (the `universal-client` folder no longer exists).

## Global Constraints

- Swift 6 language mode (`SWIFT_VERSION` 6.0 in `Project.swift`), iOS 27.0 deployment target, no third-party dependencies. Modules are static frameworks; strings therefore resolve from `Bundle.main` and no `bundle:` argument is used anywhere.
- Work on local `main`, commit at the end of every task, never push. End every commit message with the line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- Every endpoint path starts with `/api/v1/` (the desktop's rule: a breaking change ships as `/api/v2` beside it).
- Shipped languages, exactly: `en` (source), `zh-Hant`, `zh-HK`, `ja`, `ko`, `fr`, `de`, `es`, `pt-BR`, `it`. There is no `zh-Hans`: a Simplified Chinese phone shows English, as on the desktop.
- Catalog keys are the English source text. Never build a sentence by concatenation. User data (chat titles, snippets, server text) is shown from a `String` variable or `Text(verbatim:)`, never as a literal key. Never pass a ternary of two string literals to a SwiftUI text initializer (it silently becomes non-localized); use `if/else` with one literal per branch. Enums expose `title: LocalizedStringResource` built with an explicit `LocalizedStringResource("…")`, never `rawValue`.
- Drawer numbers: width `min(0.78 × container width, 360 pt)`; edge grab zone `28 pt`; `DragGesture(minimumDistance: 12)`, horizontal-dominant; corner radius `40 × min(progress × 4, 1)`; scrim `systemBackground` at `0.6 × progress`; shadow `0.15 × progress`; the container uses `.ignoresSafeArea(.container)`, never `.all` (or the composer would not rise with the keyboard). Sidebar rows have no swipe actions; delete is a long-press context menu.
- Search numbers: debounce 300 ms; at most 50 chats; snippet 40 characters before the match, 80 after, 120 when there is no match; results grouped by `chatId` in server order.
- Tests use Swift Testing, assert structure not copy, and follow the existing per-file `URLProtocol` mock pattern. Unit-test bundles are not hosted by the app and carry no catalogs, so localized copy resolves to its English key there.
- Real chat titles are long and multi-line (observed: up to 1211 characters, some with newlines). Every place a title is displayed collapses whitespace and limits lines.
- UI verification talks to the user's real desktop server (`http://localhost:60223`) with read-only requests only. Never delete a chat, send a message or press Save against it.
- Scripts are Python 3.9-compatible standard library only. Do not touch `.superpowers/` (git-ignored).

## Shared commands

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
UDID=57E4297B-06D3-45D5-8E46-261CCC7DBB3B            # iPhone 17, iOS 27.0 simulator
tuist generate --no-open                              # after adding or removing files
# one module's tests (Models | NetworkingKit | ChatFeature | SettingsFeature); a failing run can stall ~10 min
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature \
  -destination "platform=iOS Simulator,id=$UDID" 2>&1 | grep -E "Test run with|TEST SUCCEEDED|TEST FAILED|error:"
# the whole app
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App \
  -destination "platform=iOS Simulator,id=$UDID" 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Shell variables (`UDID`, `EXCLUDES`, `SCRATCH`, `APP`) do not persist between separate shell invocations; declare them again in each command that uses them. `EXCLUDES` is `--exclude Sources/App/RootView.swift --exclude Sources/ChatFeature/ChatListView.swift --exclude Sources/ChatFeature/ChatDetailView.swift` while those files still exist.

`-only-testing:` takes the Swift type name, not the `@Suite` string, and a wrong name still prints `** TEST SUCCEEDED **`, so always look for a `Test run with N tests` line. If the compiler rejects an iOS 27 SwiftUI spelling used below, look it up in the SDK's `SwiftUI.swiftinterface` (`xcrun --sdk iphonesimulator --show-sdk-path`) instead of guessing, and keep the behavior.

---

### Task 1: Address the desktop's versioned API (`/api/v1`)

The desktop moved every route under `/api/v1` on 2026-09-19 (its `CLAUDE.md` names `exodus-ios` as a client that must follow). Against the current server every request of the shipped app is a 404. This task is the fix and a prerequisite for all live verification.

**Files:**
- Modify: `Sources/ChatFeature/ChatDetailViewModel.swift`, `Sources/ChatFeature/ChatListViewModel.swift`, `Sources/NetworkingKit/ChatStreamManager.swift`, `Sources/SettingsFeature/SettingsViewModel.swift` (path literals and comments that mention `/api/`)
- Modify: every test file that mentions `/api/` (`Tests/**/*.swift`)
- Modify: `README.md`

**Interfaces:**
- Produces: every path handed to `APIClient.get/post/delete` and the chat SSE `POST` begins with `/api/v1/`. Later tasks write `/api/v1/...` literally (there is no prefix constant).

- [ ] **Step 1: Update the tests first**

```bash
find Tests -name '*.swift' -exec sed -i '' 's#/api/#/api/v1/#g' {} +
grep -rn '/api/v1/v1' Tests && echo "DOUBLED PREFIX" || echo ok
git diff --stat
```

Expected: `ok`, and a diff limited to the seven test files that mentioned `/api/` (`APIClientTests`, `ChatDetailViewModelTests`, `ChatListViewModelTests`, `ChatHistoryRowsTests`, `ChatSummaryTests`, `SettingsTests`, `SettingsViewModelTests`). Skim the diff: only path strings and comments may change.

- [ ] **Step 2: Run the module suites and see them fail**

Run the `ChatFeature`, `SettingsFeature` and `NetworkingKit` commands from "Shared commands".
Expected: `TEST FAILED` for those three (their tests now expect `/api/v1/...` while the sources still send `/api/...`). `Models` still passes.

- [ ] **Step 3: Update the sources**

```bash
grep -rn '/api/' Sources
sed -i '' 's#/api/#/api/v1/#g' \
  Sources/ChatFeature/ChatDetailViewModel.swift Sources/ChatFeature/ChatListViewModel.swift \
  Sources/ChatFeature/ChatHistoryRows.swift Sources/NetworkingKit/ChatStreamManager.swift \
  Sources/SettingsFeature/SettingsViewModel.swift
grep -rn '/api/' Sources | grep -v '/api/v1/' && echo "MISSED A PATH" || echo "all paths versioned"
```

Expected: the final line reads `all paths versioned`. If `grep` listed a file not named in the `sed` command (for example a comment in `Sources/Models/*.swift`), apply the same replacement to it. The changed literals are `"/api/v1/chat/\(chatId)"`, `"/api/v1/history"`, `"/api/v1/chat/\(chat.id)"`, `base.appendingPathComponent("/api/v1/chat")`, `"/api/v1/settings"`, `"/api/v1/settings/models"`.

- [ ] **Step 4: Run every module and see them pass**

Run all four commands from "Shared commands" (`Models`, `NetworkingKit`, `ChatFeature`, `SettingsFeature`).
Expected: `TEST SUCCEEDED` each, with the same test counts as before the task (Models 26, NetworkingKit 34, SettingsFeature 28, ChatFeature 52).

- [ ] **Step 5: Smoke-check the four read-only endpoints on the live desktop**

```bash
for p in history settings "chat/00000000-0000-4000-8000-000000000000" "chat/search?query=hi"; do
  curl --noproxy '*' -s -o /dev/null -w "GET /api/v1/$p -> %{http_code}\n" "http://localhost:60223/api/v1/$p"
done
```

Expected: four `200` lines. If the desktop app is not running, report that and skip this step (the unit tests already prove the paths); do not start it yourself.

- [ ] **Step 6: Update the README**

In `README.md`, replace every `universal-client` with `exodus`, and in "Connecting to the desktop" replace the run instruction with:

```
Run the desktop app from `../exodus` (`bun start`); it serves the API on port 60223 under `/api/v1`, the
versioned prefix this app addresses. The default address, `http://localhost:60223`, works from the Simulator
on the same Mac.
```

(Keep the rest of that paragraph: the real-iPhone LAN address and the local-network permission note. Leave the older files under `docs/superpowers/` untouched; they are history.)

- [ ] **Step 7: Commit**

```bash
git add -A Sources Tests README.md
git commit -m "Address the desktop's versioned API (/api/v1)

The desktop mounts every route under /api/v1 as of its ae80bbcd; against it
the unversioned paths were all 404.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: i18n foundation and the surviving legacy strings

Creates the String Catalogs, the `scripts/l10n.py` tool (add keys, fill translations, seed from the desktop, audit) and the Tuist language options; puts every string in files that will survive this redesign through the catalog; leaves the three files that Tasks 6 and 7 replace (`RootView.swift`, `ChatListView.swift`, `ChatDetailView.swift`) for those tasks, so the audit is told to skip them until then.

**Files:**
- Create: `scripts/l10n.py`, `Resources/App/Localizable.xcstrings`, `Resources/App/InfoPlist.xcstrings`
- Modify: `Project.swift`
- Modify: `Sources/NetworkingKit/APIClient.swift`, `Sources/NetworkingKit/ChatStreamManager.swift`, `Sources/NetworkingKit/SSEClient.swift`
- Modify: `Sources/SettingsFeature/SettingsView.swift`, `Sources/SettingsFeature/SettingsViewModel.swift`
- Modify: `Sources/PhilharmonicFeature/PhilharmonicPlaceholderView.swift`, `Sources/ChatFeature/MessageRow.swift`, `Sources/ChatFeature/ChatDetailViewModel.swift`
- Modify: `Tests/ChatFeatureTests/ChatDetailViewModelTests.swift`, `README.md`

**Interfaces:**
- Produces: `python3 scripts/l10n.py audit [--source-only] [--exclude PATH]…`, `add KEY [--comment T] [--no-translate] [--en-value T] [--file F]`, `fill FILE.json [--file F]`, `seed-from-desktop LOCALES_DIR [--file F]`. Later tasks add their keys with `add` and the audit must stay green.
- Produces: `Resources/App/Localizable.xcstrings` (keys = English text) and `Resources/App/InfoPlist.xcstrings` (key `NSLocalNetworkUsageDescription`, English value explicit).
- Produces: `ChatDetailViewModel.displayTitle` returns `String(localized: "New chat")` for an empty transcript and `String(localized: "Chat")` otherwise.

- [ ] **Step 1: Write the tool and watch the audit fail**

Create `scripts/l10n.py` with exactly this content, then `chmod +x scripts/l10n.py`:

```python
#!/usr/bin/env python3
"""Localization tooling for exodus-ios (standard library only, Python 3.9+).

  l10n.py audit [--source-only] [--exclude PATH ...]
      Checks both catalogs and the Swift sources; exit status 1 on any error.
      --source-only skips the "every language is translated" check (used while
      strings are still being added); every other check still runs.
  l10n.py add KEY [--comment TEXT] [--no-translate] [--en-value TEXT] [--file PATH]
      Adds KEY (the English source text) to a catalog if it is not there yet.
  l10n.py fill TRANSLATIONS.json [--file PATH]
      Merges {"key": {"lang": "text"}} into a catalog as translated strings.
  l10n.py seed-from-desktop LOCALES_DIR [--file PATH]
      Copies the desktop app's translation of every key whose English text
      equals one of its English strings exactly (never overwrites a value).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALIZABLE = ROOT / "Resources/App/Localizable.xcstrings"
INFOPLIST = ROOT / "Resources/App/InfoPlist.xcstrings"
SOURCE_LANGUAGE = "en"
SHIPPED = ["en", "zh-Hant", "zh-HK", "ja", "ko", "fr", "de", "es", "pt-BR", "it"]
# The desktop's locale directory -> our catalog language.
DESKTOP_LANGUAGE = {
    "en": "en", "zh-Hant-TW": "zh-Hant", "zh-Hant-HK": "zh-HK", "ja": "ja", "ko": "ko",
    "fr": "fr", "de": "de", "es": "es", "pt-BR": "pt-BR", "it": "it",
}
DESKTOP_NAMESPACES = ["common", "chat", "settings"]  # preferred when an English text repeats

PLACEHOLDER = r"%(?:\d+\$)?[-+0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[diouxXeEfFgGaAcCsSp@]"
PLACEHOLDER_RE = re.compile(PLACEHOLDER)
CJK_RE = re.compile("[⺀-鿿가-힯＀-￯]")
# A SwiftUI / Foundation call whose first argument is a localizable string literal.
CALL_RE = re.compile(
    r"(?:\bText\(|\bLabel\(|\bButton\(|\bTextField\(|\bSecureField\(|\bSection\(|\bPicker\("
    r"|\bToggle\(|\bContentUnavailableView\(|\.navigationTitle\(|\.accessibility(?:Label|Hint|Value)\("
    r"|\.alert\(|\bString\(\s*localized:\s*|\bLocalizedStringResource\()\s*\""
)
# `cond ? "A" : "B"` handed to a SwiftUI text initializer may resolve to the non-localizing String overload.
TERNARY_RE = re.compile(r'\?\s*"(?:[^"\\]|\\.)*"\s*:\s*"')


# ---------------------------------------------------------------- catalog files
def resolve(path):
    if not path:
        return LOCALIZABLE
    p = Path(path)
    return p if p.is_absolute() else ROOT / p


def load(path):
    if not path.exists():
        return {"sourceLanguage": SOURCE_LANGUAGE, "strings": {}, "version": "1.0"}
    return json.loads(path.read_text(encoding="utf-8"))


def save(path, catalog):
    text = json.dumps(catalog, indent=2, separators=(",", " : "), ensure_ascii=False, sort_keys=True)
    path.write_text(text + "\n", encoding="utf-8")


def unit_value(loc):
    if not loc or "stringUnit" not in loc:
        return None
    return loc["stringUnit"].get("value")


def placeholders(text):
    return sorted(re.sub(r"^%\d+\$", "%", m.group(0)) for m in PLACEHOLDER_RE.finditer(text.replace("%%", "")))


# ---------------------------------------------------------------- Swift scanning
def skip_string(text, i):
    """text[i] is the opening quote; returns the index just past the closing quote."""
    n, j = len(text), i + 1
    while j < n:
        c = text[j]
        if c == "\\":
            j = skip_parens(text, j + 1) if text[j + 1:j + 2] == "(" else j + 2
        elif c == '"':
            return j + 1
        else:
            j += 1
    return n


def skip_parens(text, i):
    """text[i] is '('; returns the index just past the matching ')'."""
    depth, n, j = 0, len(text), i
    while j < n:
        c = text[j]
        if c == '"':
            j = skip_string(text, j)
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return n


def strip_comments(text):
    """Blank out // and /* */ comments (keeping newlines) without touching string contents."""
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j == -1 else j + 3
            out.append(text[i:j])
            i = j
        elif text[i] == '"':
            j = skip_string(text, i)
            out.append(text[i:j])
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i))
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}


def literal_pieces(raw):
    """Splits a Swift string literal body on its interpolations; unescapes each piece."""
    pieces, current, i, n = [], [], 0, len(raw)
    while i < n:
        c = raw[i]
        if c != "\\":
            current.append(c)
            i += 1
            continue
        nxt = raw[i + 1:i + 2]
        if nxt == "(":
            pieces.append("".join(current))
            current = []
            i = skip_parens(raw, i + 1)
        elif nxt == "u" and raw[i + 2:i + 3] == "{":
            end = raw.find("}", i + 3)
            current.append(chr(int(raw[i + 3:end], 16)))
            i = end + 1
        else:
            current.append(_ESCAPES.get(nxt, nxt))
            i += 2
    pieces.append("".join(current))
    return pieces


def match_key(pieces, keys):
    pattern = re.compile(PLACEHOLDER.join(re.escape(p) for p in pieces))
    for key in keys:
        if pattern.fullmatch(key):
            return key
    return None


# ---------------------------------------------------------------- audit
def audit_catalog(path, implicit_source, source_only):
    rel = path.relative_to(ROOT).as_posix()
    if not path.exists():
        return ["%s: missing" % rel]
    catalog = load(path)
    errors = []
    if catalog.get("sourceLanguage") != SOURCE_LANGUAGE:
        errors.append("%s: sourceLanguage must be %r" % (rel, SOURCE_LANGUAGE))
    required = [l for l in SHIPPED if not (implicit_source and l == SOURCE_LANGUAGE)]
    for key, entry in sorted(catalog.get("strings", {}).items()):
        if entry.get("shouldTranslate") is False:
            continue
        locs = entry.get("localizations", {})
        stray = sorted(set(locs) - set(SHIPPED))
        if stray:
            errors.append("%s: %r has languages outside the shipped set: %s" % (rel, key, ", ".join(stray)))
        source_text = key if implicit_source else unit_value(locs.get(SOURCE_LANGUAGE))
        if source_text is None:
            errors.append("%s: %r has no %s value" % (rel, key, SOURCE_LANGUAGE))
            continue
        for lang in required:
            loc = locs.get(lang)
            if loc is None:
                if not source_only or lang == SOURCE_LANGUAGE:
                    errors.append("%s: %r is missing %s" % (rel, key, lang))
                continue
            if "variations" in loc or "stringUnit" not in loc:
                errors.append("%s: %r [%s] must be a plain stringUnit (no variations)" % (rel, key, lang))
                continue
            unit = loc["stringUnit"]
            value = unit.get("value", "")
            if unit.get("state") != "translated" or not value.strip():
                errors.append("%s: %r [%s] is not translated" % (rel, key, lang))
            elif placeholders(value) != placeholders(source_text):
                errors.append("%s: %r [%s] placeholders differ from the source" % (rel, key, lang))
    return errors


def audit_sources(keys, excluded):
    errors, used = [], set()
    files = sorted((ROOT / "Sources").rglob("*.swift")) + [ROOT / "Project.swift"]
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        if rel in excluded:
            continue
        raw = path.read_text(encoding="utf-8")
        raw_lines = raw.split("\n")
        text = strip_comments(raw)
        cjk = CJK_RE.search(text)
        if cjk:
            line = text.count("\n", 0, cjk.start()) + 1
            if "l10n:ignore" not in raw_lines[line - 1]:
                errors.append("%s:%d: hard-coded CJK text; put it in the String Catalog" % (rel, line))
        if path.name == "Project.swift":
            continue
        for m in TERNARY_RE.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            if "l10n:ignore" not in raw_lines[line - 1]:
                errors.append(
                    "%s:%d: a ternary of string literals is not reliably localized; use if/else, one literal per branch"
                    % (rel, line)
                )
        for m in CALL_RE.finditer(text):
            start = m.end() - 1
            end = skip_string(text, start)
            pieces = literal_pieces(text[start + 1:end - 1])
            line = text.count("\n", 0, start) + 1
            if "l10n:ignore" in raw_lines[line - 1] or not any(pieces):
                continue
            key = match_key(pieces, keys)
            if key is None:
                errors.append('%s:%d: "%s" is not in Localizable.xcstrings' % (rel, line, "%@".join(pieces)))
            else:
                used.add(key)
    return errors, used


def cmd_audit(args):
    excluded = {Path(p).as_posix() for p in args.exclude}
    errors = audit_catalog(LOCALIZABLE, True, args.source_only) + audit_catalog(INFOPLIST, False, args.source_only)
    strings = load(LOCALIZABLE)["strings"]
    source_errors, used = audit_sources(set(strings), excluded)
    errors += source_errors
    for key, entry in sorted(strings.items()):
        if entry.get("shouldTranslate") is not False and key not in used:
            print("warning: %r is not referenced by any Swift string literal" % key)
    for e in errors:
        print("error: " + e)
    print("%d error(s)" % len(errors))
    return 1 if errors else 0


# ---------------------------------------------------------------- editing
def cmd_add(args):
    path = resolve(args.file)
    catalog = load(path)
    if args.key in catalog["strings"]:
        print("%r already exists" % args.key)
        return 0
    entry = {"extractionState": "manual"}
    if args.comment:
        entry["comment"] = args.comment
    if args.no_translate:
        entry["shouldTranslate"] = False
    if args.en_value is not None:
        entry["localizations"] = {SOURCE_LANGUAGE: {"stringUnit": {"state": "translated", "value": args.en_value}}}
    catalog["strings"][args.key] = entry
    save(path, catalog)
    print("added %r" % args.key)
    return 0


def cmd_fill(args):
    path = resolve(args.file)
    catalog = load(path)
    translations = json.loads(Path(args.translations).read_text(encoding="utf-8"))
    for key, values in translations.items():
        entry = catalog["strings"].get(key)
        if entry is None:
            sys.exit("unknown key %r; add it first" % key)
        locs = entry.setdefault("localizations", {})
        for lang, text in values.items():
            if lang not in SHIPPED:
                sys.exit("%r: %s is not a shipped language" % (key, lang))
            locs[lang] = {"stringUnit": {"state": "translated", "value": text}}
    save(path, catalog)
    return 0


def flatten(node, prefix=""):
    for k, v in node.items():
        if isinstance(v, dict):
            yield from flatten(v, "%s%s." % (prefix, k))
        elif isinstance(v, str):
            yield "%s%s" % (prefix, k), v


def cmd_seed(args):
    path = resolve(args.file)
    catalog = load(path)
    locales = Path(args.locales_dir).expanduser()
    values, english = {}, {}  # (lang, namespace, key) -> text ; english text -> [(namespace, key)]
    for locale_dir in sorted(p for p in locales.iterdir() if p.is_dir()):
        lang = DESKTOP_LANGUAGE.get(locale_dir.name)
        if lang is None:
            continue
        for f in sorted(locale_dir.glob("*.json")):
            for key, text in flatten(json.loads(f.read_text(encoding="utf-8"))):
                values[(lang, f.stem, key)] = text
                if lang == SOURCE_LANGUAGE:
                    english.setdefault(text, []).append((f.stem, key))
    targets = [l for l in SHIPPED if l != SOURCE_LANGUAGE]
    seeded, skipped = 0, []
    for key, entry in sorted(catalog["strings"].items()):
        if entry.get("shouldTranslate") is False:
            continue
        candidates = sorted(
            english.get(key, []),
            key=lambda c: (DESKTOP_NAMESPACES.index(c[0]) if c[0] in DESKTOP_NAMESPACES else 99, c),
        )
        chosen = None
        for ns, k in candidates:
            texts = [values.get((lang, ns, k)) for lang in targets]
            if all(t and "{{" not in t for t in texts) and not PLACEHOLDER_RE.search(key):
                chosen = (ns, k, texts)
                break
        if chosen is None:
            skipped.append(key)
            continue
        locs = entry.setdefault("localizations", {})
        for lang, text in zip(targets, chosen[2]):
            locs.setdefault(lang, {"stringUnit": {"state": "translated", "value": text}})
        seeded += 1
        print("seeded %r from %s:%s" % (key, chosen[0], chosen[1]))
    save(path, catalog)
    print("%d seeded; %d left for manual translation:" % (seeded, len(skipped)))
    for key in skipped:
        print("  " + key)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    audit = sub.add_parser("audit")
    audit.add_argument("--source-only", action="store_true")
    audit.add_argument("--exclude", action="append", default=[])
    audit.set_defaults(run=cmd_audit)
    add = sub.add_parser("add")
    add.add_argument("key")
    add.add_argument("--comment")
    add.add_argument("--no-translate", action="store_true")
    add.add_argument("--en-value")
    add.add_argument("--file")
    add.set_defaults(run=cmd_add)
    fill = sub.add_parser("fill")
    fill.add_argument("translations")
    fill.add_argument("--file")
    fill.set_defaults(run=cmd_fill)
    seed = sub.add_parser("seed-from-desktop")
    seed.add_argument("locales_dir")
    seed.add_argument("--file")
    seed.set_defaults(run=cmd_seed)
    args = parser.parse_args()
    sys.exit(args.run(args))


if __name__ == "__main__":
    main()
```

Run the audit; it must FAIL now (no catalogs yet, hard-coded Chinese still in the sources):

```bash
EXCLUDES="--exclude Sources/App/RootView.swift --exclude Sources/ChatFeature/ChatListView.swift --exclude Sources/ChatFeature/ChatDetailView.swift"
python3 scripts/l10n.py audit --source-only $EXCLUDES
```

Expected: exit status 1, `Resources/App/Localizable.xcstrings: missing`, `Resources/App/InfoPlist.xcstrings: missing`, a CJK error for `SettingsView.swift` and `PhilharmonicPlaceholderView.swift`, ternary errors for `SettingsView.swift:91`, `MessageRow.swift:40` and `ChatDetailViewModel.swift:43`, and many `is not in Localizable.xcstrings` lines.

- [ ] **Step 2: Add the Tuist language options and the English permission text**

In `Project.swift`, add `options` to the `Project(...)` initializer (right after `name:`) and change the permission string:

```swift
let project = Project(
    name: "ExodusIos",
    options: .options(
        defaultKnownRegions: ["en", "zh-Hant", "zh-HK", "ja", "ko", "fr", "de", "es", "pt-BR", "it"],
        developmentRegion: "en"
    ),
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
```

```swift
                    "NSLocalNetworkUsageDescription":
                        "Exodus needs local network access to connect to the Exodus service running on your computer."
```

- [ ] **Step 3: Create both catalogs**

```bash
python3 scripts/l10n.py add NSLocalNetworkUsageDescription --file Resources/App/InfoPlist.xcstrings \
  --comment "Local-network permission prompt. Exodus is the app's name and stays as is." \
  --en-value "Exodus needs local network access to connect to the Exodus service running on your computer."
add() { python3 scripts/l10n.py add "$@"; }
add "Connection" --comment "Settings section header for the server address."
add "Server address" --comment "Accessibility label of the server address field in Settings."
add "AI Providers" --comment "Settings section header."
add "Provider" --comment "Picker label: which AI provider to use."
add "API Key" --comment "Field label for a provider's API key."
add "Ollama runs on your Mac and needs no API key." --comment "Footnote shown instead of the API key field when the Ollama provider is selected."
add "Model" --comment "Label for the AI model field or picker."
add "Select a model" --comment "Placeholder row in the model picker when no model is chosen."
add "Loading models" --comment "Accessibility label of the spinner while the model list loads."
add "Refresh model list" --comment "Button that reloads the provider's model list."
add "Settings" --comment "Title of the Settings screen and accessibility label of the gear button."
add "Save" --comment "Toolbar button in Settings."
add "Connect" --comment "Toolbar button in Settings before the server's settings are loaded."
add "Cancel" --comment "Dismisses a screen or leaves search, changing nothing."
add "Server address must look like %@" --comment "Validation error. %@ is an example address such as http://192.168.1.10:60223 and must stay unchanged."
add "Connect to the server and load its settings before saving." --comment "Error shown when saving is attempted before the server's settings were loaded."
add "Invalid server URL: %@" --comment "Error. %@ is the address the user typed."
add "Invalid server URL" --comment "Short error when the stored server address cannot be parsed."
add "HTTP %lld" --comment "Fallback error text for a server response without a message. %lld is the HTTP status code."
add "Coming soon" --comment "Marks a workspace that is not available yet, and the title of its placeholder screen."
add "The Philharmonic multi-agent workspace hasn't been ported to iOS yet." --comment "Placeholder screen body. Philharmonic is a product name and stays untranslated."
add "Used: %@" --comment "Row for a tool call in the transcript. %@ is the tool's name."
add "Used a tool" --comment "Row for a tool call whose name is unknown."
add "New chat" --comment "Button that starts a new conversation, and the title of an empty conversation."
add "Chat" --comment "Name of the chat workspace, and the title of an open conversation that has no name yet."
```

- [ ] **Step 4: Move the surviving strings into the catalog**

`Sources/NetworkingKit/APIClient.swift`: the two client-generated messages become localized:

```swift
            throw HTTPError(
                statusCode: 0, code: "INVALID_BASE_URL",
                message: String(localized: "Invalid server URL: \(serverConfig.baseURLString)"))
```

```swift
        let message =
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "HTTP \(http.statusCode)") : text
```

`Sources/NetworkingKit/ChatStreamManager.swift` (the `fail` call in `send`):

```swift
                await self?.fail(chatId: chatId, generation: generation, message: String(localized: "Invalid server URL"))
```

`Sources/NetworkingKit/SSEClient.swift` (the fallback `HTTPError` at line 22):

```swift
                        throw HTTPError(
                            statusCode: http.statusCode, code: "UNKNOWN_ERROR",
                            message: String(localized: "HTTP \(http.statusCode)"))
```

`Sources/SettingsFeature/SettingsViewModel.swift`: add `private static let exampleServerURL = "http://192.168.1.10:60223"` next to the other private members and use it:

```swift
            errorMessage = String(localized: "Server address must look like \(Self.exampleServerURL)")
```

```swift
            errorMessage = String(localized: "Connect to the server and load its settings before saving.")
```

`Sources/SettingsFeature/SettingsView.swift`: the section title and the address field (the URL example is data, not a key):

```swift
                Section("Connection") {
                    TextField(
                        text: $viewModel.serverURLText,
                        prompt: Text(verbatim: "http://192.168.1.10:60223")
                    ) {
                        Text("Server address")
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit {
                        // A new address means a different server: reload its provider settings.
                        if viewModel.saveServerURL() {
                            Task { await viewModel.loadSettings() }
                        }
                    }
                }
```

In the same file the toolbar's confirmation button picks between two literals with a ternary, which is not reliably localized. Make it two literals in an `if/else` (the action body is unchanged):

```swift
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            guard viewModel.saveServerURL() else { return }
                            // Not loaded (first run, or the address just changed): connect to that server and
                            // load its settings instead of writing. Never write to a server we haven't read.
                            guard viewModel.hasLoadedSettings else {
                                await viewModel.loadSettings()
                                return
                            }
                            if await viewModel.save() {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.hasLoadedSettings {
                            Text("Save")
                        } else {
                            Text("Connect")
                        }
                    }
                    .disabled(viewModel.isSaving || viewModel.isLoading)
                }
```

`Sources/PhilharmonicFeature/PhilharmonicPlaceholderView.swift`:

```swift
            Text("Coming soon")
                .font(.title2)
                .fontWeight(.semibold)
            Text("The Philharmonic multi-agent workspace hasn't been ported to iOS yet.")
```

`Sources/ChatFeature/MessageRow.swift`: the SF Symbol ternary on line 40 is not text, so mark it for the audit by appending `// l10n:ignore: SF Symbol names` to that line. Then replace the `Text("Used: \(message.toolName ?? "tool")")` line inside the `toolResult` case with a branch (no nested literal, no fallback string):

```swift
                if let toolName = message.toolName {
                    Text("Used: \(toolName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Used a tool")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
```

`Sources/ChatFeature/ChatDetailViewModel.swift`:

```swift
    public var displayTitle: String {
        chatTitle ?? (messages.isEmpty ? String(localized: "New chat") : String(localized: "Chat"))
    }
```

- [ ] **Step 5: Update the existing title test**

In `Tests/ChatFeatureTests/ChatDetailViewModelTests.swift`, the `displayTitle` test now expects the sentence-case string. Change its `@Test` title and the expectation:

```swift
    @Test("the navigation title comes from the title event, else New chat for an empty transcript and Chat once there are messages")
    func displayTitle() async throws {
        serve(history: historyRowsJSON, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        #expect(vm.displayTitle == "New chat")
        await vm.loadHistory()
        #expect(vm.displayTitle == "Chat")
    }
```

- [ ] **Step 6: Run the audit and the module tests**

```bash
python3 scripts/l10n.py audit --source-only $EXCLUDES
```

Expected: `0 error(s)` (warnings about keys not referenced by code are fine: `Chat` and `New chat` are used only through `String(localized:)` matched by the tool, so they should not warn; any warning must be explained by an excluded file). Then run the `ChatFeature`, `SettingsFeature`, `NetworkingKit` and `Models` commands: all `TEST SUCCEEDED`, counts unchanged from Task 1.

- [ ] **Step 7: Prove the catalogs reach the app bundle**

```bash
SCRATCH=<the scratchpad directory from your dispatch>
printf '{"Settings":{"de":"Einstellungen"}}' > "$SCRATCH/smoke.json"
python3 scripts/l10n.py fill "$SCRATCH/smoke.json"
tuist generate --no-open
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -derivedDataPath "$SCRATCH/dd" \
  -destination "platform=iOS Simulator,id=$UDID" 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
APP="$SCRATCH/dd/Build/Products/Debug-iphonesimulator/Exodus.app"
ls "$APP" | grep lproj
plutil -p "$APP/de.lproj/Localizable.strings"
plutil -p "$APP/en.lproj/InfoPlist.strings"
plutil -p "$APP/Info.plist" | grep NSLocalNetwork
grep -A14 knownRegions ExodusIos.xcodeproj/project.pbxproj | head -16
git status --short Resources
```

Expected: `BUILD SUCCEEDED`; `de.lproj` and `en.lproj` listed; `"Settings" => "Einstellungen"`; the English permission text in `en.lproj/InfoPlist.strings` and in `Info.plist`; the ten regions in `knownRegions`; `git status` shows only the two catalog files as new or changed (the build must not rewrite them; if it does, look at the diff and stop to report). If `de.lproj` is missing, the catalog is not being compiled into the app: check that `Resources/App` is still a `buildableFolders` entry of the `App` target and that the JSON is valid (`python3 -c "import json;json.load(open('Resources/App/Localizable.xcstrings'))"`). The German value stays; Task 8 keeps or replaces it.

- [ ] **Step 8: Document the conventions in the README**

Append to `README.md` (before "Security note") a section that states, in plain sentences: strings live in `Resources/App/Localizable.xcstrings` and `InfoPlist.xcstrings` keyed by English text; SwiftUI literals localize automatically and other code uses `String(localized:)` or `LocalizedStringResource("…")`; the shipped languages (the ten listed in Global Constraints; there is no Simplified Chinese, matching the desktop); how to add a string (`python3 scripts/l10n.py add "Text" --comment "…"`), fill translations (`fill`), seed from the desktop's catalogs (`seed-from-desktop ~/Code/exodus/exodus/packages/shared/src/i18n/locales`) and audit (`audit`); the never-list from Global Constraints (no concatenation, no ternary of literals, user data verbatim); and that translations are AI-generated unless copied from the desktop and have not been reviewed by native speakers. Also change the old "then 连接" wording in "Connecting to the desktop" to "then Connection".

- [ ] **Step 9: Commit**

```bash
git add -A scripts Resources Project.swift Sources Tests README.md
git commit -m "i18n foundation: String Catalogs, l10n tool, Tuist regions

Every string in the files that survive the redesign goes through the
catalog; the tool adds keys, fills translations and audits them.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Search data layer (TDD)

The search wire type, query-string support in `APIClient`, the snippet builder and `ChatSearchViewModel`. Nothing here touches a view.

**Files:**
- Create: `Sources/Models/ChatSearchHit.swift`, `Sources/ChatFeature/CollapsedWhitespace.swift`, `Sources/ChatFeature/ChatSearchSnippet.swift`, `Sources/ChatFeature/ChatSearchViewModel.swift`
- Modify: `Sources/NetworkingKit/APIClient.swift`
- Test: `Tests/ModelsTests/ChatSearchHitTests.swift`, `Tests/NetworkingKitTests/APIClientTests.swift` (add tests), `Tests/ChatFeatureTests/ChatSearchSnippetTests.swift`, `Tests/ChatFeatureTests/ChatSearchViewModelTests.swift`

**Interfaces:**
- Produces: `struct ChatSearchHit: Decodable, Equatable, Sendable, Identifiable` with `init(id:chatId:role:searchText:title:createdAt:)`.
- Produces: `APIClient.get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T`.
- Produces: `extension String { var collapsedWhitespace: String }` (internal to ChatFeature).
- Produces: `enum ChatSearchSnippet { static func make(from text: String?, query: String) -> String? }`.
- Produces: `struct ChatSearchResult: Identifiable, Equatable, Sendable { id, title, snippet: String? }`, `protocol ChatSearchService`, `struct APIChatSearchService`, and `@MainActor @Observable final class ChatSearchViewModel` with `Phase` (`idle`, `results([ChatSearchResult])`, `empty`, `failed(String)`), `query`, `phase`, `isSearching`, `hasQuery`, `updateQuery(_:)`, `retry()`, `reset()`, `static func group(_:query:)`.

- [ ] **Step 1: Write the `ChatSearchHit` tests**

Create `Tests/ModelsTests/ChatSearchHitTests.swift`:

```swift
import Foundation
import Testing

@testable import Models

@Suite("ChatSearchHit")
struct ChatSearchHitTests {
    @Test("decodes a real search row and ignores the other message columns")
    func decodesARealRow() throws {
        let json = #"""
            [{"id":"m1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"hello"}],
              "searchText":"hello world","title":"Greeting","createdAt":"2026-09-09T00:26:27.327Z",
              "usage":{"input":3},"toolCallId":null,"details":null,"durationMs":12}]
            """#
        let hits = try JSONDecoder().decode([ChatSearchHit].self, from: Data(json.utf8))
        #expect(
            hits == [
                ChatSearchHit(
                    id: "m1", chatId: "c1", role: "assistant", searchText: "hello world", title: "Greeting",
                    createdAt: "2026-09-09T00:26:27.327Z")
            ])
    }

    @Test("a null or missing searchText, role and createdAt decode as nil")
    func optionalFieldsMayBeMissing() throws {
        let json = #"{"id":"m1","chatId":"c1","title":"T","searchText":null}"#
        let hit = try JSONDecoder().decode(ChatSearchHit.self, from: Data(json.utf8))
        #expect(hit.searchText == nil)
        #expect(hit.role == nil)
        #expect(hit.createdAt == nil)
    }

    @Test("a row without a title is rejected")
    func titleIsRequired() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChatSearchHit.self, from: Data(#"{"id":"m1","chatId":"c1"}"#.utf8))
        }
    }
}
```

- [ ] **Step 2: Run it and see it fail**

Run the `Models` command. Expected: build failure `cannot find 'ChatSearchHit' in scope`.

- [ ] **Step 3: Implement `ChatSearchHit`**

Create `Sources/Models/ChatSearchHit.swift`:

```swift
/// One row of `GET /api/v1/chat/search`: a message database row plus its chat's `title`. Only the
/// columns the app uses are decoded; every other column of the row is ignored. `searchText` is the
/// indexable text of a user or assistant message (text blocks only), and may be null.
public struct ChatSearchHit: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var chatId: String
    public var role: String?
    public var searchText: String?
    public var title: String
    public var createdAt: String?

    public init(
        id: String, chatId: String, role: String? = nil, searchText: String? = nil, title: String,
        createdAt: String? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.role = role
        self.searchText = searchText
        self.title = title
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, chatId, role, searchText, title, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        chatId = try container.decode(String.self, forKey: .chatId)
        title = try container.decode(String.self, forKey: .title)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        searchText = try container.decodeIfPresent(String.self, forKey: .searchText)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}
```

- [ ] **Step 4: Run it and see it pass**

Run `tuist generate --no-open`, then the `Models` command. Expected: `TEST SUCCEEDED`, three more tests than before (29).

- [ ] **Step 5: Write the `APIClient` query tests**

Append these tests inside `struct APIClientTests` in `Tests/NetworkingKitTests/APIClientTests.swift` (they use the file's existing `stub`, `makeClient` and `RequestRecorder`):

```swift
    @Test("get(_:query:) percent-encodes reserved characters so the server decodes the original text")
    func getEncodesReservedCharacters() async throws {
        let recorder = stub(status: 200, body: "[]")
        let _: [ChatSummary] = try await makeClient().get(
            "/api/v1/chat/search", query: [URLQueryItem(name: "query", value: "c++ & 100%")])
        let url = try #require(recorder.requests.first?.url)
        #expect(url.path == "/api/v1/chat/search")
        #expect(url.absoluteString.hasSuffix("/api/v1/chat/search?query=c%2B%2B%20%26%20100%25"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items == [URLQueryItem(name: "query", value: "c++ & 100%")])
    }

    @Test("query values with CJK text, spaces and # are UTF-8 percent-encoded")
    func getEncodesCJKAndFragmentCharacters() async throws {
        let recorder = stub(status: 200, body: "[]")
        let _: [ChatSummary] = try await makeClient().get(
            "/api/v1/chat/search", query: [URLQueryItem(name: "query", value: "你好 #1")])
        let url = try #require(recorder.requests.first?.url)
        #expect(url.absoluteString.hasSuffix("?query=%E4%BD%A0%E5%A5%BD%20%231"))
    }

    @Test("a get without query items sends no question mark")
    func getWithoutQueryHasNoQueryString() async throws {
        let recorder = stub(status: 200, body: "[]")
        let _: [ChatSummary] = try await makeClient().get("/api/v1/history")
        let url = try #require(recorder.requests.first?.url)
        #expect(url.query == nil)
        #expect(url.absoluteString.hasSuffix("/api/v1/history"))
    }
```

- [ ] **Step 6: Run and see them fail**

Run the `NetworkingKit` command. Expected: build failure (`extra argument 'query' in call`).

- [ ] **Step 7: Implement `get(_:query:)`**

In `Sources/NetworkingKit/APIClient.swift` change `get`, thread `query` through `send`, and build the URL with `URLComponents`:

```swift
    public func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(path: path, query: query, method: "GET", body: Optional<String>.none)
    }
```

```swift
    private func send<Body: Encodable, T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Body?,
        decodeResponse: Bool = true
    ) async throws -> T {
        guard let base = URL(string: serverConfig.baseURLString) else {
            throw HTTPError(
                statusCode: 0, code: "INVALID_BASE_URL",
                message: String(localized: "Invalid server URL: \(serverConfig.baseURLString)"))
        }
        var url = base.appendingPathComponent(path)
        if !query.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.percentEncodedQuery = query
                .map { "\(Self.encodeQueryComponent($0.name))=\(Self.encodeQueryComponent($0.value ?? ""))" }
                .joined(separator: "&")
            guard let withQuery = components?.url else {
                throw HTTPError(
                    statusCode: 0, code: "INVALID_BASE_URL",
                    message: String(localized: "Invalid server URL: \(serverConfig.baseURLString)"))
            }
            url = withQuery
        }
        var request = URLRequest(url: url)
```

(Keep the rest of `send` unchanged from `request.httpMethod = method` on.) Add the helper next to `throwIfError`:

```swift
    /// Percent-encodes one query name or value. `+ & = # ? ;` are encoded too (unlike
    /// `urlQueryAllowed`), so a value such as `c++ & 100%` reaches the server as typed.
    private static func encodeQueryComponent(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#?;")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
```

- [ ] **Step 8: Run and see them pass**

Run the `NetworkingKit` command. Expected: `TEST SUCCEEDED`, three more tests than before (37).

- [ ] **Step 9: Write the snippet tests**

Create `Tests/ChatFeatureTests/ChatSearchSnippetTests.swift`:

```swift
import Testing

@testable import ChatFeature

@Suite("ChatSearchSnippet")
struct ChatSearchSnippetTests {
    @Test("windows around the first match: 40 characters before, 80 after, ellipses on both cut ends")
    func windowsAroundTheMatch() throws {
        let text = String(repeating: "a", count: 100) + "NEEDLE" + String(repeating: "b", count: 100)
        let snippet = try #require(ChatSearchSnippet.make(from: text, query: "needle"))
        #expect(snippet == "…" + String(repeating: "a", count: 40) + "NEEDLE" + String(repeating: "b", count: 80) + "…")
    }

    @Test("no ellipsis when the window reaches both ends of the text")
    func shortTextIsReturnedWhole() throws {
        #expect(ChatSearchSnippet.make(from: "alpha needle omega", query: "needle") == "alpha needle omega")
    }

    @Test("matching ignores case and diacritics")
    func matchIgnoresCaseAndDiacritics() throws {
        let text = String(repeating: "x", count: 60) + "Café au lait" + String(repeating: "y", count: 10)
        let snippet = try #require(ChatSearchSnippet.make(from: text, query: "CAFE"))
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.contains("Café au lait"))
    }

    @Test("runs of whitespace and newlines collapse to single spaces")
    func whitespaceCollapses() {
        #expect(ChatSearchSnippet.make(from: "one\n\n  two\tthree", query: "two") == "one two three")
    }

    @Test("a text without the query falls back to its first 120 characters")
    func noMatchFallsBackToTheStart() throws {
        let text = String(repeating: "z", count: 300)
        let snippet = try #require(ChatSearchSnippet.make(from: text, query: "missing"))
        #expect(snippet == String(repeating: "z", count: 120) + "…")
    }

    @Test("a nil, empty or blank text has no snippet")
    func emptyTextHasNoSnippet() {
        #expect(ChatSearchSnippet.make(from: nil, query: "a") == nil)
        #expect(ChatSearchSnippet.make(from: "", query: "a") == nil)
        #expect(ChatSearchSnippet.make(from: " \n\t ", query: "a") == nil)
    }

    @Test("CJK text has no spaces to break on and is windowed by characters")
    func cjkIsWindowedByCharacters() throws {
        let text = String(repeating: "前", count: 60) + "台积电" + String(repeating: "后", count: 100)
        let snippet = try #require(ChatSearchSnippet.make(from: text, query: "台积电"))
        #expect(snippet == "…" + String(repeating: "前", count: 40) + "台积电" + String(repeating: "后", count: 80) + "…")
    }

    @Test("collapsedWhitespace joins words with single spaces and trims the ends")
    func collapsedWhitespace() {
        #expect("  a \n\n b\tc  ".collapsedWhitespace == "a b c")
        #expect("".collapsedWhitespace == "")
    }
}
```

- [ ] **Step 10: Run and see them fail**

Run the `ChatFeature` command. Expected: build failure (`cannot find 'ChatSearchSnippet' in scope`).

- [ ] **Step 11: Implement the snippet builder**

Create `Sources/ChatFeature/CollapsedWhitespace.swift`:

```swift
extension String {
    /// Every run of whitespace and newlines collapsed to one space, the ends trimmed. Real chat
    /// titles can be long and multi-line; every place that shows one goes through this.
    var collapsedWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
```

Create `Sources/ChatFeature/ChatSearchSnippet.swift`:

```swift
import Foundation

/// Builds the one-line context shown under a search result's title.
enum ChatSearchSnippet {
    static let charactersBefore = 40
    static let charactersAfter = 80
    static let fallbackLength = 120

    /// `text` is a hit's `searchText`. The window is centred on the first case- and
    /// diacritic-insensitive match of `query`; with no match it is the start of the text. Nil when
    /// there is no text.
    static func make(from text: String?, query: String) -> String? {
        guard let text else { return nil }
        let collapsed = text.collapsedWhitespace
        guard !collapsed.isEmpty else { return nil }
        let needle = query.collapsedWhitespace
        if !needle.isEmpty,
            let match = collapsed.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
        {
            let start =
                collapsed.index(match.lowerBound, offsetBy: -charactersBefore, limitedBy: collapsed.startIndex)
                ?? collapsed.startIndex
            let end =
                collapsed.index(match.upperBound, offsetBy: charactersAfter, limitedBy: collapsed.endIndex)
                ?? collapsed.endIndex
            return window(of: collapsed, from: start, to: end)
        }
        let end =
            collapsed.index(collapsed.startIndex, offsetBy: fallbackLength, limitedBy: collapsed.endIndex)
            ?? collapsed.endIndex
        return window(of: collapsed, from: collapsed.startIndex, to: end)
    }

    private static func window(of text: String, from start: String.Index, to end: String.Index) -> String {
        let body = text[start..<end].trimmingCharacters(in: .whitespaces)
        return (start > text.startIndex ? "…" : "") + body + (end < text.endIndex ? "…" : "")
    }
}
```

- [ ] **Step 12: Run and see them pass**

Run `tuist generate --no-open`, then the `ChatFeature` command. Expected: `TEST SUCCEEDED`, eight more tests than before (60).

- [ ] **Step 13: Write the view-model tests**

Create `Tests/ChatFeatureTests/ChatSearchViewModelTests.swift`:

```swift
import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

// MARK: - Test doubles

/// Answers immediately from a script (then with no hits), recording every query it saw.
private actor RecordingService: ChatSearchService {
    private(set) var queries: [String] = []
    private var script: [Result<[ChatSearchHit], Error>]

    init(script: [Result<[ChatSearchHit], Error>] = []) { self.script = script }

    func search(query: String) async throws -> [ChatSearchHit] {
        queries.append(query)
        if script.isEmpty { return [] }
        return try script.removeFirst().get()
    }
}

/// Holds every request open until the test completes it, so responses can arrive out of order.
private actor ControlledService: ChatSearchService {
    private(set) var queries: [String] = []
    private var pending: [String: CheckedContinuation<[ChatSearchHit], Error>] = [:]

    func search(query: String) async throws -> [ChatSearchHit] {
        queries.append(query)
        return try await withCheckedThrowingContinuation { pending[query] = $0 }
    }

    func complete(_ query: String, with hits: [ChatSearchHit]) {
        pending.removeValue(forKey: query)?.resume(returning: hits)
    }
}

private func hit(_ chatId: String, title: String = "T", text: String? = "some text", id: String = UUID().uuidString)
    -> ChatSearchHit
{
    ChatSearchHit(id: id, chatId: chatId, role: "assistant", searchText: text, title: title, createdAt: nil)
}

/// Polls (bounded) until `condition` holds, so a broken build fails instead of hanging.
@MainActor
private func waitUntil(
    _ what: String, timeout: Duration = .seconds(5), _ condition: @MainActor () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
        try #require(ContinuousClock.now < deadline, "timed out waiting for \(what)")
        try await Task.sleep(for: .milliseconds(2))
    }
}

private final class SearchMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SearchMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - Tests

@MainActor
@Suite("ChatSearchViewModel", .serialized)
struct ChatSearchViewModelTests {
    @Test("a blank query issues no request and stays idle")
    func blankQueryDoesNotSearch() async throws {
        let service = RecordingService()
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(5))
        vm.updateQuery("   ")
        try await Task.sleep(for: .milliseconds(60))
        #expect(await service.queries.isEmpty)
        #expect(vm.phase == .idle)
        #expect(vm.isSearching == false)
        #expect(vm.hasQuery == false)
    }

    @Test("rapid edits are coalesced into one request for the last text")
    func debounceCoalescesEdits() async throws {
        let service = RecordingService()
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(40))
        vm.updateQuery("a")
        vm.updateQuery("ab")
        vm.updateQuery("abc")
        try await waitUntil("the search to finish") { vm.phase != .idle }
        #expect(await service.queries == ["abc"])
        #expect(vm.phase == .empty)
        #expect(vm.isSearching == false)
    }

    @Test("hits are grouped by chat in first-seen order, one result per chat, with a snippet and a one-line title")
    func groupsHitsByChat() async throws {
        let service = RecordingService(script: [
            .success([
                hit("c1", title: "One", text: "alpha needle omega", id: "m1"),
                hit("c1", title: "One", text: "second hit in the same chat", id: "m2"),
                hit("c2", title: "Two\n\nlines", text: nil, id: "m3"),
            ])
        ])
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("needle")
        try await waitUntil("results") { vm.phase != .idle }
        #expect(
            vm.phase == .results([
                ChatSearchResult(id: "c1", title: "One", snippet: "alpha needle omega"),
                ChatSearchResult(id: "c2", title: "Two lines", snippet: nil),
            ]))
    }

    @Test("at most 50 chats are listed")
    func capsTheResults() async throws {
        let hits = (0..<60).map { hit("chat\($0)", id: "m\($0)") }
        let service = RecordingService(script: [.success(hits)])
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("some")
        try await waitUntil("results") { vm.phase != .idle }
        guard case .results(let results) = vm.phase else {
            Issue.record("expected results")
            return
        }
        #expect(results.count == ChatSearchViewModel.maxResults)
        #expect(results.first?.id == "chat0")
        #expect(results.last?.id == "chat49")
    }

    @Test("a failure is shown as failed(message) and retry() runs the same query again")
    func failureThenRetry() async throws {
        let service = RecordingService(script: [
            .failure(HTTPError(statusCode: 500, code: "X", message: "boom")),
            .success([hit("c1", title: "One", text: "some text")]),
        ])
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("q")
        try await waitUntil("the failure") { vm.phase != .idle }
        #expect(vm.phase == .failed("boom"))
        #expect(vm.isSearching == false)

        vm.retry()
        try await waitUntil("the retry") { vm.phase != .failed("boom") }
        #expect(vm.phase == .results([ChatSearchResult(id: "c1", title: "One", snippet: "some text")]))
        #expect(await service.queries == ["q", "q"])
    }

    @Test("a response that arrives after a newer query started is dropped")
    func staleResponseIsDropped() async throws {
        let service = ControlledService()
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("first")
        try await waitUntil("the first request") { await service.queries == ["first"] }
        vm.updateQuery("second")
        try await waitUntil("the second request") { await service.queries == ["first", "second"] }

        await service.complete("second", with: [hit("c2", title: "Second")])
        try await waitUntil("the second results") { vm.phase != .idle }
        await service.complete("first", with: [hit("c1", title: "First")])
        try await Task.sleep(for: .milliseconds(50))

        #expect(vm.phase == .results([ChatSearchResult(id: "c2", title: "Second", snippet: "some text")]))
        #expect(vm.isSearching == false)
    }

    @Test("reset() clears the query and results, and a response that arrives afterwards is ignored")
    func resetClearsEverything() async throws {
        let service = ControlledService()
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("q")
        try await waitUntil("the request") { await service.queries == ["q"] }
        #expect(vm.isSearching)

        vm.reset()
        #expect(vm.query == "")
        #expect(vm.phase == .idle)
        #expect(vm.isSearching == false)

        await service.complete("q", with: [hit("c1")])
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.phase == .idle)
    }

    @Test("a cancellation is not shown as a failure")
    func cancellationIsNotAFailure() async throws {
        let service = RecordingService(script: [.failure(CancellationError())])
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("q")
        try await waitUntil("the request to finish") { vm.isSearching == false && !(await service.queries.isEmpty) }
        #expect(vm.phase == .idle)
    }

    @Test("hasQuery ignores surrounding whitespace")
    func hasQueryTrims() {
        let vm = ChatSearchViewModel(service: RecordingService(), debounce: .milliseconds(1))
        #expect(vm.hasQuery == false)
        vm.updateQuery("  x ")
        #expect(vm.hasQuery)
        vm.reset()
    }

    @Test("APIChatSearchService calls GET /api/v1/chat/search with the query encoded and decodes the rows")
    func apiServiceUsesTheRightEndpoint() async throws {
        let seen = Mutex<URL?>(nil)
        let rows = #"[{"id":"m1","chatId":"c1","role":"user","searchText":"hi","title":"Greeting"}]"#
        SearchMockURLProtocol.handler = { request in
            seen.withLock { $0 = request.url }
            return (200, Data(rows.utf8))
        }
        let suite = "ChatSearchViewModelTests.apiService"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let client = APIClient(
            session: SearchMockURLProtocol.makeSession(), serverConfig: ServerConfigStore(userDefaults: defaults))

        let hits = try await APIChatSearchService(apiClient: client).search(query: "c++ tips")

        let url = try #require(seen.withLock { $0 })
        #expect(url.path == "/api/v1/chat/search")
        #expect(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                == [URLQueryItem(name: "query", value: "c++ tips")])
        #expect(hits.map(\.chatId) == ["c1"])
    }
}
```

- [ ] **Step 14: Run and see them fail**

Run the `ChatFeature` command. Expected: build failure (`cannot find 'ChatSearchViewModel' in scope`).

- [ ] **Step 15: Implement the view model**

Create `Sources/ChatFeature/ChatSearchViewModel.swift`:

```swift
import Foundation
import Models
import NetworkingKit
import Observation

/// One chat in the search results: its title and the context of its first matching message.
public struct ChatSearchResult: Identifiable, Equatable, Sendable {
    public let id: String  // the chat id
    public let title: String
    public let snippet: String?

    public init(id: String, title: String, snippet: String?) {
        self.id = id
        self.title = title
        self.snippet = snippet
    }
}

/// The seam between the view model and the network, so tests can answer out of order.
public protocol ChatSearchService: Sendable {
    func search(query: String) async throws -> [ChatSearchHit]
}

public struct APIChatSearchService: ChatSearchService {
    private let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public func search(query: String) async throws -> [ChatSearchHit] {
        try await apiClient.get("/api/v1/chat/search", query: [URLQueryItem(name: "query", value: query)])
    }
}

@MainActor
@Observable
public final class ChatSearchViewModel {
    public enum Phase: Equatable {
        case idle
        case results([ChatSearchResult])
        case empty
        case failed(String)
    }

    public static let maxResults = 50

    public private(set) var query = ""
    public private(set) var phase: Phase = .idle
    public private(set) var isSearching = false

    /// True when the trimmed query is non-empty: the sidebar shows results instead of Recents.
    public var hasQuery: Bool { !trimmedQuery.isEmpty }

    private let service: any ChatSearchService
    private let debounce: Duration
    /// Bumped by every new query and by `reset()`. A response applies only if it is still the current one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(service: any ChatSearchService, debounce: Duration = .milliseconds(300)) {
        self.service = service
        self.debounce = debounce
    }

    public convenience init(apiClient: APIClient, debounce: Duration = .milliseconds(300)) {
        self.init(service: APIChatSearchService(apiClient: apiClient), debounce: debounce)
    }

    public func updateQuery(_ text: String) {
        guard text != query else { return }
        query = text
        run()
    }

    /// Runs the current query again (the Retry button after a failure).
    public func retry() {
        guard hasQuery else { return }
        run()
    }

    /// Leaves search: cancels work, forgets the query and the results.
    public func reset() {
        task?.cancel()
        task = nil
        generation += 1
        query = ""
        phase = .idle
        isSearching = false
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func run() {
        task?.cancel()
        generation += 1
        let generation = generation
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else {
            task = nil
            phase = .idle
            isSearching = false
            return
        }
        isSearching = true
        let debounce = debounce
        task = Task { [weak self] in
            do { try await Task.sleep(for: debounce) } catch { return }
            await self?.perform(trimmed, generation: generation)
        }
    }

    private func perform(_ trimmed: String, generation: Int) async {
        do {
            let hits = try await service.search(query: trimmed)
            guard generation == self.generation else { return }
            let results = Self.group(hits, query: trimmed)
            phase = results.isEmpty ? .empty : .results(results)
            isSearching = false
        } catch {
            guard generation == self.generation else { return }
            isSearching = false
            if Self.isCancellation(error) { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// One result per chat, in the order the server returned them, at most `maxResults`. The first
    /// hit of a chat supplies the snippet.
    static func group(_ hits: [ChatSearchHit], query: String) -> [ChatSearchResult] {
        var seen = Set<String>()
        var results: [ChatSearchResult] = []
        for hit in hits where seen.insert(hit.chatId).inserted {
            results.append(
                ChatSearchResult(
                    id: hit.chatId, title: hit.title.collapsedWhitespace,
                    snippet: ChatSearchSnippet.make(from: hit.searchText, query: query)))
            if results.count == maxResults { break }
        }
        return results
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
```

- [ ] **Step 16: Run and see them pass**

Run `tuist generate --no-open`, then the `ChatFeature` command. Expected: `TEST SUCCEEDED`, ten more tests than after Step 12 (70), and a `Test run with 70 tests` line. Then run `Models` and `NetworkingKit` once more (still green).

- [ ] **Step 17: Commit**

```bash
git add -A Sources Tests
git commit -m "Search data layer: hit type, query-string GET, snippets, view model

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: View-model groundwork for the sidebar and the new detail screen

`ChatListViewModel` learns to report whether a delete succeeded and to refresh in the background without raising alerts; `ChatDetailViewModel` learns an initial title, a one-line title, and an empty-state flag; `ChatDetailView` accepts the title.

**Files:**
- Modify: `Sources/ChatFeature/ChatListViewModel.swift`, `Sources/ChatFeature/ChatDetailViewModel.swift`, `Sources/ChatFeature/ChatDetailView.swift` (init only)
- Test: `Tests/ChatFeatureTests/ChatListViewModelTests.swift`, `Tests/ChatFeatureTests/ChatDetailViewModelTests.swift`

**Interfaces:**
- Consumes: `String.collapsedWhitespace` (Task 3).
- Produces: `@discardableResult func ChatListViewModel.delete(_:) async -> Bool` (true only when the server confirmed); `func ChatListViewModel.refresh() async` (silent reload).
- Produces: `ChatDetailViewModel.init(chatId:title:apiClient:streamManager:serverConfig:)` (`title` defaults to nil), `var showsEmptyState: Bool`; `chatTitle` is always one line.
- Produces: `ChatDetailView.init(chatId:title:apiClient:streamManager:serverConfig:)` (`title` defaults to nil).

- [ ] **Step 1: Write the list view-model tests**

In `Tests/ChatFeatureTests/ChatListViewModelTests.swift`, add these tests inside `struct ChatListViewModelTests` (the file's `serve`, `makeViewModel`, `twoChatsJSON` and `serverErrorJSON` already exist):

```swift
    @Test("delete(_:) reports whether the server confirmed the delete")
    func deleteReportsSuccess() async throws {
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        let first = try #require(vm.chats.first)
        #expect(await vm.delete(first) == true)

        serve(
            history: twoChatsJSON, deleteStatus: 500,
            deleteBody: #"{"type":"error","error":{"code":"DB_QUERY_FAILED","message":"Failed to delete chat"}}"#,
            recorder: RequestRecorder())
        let second = try #require(vm.chats.first)
        #expect(await vm.delete(second) == false)
        #expect(vm.chats.map(\.id) == ["c2"])
    }

    @Test("refresh() replaces a list that is on screen without touching the error state")
    func refreshReplacesTheListSilently() async throws {
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        serve(
            history: #"[{"id":"c3","title":"Fresh","createdAt":"2026-09-19T00:00:00.000Z"}]"#, recorder: RequestRecorder())
        await vm.refresh()
        #expect(vm.chats.map(\.id) == ["c3"])
        #expect(vm.errorMessage == nil)
        #expect(vm.loadFailed == false)
    }

    @Test("refresh() keeps the stale list and raises no error when the server fails")
    func refreshFailureIsSilentWhileAListIsShown() async throws {
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        await vm.refresh()
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.errorMessage == nil)
        #expect(vm.showsErrorAlert == false)
    }

    @Test("refresh() before anything is shown behaves like load(): a failure is reported")
    func refreshOnAnEmptyListLoads() async throws {
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.refresh()
        #expect(vm.loadFailed)
        #expect(vm.errorMessage == "Failed to get chat history")
    }

    @Test("refresh() does not resurrect a chat that was deleted")
    func refreshKeepsDeletedChatsGone() async throws {
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        let first = try #require(vm.chats.first)
        await vm.delete(first)
        serve(history: twoChatsJSON, recorder: RequestRecorder())  // a stale answer that still lists c1
        await vm.refresh()
        #expect(vm.chats.map(\.id) == ["c2"])
    }
```

- [ ] **Step 2: Run and see them fail**

Run the `ChatFeature` command. Expected: build failure (`value of type 'ChatListViewModel' has no member 'refresh'`).

- [ ] **Step 3: Implement `delete -> Bool` and `refresh()`**

In `Sources/ChatFeature/ChatListViewModel.swift` replace `delete(_:)` and add `refresh()` after `load()`:

```swift
    /// Reloads in the background (the drawer opened, Settings closed). While a list is on screen a
    /// failure is dropped: a stale list is still useful, and an alert every time the drawer opens
    /// offline would be noise. With nothing on screen it is a plain `load()`.
    public func refresh() async {
        guard hasLoaded, !chats.isEmpty else {
            await load()
            return
        }
        guard let loaded: [ChatSummary] = try? await apiClient.get("/api/v1/history") else { return }
        chats = loaded.filter { !deletedIDs.contains($0.id) }
        loadFailed = false
    }

    /// True only when the server confirmed the delete.
    @discardableResult
    public func delete(_ chat: ChatSummary) async -> Bool {
        do {
            try await apiClient.delete("/api/v1/chat/\(chat.id)")
            deletedIDs.insert(chat.id)
            chats.removeAll { $0.id == chat.id }
            return true
        } catch {
            guard !Self.isCancellation(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }
```

- [ ] **Step 4: Run and see them pass**

Run the `ChatFeature` command. Expected: `TEST SUCCEEDED`, five more tests than before (75).

- [ ] **Step 5: Write the detail view-model tests**

In `Tests/ChatFeatureTests/ChatDetailViewModelTests.swift`: first extend the harness factory (it is inside `private struct Harness`):

```swift
    func makeViewModel(chatId: String = "c1", title: String? = nil) -> ChatDetailViewModel {
        ChatDetailViewModel(
            chatId: chatId, title: title, apiClient: apiClient, streamManager: manager, serverConfig: config)
    }
```

Add a multi-line title stream near the other reply constants:

```swift
private let multilineTitleReply = """
    data: {"type":"title","title":"First line\\n\\nSecond line"}\n\n\
    data: {"type":"done","messages":[{"id":"u2","role":"user","content":"hey"},{"id":"a2","role":"assistant","content":"Hello!"}]}\n\n
    """
```

and add these tests inside `struct ChatDetailViewModelTests`:

```swift
    @Test("a chat opened with a title shows it, collapsed to one line")
    func initialTitleIsShownOnOneLine() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        #expect(Harness().makeViewModel(title: "Trip planning").displayTitle == "Trip planning")
        #expect(Harness().makeViewModel(title: "Line one\n\nLine two").displayTitle == "Line one Line two")
        #expect(Harness().makeViewModel(title: "  \n ").displayTitle == "New chat")
    }

    @Test("a title event is collapsed to one line too", .timeLimit(.minutes(1)))
    func titleEventIsCollapsed() async throws {
        serve(history: "[]", reply: multilineTitleReply, recorder: RequestRecorder())
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.chatTitle == "First line Second line")
    }

    @Test("showsEmptyState is true only for a loaded, empty, idle chat")
    func emptyStateOnlyForALoadedEmptyChat() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        #expect(vm.showsEmptyState == false)  // not loaded yet: the screen must not flash "empty"
        await vm.loadHistory()
        #expect(vm.showsEmptyState)
    }

    @Test("showsEmptyState is false when the transcript has messages")
    func noEmptyStateWithMessages() async throws {
        serve(history: historyRowsJSON, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.showsEmptyState == false)
    }

    @Test("showsEmptyState is false after a failed load")
    func noEmptyStateAfterAFailedLoad() async throws {
        serve(history: envelope404, historyStatus: 500, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.hasLoadedHistory == false)
        #expect(vm.showsEmptyState == false)
    }

    @Test("showsEmptyState is false while a turn is in flight", .timeLimit(.minutes(1)))
    func noEmptyStateWhileATurnIsInFlight() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: "", holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the chat POST to reach the server") { recorder.lines.contains("POST /api/v1/chat") }
        #expect(vm.showsEmptyState == false)
        harness.session.invalidateAndCancel()
        await send.value
    }
```

- [ ] **Step 6: Run and see them fail**

Run the `ChatFeature` command. Expected: build failure (`extra argument 'title' in call`).

- [ ] **Step 7: Implement the view-model changes**

In `Sources/ChatFeature/ChatDetailViewModel.swift`: change the initializer, add `showsEmptyState`, and normalize titles.

```swift
    public init(
        chatId: String, title: String? = nil, apiClient: APIClient, streamManager: ChatStreamManager,
        serverConfig: ServerConfigStore
    ) {
        self.chatId = chatId
        self.chatTitle = Self.oneLine(title)
        self.apiClient = apiClient
        self.streamManager = streamManager
        self.serverConfig = serverConfig
    }
```

Add next to `canSend`:

```swift
    /// True for a loaded, empty chat with nothing in flight: the view shows its greeting. Never true
    /// before the history is known, so opening a chat does not flash the greeting.
    public var showsEmptyState: Bool { hasLoadedHistory && messages.isEmpty && !isTurnInFlight }
```

In `consume`, the `.title` case becomes:

```swift
            case .title(let title):
                chatTitle = Self.oneLine(title) ?? chatTitle
```

and add the helper beside `isCancellation`:

```swift
    /// A chat title on one line; nil when there is nothing to show. Real titles can be long and multi-line.
    private static func oneLine(_ title: String?) -> String? {
        guard let collapsed = title?.collapsedWhitespace, !collapsed.isEmpty else { return nil }
        return collapsed
    }
```

In `Sources/ChatFeature/ChatDetailView.swift` change only the initializer to pass the title through:

```swift
    public init(
        chatId: String, title: String? = nil, apiClient: APIClient, streamManager: ChatStreamManager,
        serverConfig: ServerConfigStore
    ) {
        _viewModel = State(
            initialValue: ChatDetailViewModel(
                chatId: chatId, title: title, apiClient: apiClient, streamManager: streamManager,
                serverConfig: serverConfig))
    }
```

- [ ] **Step 8: Run and see them pass**

Run the `ChatFeature` command. Expected: `TEST SUCCEEDED`, six more tests than after Step 4 (81). Build the whole app (the `App` command from "Shared commands"): `BUILD SUCCEEDED` (`RootView` and `ChatListView` still compile against the unchanged call sites).

- [ ] **Step 9: Commit**

```bash
git add -A Sources Tests
git commit -m "View-model groundwork: silent refresh, delete result, one-line titles, empty state

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `ChatSidebarView` (Recents, long-press delete, inline search)

The drawer's content, in ChatFeature, with its own `NavigationStack`. It is compiled and audited here and shown on screen in Task 6 (the App does not use it yet).

**Files:**
- Create: `Sources/ChatFeature/ChatSidebarView.swift`, `Sources/ChatFeature/SidebarSearchBar.swift`
- Modify: `Resources/App/Localizable.xcstrings` (through `l10n.py add`)

**Interfaces:**
- Consumes: `ChatListViewModel` (`chats`, `isLoading`, `hasLoaded`, `loadFailed`, `errorMessage`, `showsErrorAlert`, `load()`, `refresh()`, `delete(_:) -> Bool`); `ChatSearchViewModel` (`query`, `phase`, `isSearching`, `hasQuery`, `updateQuery(_:)`, `retry()`, `reset()`); `String.collapsedWhitespace`.
- Produces: `public struct ChatSidebarView<Workspaces: View>: View` with

```swift
public init(
    apiClient: APIClient,
    activeChatId: String,
    isOpen: Bool,
    reloadToken: Int,
    onSelectChat: @escaping (String, String?) -> Void,   // chat id, title
    onNewChat: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void,
    onDeleteChat: @escaping (String) -> Void,            // called only after the server confirmed the delete
    @ViewBuilder workspaces: () -> Workspaces
)
```

  and accessibility identifiers `sidebarSearch`, `sidebarNewChat`, `sidebarSettings`, `searchField`, `searchCancel` (used by Task 9's UI test).

- [ ] **Step 1: Add the keys**

```bash
add() { python3 scripts/l10n.py add "$@"; }
add "Recents" --comment "Section header above the list of recent conversations in the sidebar."
add "Search" --comment "Sidebar search: the field's placeholder and the accessibility label of the magnifier button."
add "Clear" --comment "Accessibility label of the button that clears the search text."
add "Delete" --comment "Context-menu action that deletes a conversation."
add "Can't load chats" --comment "Title shown when the conversation list could not be loaded."
add "Pull down or tap Retry to try again." --comment "Hint under the load failure message."
add "Retry" --comment "Button that repeats a failed request."
add "No chats yet" --comment "Shown when the conversation list is empty."
add "Error" --comment "Title of an error alert."
add "OK" --comment "Dismisses an alert."
add "No results" --comment "Shown when a search finds nothing."
add "Search failed" --comment "Title shown when a search request fails."
add "Searching" --comment "Accessibility label of the spinner while a search runs."
```

- [ ] **Step 2: Write the search bar**

Create `Sources/ChatFeature/SidebarSearchBar.swift`:

```swift
import SwiftUI

/// The sidebar's search field: a native `TextField` in a glass capsule with a Cancel button. Built by
/// hand because `.searchable` did not respond inside the drawer (see the spec, section 3).
struct SidebarSearchBar: View {
    @Binding var text: String
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search", text: $text)
                    .focused($focused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("searchField")
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)

            Button("Cancel", action: onCancel)
                .accessibilityIdentifier("searchCancel")
        }
        .padding(.horizontal, 12)
        .onAppear { focused = true }
    }
}
```

- [ ] **Step 3: Write the sidebar**

Create `Sources/ChatFeature/ChatSidebarView.swift`:

```swift
import Models
import NetworkingKit
import SwiftUI

/// The drawer's content: workspaces, Recents, and an inline search. It owns its `NavigationStack`, so
/// the title, the search button and the bottom bar are native. Rows have no swipe actions (a left
/// swipe closes the drawer); a chat is deleted from its long-press menu.
public struct ChatSidebarView<Workspaces: View>: View {
    @State private var list: ChatListViewModel
    @State private var search: ChatSearchViewModel
    @State private var isSearching = false

    private let activeChatId: String
    private let isOpen: Bool
    private let reloadToken: Int
    private let onSelectChat: (String, String?) -> Void
    private let onNewChat: () -> Void
    private let onOpenSettings: () -> Void
    private let onDeleteChat: (String) -> Void
    private let workspaces: Workspaces

    /// A brand name: a plain `String`, shown as is and never looked up in the catalog.
    private static var appName: String { "Exodus" }

    public init(
        apiClient: APIClient,
        activeChatId: String,
        isOpen: Bool,
        reloadToken: Int,
        onSelectChat: @escaping (String, String?) -> Void,
        onNewChat: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onDeleteChat: @escaping (String) -> Void,
        @ViewBuilder workspaces: () -> Workspaces
    ) {
        _list = State(initialValue: ChatListViewModel(apiClient: apiClient))
        _search = State(initialValue: ChatSearchViewModel(apiClient: apiClient))
        self.activeChatId = activeChatId
        self.isOpen = isOpen
        self.reloadToken = reloadToken
        self.onSelectChat = onSelectChat
        self.onNewChat = onNewChat
        self.onOpenSettings = onOpenSettings
        self.onDeleteChat = onDeleteChat
        self.workspaces = workspaces()
    }

    public var body: some View {
        NavigationStack {
            List {
                if isSearching && search.hasQuery {
                    searchResultRows
                } else {
                    if !isSearching {
                        Section { workspaces }
                    }
                    Section("Recents") {
                        ForEach(list.chats) { chat in
                            row(for: chat)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay { overlayContent }
            .navigationTitle(isSearching ? "" : Self.appName)
            .navigationBarTitleDisplayMode(isSearching ? .inline : .large)
            .safeAreaBar(edge: .top) {
                if isSearching {
                    SidebarSearchBar(
                        text: Binding(get: { search.query }, set: { search.updateQuery($0) }),
                        onCancel: leaveSearch)
                }
            }
            .toolbar { sidebarToolbar }
            // Hidden while searching so it cannot ghost through the keyboard.
            .toolbarVisibility(isSearching ? .hidden : .visible, for: .bottomBar)
            .task(id: reloadToken) { await list.refresh() }
            .refreshable { await list.load() }
            .onChange(of: isOpen) { _, nowOpen in
                if nowOpen {
                    Task { await list.refresh() }
                } else {
                    leaveSearch()
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { list.showsErrorAlert },
                    set: { if !$0 { list.errorMessage = nil } }
                )
            ) {
                Button("OK") {}
            } message: {
                Text(list.errorMessage ?? "")
            }
        }
    }

    // MARK: - Rows

    private func row(for chat: ChatSummary) -> some View {
        Button {
            onSelectChat(chat.id, chat.title)
        } label: {
            Text(chat.title.collapsedWhitespace)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(chat.id == activeChatId ? Color.accentColor.opacity(0.12) : Color.clear)
        .accessibilityAddTraits(chat.id == activeChatId ? .isSelected : [])
        // Closes over this row's chat, so nothing indexes `list.chats` after a concurrent load.
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    if await list.delete(chat) { onDeleteChat(chat.id) }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var searchResultRows: some View {
        if case .results(let results) = search.phase {
            ForEach(results) { result in
                Button {
                    onSelectChat(result.id, result.title)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .lineLimit(1)
                        if let snippet = result.snippet {
                            Text(snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var overlayContent: some View {
        if isSearching && search.hasQuery {
            switch search.phase {
            case .idle where search.isSearching:
                ProgressView()
                    .accessibilityLabel("Searching")
            case .empty:
                ContentUnavailableView("No results", systemImage: "magnifyingglass")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Search failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { search.retry() }
                }
            default:
                EmptyView()
            }
        } else if list.chats.isEmpty {
            // Not loaded yet reads as "loading", never as "No chats yet".
            if list.isLoading || !list.hasLoaded {
                ProgressView()
            } else if list.loadFailed {
                ContentUnavailableView {
                    Label("Can't load chats", systemImage: "wifi.exclamationmark")
                } description: {
                    // The error text lives here, not in an alert (see `showsErrorAlert`).
                    VStack(spacing: 4) {
                        if let message = list.errorMessage {
                            Text(message)
                        }
                        Text("Pull down or tap Retry to try again.")
                    }
                } actions: {
                    Button("Retry") { Task { await list.load() } }
                }
            } else {
                ContentUnavailableView("No chats yet", systemImage: "message")
            }
        }
    }

    // MARK: - Toolbar and search mode

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        if !isSearching {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) { isSearching = true }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("sidebarSearch")
            }
        }
        ToolbarItem(placement: .bottomBar) {
            Button(action: onNewChat) {
                Label("New chat", systemImage: "square.and.pencil")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("sidebarNewChat")
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("sidebarSettings")
        }
    }

    private func leaveSearch() {
        withAnimation(.snappy) { isSearching = false }
        search.reset()
    }
}
```

- [ ] **Step 4: Audit and build**

```bash
python3 scripts/l10n.py audit --source-only $EXCLUDES
tuist generate --no-open
```

(`EXCLUDES` is the variable from Task 2 Step 1; re-create it in a new shell: `--exclude Sources/App/RootView.swift --exclude Sources/ChatFeature/ChatListView.swift --exclude Sources/ChatFeature/ChatDetailView.swift`.) Expected: `0 error(s)`. Then the `App` build command: `BUILD SUCCEEDED`. Fix any compile error by adjusting spelling only; the behavior described in the doc comments is the requirement.

- [ ] **Step 5: Commit**

```bash
git add -A Sources Resources
git commit -m "Chat sidebar: Recents, long-press delete, inline search

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: `SideDrawer` and `AppShell` replace the list-then-push root

The custom sliding container, the shell that owns the active chat and the drawer, and the deletion of the old root and list view.

**Files:**
- Create: `Sources/App/SideDrawer.swift`, `Sources/App/AppShell.swift`, `Sources/App/WorkspaceRow.swift`
- Modify: `Sources/App/AppWorkspace.swift`, `Sources/App/ExodusApp.swift`, `Sources/ChatFeature/ChatListViewModel.swift` (remove `relativeTime`), `Tests/ChatFeatureTests/ChatListViewModelTests.swift` (remove its test), `Resources/App/Localizable.xcstrings`
- Delete: `Sources/App/RootView.swift`, `Sources/ChatFeature/ChatListView.swift`

**Interfaces:**
- Consumes: `ChatSidebarView` (Task 5), `ChatDetailView(chatId:title:apiClient:streamManager:serverConfig:)` (Task 4), `PhilharmonicPlaceholderView`, `SettingsView`.
- Produces: `AppShell(apiClient:streamManager:serverConfig:)`, `SideDrawer(isOpen:sidebar:content:)`, `func drawerAnimation(reduceMotion: Bool) -> Animation`, `enum AppWorkspace` with `title: LocalizedStringResource`, `systemImage`, `isAvailable`. Accessibility identifiers `sidebarToggle` and `topNewChat` (Task 9).

- [ ] **Step 1: Add the keys**

```bash
add() { python3 scripts/l10n.py add "$@"; }
add "Philharmonic" --no-translate --comment "Product name of the multi-agent workspace; never translated."
add "Open sidebar" --comment "Accessibility label of the button that opens the sidebar."
add "Close sidebar" --comment "Accessibility label of the button and scrim that close the sidebar."
```

- [ ] **Step 2: Rewrite `AppWorkspace`**

Replace the whole of `Sources/App/AppWorkspace.swift`:

```swift
import Foundation

/// The top-level areas of the app. Philharmonic is listed but not available yet.
enum AppWorkspace: CaseIterable, Identifiable {
    case chat
    case philharmonic

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .chat:
            LocalizedStringResource(
                "Chat", comment: "Name of the chat workspace, and the title of an open conversation that has no name yet.")
        case .philharmonic:
            LocalizedStringResource("Philharmonic")
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .philharmonic: "music.note.list"
        }
    }

    var isAvailable: Bool { self == .chat }
}
```

- [ ] **Step 3: Write the drawer**

Create `Sources/App/SideDrawer.swift`:

```swift
import SwiftUI
import UIKit

/// The animation for opening and closing the drawer; the shell's own toggles use it too.
func drawerAnimation(reduceMotion: Bool) -> Animation {
    reduceMotion ? .easeInOut(duration: 0.2) : .snappy
}

/// A slide-out drawer like the ChatGPT app's: the content is a rounded card that is pushed to the
/// right over a sidebar. iOS has no native phone drawer, so this container is custom; everything
/// inside it is native SwiftUI. It ignores only the `.container` safe area, never the keyboard's,
/// so a composer inside the card still rises with the keyboard.
struct SideDrawer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var content: () -> Content

    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxDrawerWidth: CGFloat = 360
    private let edgeGrabWidth: CGFloat = 28
    private let openCornerRadius: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let drawerWidth = min(geo.size.width * 0.78, maxDrawerWidth)
            let base: CGFloat = isOpen ? drawerWidth : 0
            let offset = min(max(base + drag, 0), drawerWidth)
            let progress = drawerWidth > 0 ? offset / drawerWidth : 0

            ZStack(alignment: .leading) {
                sidebar()
                    .frame(width: drawerWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    // Closed: invisible, inert and skipped by VoiceOver.
                    .opacity(progress > 0 ? 1 : 0)
                    .allowsHitTesting(isOpen)
                    .accessibilityHidden(!isOpen)

                content()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .background(Color(.systemBackground))
                    .overlay {
                        Color(.systemBackground)
                            .opacity(0.6 * progress)
                            .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius(progress), style: .continuous))
                    .shadow(color: .black.opacity(0.15 * progress), radius: 24, x: -4)
                    .offset(x: offset)
                    .accessibilityHidden(isOpen)

                if isOpen {
                    // The tap target over the card: one VoiceOver button that closes the drawer.
                    Color.clear
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .offset(x: offset)
                        .onTapGesture { setOpen(false) }
                        .accessibilityElement()
                        .accessibilityLabel("Close sidebar")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .simultaneousGesture(dragGesture(drawerWidth: drawerWidth, base: base))
            .accessibilityAction(.escape) { setOpen(false) }
        }
        .ignoresSafeArea(.container)
        .onChange(of: isOpen) { _, nowOpen in
            if nowOpen { dismissKeyboard() }
        }
    }

    private func cornerRadius(_ progress: CGFloat) -> CGFloat {
        if reduceMotion { return progress > 0 ? openCornerRadius : 0 }
        return openCornerRadius * min(progress * 4, 1)
    }

    /// One horizontal-dominant drag. Closed, it only starts at the left edge; open, it starts anywhere.
    private func dragGesture(drawerWidth: CGFloat, base: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drag) { value, state, _ in
                guard isHorizontal(value.translation), canStart(at: value.startLocation) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard isHorizontal(value.translation), canStart(at: value.startLocation) else { return }
                setOpen(base + value.predictedEndTranslation.width > drawerWidth / 2)
            }
    }

    private func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height)
    }

    private func canStart(at location: CGPoint) -> Bool {
        isOpen || location.x < edgeGrabWidth
    }

    private func setOpen(_ open: Bool) {
        withAnimation(drawerAnimation(reduceMotion: reduceMotion)) { isOpen = open }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
```

(If Swift 6 rejects the `UIApplication.shared` call inside the `onChange` closure for actor isolation, wrap it: `MainActor.assumeIsolated { UIApplication.shared.sendAction(...) }`.)

- [ ] **Step 4: Write the workspace row and the shell**

Create `Sources/App/WorkspaceRow.swift`:

```swift
import SwiftUI

/// One workspace in the sidebar. An unavailable workspace is disabled and says why.
struct WorkspaceRow: View {
    let option: AppWorkspace
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(option.title)
                } icon: {
                    Image(systemName: option.systemImage)
                }
                if !option.isAvailable {
                    Spacer()
                    Text("Coming soon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!option.isAvailable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
```

Create `Sources/App/AppShell.swift`:

```swift
import ChatFeature
import NetworkingKit
import PhilharmonicFeature
import SettingsFeature
import SwiftUI

/// The chat on screen. A new chat is a fresh lowercased UUID with no title; the server creates the
/// chat when the first message is sent.
struct ActiveChat: Equatable {
    var id: String
    var title: String?

    static func new() -> ActiveChat { ActiveChat(id: UUID().uuidString.lowercased(), title: nil) }
}

/// The app's root: a drawer whose sidebar lists chats and whose card shows the active chat.
struct AppShell: View {
    let apiClient: APIClient
    let streamManager: ChatStreamManager
    let serverConfig: ServerConfigStore

    @State private var activeChat = ActiveChat.new()
    @State private var isSidebarOpen = false
    @State private var workspace: AppWorkspace = .chat
    @State private var showSettings = false
    /// Bumped when Settings closes so the sidebar reloads Recents from the (possibly new) server.
    @State private var recentsReloadToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SideDrawer(isOpen: $isSidebarOpen) {
            ChatSidebarView(
                apiClient: apiClient,
                activeChatId: activeChat.id,
                isOpen: isSidebarOpen,
                reloadToken: recentsReloadToken,
                onSelectChat: { id, title in select(id: id, title: title) },
                onNewChat: { startNewChat() },
                onOpenSettings: { showSettings = true },
                onDeleteChat: { id in
                    // The deleted chat was the one on screen: leave it for a fresh one, drawer stays open.
                    if id == activeChat.id { activeChat = .new() }
                }
            ) {
                ForEach(AppWorkspace.allCases) { option in
                    WorkspaceRow(option: option, isSelected: option == workspace) {
                        workspace = option
                        setSidebar(open: false)
                    }
                }
            }
        } content: {
            NavigationStack {
                detail
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                setSidebar(open: !isSidebarOpen)
                            } label: {
                                if isSidebarOpen {
                                    Label("Close sidebar", systemImage: "sidebar.leading")
                                } else {
                                    Label("Open sidebar", systemImage: "sidebar.leading")
                                }
                            }
                            .accessibilityIdentifier("sidebarToggle")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                startNewChat()
                            } label: {
                                Label("New chat", systemImage: "square.and.pencil")
                            }
                            .accessibilityIdentifier("topNewChat")
                        }
                    }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { recentsReloadToken += 1 }) {
            SettingsView(apiClient: apiClient, serverConfig: serverConfig)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace {
        case .chat:
            ChatDetailView(
                chatId: activeChat.id, title: activeChat.title, apiClient: apiClient,
                streamManager: streamManager, serverConfig: serverConfig
            )
            // A different chat is a different view model.
            .id(activeChat.id)
        case .philharmonic:
            PhilharmonicPlaceholderView()
        }
    }

    private func select(id: String, title: String?) {
        activeChat = ActiveChat(id: id, title: title)
        setSidebar(open: false)
    }

    private func startNewChat() {
        activeChat = .new()
        setSidebar(open: false)
    }

    private func setSidebar(open: Bool) {
        withAnimation(drawerAnimation(reduceMotion: reduceMotion)) { isSidebarOpen = open }
    }
}
```

- [ ] **Step 5: Point the app at the shell and delete the old root**

`Sources/App/ExodusApp.swift`: the scene body becomes

```swift
    var body: some Scene {
        WindowGroup {
            AppShell(apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig)
        }
    }
```

```bash
git rm Sources/App/RootView.swift Sources/ChatFeature/ChatListView.swift
```

In `Sources/ChatFeature/ChatListViewModel.swift` delete the whole `relativeTime(forCreatedAt:now:locale:)` function and its doc comment (rows show titles only now). In `Tests/ChatFeatureTests/ChatListViewModelTests.swift` delete the `@Test` whose function is `relativeTimeIsHumanReadable`.

- [ ] **Step 6: Generate, build, test, audit**

```bash
tuist generate --no-open
python3 scripts/l10n.py audit --source-only --exclude Sources/ChatFeature/ChatDetailView.swift
```

Expected audit: `0 error(s)`. Then the `App` build command (`BUILD SUCCEEDED`; fix compile errors by spelling only), then the four module test commands: all `TEST SUCCEEDED`; `ChatFeature` is one test lower than after Task 4 (80).

- [ ] **Step 7: Launch it against the live desktop and look**

```bash
SCRATCH=<the scratchpad directory from your dispatch>
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -derivedDataPath "$SCRATCH/dd" \
  -destination "platform=iOS Simulator,id=$UDID" 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
APP="$SCRATCH/dd/Build/Products/Debug-iphonesimulator/Exodus.app"
xcrun simctl terminate $UDID app.yancey.exodus.exodus-ios 2>/dev/null
xcrun simctl install $UDID "$APP" && xcrun simctl launch $UDID app.yancey.exodus.exodus-ios
sleep 5; xcrun simctl io $UDID screenshot "$SCRATCH/task6-launch.png"
```

Open `task6-launch.png` with the Read tool. Expected: no crash; a new-chat screen with a circular glass sidebar button on the left, the title "New chat" and a circular new-chat button on the right. (The composer is still the old style until Task 7.) If the desktop is not running the screen is still fine; the sidebar is verified in Task 9.

- [ ] **Step 8: Commit**

```bash
git add -A Sources Tests Resources
git commit -m "Drawer shell: SideDrawer and AppShell replace the list-then-push root

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Restyle `ChatDetailView`

A glass composer, a greeting for an empty chat, interactive keyboard dismissal. Streaming, Stop, the pending row, re-attaching and the history retry are unchanged.

**Files:**
- Modify: `Sources/ChatFeature/ChatDetailView.swift` (replace the whole file), `Resources/App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ChatDetailViewModel` (`messages`, `showsPendingRow`, `showsEmptyState`, `isTurnInFlight`, `canSend`, `composerText`, `displayTitle`, `errorMessage`, `onAppear()`, `loadHistory()`, `sendMessage()`, `stop()`).
- Produces: accessibility identifiers `composerField`, `sendButton`, `stopButton` (Task 9).

- [ ] **Step 1: Add the keys**

```bash
add() { python3 scripts/l10n.py add "$@"; }
add "Ask Exodus" --comment "Placeholder of the message field. Exodus is the app's name and stays as is."
add "What can I help with?" --comment "Greeting in the middle of an empty new conversation."
add "Send" --comment "Accessibility label of the send button."
add "Stop" --comment "Accessibility label of the button that stops the reply in progress."
```

- [ ] **Step 2: Replace `ChatDetailView`**

Write `Sources/ChatFeature/ChatDetailView.swift`:

```swift
import Models
import NetworkingKit
import SwiftUI

public struct ChatDetailView: View {
    @State private var viewModel: ChatDetailViewModel

    public init(
        chatId: String, title: String? = nil, apiClient: APIClient, streamManager: ChatStreamManager,
        serverConfig: ServerConfigStore
    ) {
        _viewModel = State(
            initialValue: ChatDetailViewModel(
                chatId: chatId, title: title, apiClient: apiClient, streamManager: streamManager,
                serverConfig: serverConfig))
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        MessageRow(
                            message: message,
                            showsTypingIndicator: viewModel.isTurnInFlight && message.id == viewModel.messages.last?.id
                        )
                        .id(message.id)
                    }
                    // Between tapping send and the first assistant message the transcript ends
                    // with the user's message; without this the screen would show nothing.
                    if viewModel.showsPendingRow {
                        AssistantBubble(text: AttributedString("…"))
                            .id(Self.pendingRowID)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            // Pull down to retry a history load that failed (the composer stays disabled until it succeeds).
            .scrollBounceBehavior(.always)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await viewModel.loadHistory() }
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy, animated: true)
            }
            // Follow a reply as it streams in: the count is constant while the last message grows.
            .onChange(of: viewModel.messages.last?.answerText) {
                scrollToBottom(proxy, animated: false)
            }
            // Sending adds the pending row; reaching it is the point of `isTurnInFlight` flipping.
            .onChange(of: viewModel.isTurnInFlight) {
                scrollToBottom(proxy, animated: true)
            }
        }
        .overlay {
            if viewModel.showsEmptyState { emptyState }
        }
        .safeAreaBar(edge: .bottom) { composer }
        .navigationTitle(viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        Text("What can I help with?")
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Exodus", text: $viewModel.composerText, axis: .vertical)
                .lineLimit(1...5)
                .padding(.vertical, 8)
                .accessibilityIdentifier("composerField")
            if viewModel.isTurnInFlight {
                // The way out of a turn that will not finish (a half-open connection can otherwise
                // keep the composer locked for up to an hour).
                Button {
                    Task { await viewModel.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier("stopButton")
            } else {
                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    Label("Send", systemImage: "arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(!viewModel.canSend)
                .accessibilityIdentifier("sendButton")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    /// Stable id of the pending "…" row, so the scroll view can be pointed at it.
    private static let pendingRowID = "pending"

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let targetId = viewModel.showsPendingRow ? Self.pendingRowID : viewModel.messages.last?.id
        guard let targetId else { return }
        if animated {
            withAnimation { proxy.scrollTo(targetId, anchor: .bottom) }
        } else {
            proxy.scrollTo(targetId, anchor: .bottom)
        }
    }
}
```

- [ ] **Step 3: Audit strictly, build, test**

```bash
python3 scripts/l10n.py audit --source-only
```

Expected: `0 error(s)` and no `--exclude` any more (every Swift file is now audited). Then the `App` build (`BUILD SUCCEEDED`), and the `ChatFeature` tests (`TEST SUCCEEDED`, unchanged count, 80).

- [ ] **Step 4: Look at it**

Repeat Task 6 Step 7 with the screenshot named `task7-launch.png`. Expected: the greeting "What can I help with?" centered in the card (a new chat has no history), and a glass composer capsule at the bottom with the placeholder "Ask Exodus" and a circular send button (disabled look, since the field is empty).

- [ ] **Step 5: Commit**

```bash
git add -A Sources Resources
git commit -m "Chat detail: glass composer, empty-chat greeting, interactive keyboard dismissal

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Translations in the ten shipped languages

Fill both catalogs. Reuse the desktop's wording wherever a string is identical, translate the rest, then make the strict audit pass.

**Files:**
- Modify: `Resources/App/Localizable.xcstrings`, `Resources/App/InfoPlist.xcstrings` (through the tool; edit no JSON by hand)

**Interfaces:**
- Consumes: the keys added in Tasks 2, 5, 6, 7 (the audit lists any that are missing a language).
- Produces: every key in both catalogs translated in `zh-Hant`, `zh-HK`, `ja`, `ko`, `fr`, `de`, `es`, `pt-BR`, `it`; `python3 scripts/l10n.py audit` (strict) prints `0 error(s)`.

- [ ] **Step 1: Seed from the desktop**

```bash
python3 scripts/l10n.py seed-from-desktop ~/Code/exodus/exodus/packages/shared/src/i18n/locales
```

Expected: about twenty keys seeded (Cancel, Delete, Retry, Save, Settings, Send, Stop, Search, Chat, New chat, Connection, Model, Provider, API Key, AI Providers, Select a model, Refresh model list, and so on), followed by the list of keys left for manual translation. The desktop's own catalogs are the source, so the wording matches the desktop app.

- [ ] **Step 2: Check the seeded wording fits**

The tool matches on English text only, so read the seeded value of each of these against how the string is used here, and overwrite any that do not fit (with `fill`, Step 3): `Search` (a short label for the magnifier button and the field: a noun or imperative, not "Search results"), `Connection` (the connection to the desktop app, not a database connection), `Chat`, `Model`, `Provider`, `Select a model`. To inspect them:

```bash
python3 - <<'EOF'
import json
strings = json.load(open("Resources/App/Localizable.xcstrings"))["strings"]
for key in ["Search", "Connection", "Chat", "Model", "Provider", "Select a model"]:
    localizations = strings[key].get("localizations", {})
    print(key, {lang: loc["stringUnit"]["value"] for lang, loc in localizations.items()})
EOF
```

- [ ] **Step 3: Translate the rest**

Write `SCRATCH/translations.json` (outside the repo) with an entry for every key the seed step listed as left over, in this shape (one example entry; do the same for every key):

```json
{
  "Recents": {
    "zh-Hant": "最近", "zh-HK": "最近", "ja": "最近", "ko": "최근",
    "fr": "Récents", "de": "Zuletzt", "es": "Recientes", "pt-BR": "Recentes", "it": "Recenti"
  }
}
```

The keys normally left over, with what each means (the audit is the source of truth for the exact list): `Recents` (sidebar section header), `Clear` (accessibility label of the clear-text button), `No chats yet`, `Error` (alert title), `OK`, `No results`, `Search failed`, `Searching` (spinner label), `Ask Exodus` (message field placeholder; keep the name Exodus), `What can I help with?` (greeting in an empty chat), `Server address` (accessibility label), `Loading models`, `Connect` (toolbar button before the server's settings are loaded), `Used: %@` (tool row; `%@` is the tool name), `Used a tool`, `Can't load chats`, `Pull down or tap Retry to try again.`, `Ollama runs on your Mac and needs no API key.`, `Server address must look like %@` (`%@` is an example address), `Connect to the server and load its settings before saving.`, `Invalid server URL: %@`, `Invalid server URL`, `HTTP %lld` (the same in every language, but it still needs an entry), `The Philharmonic multi-agent workspace hasn't been ported to iOS yet.`, `Coming soon`, `Open sidebar`, `Close sidebar`.

Rules:
- Mirror the desktop's tone in each language. To find its register, read how the desktop's catalog for that language addresses the user in a sentence containing "you" or "your" (for example in `settings.json`) and match the formality (de du/Sie, fr tu/vous, es tú/usted, it tu/Lei, ko and ja politeness level).
- Keep every placeholder (`%@`, `%lld`) exactly and use each once. Never translate `Exodus`, `Philharmonic`, `Ollama`, `iOS`, `API`, `HTTP` or URLs.
- `zh-Hant` uses Taiwan wording and `zh-HK` uses Hong Kong wording; give both, identical where the wording is the same.
- Button and label strings are short imperative or noun forms, not sentences. A string must fit a narrow sidebar (about 260 pt): prefer the shorter natural form.

Then `python3 scripts/l10n.py fill "$SCRATCH/translations.json"`.

- [ ] **Step 4: Translate the permission text**

Write `SCRATCH/infoplist.json`:

```json
{ "NSLocalNetworkUsageDescription": { "zh-Hant": "…", "zh-HK": "…", "ja": "…", "ko": "…", "fr": "…", "de": "…", "es": "…", "pt-BR": "…", "it": "…" } }
```

with the real translation of "Exodus needs local network access to connect to the Exodus service running on your computer." in each language (the `…` above stands for that text, not a value to keep), then `python3 scripts/l10n.py fill "$SCRATCH/infoplist.json" --file Resources/App/InfoPlist.xcstrings`.

- [ ] **Step 5: The strict audit and the bundle**

```bash
python3 scripts/l10n.py audit
```

Expected: `0 error(s)` and no warnings. Fix every reported key or placeholder problem with `fill`. Then rebuild as in Task 6 Step 7 and run `ls "$APP" | grep lproj`: ten `.lproj` folders (`en`, `zh-Hant`, `zh-HK`, `ja`, `ko`, `fr`, `de`, `es`, `pt-BR`, `it`). Run `git status --short Resources`: only the two catalogs changed.

- [ ] **Step 6: Commit**

```bash
git add -A Resources
git commit -m "Translate the app into the desktop's ten languages

Wording is copied from the desktop's catalogs where the English text is
identical; the rest is machine translation, not reviewed by native speakers.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Simulator verification, README, final checks

Drive the real app in the simulator against the real desktop (read-only), look at the screenshots, fix what is wrong, and finish the docs. The UI test target used here is temporary and is never committed.

**Files:**
- Modify (temporarily, reverted before committing): `Project.swift`
- Create (temporarily, deleted before committing): `UITests/ExodusUITests.swift`
- Modify: `README.md`, plus any source file a defect requires

**Interfaces:**
- Consumes: the accessibility identifiers `sidebarToggle`, `topNewChat`, `sidebarSearch`, `sidebarNewChat`, `sidebarSettings`, `searchField`, `searchCancel`, `composerField`.
- Produces: screenshots in `SCRATCH/ui/`, a reviewed-and-fixed UI, an updated README.

- [ ] **Step 1: Check the desktop is up**

```bash
curl --noproxy '*' -s -o /dev/null -w "%{http_code}\n" http://localhost:60223/api/v1/history
```

Expected `200`. If not, stop this task's live steps and report "desktop not running"; do Steps 7 to 9 only.

- [ ] **Step 2: Add the temporary UI test target**

In `Project.swift`, add to the `targets` array:

```swift
        .target(
            name: "ExodusUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "\(bundleIdRoot).ExodusUITests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["UITests"],
            dependencies: [.target(name: "App")]
        ),
```

Create `UITests/ExodusUITests.swift` (replace `SCRATCH_DIR` with the scratchpad directory from your dispatch):

```swift
import XCTest

/// TEMPORARY, never committed. Drives the real app against the desktop server with read-only actions only:
/// it never deletes a chat, sends a message or presses Save.
final class ExodusUITests: XCTestCase {
    static let outDir = "SCRATCH_DIR/ui"

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: Self.outDir, withIntermediateDirectories: true)
    }

    func shot(_ app: XCUIApplication, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(Self.outDir)/\(name).png"))
    }

    func launch(language: String? = nil, locale: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var args = extra
        if let language { args += ["-AppleLanguages", "(\(language))"] }
        if let locale { args += ["-AppleLocale", locale] }
        app.launchArguments = args
        app.launch()
        sleep(3)
        return app
    }

    func openDrawerByEdgeSwipe(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        sleep(2)
    }

    func sidebarVisible(_ app: XCUIApplication) -> Bool { app.buttons["sidebarSearch"].exists }

    @MainActor func testDrawerGestures() {
        let app = launch()
        shot(app, "1-new-chat")
        XCTAssertFalse(sidebarVisible(app), "the sidebar is hidden while the drawer is closed")

        // a rightward drag that does not start at the edge must not open the drawer
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)))
        sleep(1)
        XCTAssertFalse(sidebarVisible(app), "only an edge drag opens the drawer")

        openDrawerByEdgeSwipe(app)
        shot(app, "2-open")
        XCTAssertTrue(sidebarVisible(app))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
        sleep(2)
        shot(app, "3-closed-by-left-swipe")
        XCTAssertFalse(sidebarVisible(app))

        app.buttons["sidebarToggle"].tap()
        sleep(2)
        XCTAssertTrue(sidebarVisible(app), "the toolbar button opens the drawer")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        sleep(2)
        shot(app, "4-closed-by-scrim")
        XCTAssertFalse(sidebarVisible(app), "tapping the scrim closes the drawer")
    }

    @MainActor func testSelectingARecentChatOpensIt() {
        let app = launch()
        openDrawerByEdgeSwipe(app)
        let firstRow = app.collectionViews.cells.element(boundBy: 2)  // after the two workspace rows
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()
        sleep(3)
        shot(app, "5-recent-opened")
        XCTAssertFalse(sidebarVisible(app), "selecting a chat closes the drawer")
    }

    @MainActor func testSearchFlow() {
        let app = launch()
        openDrawerByEdgeSwipe(app)
        app.buttons["sidebarSearch"].tap()
        XCTAssertTrue(app.textFields["searchField"].waitForExistence(timeout: 3))
        shot(app, "6-search-open")
        app.typeText("hi")
        sleep(3)
        shot(app, "7-search-results")
        app.buttons["searchCancel"].tap()
        sleep(1)
        XCTAssertFalse(app.textFields["searchField"].exists)
        shot(app, "8-search-cancelled")
    }

    @MainActor func testComposerRisesWithTheKeyboard() {
        let app = launch()
        let field = app.textFields["composerField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        sleep(2)
        shot(app, "9-composer-keyboard")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertLessThan(field.frame.maxY, app.keyboards.firstMatch.frame.minY, "the composer sits above the keyboard")
    }

    @MainActor func testLanguages() {
        let cases: [(String, String)] = [
            ("de", "de_DE"), ("fr", "fr_FR"), ("ja", "ja_JP"), ("zh-Hant", "zh_TW"), ("zh-Hans", "zh_CN"),
        ]
        for (language, locale) in cases {
            let app = launch(language: language, locale: locale)
            shot(app, "lang-\(language)-1-chat")
            openDrawerByEdgeSwipe(app)
            shot(app, "lang-\(language)-2-sidebar")
            app.buttons["sidebarSettings"].tap()
            sleep(3)
            shot(app, "lang-\(language)-3-settings")
            app.terminate()
        }
    }

    @MainActor func testLargeDynamicType() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        shot(app, "dt-1-chat")
        openDrawerByEdgeSwipe(app)
        shot(app, "dt-2-sidebar")
    }
}
```

- [ ] **Step 3: Run the UI tests**

```bash
tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme App -derivedDataPath "$SCRATCH/dd" \
  -destination "platform=iOS Simulator,id=$UDID" -only-testing:ExodusUITests 2>&1 \
  | grep -E "Test Case.*(passed|failed)|error:|TEST SUCCEEDED|TEST FAILED|Executed"
ls "$SCRATCH/ui"
```

Expected: the six tests run; a failed XCTAssert is a real defect to fix (or a wrong assumption in the test, e.g. the row index in `testSelectingARecentChatOpensIt`, to be corrected and noted). If `App` does not run the UI tests, try `-scheme ExodusUITests`.

- [ ] **Step 4: Read every screenshot and check it**

Open each PNG in `$SCRATCH/ui/` with the Read tool. Acceptance:
- `1-new-chat`: circular glass sidebar button left, title "New chat", circular new-chat button right, the greeting centered, a glass composer capsule at the bottom.
- `2-open`: the sidebar occupies about 78% of the width with the title "Exodus", a magnifier circle, a "Chat" row, a greyed "Philharmonic" row with "Coming soon", a "Recents" section of real chat titles each on ONE line (the 1211-character multi-line titles must not spill), a blue "New chat" pill bottom-left and a gear bottom-right; the chat card is pushed right with a rounded corner and a dim overlay.
- `3`, `4`: the card is back, nothing of the sidebar shows through.
- `5-recent-opened`: the chosen chat's transcript and its real title in the top bar.
- `6`, `7`, `8`: a glass search capsule with a Cancel button and the keyboard; results are a title plus at most two lines of snippet; the bottom bar is gone while searching; after Cancel the Recents list is back.
- `9-composer-keyboard`: the composer is fully above the keyboard, and nothing of the sidebar shows through the translucent keyboard.
- `lang-de`, `lang-fr`, `lang-ja`, `lang-zh-Hant`: every label is in that language and nothing is truncated (the "New chat" pill, the "Coming soon" note, Settings titles). `lang-zh-Hans`: the app is in English.
- `dt-1`, `dt-2`: no overlapping or clipped text at the large Dynamic Type size.

- [ ] **Step 5: Fix every defect found**

Fix in the sources, rerun the affected UI test and the affected module tests, and run `python3 scripts/l10n.py audit`. A fix that changes a string also updates the catalog and all ten languages.

If `lang-zh-Hans-*` shows a Traditional Chinese catalog instead of English (iOS matched the Simplified phone to a Traditional catalog), apply the spec's fallback: add `zh-Hans` to `SHIPPED` in `scripts/l10n.py` and to `defaultKnownRegions` in `Project.swift`, fill every key of both catalogs for `zh-Hans` with its English source text (`fill`), rerun the audit and that screenshot, and say so in the README's language paragraph.

- [ ] **Step 6: Remove the temporary target**

```bash
git checkout -- Project.swift
rm -rf UITests
tuist generate --no-open
git status --short
```

Expected: `git status` lists only files you intend to commit (README and any defect fixes); no `UITests`, no `Project.swift` change beyond Task 2's.

- [ ] **Step 7: Update the README**

In `README.md`: change the intro sentence "it lists chats, sends messages…" to mention the ChatGPT-style drawer with Recents and search; in "Modules" change the `ChatFeature` line to "chat sidebar (Recents, search) and chat detail (history, streaming send, Stop)" and the `App` line to "composition root, the drawer shell (`SideDrawer`, `AppShell`) and the workspace list". Add a short "Known limits" paragraph: the sidebar search field is hand-built because `.searchable` was inert inside the drawer on the iOS 27.0 simulator; translations other than English are machine-generated unless copied from the desktop and have not been reviewed by native speakers; there are no automated UI tests for the drawer (the checks in this plan were run by hand with a temporary XCUITest).

- [ ] **Step 8: Final verification**

```bash
python3 scripts/l10n.py audit
for scheme in Models NetworkingKit ChatFeature SettingsFeature; do
  xcodebuild test -workspace ExodusIos.xcworkspace -scheme $scheme -destination "platform=iOS Simulator,id=$UDID" 2>&1 \
    | grep -E "Test run with|TEST SUCCEEDED|TEST FAILED|error:"
done
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "platform=iOS Simulator,id=$UDID" 2>&1 \
  | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
grep -rn '"/api/' Sources | grep -v '/api/v1/' && echo "UNVERSIONED PATH" || echo "all paths versioned"
```

Expected: `0 error(s)`; four `TEST SUCCEEDED` (Models 29, NetworkingKit 37, SettingsFeature 28, ChatFeature 80); `BUILD SUCCEEDED`; `all paths versioned`.

- [ ] **Step 9: Commit**

```bash
git add -A README.md Sources Resources Tests
git commit -m "Verify the drawer, search and languages in the simulator; update the README

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Human walkthrough (after Task 9; for the project owner, on a real iPhone with iOS 27 or later)

1. First run: the local-network permission prompt appears in the phone's language. In Settings, under "Connection", enter the Mac's address (`http://<LAN IP>:60223`); Recents load.
2. Drawer feel: an edge swipe follows the finger and settles with momentum; a left swipe or a tap on the dimmed card closes it; the card's rounded corner and shadow look right.
3. VoiceOver: the sidebar button reads "Open sidebar" and "Close sidebar"; with the drawer open, focus is in the sidebar and a two-finger scrub closes it. Turn on Reduce Motion: the drawer uses a plain short slide.
4. Send a message: it streams, Stop works, and reopening the chat from Recents shows its real title in the top bar.
5. Search a word you know appears in an old chat: results show the chat title and a snippet around the word; a tap opens that chat; Cancel returns to Recents.
6. Long-press a throwaway chat and delete it. Delete the chat that is open: the screen switches to a new chat and the drawer stays open.
7. Languages: in the system Settings, give Exodus a per-app language (try German and Japanese): nothing is cut off. With the phone in Simplified Chinese the app is in English, as on the desktop.

## Not in this plan

Philharmonic itself; renaming chats; highlighting the match or scrolling to it; committed UI tests (they would need a stub server); a native-speaker review of the nine machine-translated catalogs; right-to-left languages.
