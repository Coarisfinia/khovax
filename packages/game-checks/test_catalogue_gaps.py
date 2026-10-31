"""Tests catalogue_gaps.py (#1968) on small catalogues: entries are read by their context and text,
over continued lines, escapes and plurals; the header, obsolete entries, fuzzy ones and empty
translations translate nothing; and a catalogue's gaps against the template (texts it leaves
untranslated, and texts the template no longer has) are reported as warnings.

    uv run --locked --package khovax-game-checks packages/game-checks/test_catalogue_gaps.py
"""

import unittest

from catalogue_gaps import Entry, entries, gaps, report

TEMPLATE = """msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\\n"

#: a.gd
msgid "Taken"
msgstr ""

#: b.gd
msgctxt "gear rarity"
msgid "Rare"
msgstr ""

#: c.gd
msgid "Nodes to take: {count}"
msgid_plural "Nodes to take: {count}"
msgstr[0] ""
msgstr[1] ""

#: d.gd
msgid ""
"Two "
"\\"lines\\"\\n"
msgstr ""
"""

CATALOGUE = """msgid ""
msgstr ""
"Language: de\\n"

msgid "Taken"
msgstr "Genommen"

#, fuzzy
msgctxt "gear rarity"
msgid "Rare"
msgstr "Selten"

msgid "Nodes to take: {count}"
msgid_plural "Nodes to take: {count}"
msgstr[0] "Ein Knoten"
msgstr[1] ""

msgid "Gone"
msgstr "Weg"

#~ msgid "Long gone"
#~ msgstr "Lange weg"
"""


class CatalogueGapsTest(unittest.TestCase):
    def test_reads_entries(self) -> None:
        self.assertEqual(
            entries(TEMPLATE),
            [
                Entry(None, "Taken", False),
                Entry("gear rarity", "Rare", False),
                Entry(None, "Nodes to take: {count}", False),
                Entry(None, 'Two "lines"\n', False),
            ],
        )

    def test_fuzzy_partial_and_obsolete_translate_nothing(self) -> None:
        self.assertEqual(
            entries(CATALOGUE),
            [
                Entry(None, "Taken", True),
                Entry("gear rarity", "Rare", False),
                Entry(None, "Nodes to take: {count}", False),
                Entry(None, "Gone", True),
            ],
        )

    def test_gaps_against_the_template(self) -> None:
        missing, stale = gaps(entries(TEMPLATE), entries(CATALOGUE))
        self.assertEqual(
            missing,
            [("gear rarity", "Rare"), (None, "Nodes to take: {count}"), (None, 'Two "lines"\n')],
        )
        self.assertEqual(stale, [(None, "Gone")])

    def test_reports_gaps(self) -> None:
        warnings = report("de", TEMPLATE, CATALOGUE)
        self.assertEqual(len(warnings), 2)
        self.assertIn("3 of 4", warnings[0])
        self.assertIn("Rare (gear rarity)", warnings[0])
        self.assertIn("Gone", warnings[1])
        complete = CATALOGUE.replace('msgstr[1] ""', 'msgstr[1] "{count} Knoten"')
        self.assertEqual(len(report("de", TEMPLATE.split("#: b.gd")[0], complete)), 1)


if __name__ == "__main__":
    unittest.main()
