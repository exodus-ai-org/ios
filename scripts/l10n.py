#!/usr/bin/env python3
"""Localization tooling for exodus-ios (standard library only, Python 3.9+).

  l10n.py audit [--source-only] [--exclude PATH ...]
      Checks both catalogs and the Swift sources; exit status 1 on any error.
      --source-only skips the "every language is translated" check (used while
      strings are still being added); every other check still runs.
  l10n.py add KEY [--comment TEXT] [--no-translate] [--en-value TEXT] [--file PATH]
      Adds KEY to a catalog if it is not there yet. A key is symbolic, never the English text:
      `ios:<module>.<screen>.<element>` (this app only; --en-value gives its English text) or
      `<namespace>:<dotted.path>` (also on the desktop; the sync writes its text).
  l10n.py fill TRANSLATIONS.json [--file PATH]
      Merges {"key": {"lang": "text"}} into a catalog as translated strings.
  l10n.py sync-from-desktop [LOCALES_DIR] [--file PATH]
      Overwrites every non-`ios:` key with the desktop's text in all ten languages ({{x}} becomes
      %@, and then a literal % becomes %%); `ios:` keys are never touched. A catalog key the desktop
      only has as `<key>_one` / `<key>_other` / … becomes a plural (`variations.plural`, {{count}} as
      %lld, which must be the first placeholder). A language that orders the placeholders differently
      from English gets positional ones (%2$@ … %1$@) and is listed. Exit status 1 when a shared key
      is not on the desktop (renamed or removed?) or cannot be shared as-is (markup, a plural-suffixed
      catalog key, placeholders that differ between languages).
      Default LOCALES_DIR: Vendor/exodus-locales
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


def source_value(loc):
    """The text a localization is compared against: its plain value, or a plural's `other` form."""
    if loc and "stringUnit" not in loc:
        return unit_value(loc.get("variations", {}).get("plural", {}).get("other"))
    return unit_value(loc)


def forms(loc):
    """[(label, stringUnit)] of a localization: one plain unit, or one per plural category.
    None when it is neither (another kind of variation, a substitution, or an empty plural)."""
    if "stringUnit" in loc and "variations" not in loc and "substitutions" not in loc:
        return [("", loc["stringUnit"])]
    plural = loc.get("variations", {}).get("plural") if set(loc) == {"variations"} else None
    if not plural or set(loc["variations"]) != {"plural"} or "other" not in plural:
        return None
    if any(c not in PLURAL_CATEGORIES or "stringUnit" not in f for c, f in plural.items()):
        return None
    return [(" " + c, plural[c]["stringUnit"]) for c in PLURAL_CATEGORIES if c in plural]


def placeholders(text):
    return sorted(re.sub(r"^%\d+\$", "%", m.group(0)) for m in PLACEHOLDER_RE.finditer(text.replace("%%", "")))


INTERP_RE = re.compile(r"\{\{(\w+)\}\}")
IOS_PREFIX = "ios:"
# i18next <Trans> markup (`<1>…</1>`, `<strong>`, `<br/>`) and CLDR plural suffixes: neither fits a plain string.
MARKUP_RE = re.compile(r"</?[A-Za-z0-9]+\s*/?>")
PLURAL_CATEGORIES = ["zero", "one", "two", "few", "many", "other"]
PLURAL_KEY_RE = re.compile(r"_(?:zero|one|two|few|many|other)$")
PLURAL_COUNT = "count"
MISSING_HEADING = "shared key not found on the desktop (renamed or removed?)"
UNSHAREABLE_HEADING = "not shareable as-is: markup/plural"
REORDERED_HEADING = "placeholders reordered (written positional, %n$):"


def convert_placeholders(text, order=None, plural=False):
    """Every `{{name}}` becomes `%@` — see the design spec's §5 for why never a typed specifier — except a
    plural's `{{count}}`, which is `%lld` (the plural rule needs a number). With `order` (the names in English
    order) each becomes positional, `%<n>$@`, for a language that puts them in another order.
    In a text with a placeholder a literal `%` becomes `%%` first (an existing `%%` stays), or `%@% rain` would
    read `% r` as a conversion. A text without one is shown as stored, never formatted, so its `%` stays as is."""
    if not INTERP_RE.search(text):
        return text

    def spec(m):
        kind = "lld" if plural and m.group(1) == PLURAL_COUNT else "@"
        return "%%%d$%s" % (order.index(m.group(1)) + 1, kind) if order else "%" + kind

    return INTERP_RE.sub(spec, re.sub(r"%%|%", "%%", text))


