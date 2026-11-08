"""Tests known_gaps_check.py (#2182) on small versions of the list: an entry taken out passes, one
added is named, and a version without the list can't be compared.

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

    def test_a_missing_list_cant_be_compared(self) -> None:
        self.assertIsNone(added(BEFORE, "renamed"))
        self.assertIsNone(added("renamed", BEFORE))


if __name__ == "__main__":
    unittest.main()
