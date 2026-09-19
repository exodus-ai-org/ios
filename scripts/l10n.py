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