def placeholder_names(text):
    return INTERP_RE.findall(text)


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
    # A key is a plain literal, so `pieces` has one entry. A literal with an interpolation is no key:
    # it is reported, because that call site should be `String(localized:defaultValue:)`.
    return pieces[0] if len(pieces) == 1 and pieces[0] in keys else None


# ---------------------------------------------------------------- audit
LOCALIZED_CALL_RE = re.compile(r"String\(\s*localized:")
DEFAULT_VALUE_RE = re.compile(r"\s*,\s*defaultValue:\s*")


def rendered(text):
    """A catalog text as a reader sees it, every placeholder as `%@` (`%lld`, `%1$@`, … alike) and `%%` as `%`."""
    return re.sub("%%|" + PLACEHOLDER, lambda m: "%" if m.group(0) == "%%" else "%@", text)


def default_value_errors(text, call_start, key_end, key, strings, where):
    """`String(localized: "key", defaultValue: "…")`: the call carries a `defaultValue:`, and when that is a
    literal its text (each interpolation as `%@`) is the catalog's `en` for the key."""
    args = text[key_end:skip_parens(text, text.index("(", call_start)) - 1]
    given = DEFAULT_VALUE_RE.match(args)
    if given is None:
        return ['%s: String(localized: "%s") needs a defaultValue: with the English text' % (where, key)]
    literal = key_end + given.end()
    if not text.startswith('"', literal) or text.startswith('"""', literal):
        return []  # not a plain literal: nothing to compare
    default = "%@".join(literal_pieces(text[literal + 1:skip_string(text, literal) - 1]))
    loc = strings[key].get("localizations", {}).get(SOURCE_LANGUAGE)
    en = source_value(loc)
    # A plural's call site may branch on the count to give each English form as its own defaultValue.
    texts = [u.get("value", "") for _, u in forms(loc) or []] if loc else []
    if en is None or default in map(rendered, texts or [en]):
        return []  # no en is the catalog audit's error
    return ['%s: defaultValue "%s" differs from the catalog en "%s" for "%s"' % (where, default, en, key)]


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
        source_text = key if implicit_source else source_value(locs.get(SOURCE_LANGUAGE))
        if source_text is None:
            errors.append("%s: %r has no %s value" % (rel, key, SOURCE_LANGUAGE))
            continue
        for lang in required:
            loc = locs.get(lang)
            if loc is None:
                if not source_only or lang == SOURCE_LANGUAGE:
                    errors.append("%s: %r is missing %s" % (rel, key, lang))
                continue
            units = forms(loc)
            if units is None:
                errors.append("%s: %r [%s] must be a plain stringUnit or a plural with an `other` form" % (rel, key, lang))
                continue
            for label, unit in units:
                value = unit.get("value", "")
                if unit.get("state") != "translated" or not value.strip():
                    errors.append("%s: %r [%s%s] is not translated" % (rel, key, lang, label))
                elif placeholders(value) != placeholders(source_text):
                    errors.append("%s: %r [%s%s] placeholders differ from the source" % (rel, key, lang, label))
    return errors


def vendor_errors(strings):
    """A desktop-namespaced catalog key must be in the vendored subtree, or nothing records where its
    text came from (a later `sync-from-desktop` would report it missing)."""
    vendor = ROOT / "Vendor/exodus-locales"
    if not vendor.is_dir():
        return []
    en = {key for (lang, key) in flatten_desktop_locales(vendor) if lang == SOURCE_LANGUAGE}
    return [
        "%r is a desktop key but not in Vendor/exodus-locales (sync the subtree, or make it an ios: key)" % key
        for key, entry in sorted(strings.items())
        if not key.startswith(IOS_PREFIX) and entry.get("shouldTranslate") is not False
        and key not in en and not any("%s_%s" % (key, c) in en for c in PLURAL_CATEGORIES)
    ]


def audit_sources(strings, excluded):
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
            key = match_key(pieces, strings)
            if key is None:
                errors.append('%s:%d: "%s" is not in Localizable.xcstrings' % (rel, line, "%@".join(pieces)))
                continue
            used.add(key)
            if LOCALIZED_CALL_RE.match(m.group(0)):
                errors += default_value_errors(text, m.start(), end, key, strings, "%s:%d" % (rel, line))
    return errors, used


def cmd_audit(args):
    excluded = {Path(p).as_posix() for p in args.exclude}
    errors = audit_catalog(LOCALIZABLE, False, args.source_only) + audit_catalog(INFOPLIST, False, args.source_only)
    strings = load(LOCALIZABLE)["strings"]
    source_errors, used = audit_sources(strings, excluded)
    errors += source_errors + vendor_errors(strings)
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


