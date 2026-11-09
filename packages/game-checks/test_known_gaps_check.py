"""Tests known_gaps_check.py (#2182) on small versions of the list: an entry taken out passes, one
added is named however it's written or whatever comments surround it, and a version without a
readable list can't be compared.

    uv run --locked --package khovax-game-checks packages/game-checks/test_known_gaps_check.py
"""

import unittest

from known_gaps_check import added, entries

BEFORE = """## "a/quoted" comment
const KNOWN_GAPS: Array[String] = [
	# #1: don't read this comment's apostrophes, or "this"
	"f/t",
	"f/u",
]
const OTHER: Array[String] = ["g/z"]
"""


class KnownGapsTest(unittest.TestCase):
    def test_entries_are_only_the_lists(self) -> None:
        self.assertEqual(entries(BEFORE), {"f/t", "f/u"})
        self.assertEqual(entries("const KNOWN_GAPS: Array[String] = []"), set())

    def test_taking_entries_out_passes(self) -> None:
        self.assertEqual(added(BEFORE, BEFORE.replace('\t"f/u",\n', "")), [])

    def test_a_new_entry_is_named(self) -> None:
        self.assertEqual(added(BEFORE, BEFORE.replace('"f/u"', '"f/u", "g/t"')), ["g/t"])

    def test_a_single_quoted_entry_is_named(self) -> None:
        self.assertEqual(added(BEFORE, BEFORE.replace('"f/u"', "\"f/u\", 'g/t'")), ["g/t"])

    def test_a_bracket_in_a_comment_doesnt_end_the_list(self) -> None:
        after = BEFORE.replace('\t"f/u",\n', '\t"f/u",\n\t# see [#9]\n\t"x/y",\n')
        self.assertEqual(added(BEFORE, after), ["x/y"])

    def test_a_commented_out_list_isnt_the_list(self) -> None:
        decoy = '# const KNOWN_GAPS: Array[String] = ["f/t", "f/u", "x/y"]\n'
        self.assertEqual(added(BEFORE, decoy + BEFORE.replace('"f/u"', '"f/u", "x/y"')), ["x/y"])

    def test_marks_inside_an_entry_are_part_of_it(self) -> None:
        after = BEFORE.replace('"f/u"', '"f/u", "x#y", "p]q"')
        self.assertEqual(added(BEFORE, after), ["p]q", "x#y"])

    def test_anything_after_the_list_cant_be_compared(self) -> None:
        self.assertIsNone(added(BEFORE, BEFORE.replace('\n]\n', '\n] + ["x/y"]\n')))

    def test_a_missing_list_cant_be_compared(self) -> None:
        self.assertIsNone(added(BEFORE, "renamed"))
        self.assertIsNone(added("renamed", BEFORE))


if __name__ == "__main__":
    unittest.main()
