#!/usr/bin/env python3
"""Unit tests for scripts/l10n.py. Run: python3 -m unittest Tests.L10nScriptTests.test_l10n"""
import argparse
import contextlib
import io
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

    def test_a_percent_after_a_placeholder_is_escaped(self):
        # chat.json: "{{percent}}% rain". As "%@% rain" Foundation reads "% r" as a conversion
        # and the text renders "40 rain".
        self.assertEqual(l10n.convert_placeholders("{{percent}}% rain"), "%@%% rain")

    def test_a_percent_in_a_text_without_placeholders_is_left_alone(self):
        # A string with no arguments is shown as stored, never formatted: "%%" would show as "%%".
        # settings.json: "(50-95%). Default: 75%."
        self.assertEqual(l10n.convert_placeholders("50%"), "50%")
        self.assertEqual(
            l10n.convert_placeholders("(50-95%). Default: 75%."), "(50-95%). Default: 75%."
        )

    def test_every_percent_in_a_text_with_a_placeholder_is_escaped(self):
        self.assertEqual(
            l10n.convert_placeholders("{{min}}-95%. Default: 75%."), "%@-95%%. Default: 75%%."
        )

    def test_a_lone_percent_in_a_text_without_placeholders_is_not_a_placeholder(self):
        # The audit compares placeholders across languages; a literal percent must not count as one.
        self.assertEqual(l10n.placeholders("(50-95%). Default: 75%."), [])
        self.assertEqual(l10n.placeholders("(50-95 %). Standard: 75 %."), [])

    def test_an_already_escaped_percent_is_not_escaped_twice(self):
        self.assertEqual(l10n.convert_placeholders("50%%"), "50%%")
        self.assertEqual(l10n.convert_placeholders("{{n}}%% and 5%"), "%@%% and 5%%")

    def test_a_text_without_a_percent_is_unchanged(self):
        self.assertEqual(l10n.convert_placeholders("Ask Exodus anything."), "Ask Exodus anything.")

    def test_the_converted_text_has_only_the_placeholders_that_were_written(self):
        # What the audit compares across languages: an escaped percent is a literal, not a placeholder.
        self.assertEqual(l10n.placeholders(l10n.convert_placeholders("{{percent}}% rain")), ["%@"])


class PlaceholdersTests(unittest.TestCase):
    def test_an_escaped_percent_is_a_literal(self):
        self.assertEqual(l10n.placeholders("%@%% rain"), ["%@"])
        self.assertEqual(l10n.placeholders("50%% off"), [])

    def test_positional_specifiers_compare_like_plain_ones(self):
        self.assertEqual(l10n.placeholders("%2$@ of %1$@"), ["%@", "%@"])

    def test_typed_specifiers_are_kept_apart_from_at(self):
        self.assertEqual(l10n.placeholders("HTTP %lld"), ["%lld"])


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


DESKTOP_DIRS = {
    "en": "en", "zh-Hant": "zh-Hant-TW", "zh-HK": "zh-Hant-HK", "ja": "ja", "ko": "ko",
    "fr": "fr", "de": "de", "es": "es", "pt-BR": "pt-BR", "it": "it",
}
MISSING_HEADING = "shared key not found on the desktop (renamed or removed?)"
UNSHAREABLE_HEADING = "not shareable as-is: markup/plural"


def listed_under(out, heading):
    """The keys `cmd_sync` printed as an indented list below a line containing `heading`."""
    lines = out.splitlines()
    for i, line in enumerate(lines):
        if heading in line:
            keys = []
            for item in lines[i + 1:]:
                if not item.startswith("  "):
                    break
                keys.append(item.split()[0])
            return keys
    return None


class CmdSyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.locales = self.root / "locales"
        self.texts = {
            "en": "Ask Exodus", "zh-Hant-TW": "詢問 Exodus", "zh-Hant-HK": "詢問 Exodus",
            "ja": "Exodusに聞く", "ko": "Exodus에게 물어보기", "fr": "Demander à Exodus",
            "de": "Exodus fragen", "es": "Preguntar a Exodus",
            "pt-BR": "Perguntar ao Exodus", "it": "Chiedi a Exodus",
        }
        for desktop_dir in self.texts:
            self.write_chat(desktop_dir)

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
                "ios:onlyKey": {
                    "extractionState": "manual",
                    "localizations": {
                        "en": {"stringUnit": {"state": "translated", "value": "iOS only"}},
                    },
                },
            },
        }))

    def write_chat(self, desktop_dir, extra=None, base=True):
        """chat.json of one desktop locale: the base key `composer.placeholder`, plus `extra`."""
        tree = {"composer": {"placeholder": self.texts[desktop_dir]}} if base else {}
        tree.update(extra or {})
        d = self.locales / desktop_dir
        d.mkdir(parents=True, exist_ok=True)
        (d / "chat.json").write_text(json.dumps(tree, ensure_ascii=False))

    def add_entry(self, key, entry):
        catalog = json.loads(self.catalog_path.read_text())
        catalog["strings"][key] = entry
        self.catalog_path.write_text(json.dumps(catalog))

    def catalog(self):
        return json.loads(self.catalog_path.read_text())["strings"]

    def run_sync(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = l10n.cmd_sync(argparse.Namespace(locales_dir=str(self.locales), file=str(self.catalog_path)))
        return code, out.getvalue()

    def test_shared_key_is_overwritten_from_every_shipped_language(self):
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        zh_hant = self.catalog()["chat:composer.placeholder"]["localizations"]["zh-Hant"]
        self.assertEqual(zh_hant["stringUnit"]["value"], "詢問 Exodus")

    def test_ios_only_key_is_untouched(self):
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        self.assertNotIn("zh-Hant", self.catalog()["ios:onlyKey"]["localizations"])

    def test_each_synced_key_is_reported(self):
        code, out = self.run_sync()
        self.assertIn("synced 'chat:composer.placeholder' from the desktop", out)
        self.assertIn("1 synced;", out)

    def test_desktop_placeholders_become_percent_at_in_every_language(self):
        for lang, desktop_dir in DESKTOP_DIRS.items():
            self.write_chat(desktop_dir, {"greeting": "Hi {{name}} (" + lang + ")"})
        self.add_entry("chat:greeting", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        locs = self.catalog()["chat:greeting"]["localizations"]
        for lang in DESKTOP_DIRS:
            self.assertEqual(locs[lang]["stringUnit"]["value"], "Hi %@ (" + lang + ")")
            self.assertEqual(locs[lang]["stringUnit"]["state"], "translated")

    def test_a_desktop_percent_sign_is_escaped_in_every_language(self):
        for desktop_dir in DESKTOP_DIRS.values():
            self.write_chat(desktop_dir, {"rain": "{{percent}}% rain"})
        self.add_entry("chat:rain", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        locs = self.catalog()["chat:rain"]["localizations"]
        self.assertEqual({v["stringUnit"]["value"] for v in locs.values()}, {"%@%% rain"})

    def test_a_desktop_percent_sign_without_placeholders_is_kept_as_is(self):
        for desktop_dir in DESKTOP_DIRS.values():
            self.write_chat(desktop_dir, {"range": "(50-95%). Default: 75%."})
        self.add_entry("chat:range", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        locs = self.catalog()["chat:range"]["localizations"]
        self.assertEqual({v["stringUnit"]["value"] for v in locs.values()}, {"(50-95%). Default: 75%."})

    def test_a_should_translate_false_entry_is_skipped(self):
        entry = {"extractionState": "manual", "shouldTranslate": False}
        self.add_entry("chat:brandName", entry)  # not on the desktop, and must not need to be
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        self.assertEqual(self.catalog()["chat:brandName"], entry)
        self.assertNotIn("chat:brandName", out)

    def test_a_shared_key_missing_in_one_language_is_an_error(self):
        self.write_chat("ja", base=False)
        code, out = self.run_sync()
        self.assertEqual(code, 1)
        self.assertEqual(listed_under(out, MISSING_HEADING), ["chat:composer.placeholder"])
        self.assertIn("ja", out)

    def test_a_shared_key_missing_everywhere_is_an_error(self):
        self.add_entry("chat:removed.key", {
            "extractionState": "manual",
            "localizations": {"en": {"stringUnit": {"state": "translated", "value": "Gone"}}},
        })
        code, out = self.run_sync()
        self.assertEqual(code, 1)
        self.assertEqual(listed_under(out, MISSING_HEADING), ["chat:removed.key"])

    def test_an_error_does_not_stop_the_other_keys_and_the_file_is_saved(self):
        self.add_entry("chat:removed.key", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 1)
        # chat:composer.placeholder still got the desktop's text, and the file was written.
        zh_hant = self.catalog()["chat:composer.placeholder"]["localizations"]["zh-Hant"]
        self.assertEqual(zh_hant["stringUnit"]["value"], "詢問 Exodus")
        self.assertEqual(listed_under(out, MISSING_HEADING), ["chat:removed.key"])

    def test_an_ios_key_the_desktop_lacks_is_not_an_error(self):
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        self.assertNotIn(MISSING_HEADING, out)
        self.assertIn("independently translated", out)
        self.assertIn("ios:onlyKey", out)

    def test_a_shared_key_with_desktop_markup_is_an_error_and_is_not_overwritten(self):
        for markup in ["Ask <1>Exodus</1>", "Ask <strong>Exodus</strong>", "Ask<br/>Exodus", "<i>Ask</i> Exodus"]:
            with self.subTest(markup=markup):
                # The markup is in one language only: any language counts.
                self.write_chat("fr", {"composer": {"placeholder": markup}})
                code, out = self.run_sync()
                self.assertEqual(code, 1)
                self.assertEqual(listed_under(out, UNSHAREABLE_HEADING), ["chat:composer.placeholder"])
                self.assertNotIn(MISSING_HEADING, out)
                locs = self.catalog()["chat:composer.placeholder"]["localizations"]
                self.assertEqual(locs["zh-Hant"]["stringUnit"]["value"], "STALE")
                self.assertNotIn("fr", locs)

    def test_a_plural_suffixed_shared_key_is_an_error(self):
        for suffix in ["zero", "one", "two", "few", "many", "other"]:
            with self.subTest(suffix=suffix):
                for desktop_dir in DESKTOP_DIRS.values():
                    self.write_chat(desktop_dir, {"items_" + suffix: "{{count}} items"})
                self.add_entry("chat:items_" + suffix, {"extractionState": "manual"})
                code, out = self.run_sync()
                self.assertEqual(code, 1)
                self.assertIn("chat:items_" + suffix, listed_under(out, UNSHAREABLE_HEADING))
                self.assertNotIn("localizations", self.catalog()["chat:items_" + suffix])

    def test_a_key_that_merely_ends_like_a_plural_word_is_shared_normally(self):
        # "_one" must be a suffix after an underscore, not the end of a word.
        for desktop_dir in DESKTOP_DIRS.values():
            self.write_chat(desktop_dir, {"phone": "Phone", "someone": "Someone"})
        self.add_entry("chat:phone", {"extractionState": "manual"})
        self.add_entry("chat:someone", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)

    def test_markup_and_missing_errors_are_listed_separately(self):
        self.write_chat("fr", {"composer": {"placeholder": "Ask <1>Exodus</1>"}})
        self.add_entry("chat:removed.key", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 1)
        self.assertEqual(listed_under(out, MISSING_HEADING), ["chat:removed.key"])
        self.assertEqual(listed_under(out, UNSHAREABLE_HEADING), ["chat:composer.placeholder"])

    # ---- plural keys and reordered placeholders

    def write_plurals(self, forms_by_dir):
        for desktop_dir in DESKTOP_DIRS.values():
            self.write_chat(desktop_dir, forms_by_dir.get(desktop_dir, forms_by_dir["en"]))

    def test_a_plural_on_the_desktop_becomes_catalog_plural_variations(self):
        self.write_plurals({
            "en": {"note_one": "{{count}} more character", "note_other": "{{count}} more characters"},
            "ja": {"note_other": "さらに{{count}}文字"},
        })
        self.add_entry("chat:note", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        locs = self.catalog()["chat:note"]["localizations"]
        self.assertEqual(locs["en"], {"variations": {"plural": {
            "one": translated("%lld more character"), "other": translated("%lld more characters")}}})
        # ja has no `one` form on the desktop, and gets none here.
        self.assertEqual(locs["ja"], {"variations": {"plural": {"other": translated("さらに%lld文字")}}})

    def test_a_plural_with_a_second_placeholder_keeps_it_as_percent_at(self):
        self.write_plurals({"en": {"label_one": "Used {{count}} memory · {{keys}}",
                                   "label_other": "Used {{count}} memories · {{keys}}"}})
        self.add_entry("chat:label", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        other = self.catalog()["chat:label"]["localizations"]["fr"]["variations"]["plural"]["other"]
        self.assertEqual(other["stringUnit"]["value"], "Used %lld memories · %@")

    def test_a_plural_whose_first_placeholder_is_not_count_is_an_error(self):
        # The compiled plural rule reads the first argument; anything else there would pick the form.
        self.write_plurals({"en": {"label_one": "{{keys}}: {{count}} memory", "label_other": "{{keys}}: {{count}} memories"}})
        self.add_entry("chat:label", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 1)
        self.assertEqual(listed_under(out, UNSHAREABLE_HEADING), ["chat:label"])
        self.assertNotIn("localizations", self.catalog()["chat:label"])

    def test_a_plural_language_that_moves_count_later_gets_positional_placeholders(self):
        self.write_plurals({
            "en": {"label_one": "Used {{count}} memory · {{keys}}", "label_other": "Used {{count}} memories · {{keys}}"},
            "ko": {"label_other": "{{keys}} · {{count}}개 사용"},
        })
        self.add_entry("chat:label", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        ko = self.catalog()["chat:label"]["localizations"]["ko"]["variations"]["plural"]["other"]
        self.assertEqual(ko["stringUnit"]["value"], "%2$@ · %1$lld개 사용")

    def test_a_language_missing_the_other_form_is_missing(self):
        self.write_plurals({"en": {"note_one": "{{count}} x", "note_other": "{{count}} xs"},
                            "de": {"note_one": "{{count}} x"}})
        self.add_entry("chat:note", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 1)
        self.assertEqual(listed_under(out, MISSING_HEADING), ["chat:note"])
        self.assertIn("de", out)

    def test_plain_in_one_language_and_plural_in_another_is_an_error(self):
        self.write_plurals({"en": {"note_one": "{{count}} x", "note_other": "{{count}} xs"},
                            "it": {"note": "{{count}} x"}})
        self.add_entry("chat:note", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 1)
        self.assertEqual(listed_under(out, UNSHAREABLE_HEADING), ["chat:note"])

    def test_reordered_placeholders_become_positional_and_are_listed(self):
        # chat:placeDetail.pagination: ja and ko put the total first.
        self.write_plurals({
            "en": {"pagination": "{{index}} of {{total}}"},
            "ja": {"pagination": "{{total}}件中{{index}}件目"},
            "ko": {"pagination": "{{total}} 중 {{index}}"},
        })
        self.add_entry("chat:pagination", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        locs = self.catalog()["chat:pagination"]["localizations"]
        self.assertEqual(locs["en"]["stringUnit"]["value"], "%@ of %@")
        self.assertEqual(locs["ja"]["stringUnit"]["value"], "%2$@件中%1$@件目")
        self.assertEqual(locs["ko"]["stringUnit"]["value"], "%2$@ 중 %1$@")
        self.assertEqual(listed_under(out, l10n.REORDERED_HEADING), ["chat:pagination"])
        self.assertIn("ja, ko", out)

    def test_placeholders_in_the_same_order_are_not_listed_as_reordered(self):
        self.write_plurals({"en": {"pagination": "{{index}} of {{total}}"}})
        self.add_entry("chat:pagination", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 0, out)
        self.assertNotIn(l10n.REORDERED_HEADING, out)

    def test_a_language_with_other_placeholders_is_an_error(self):
        self.write_plurals({"en": {"pagination": "{{index}} of {{total}}"}, "fr": {"pagination": "{{index}} sur {{count}}"}})
        self.add_entry("chat:pagination", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 1)
        self.assertEqual(listed_under(out, UNSHAREABLE_HEADING), ["chat:pagination"])
        self.assertIn("fr", out)

    def test_a_reordered_text_with_a_repeated_placeholder_is_an_error(self):
        self.write_plurals({"en": {"x": "{{a}} and {{a}} or {{b}}"}, "ja": {"x": "{{b}} {{a}} {{a}}"}})
        self.add_entry("chat:x", {"extractionState": "manual"})
        code, out = self.run_sync()
        self.assertEqual(code, 1)
        self.assertEqual(listed_under(out, UNSHAREABLE_HEADING), ["chat:x"])


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


def catalog_of(**en_by_key):
    """A catalog fixture: each keyword is a key (`__` stands for `:`, `_` inside a name is kept) mapped
    to its English text."""
    return {
        key.replace("__", ":"): {"extractionState": "manual", "localizations": {"en": translated(en)}}
        for key, en in en_by_key.items()
    }


class AuditDefaultValueTests(unittest.TestCase):
    """`String(localized:)` must carry `defaultValue:`, and its text must be the catalog's `en`."""

    STRINGS = {
        "ios:x": {"extractionState": "manual", "localizations": {"en": translated("Hello")}},
        "ios:paired": {"extractionState": "manual", "localizations": {"en": translated("Paired with %@")}},
        "ios:http": {"extractionState": "manual", "localizations": {"en": translated("HTTP %lld")}},
        "ios:two": {"extractionState": "manual", "localizations": {"en": translated("%1$@ of %2$@")}},
        "ios:rain": {"extractionState": "manual", "localizations": {"en": translated("50%% rain")}},
    }

    def audit(self, swift, strings=None):
        with fake_repo(self.STRINGS if strings is None else strings, swift=swift):
            return run_audit()

    def test_a_call_without_default_value_is_an_error(self):
        code, out = self.audit('let s = String(localized: "ios:x", comment: "c")\n')
        self.assertEqual(code, 1)
        self.assertIn("defaultValue", out)
        self.assertIn("View.swift:1", out)
        self.assertIn("ios:x", out)

    def test_a_bare_call_with_only_the_key_is_an_error(self):
        code, out = self.audit('let s = String(localized: "ios:x")\n')
        self.assertEqual(code, 1)
        self.assertIn("defaultValue", out)

    def test_a_matching_default_value_passes(self):
        code, out = self.audit('let s = String(localized: "ios:x", defaultValue: "Hello", comment: "c")\n')
        self.assertEqual(code, 0, out)

    def test_a_default_value_that_differs_from_the_catalog_en_is_an_error_naming_both(self):
        code, out = self.audit('let s = String(localized: "ios:x", defaultValue: "Goodbye", comment: "c")\n')
        self.assertEqual(code, 1)
        self.assertIn("Goodbye", out)
        self.assertIn("Hello", out)
        self.assertIn("ios:x", out)
        self.assertIn("View.swift:1", out)

    def test_an_interpolation_stands_for_percent_at(self):
        swift = 'let s = String(localized: "ios:paired", defaultValue: "Paired with \\(name)", comment: "c")\n'
        code, out = self.audit(swift)
        self.assertEqual(code, 0, out)

    def test_a_typed_catalog_placeholder_is_read_as_percent_at(self):
        swift = 'let s = String(localized: "ios:http", defaultValue: "HTTP \\(http.statusCode)", comment: "c")\n'
        code, out = self.audit(swift)
        self.assertEqual(code, 0, out)

    def test_positional_catalog_placeholders_are_read_as_percent_at(self):
        swift = 'let s = String(localized: "ios:two", defaultValue: "\\(a) of \\(b)", comment: "c")\n'
        code, out = self.audit(swift)
        self.assertEqual(code, 0, out)

    def test_a_wrong_number_of_interpolations_is_an_error(self):
        swift = 'let s = String(localized: "ios:paired", defaultValue: "Paired with you", comment: "c")\n'
        code, out = self.audit(swift)
        self.assertEqual(code, 1)
        self.assertIn("Paired with you", out)
        self.assertIn("Paired with %@", out)

    def test_an_interpolation_with_nested_calls_and_strings_is_one_placeholder(self):
        swift = ('let s = String(localized: "ios:paired", '
                 'defaultValue: "Paired with \\(names.joined(separator: ", "))", comment: "c")\n')
        code, out = self.audit(swift)
        self.assertEqual(code, 0, out)

    def test_a_literal_percent_matches_an_escaped_percent_in_the_catalog(self):
        code, out = self.audit('let s = String(localized: "ios:rain", defaultValue: "50% rain", comment: "c")\n')
        self.assertEqual(code, 0, out)

    def test_a_multi_line_call_is_checked(self):
        swift = (
            "let s = String(\n"
            '    localized: "ios:x",\n'
            '    defaultValue: "Hello",\n'
            '    comment: "c")\n'
        )
        code, out = self.audit(swift)
        self.assertEqual(code, 0, out)
        code, out = self.audit(swift.replace("Hello", "Bye"))
        self.assertEqual(code, 1)
        self.assertIn("Bye", out)
        code, out = self.audit(swift.replace('    defaultValue: "Hello",\n', ""))
        self.assertEqual(code, 1)
        self.assertIn("defaultValue", out)

    def test_a_default_value_that_is_not_a_literal_is_only_checked_for_presence(self):
        code, out = self.audit('let s = String(localized: "ios:x", defaultValue: fallback, comment: "c")\n')
        self.assertEqual(code, 0, out)

    def test_an_unknown_key_reports_the_missing_key_only(self):
        code, out = self.audit('let s = String(localized: "ios:nope", defaultValue: "Hi", comment: "c")\n')
        self.assertEqual(code, 1)
        self.assertIn("is not in Localizable.xcstrings", out)
        self.assertNotIn("differs", out)

    def test_a_view_literal_needs_no_default_value(self):
        code, out = self.audit('Text("ios:x")\n')
        self.assertEqual(code, 0, out)

    def test_an_l10n_ignore_line_is_skipped(self):
        code, out = self.audit('let s = String(localized: "ios:x") // l10n:ignore\n')
        self.assertEqual(code, 0, out)

    def test_a_default_value_in_a_comment_is_not_read(self):
        swift = '// String(localized: "ios:x", defaultValue: "Goodbye")\nText("ios:x")\n'
        code, out = self.audit(swift)
        self.assertEqual(code, 0, out)


def plural_loc(**forms):
    return {"variations": {"plural": {c: translated(v) for c, v in forms.items()}}}


class AuditPluralTests(unittest.TestCase):
    def entry(self, **locs):
        return {"chat:note": {"extractionState": "manual", "localizations": locs}}

    def errors(self, strings):
        with fake_repo(strings):
            return l10n.audit_catalog(l10n.LOCALIZABLE, implicit_source=False, source_only=True)

    def test_a_plural_localization_passes(self):
        strings = self.entry(en=plural_loc(one="%lld thing", other="%lld things"), ja=plural_loc(other="%lld 件"))
        self.assertEqual(self.errors(strings), [])

    def test_a_plural_without_other_is_an_error(self):
        strings = self.entry(en=plural_loc(one="%lld thing", other="%lld things"), ja=plural_loc(one="%lld 件"))
        self.assertTrue(any("[ja]" in e and "plural" in e for e in self.errors(strings)), self.errors(strings))

    def test_each_plural_form_is_checked_for_placeholders(self):
        strings = self.entry(en=plural_loc(one="%lld thing", other="%lld things"), fr=plural_loc(one="une chose", other="%lld choses"))
        errors = self.errors(strings)
        self.assertTrue(any("[fr one] placeholders differ" in e for e in errors), errors)

    def test_an_untranslated_plural_form_is_an_error(self):
        strings = self.entry(en=plural_loc(other="%lld things"))
        strings["chat:note"]["localizations"]["de"] = {"variations": {"plural": {"other": {"stringUnit": {"state": "new", "value": "%lld"}}}}}
        self.assertTrue(any("[de other] is not translated" in e for e in self.errors(strings)))

    def test_a_substitution_or_device_variation_is_still_an_error(self):
        subst = {"stringUnit": translated("%#@n@")["stringUnit"], "substitutions": {"n": {}}}
        device = {"variations": {"device": {"iphone": translated("x")}}}
        for loc in (subst, device):
            with self.subTest(loc=loc):
                strings = self.entry(en=plural_loc(other="%lld things"), ko=loc)
                self.assertTrue(any("[ko] must be a plain stringUnit or a plural" in e for e in self.errors(strings)))

    def test_a_default_value_is_compared_with_the_plural_other_form(self):
        strings = self.entry(**{lang: plural_loc(one="%lld thing", other="%lld things") for lang in l10n.SHIPPED})
        swift = 'let s = String(localized: "chat:note", defaultValue: "\\(n) things", comment: "c")\n'
        with fake_repo(strings, swift=swift):
            code, out = run_audit()
        self.assertEqual(code, 0, out)
        with fake_repo(strings, swift=swift.replace("things", "items")):
            code, out = run_audit()
        self.assertEqual(code, 1)
        self.assertIn("differs from the catalog en", out)

    def test_a_default_value_may_be_any_english_plural_form(self):
        # Without the catalog (the hostless tests) defaultValue is the text, so a call site gives each form.
        strings = self.entry(**{lang: plural_loc(one="%lld thing", other="%lld things") for lang in l10n.SHIPPED})
        swift = 'let s = String(localized: "chat:note", defaultValue: "\\(n) thing", comment: "c")\n'
        with fake_repo(strings, swift=swift):
            code, out = run_audit()
        self.assertEqual(code, 0, out)


class AuditVendorTests(unittest.TestCase):
    """A desktop-namespaced key must also be in Vendor/exodus-locales (I1 of the C9 review)."""

    STRINGS = {
        "chat:composer.placeholder": {"extractionState": "manual", "localizations": {"en": translated("Ask")}},
        "chat:note": {"extractionState": "manual", "localizations": {"en": plural_loc(other="%lld things")}},
        "ios:x": {"extractionState": "manual", "localizations": {"en": translated("iOS")}},
        "chat:brand": {"extractionState": "manual", "shouldTranslate": False},
    }
    SWIFT = 'Text("chat:composer.placeholder")\nText("chat:note")\nText("ios:x")\n'

    def audit_with_vendor(self, chat):
        with fake_repo(self.STRINGS, swift=self.SWIFT) as root:
            (root / "Vendor/exodus-locales/en").mkdir(parents=True)
            (root / "Vendor/exodus-locales/en/chat.json").write_text(json.dumps(chat))
            return run_audit()

    def test_every_desktop_key_in_the_vendor_passes(self):
        code, out = self.audit_with_vendor({"composer": {"placeholder": "Ask"}, "note_one": "a", "note_other": "b"})
        self.assertEqual(code, 0, out)

    def test_a_desktop_key_missing_from_the_vendor_fails(self):
        code, out = self.audit_with_vendor({"note_other": "b"})
        self.assertEqual(code, 1)
        self.assertIn("'chat:composer.placeholder' is a desktop key but not in Vendor/exodus-locales", out)
        self.assertNotIn("'chat:note'", out.split("error:", 1)[-1])
        self.assertNotIn("ios:x' is a desktop key", out)
        self.assertNotIn("chat:brand' is a desktop key", out)


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


if __name__ == "__main__":
    unittest.main()