def desktop_forms(values, key):
    """lang -> {"": text} for a plain desktop key, or lang -> {category: text} when the desktop has it only
    as plural suffixes; a language with neither is left out."""
    found = {}
    for lang in SHIPPED:
        if values.get((lang, key)):
            found[lang] = {"": values[(lang, key)]}
            continue
        plural = {c: values[(lang, "%s_%s" % (key, c))] for c in PLURAL_CATEGORIES if values.get((lang, "%s_%s" % (key, c)))}
        if "other" in plural:
            found[lang] = plural
    return found


def share(key, found):
    """(localizations, reordered languages) for a key every language has, or (None, reason)."""
    plural = "" not in found[SOURCE_LANGUAGE]
    if plural and any("" in f for f in found.values()) or not plural and any("" not in f for f in found.values()):
        return None, "plain in some languages, plural in others"
    marked = [lang for lang in SHIPPED if any(MARKUP_RE.search(t) for t in found[lang].values())]
    if marked:
        return None, "markup in: " + ", ".join(marked)
    order = placeholder_names(found[SOURCE_LANGUAGE]["other" if plural else ""])
    if plural and (not order or order[0] != PLURAL_COUNT):
        return None, "plural whose first placeholder is not {{%s}}" % PLURAL_COUNT
    differ = [lang for lang in SHIPPED if any(sorted(placeholder_names(t)) != sorted(order) for t in found[lang].values())]
    if differ:
        return None, "placeholders differ in: " + ", ".join(differ)
    reordered = [lang for lang in SHIPPED if any(placeholder_names(t) != order for t in found[lang].values())]
    if reordered and len(set(order)) != len(order):
        return None, "a repeated placeholder, reordered in: " + ", ".join(reordered)
    locs = {}
    for lang in SHIPPED:
        positional = order if lang in reordered else None
        units = {
            c: {"stringUnit": {"state": "translated", "value": convert_placeholders(t, positional, plural)}}
            for c, t in found[lang].items()
        }
        locs[lang] = {"variations": {"plural": units}} if plural else units[""]
    return locs, reordered


def cmd_sync(args):
    """Overwrites every shared key from the desktop and saves. A shared key (not `ios:`) that is missing
    from the desktop, or cannot be shared as-is, is listed as an error and left as it was."""
    path = resolve(args.file)
    catalog = load(path)
    values = flatten_desktop_locales(args.locales_dir)
    synced, independent, missing, unshareable, reordered = 0, [], [], [], []
    for key, entry in sorted(catalog["strings"].items()):
        if entry.get("shouldTranslate") is False:
            continue
        if key.startswith(IOS_PREFIX):
            independent.append(key)
            continue
        if PLURAL_KEY_RE.search(key) and values.get((SOURCE_LANGUAGE, key)):
            unshareable.append("%s (plural key: use %s)" % (key, PLURAL_KEY_RE.sub("", key)))
            continue
        found = desktop_forms(values, key)
        absent = [lang for lang in SHIPPED if lang not in found]
        if absent:
            where = "every language" if len(absent) == len(SHIPPED) else ", ".join(absent)
            missing.append("%s (missing in: %s)" % (key, where))
            continue
        locs, detail = share(key, found)
        if locs is None:
            unshareable.append("%s (%s)" % (key, detail))
            continue
        if detail:
            reordered.append("%s (%s)" % (key, ", ".join(detail)))
        entry.setdefault("localizations", {}).update(locs)
        synced += 1
        print("synced %r from the desktop" % key)
    save(path, catalog)
    print("%d synced; %d independently translated (ios: keys, never on the desktop):" % (synced, len(independent)))
    for key in independent:
        print("  " + key)
    if reordered:
        print("note: " + REORDERED_HEADING)
        for line in reordered:
            print("  " + line)
    for heading, keys in ((MISSING_HEADING, missing), (UNSHAREABLE_HEADING, unshareable)):
        if keys:
            print("error: %s:" % heading)
            for line in keys:
                print("  " + line)
    return 1 if missing or unshareable else 0


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
    sync = sub.add_parser("sync-from-desktop")
    sync.add_argument("locales_dir", nargs="?", default=str(ROOT / "Vendor/exodus-locales"))
    sync.add_argument("--file")
    sync.set_defaults(run=cmd_sync)
    args = parser.parse_args()
    sys.exit(args.run(args))


if __name__ == "__main__":
    main()
