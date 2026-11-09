"""Tests determinism_check.py's patterns (#2210) on single lines: every form of global randomness
and floats is refused, and what only looks like one (in a string, a comment, a name or a member
access) isn't. The check runs this first, so CI's step for the check runs it too.

    uv run --locked --package khovax-game-checks packages/game-checks/test_determinism_check.py
"""

import unittest

from determinism_check import forbidden_lines

REFUSED = (
    "items.shuffle()",
    "var a = items.pick_random()",
    "var r := RandomNumberGenerator.new()",
    "var a := .5",
    "var a := -.5",
    "var a := [.5]",
    "var a := .5e3",
    "var a := 2.",
    "var a := (2.)",
    "var a := [2., 3]",
    "var a := 2.e3",
    "var a := 1_000.",
    "var a := sqrt(2)",
    "var a := sin(1)",
    "var a := cos(1)",
    "var a := pow(2, 3)",
    "var a := fmod(5, 3)",
    "var a := lerp(0, 1, 2)",
    "var a := deg_to_rad(90)",
    'var a := "1".to_float()',
    "var a := floor(1)",
    "var a := round(1)",
    "var a := clampf(1, 0, 2)",
    "var a := snappedf(1, 2)",
    "var a := 1e-3",
    "var a := 1_000e3",
    "var a := PI",
    "var a := TAU",
    "var a := INF",
    "var a := NAN",
    # What the check already refused stays refused.
    "var a := 0.5",
    "var a := 1e3",
    "var a := randf()",
    "var a: float = 0",
)

ALLOWED = (
    "var a := v2.x",
    "var a := items[1].y",
    "var a := 2.foo",
    "var a := 2.foo()",
    "var a := Vector2i(1, 2).x",
    "var a := grid2.size()",
    "var v2e3 := 1",
    "var a := 0x1e3",
    'var a := "2."',
    'var a := ".5"',
    'var a := "version 1.2.3"',
    'var a := "PI and sqrt(2), a float"',
    "var a := 'items.shuffle()'",
    'var a := """multi 2.',
    "and .5 lines 1.2 PI",
    'end"""',
    "var a := 1 # .5 and 2. and PI and items.shuffle() and 1.2",
    "func shuffled_ids() -> Array[int]:",
    "var sinus := 1",
    "var PI_COUNT := 1",
    "var a := Rng.new(1, 2)",
)


class FormsTest(unittest.TestCase):
    def test_every_form_is_refused(self) -> None:
        missed = [line for line in REFUSED if not forbidden_lines(line)]
        self.assertEqual(missed, [])

    def test_what_only_looks_like_one_is_allowed(self) -> None:
        self.assertEqual(forbidden_lines("\n".join(ALLOWED)), [])

    def test_a_hit_keeps_its_line_number_after_a_multi_line_string(self) -> None:
        self.assertEqual(forbidden_lines('var a := """x\ny"""\nvar b := .5'), ["3:var b := .5"])


if __name__ == "__main__":
    unittest.main()
