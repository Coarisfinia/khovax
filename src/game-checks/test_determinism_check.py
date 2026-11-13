"""Tests determinism_check.py's patterns (#2210) on single lines: every form of global randomness
and floats is refused, and what only looks like one (in a string, a comment, a name or a member
access) isn't. The check runs this first, so CI's step for the check runs it too.

    uv run --locked --package khovax-game-checks src/game-checks/test_determinism_check.py
"""

import unittest
from unittest import mock

from determinism_check import forbidden_lines, own_test_passes

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
    "var a := ease(1, 2)",
    "var a := pingpong(1, 2)",
    "var a := cubic_interpolate(0, 1, 2, 3, 4)",
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
    # Forms that got past the patterns (#2216).
    "var a := randi_range (0, 1)",
    "items.shuffle.call()",
    'items.call("shuffle")',
    "items.callv(&'pick_random', [])",
    # Float sources (#2216).
    "var a := Vector2i(3, 4).length()",
    "var a := Vector2i.ONE.length()",
    "var a := Vector2i(1, 2).abs().length()",
    "var a := Vector2i(get_x(), 4).length()",
    "var a := Vector3i(1, 2, 3).length()",
    "var a := Vector4i.ONE.length()",
    "var a := Vector2i(1, 2).distance_to(other)",
    "var a := Vector3i.ONE.abs().distance_to(other)",
    "var e := Expression.new()",
    "var a := Vector2i.ONE.snapped(Vector2i(2, 2)).length()",
    # A call nested more than one level inside the receiver or a chained method (#2223).
    "var a := Vector2i(get_x(get_y()), 4).length()",
    "var a := Vector2i(f(g(h(1))), 4).length()",
    "var a := Vector2i.ONE.clamp(Vector2i(f(g(1)), 0), b).length()",
    "var a := tile.aspect()",
    "var a := PackedFloat32Array()",
    "var a := PackedFloat64Array()",
    "var a := type_convert(x, TYPE_FLOAT)",
    "var a := str_to_var(x)",
    # Float sources and calls by name (#2223).
    "var a := PackedVector2Array()",
    "var a := PackedVector3Array()",
    "var a := PackedVector4Array()",
    "var a := PackedColorArray()",
    'var c := Callable(items, "shuffle")',
    "var c := Callable(get_items(), &'pick_random')",
    'var c := Callable.create(items, "shuffle")',
    'var c := Callable(get_items(filter_items(source)), "shuffle")',
    'items.call ("shuffle", [1, (2)])',
    'items.call(StringName("shuffle"))',
    'var c := Callable(items, StringName("pick_random"))',
    "var a := bytes_to_var(x)",
    "var a := bytes_to_var_with_objects(x)",
    "var a := bytes.decode_half(0)",
    "var a := bytes.decode_float(0)",
    "var a := bytes.decode_double(0)",
    "var a := bytes.decode_var(0)",
    "var a := bytes.to_float32_array()",
    "var a := bytes.to_float64_array()",
    'var a := text.similarity("b")',
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
    # Members named like a global float function (#2216).
    "var a := obj.round()",
    'Logger.log("x")',
    "var a := rng.exp(1)",
    "var a := vi.snapped(x)",
    # A string that only reads like a call to global randomness, or names something else (#2216).
    'var a := "the seed (in a text)"',
    'var a := x.call("shuffled")',
    'var a := "obj.call(\'shuffle\')"',
    "var a := type_convert(x, TYPE_INT)",
    "var a := text.length()",
    "var a := other.distance_to(x)",
    # Named like a float source or a call by name, but none (#2223).
    'var c := Callable(items, "shuffled")',
    'var c := Callable(items, "sort")\nvar d := "shuffle"',
    "var a := my_bytes_to_var(x)",
    "var a := bytes.decode_u32(0)",
    "var a := bytes.decode_var_size(0)",
    'items.call("sort", "shuffle")',
    'var c := Callable(items, foo("shuffle"))',
    'var a := ["shuffle"]',
    'var a := StringName("shuffle")',
    "var a := bytes.to_int32_array()",
    # A deeply nested integer vector that isn't length()'s receiver (#2223).
    "var a := f(Vector2i(g(h(1)), 2)).length()",
    "var a := Vector2i(f(g(1)), 2).x + text.length()",
)


class FormsTest(unittest.TestCase):
    def test_every_form_is_refused(self) -> None:
        missed = [line for line in REFUSED if not forbidden_lines(line)]
        self.assertEqual(missed, [])

    def test_what_only_looks_like_one_is_allowed(self) -> None:
        self.assertEqual(forbidden_lines("\n".join(ALLOWED)), [])

    def test_a_hit_keeps_its_line_number_after_a_multi_line_string(self) -> None:
        self.assertEqual(forbidden_lines('var a := """x\ny"""\nvar b := .5'), ["3:var b := .5"])

    def test_the_length_of_a_declared_vector2i_is_refused(self) -> None:
        self.assertEqual(
            forbidden_lines("var tile: Vector2i\nvar a := tile.length()"),
            ["2:var a := tile.length()"],
        )

    def test_a_declared_vector3i_or_vector4i_is_refused(self) -> None:
        self.assertEqual(
            forbidden_lines("var tile: Vector3i\nvar a := tile.distance_to(b)"),
            ["2:var a := tile.distance_to(b)"],
        )
        self.assertEqual(
            forbidden_lines("var tile: Vector4i\nvar a := tile.length()"),
            ["2:var a := tile.length()"],
        )

    def test_a_chain_on_a_declared_vector2i_is_refused(self) -> None:
        self.assertEqual(
            forbidden_lines("var tile: Vector2i\nvar a := tile.abs().length()"),
            ["2:var a := tile.abs().length()"],
        )

    def test_type_float_on_its_own_line_is_refused(self) -> None:
        self.assertEqual(
            forbidden_lines("var a := type_convert(\n\tx, TYPE_FLOAT)"),
            ["2:\tx, TYPE_FLOAT)"],
        )

    def test_a_call_by_name_over_several_lines_is_refused(self) -> None:
        self.assertEqual(
            forbidden_lines('items.call(\n\t"shuffle"\n)'),
            ['2:\t"shuffle"'],
        )
        self.assertEqual(
            forbidden_lines("var c := Callable(\n\titems,\n\t&'pick_random')"),
            ["3:\t&'pick_random')"],
        )

    def test_the_length_of_anything_else_is_allowed(self) -> None:
        for source in (
            "func f(tile: Vector2i, text: String) -> int:\n\treturn text.length()",
            "var d := {tile: Vector2i(1, 2)}\nvar a := tile.length()",
            "var d := {tile: Vector2i.ONE}\nvar a := tile.length()",
        ):
            self.assertEqual(forbidden_lines(source), [], source)


class OwnTestTest(unittest.TestCase):
    def test_a_test_module_without_tests_does_not_pass(self) -> None:
        with mock.patch(
            "determinism_check.unittest.defaultTestLoader.loadTestsFromName",
            return_value=unittest.TestSuite(),
        ):
            self.assertFalse(own_test_passes())


if __name__ == "__main__":
    unittest.main()
