"""Tests tr_placeholders.py (#1704) on small scripts: a tr() literal with two or more %
placeholders is refused, in tr(), TranslationServer.tr() and tr_n()'s plural alike; one value,
named values, %% and a literal outside tr() pass.

    uv run --locked --package khovax-game-checks packages/game-checks/test_tr_placeholders.py
"""

import unittest

from tr_placeholders import crowded, placeholders


class TrPlaceholdersTest(unittest.TestCase):
    def test_counts_specifiers(self) -> None:
        self.assertEqual(placeholders("Carried %d: %s"), 2)
        self.assertEqual(placeholders("Your standing: %+d, %s"), 2)
        self.assertEqual(placeholders("%05.1f%% of %s"), 2)
        self.assertEqual(placeholders("100%% sure: %s"), 1)
        self.assertEqual(placeholders("{stat} {shift}%"), 0)
        # A * takes a value too, a bare precision is still a specifier, and %% is read first.
        self.assertEqual(placeholders("%*d"), 2)
        self.assertEqual(placeholders("%*.*f"), 3)
        self.assertEqual(placeholders("%.f / %s"), 2)
        self.assertEqual(placeholders("%%%%s %s"), 1)

    def test_refuses_two_positional_values(self) -> None:
        source = (
            'func a() -> String:\n\treturn tr("Carried %d: %s") % [1, "x"]\n'
            "func b() -> String:\n"
            '\treturn TranslationServer.tr("%s ascended into %s!") % ["a", "b"]\n'
            'func c(n: int) -> String:\n\treturn tr_n("%s egg", "%d eggs of %s", n) % [n, "x"]\n'
        )
        self.assertEqual(
            list(crowded(source)), ["Carried %d: %s", "%s ascended into %s!", "%d eggs of %s"]
        )

    def test_passes_one_named_or_untranslated(self) -> None:
        source = (
            'func a() -> String:\n\treturn tr("Not carried: %s") % "x"\n'
            'func b() -> String:\n\treturn tr("Carried {place}: {monster}").format({})\n'
            'func c() -> String:\n\treturn tr("%d%% done") % 5\n'
            'func d() -> String:\n\treturn "%s: %s" % ["a", "b"]\n'
            '# tr("%s and %s") in a comment\n'
        )
        self.assertEqual(list(crowded(source)), [])


if __name__ == "__main__":
    unittest.main()
