"""Tests determinism_check.py's patterns (#2210) on single lines: every form of global randomness
and floats is refused, and what only looks like one (in a string, a comment, a name or a member
access) isn't. The check runs this first, so CI's step for the check runs it too.

    uv run --locked --package khovax-game-checks src/game-checks/test_determinism_check.py
"""

import unittest
from unittest import mock

from determinism_check import (
    forbidden_lines,
    inherited_members,
    int_vector_functions,
    int_vector_members,
    own_test_passes,
)

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
    # A declared name that starts another declared one (#2223).
    "var size: Vector2i\nvar size_max: Vector2i\nvar a := size_max.length()",
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
    # A name behind a raw-string prefix or grouping parentheses (#2254).
    'items.call(r"shuffle")',
    "items.callv(r'pick_random', [])",
    'var c := Callable(items, r"shuffle")',
    'items.call(("shuffle"))',
    'items.call( ( ("pick_random") ) )',
    'var c := Callable(items, ("shuffle"))',
    'items.call(StringName(("shuffle")))',
    'items.call((r"shuffle"))',
    # A name in a triple-quoted string (#2266).
    'items.call("""shuffle""")',
    "items.callv('''pick_random''', [])",
    'var c := Callable(items, r"""shuffle""")',
    "items.call(&'''pick_random''')",
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
    # Grouping parentheses that aren't call()'s first argument (#2254).
    'var a := ("shuffle")',
    'var a := foo(("shuffle"))',
    'items.call(("sort"), ("shuffle"))',
    'var a := r"shuffle"',
    # The name is only part of the argument (#2254).
    'items.call(("shuffle" + "d"))',
    'items.call("shuffle" + "d")',
    'items.call(("shuffle") + suffix)',
    'items.call(StringName("shuffle") + suffix)',
    'items.call(StringName(x + "shuffle"))',
    # A triple-quoted name that isn't call()'s whole first argument (#2266).
    'var a := """shuffle"""',
    'items.call("""shuffle""" + "d")',
)

# Variant.Type constants of types that hold floats, and of their integer twins (#2247).
FLOAT_BACKED_TYPES = (
    "VECTOR2",
    "VECTOR3",
    "VECTOR4",
    "RECT2",
    "TRANSFORM2D",
    "TRANSFORM3D",
    "PLANE",
    "QUATERNION",
    "AABB",
    "BASIS",
    "PROJECTION",
    "COLOR",
    "PACKED_FLOAT32_ARRAY",
    "PACKED_FLOAT64_ARRAY",
    "PACKED_VECTOR2_ARRAY",
    "PACKED_VECTOR3_ARRAY",
    "PACKED_VECTOR4_ARRAY",
    "PACKED_COLOR_ARRAY",
)
INTEGER_TYPES = (
    "INT",
    "VECTOR2I",
    "VECTOR3I",
    "VECTOR4I",
    "RECT2I",
    "PACKED_INT32_ARRAY",
    "PACKED_INT64_ARRAY",
    "PACKED_BYTE_ARRAY",
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

    def test_float_backed_type_constants_are_refused(self) -> None:
        # Each builds a float-backed type without naming it (#2247).
        for name in FLOAT_BACKED_TYPES:
            line = f"var a := type_convert(x, TYPE_{name})"
            self.assertEqual(forbidden_lines(line), [f"1:{line}"], name)

    def test_integer_type_constants_are_allowed(self) -> None:
        for name in INTEGER_TYPES:
            self.assertEqual(forbidden_lines(f"var a := type_convert(x, TYPE_{name})"), [], name)

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

    def test_a_declared_vector2i_counts_only_where_it_is_that_name(self) -> None:
        # Another object's member, a dictionary with the type as a value, and the same name in
        # another function (#2264).
        for source in (
            "var tile: Vector2i\nvar a := obj.tile.length()",
            "var tile: Vector2i\nvar a := get_obj().tile.length()",
            "var d := {tile: Vector2i}\nvar a := tile.length()",
            "var d := {a = 1, tile: Vector2i}\nvar a := tile.length()",
            "var d := {\n\ttile: Vector2i,\n}\nvar a := tile.length()",
            "func f(tile: Vector2i) -> void:\n\tpass\n\n\nfunc g(tile: String) -> int:"
            "\n\treturn tile.length()",
            "func f() -> void:\n\tvar tile: Vector2i\n\tif true:\n\t\tpass\n\n\n"
            "func g() -> int:\n\tvar tile := \"x\"\n\treturn tile.length()",
            "class A:\n\tfunc f(tile: Vector2i) -> void:\n\t\tpass\n\n\tfunc g(tile: String)"
            " -> int:\n\t\treturn tile.length()",
        ):
            self.assertEqual(forbidden_lines(source), [], source)

    def test_a_declaration_outside_a_function_counts_only_in_its_class(self) -> None:
        # An inner class's members and the outer class's don't reach each other, and Godot doesn't
        # warn when one shadows the other (#2288).
        for source in (
            "var tile: Vector2i\n\n\nclass Inner:\n\textends RefCounted\n\n\tvar tile: String"
            ' = "ab"\n\n\tfunc f() -> int:\n\t\treturn tile.length()',
            "var tile: Vector2i\n\n\nclass Inner:\n\tfunc f(tile: String) -> int:"
            "\n\t\treturn tile.length()",
            "static var tile: Vector2i\n\n\nclass Inner:\n\tvar tile: String"
            "\n\tvar a := tile.length()",
            "class Inner:\n\tvar tile: Vector2i\n\n\nfunc f() -> void:\n\tvar a := tile.length()",
            "class Inner:\n\tvar tile: Vector2i\n\n\nvar a := tile.length()",
            "class A:\n\tvar tile: Vector2i\n\n\nclass B:\n\tfunc f() -> void:"
            "\n\t\tvar a := tile.length()",
            "var tiles: Array[Vector2i]\n\n\nclass Inner:\n\tvar tiles: Array[String]"
            "\n\tvar a := tiles.front().length()",
            "var spots: Dictionary[String, Vector2i]\n\n\nclass Inner:"
            "\n\tvar spots: Dictionary[String, String]\n\tvar a := spots.get(key).length()",
        ):
            self.assertEqual(forbidden_lines(source), [], source)

    def test_a_declared_vector2i_still_counts_in_its_scope(self) -> None:
        # What #2264's scoping must keep refusing: the line of each length().
        for source in (
            "var tile: Vector2i\n\n\nfunc f() -> void:\n\tvar a := tile.length()",
            "func f() -> void:\n\tvar a := tile.length()\n\n\nvar tile: Vector2i",
            "var tile: Vector2i\nvar a := self.tile.length()",
            "func f(tile: Vector2i) -> void:\n\tif true:\n\t\tvar a := tile.length()",
            "func f(\n\ttile: Vector2i,\n) -> void:\n\tvar a := tile.length()",
            "func f() -> void:\n\tvar tile: Vector2i\n\n\tvar a := tile.length()",
            "var d := {}\nvar tile: Vector2i\nvar a := tile.length()",
            "var d := {f = func(tile: Vector2i) -> void: print(tile.length())}",
            "var d := {\n\tf = func(tile: Vector2i) -> void:\n\t\tprint(tile.length())\n}",
            "var d := {\n\tf = func() -> void:\n\t\tvar tile: Vector2i"
            "\n\t\tprint(tile.length())\n}",
            # Code after a multi-line string's closing quotes, and a backslash continuation
            # indented less, continue their statement: the function goes on (#2271).
            'func f() -> void:\n\tvar tile: Vector2i\n\tvar n := """a\nb""".strip_edges()'
            "\n\tvar a := tile.length()",
            "func f() -> void:\n\tvar tile: Vector2i\n\tvar n := 1 + \\\n2"
            "\n\tvar a := tile.length()",
            # In its own class, and an outer class's constant, which an inner class reaches (#2288).
            "class Inner:\n\tvar tile: Vector2i\n\n\tfunc f() -> void:\n\t\tvar a := tile.length()",
            "class Inner:\n\tvar tile: Vector2i\n\tvar a := tile.length()",
            "var tile: Vector2i\n\n\nclass Inner:\n\tpass\n\n\nfunc f() -> void:"
            "\n\tvar a := tile.length()",
            "const TILE: Vector2i = Vector2i.ONE\n\n\nclass Inner:\n\tfunc f() -> void:"
            "\n\t\tvar a := TILE.length()",
            "class A:\n\tconst TILE: Vector2i = Vector2i.ONE\n\n\tclass B:\n\t\tfunc f() -> void:"
            "\n\t\t\tvar a := TILE.length()",
            "const TILES: Array[Vector2i] = []\n\n\nclass Inner:\n\tfunc f() -> void:"
            "\n\t\tvar a := TILES[0].length()",
            "class Inner:\n\tfunc f() -> void:\n\t\tfor tile in TILES:\n\t\t\tprint(tile.length())"
            "\n\n\nconst TILES: Array[Vector2i] = []",
            "const TILES: Array[Vector2i] = []\n\n\nclass Inner:\n\tfunc f() -> void:"
            "\n\t\tfor tile in TILES.slice(1):\n\t\t\tprint(tile.length())",
            "const SPOTS: Dictionary[String, Vector2i] = {}\n\n\nclass Inner:"
            "\n\tvar a := SPOTS.get(key).length()",
            '@warning_ignore("unused_private_class_variable") const TILE: Vector2i = Vector2i.ONE'
            "\n\n\nclass Inner:\n\tvar a := TILE.length()",
        ):
            hit = [
                f"{number}:{line}"
                for number, line in enumerate(source.split("\n"), 1)
                if "length(" in line
            ]
            self.assertEqual(forbidden_lines(source), hit, source)

    def test_an_integer_vector_member_of_another_script_is_refused(self) -> None:
        # A member some rules script declares as one, reached on any object (#2262).
        for line in (
            "var a := entity.tile.length()",
            "var a := get_entity().tile.length()",
            "var a := entities[0].tile.distance_to(b)",
            "var a := entity.tile.abs().length()",
            "var a := world.entity.tile.length()",
        ):
            self.assertEqual(forbidden_lines(line, {"tile"}), [f"1:{line}"], line)

    def test_another_member_or_a_bare_name_stays_allowed(self) -> None:
        for line in (
            "var a := entity.cell.length()",
            "var a := entity.tiles.length()",
            "var a := entity.tile_name.length()",
            "var a := tile.length()",
        ):
            self.assertEqual(forbidden_lines(line, {"tile"}), [], line)

    def test_members_are_what_a_script_declares_outside_its_functions(self) -> None:
        source = "\n".join(
            (
                "signal moved(to: Vector2i)",
                "var tile: Vector2i",
                "@export var home: Vector3i = Vector3i.ONE",
                "static var spot: Vector4i",
                "const ORIGIN: Vector2i = Vector2i.ZERO",
                "var d := {key: Vector2i(1, 2)}",
                "var text: String",
                "class A:",
                "\tvar inner: Vector2i",
                "func f(param: Vector2i) -> void:",
                "\tvar local: Vector2i",
            )
        )
        self.assertEqual(int_vector_members(source), {"tile", "home", "spot", "ORIGIN", "inner"})

    def test_an_element_of_another_scripts_integer_vector_array_is_refused(self) -> None:
        # An Array[Vector2i] or typed dictionary member, read on another object as #2287 reads
        # the script's own (#2299). The members come from the script itself here; main() gathers
        # them from every rules script.
        for source in (
            "var tiles: Array[Vector2i]\nvar a := obj.tiles[0].length()",
            "var tiles: Array[Vector2i]\nvar a := obj.tiles.front().length()",
            "var tiles: Array[Vector2i]\nvar a := obj.tiles.back().length()",
            "var tiles: Array[Vector3i]\nvar a := get_world().tiles.get(i).distance_to(b)",
            "var tiles: Array[Vector2i]\nvar a := obj.tiles[ids[0]].abs().length()",
            "@export var tiles: Array[Vector2i]\nvar a := entities[0].tiles.pop_back().length()",
            "class A:\n\tconst CORNERS: Array[Vector4i] = []\nvar a := A.CORNERS[0].length()",
            'var spots: Dictionary[String, Vector2i]\nvar a := obj.spots["home"].length()',
            "static var spots: Dictionary[int, Vector2i]\nvar a := obj.spots.get(k).length()",
            "var spots: Dictionary[Rules.Kind, Vector2i]\nvar a := obj.spots[k].length()",
        ):
            hit = [
                f"{number}:{line}"
                for number, line in enumerate(source.split("\n"), 1)
                if "length(" in line or "distance_to(" in line
            ]
            self.assertEqual(forbidden_lines(source, int_vector_members(source)), hit, source)

    def test_another_scripts_array_member_read_otherwise_stays_allowed(self) -> None:
        for source in (
            "var tiles: Array[Vector2i]\nvar a := obj.tiles.size()",
            "var tiles: Array[Vector2i]\nvar a := obj.tiles_name[0].length()",
            "var tiles: Array[Vector2i]\nvar a := obj.tiles.front_name().length()",
            "var names: Array[String]\nvar a := obj.names[0].length()",
            "var names: Dictionary[Vector2i, String]\nvar a := obj.names[tile].length()",
            "func f() -> void:\n\tvar tiles: Array[Vector2i] = []\n\tprint(tiles)"
            "\n\n\nfunc g() -> int:\n\treturn obj.tiles[0].length()",
        ):
            self.assertEqual(forbidden_lines(source, int_vector_members(source)), [], source)

    def test_an_inherited_member_used_by_bare_name_is_refused(self) -> None:
        # A class has the members of the class it extends: an inner class of the same file, through
        # every step, or another rules class (#2306).
        bases = {"Base": {"tile"}}
        for source in (
            "class A:\n\tvar tile: Vector2i\n\n\nclass B extends A:\n\tfunc f() -> void:"
            "\n\t\tvar a := tile.length()",
            "class A:\n\tvar tile: Vector2i\n\n\nclass B:\n\textends A\n\n\tvar a := tile.length()",
            "class A:\n\tvar tile: Vector2i\n\n\nclass B extends A:\n\tpass\n\n\nclass C extends B:"
            "\n\tvar a := self.tile.length()",
            "class A:\n\tvar tiles: Array[Vector2i]\n\n\nclass B extends A:"
            "\n\tvar a := tiles[0].length()",
            "extends Base\n\n\nfunc f() -> void:\n\tvar a := tile.length()",
            "class_name Leaf extends Base\n\n\nfunc f() -> void:\n\tvar a := tile.length()",
            "extends RefCounted\n\n\nclass B extends Base:\n\tvar a := tile.length()",
            # The nearest class of that name around it, not a later one elsewhere.
            "class First:\n\tclass A:\n\t\tvar tile: Vector2i\n\n\tclass B extends A:"
            "\n\t\tvar a := tile.length()\n\n\nclass Second:\n\tclass A:"
            "\n\t\tvar tile: String",
        ):
            hit = [
                f"{number}:{line}"
                for number, line in enumerate(source.split("\n"), 1)
                if "length(" in line
            ]
            self.assertEqual(forbidden_lines(source, bases=bases), hit, source)

    def test_a_member_of_a_class_not_extended_stays_allowed(self) -> None:
        bases = {"Base": {"tile"}}
        for source in (
            "class A:\n\tvar tile: Vector2i\n\n\nclass B extends RefCounted:\n\tvar tile: String"
            "\n\tvar a := tile.length()",
            "extends Other\n\n\nfunc f() -> void:\n\tvar a := tile.length()",
            'extends "res://base.gd"\n\n\nfunc f() -> void:\n\tvar a := tile.length()',
            "extends Base\n\n\nclass B:\n\tvar tile: String\n\tvar a := tile.length()",
            # Classes extending each other in a circle never compile, but mustn't hang the check.
            "class A extends B:\n\tpass\n\n\nclass B extends A:\n\tvar a := tile.length()",
        ):
            self.assertEqual(forbidden_lines(source, bases=bases), [], source)

    def test_inherited_members_follow_the_rules_classes_extends(self) -> None:
        sources = [
            "class_name Base\nextends RefCounted\n\nvar tile: Vector2i\n\n\nclass Inner:"
            "\n\tvar inner: Vector2i",
            "class_name Mid\nextends Base\n\nconst SPOT: Vector2i = Vector2i.ONE",
            "class_name Leaf extends Mid",
            "extends Base\n\nvar nameless: Vector2i",
        ]
        self.assertEqual(
            inherited_members(sources),
            {"Base": {"tile"}, "Mid": {"tile", "SPOT"}, "Leaf": {"tile", "SPOT"}},
        )

    def test_an_element_of_an_integer_vector_array_is_refused(self) -> None:
        # A subscript, and a loop variable, over an Array[Vector2i] (#2261).
        for source in (
            "var tiles: Array[Vector2i] = []\nvar a := tiles[0].length()",
            "var tiles: Array[Vector3i]\nvar a := tiles[i + 1].distance_to(b)",
            "var tiles: Array[Vector4i]\nvar a := tiles[ids[0]].abs().length()",
            "var tiles: Array[Vector2i]\nvar a := self.tiles[0].length()",
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles:"
            "\n\t\tprint(tile.length())",
        ):
            hit = [
                f"{number}:{line}"
                for number, line in enumerate(source.split("\n"), 1)
                if "length(" in line or "distance_to(" in line
            ]
            self.assertEqual(forbidden_lines(source), hit, source)

    def test_an_element_of_any_other_array_is_allowed(self) -> None:
        for source in (
            "var names: Array[String]\nvar a := names[0].length()",
            "var tiles: Array[Vector2i]\nvar a := tiles.size()",
            "func f(names: Array[String]) -> void:\n\tfor name in names:\n\t\tprint(name.length())",
            "func f(tiles: Array[Vector2i]) -> void:\n\tpass\n\n\nfunc g(tiles: Array[String])"
            " -> int:\n\treturn tiles[0].length()",
            "func f(tiles: Array[Vector2i]) -> void:\n\tpass\n\n\nfunc g(tiles: Array[String])"
            " -> void:\n\tfor tile in tiles:\n\t\tprint(tile.length())",
        ):
            self.assertEqual(forbidden_lines(source), [], source)

    def test_an_element_read_otherwise_is_refused(self) -> None:
        # Through an array's methods, a deeper subscript, an array-returning call as a loop's
        # source, and a typed dictionary's values (#2287).
        for source in (
            "var tiles: Array[Vector2i]\nvar a := tiles.front().length()",
            "var tiles: Array[Vector3i]\nvar a := tiles.back().distance_to(b)",
            "var tiles: Array[Vector2i]\nvar a := tiles.pop_back().abs().length()",
            "var tiles: Array[Vector2i]\nvar a := self.tiles.pop_front( ).length()",
            "var tiles: Array[Vector2i]\nvar a := tiles.pop_at(0).length()",
            "var tiles: Array[Vector2i]\nvar a := tiles.front ().length()",
            "var spots: Dictionary[String, Vector2i]\nvar a := spots.get (key).length()",
            "var spots: Dictionary[Rules.Kind, Vector2i]\nvar a := spots[kind].length()",
            "var tiles: Array[Vector4i]\nvar a := tiles.get(ids[i + 1]).length()",
            "var tiles: Array[Vector2i]\nvar a := tiles[ids[keys[0]]].length()",
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles.slice(1, size(2)):"
            "\n\t\tprint(tile.length())",
            "var tiles: Array[Vector2i]\nfunc f() -> void:\n\tfor tile in self.tiles.duplicate():"
            "\n\t\tprint(tile.length())",
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles.filter(func(t: Vector2i)"
            " -> bool: return t.x > 0).slice(1):\n\t\tprint(tile.length())",
            'var spots: Dictionary[String, Vector2i]\nvar a := spots["home"].length()',
            "var spots: Dictionary[StringName, Vector3i]\nvar a := spots[&\"a\"].distance_to(b)",
            "var spots: Dictionary[String, Vector2i]"
            "\nvar a := spots.get(key, Vector2i.ZERO).length()",
        ):
            hit = [
                f"{number}:{line}"
                for number, line in enumerate(source.split("\n"), 1)
                if "length(" in line or "distance_to(" in line
            ]
            self.assertEqual(forbidden_lines(source), hit, source)

    def test_an_element_read_otherwise_of_anything_else_is_allowed(self) -> None:
        for source in (
            "var names: Array[String]\nvar a := names.front().length()",
            "var names: Array[String]\nvar a := names.get(0).length()",
            "var tiles: Array[Vector2i]\nvar a := tiles.front_name().length()",
            "func f(names: Array[String]) -> void:\n\tfor name in names.slice(1):"
            "\n\t\tprint(name.length())",
            "var names: Dictionary[Vector2i, String]\nvar a := names[tile].length()",
            "var names: Dictionary[Vector2i, String]\nvar a := names.get(tile).length()",
            "var spots: Dictionary[String, Vector2i]\nfunc f() -> void:\n\tfor key in spots:"
            "\n\t\tprint(key.length())",
        ):
            self.assertEqual(forbidden_lines(source), [], source)

    def test_a_loop_variable_counts_only_inside_its_loop(self) -> None:
        # After its loop ends, the same name is another variable (#2300).
        for source in (
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles:\n\t\tpass"
            '\n\tvar tile: String = "x"\n\tprint(tile.length())',
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles: pass"
            '\n\tvar tile: String = "x"\n\tprint(tile.length())',
            "func f(tiles: Array[Vector2i]) -> void:\n\tif true:\n\t\tfor tile in tiles:"
            '\n\t\t\tpass\n\tvar tile: String = "x"\n\tprint(tile.length())',
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles:\n\t\tpass\n\n\n"
            'func g() -> int:\n\tvar tile: String = "x"\n\treturn tile.length()',
        ):
            self.assertEqual(forbidden_lines(source), [], source)

    def test_a_loop_variable_still_counts_in_its_loop(self) -> None:
        # What #2300's scoping must keep refusing: the line of each length().
        for source in (
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles: print(tile.length())",
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles:\n\t\tif true:"
            "\n\t\t\tprint(tile.length())",
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles:\n\t\tpass\n"
            "\n\t\tprint(tile.length())",
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles:\n\t\tvar n := 1 + \\"
            "\n2\n\t\tprint(tile.length())",
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles:\n\t\tvar n := ["
            "\n\t1,\n\t]\n\t\tprint(tile.length())",
            "func f(tiles: Array[Vector2i]) -> void:\n\tfor tile in tiles:\n\t\tpass"
            "\n\tfor tile in tiles:\n\t\tprint(tile.length())",
        ):
            hit = [
                f"{number}:{line}"
                for number, line in enumerate(source.split("\n"), 1)
                if "length(" in line
            ]
            self.assertEqual(forbidden_lines(source), hit, source)

    def test_an_integer_vector_declared_with_an_inferred_type_is_refused(self) -> None:
        # `:=` from a constructor or a constant, for locals and members (#2292).
        for source in (
            "var tile := Vector2i.ZERO\nvar a := tile.length()",
            "var step := Vector2i(1, 0)\nvar a := step.length()",
            "const ORIGIN := Vector3i.ONE\nvar a := ORIGIN.distance_to(b)",
            "@export var home := Vector2i(abs(x), (y))\nvar a := self.home.length()",
            "static var spot := Vector2i.ONE * 2\nvar a := spot.abs().length()",
            "var tile := Vector2i(\n\t1, 0)\nvar a := tile.length()",
            "var tile := Vector2i.ONE * \\\n\t2\nvar a := tile.length()",
            "var tile := Vector2i(1, 2) * (\n\t2)\nvar a := tile.length()",
            "func f() -> void:\n\tvar tile := Vector4i(1, 2, 3, 4)\n\tprint(tile.length())",
            "func f() -> void:\n\tconst STEP := Vector2i.RIGHT\n\tprint(STEP.length())",
            # In its own class, and an outer class's constant, which an inner class reaches (#2288).
            "class Inner:\n\tvar tile := Vector2i.ONE\n\n\tfunc f() -> void:"
            "\n\t\tprint(tile.length())",
            "const TILE := Vector2i(1, 2)\n\n\nclass Inner:\n\tfunc f() -> void:"
            "\n\t\tprint(TILE.length())",
        ):
            hit = [
                f"{number}:{line}"
                for number, line in enumerate(source.split("\n"), 1)
                if "length(" in line or "distance_to(" in line
            ]
            self.assertEqual(forbidden_lines(source), hit, source)

    def test_a_name_inferred_from_anything_else_is_allowed(self) -> None:
        for source in (
            'var tile := "x"\nvar a := tile.length()',
            "var tile := str(Vector2i.ONE)\nvar a := tile.length()",
            "var tile := Vector2i(1, 2).x\nvar a := tile.length()",
            "var tile := Vector2i.ONE.x\nvar a := tile.length()",
            'var tile := Vector2i.ONE if c else "x"\nvar a := tile.length()',
            "var tile := Vector2i(1, 2) == other\nvar a := tile.length()",
            "var tile := Vector2i.ONE in tiles\nvar a := tile.length()",
            'var tile := Vector2i.ONE \\\n\tif c else "x"\nvar a := tile.length()',
            "var tile := Vector2i.ONE * (\n\t2) == other\nvar a := tile.length()",
            'var tile := (Vector2i.ONE\n\tif c else "x")\nvar a := tile.length()',
            "var tile := Vector2i.ONE\nvar a := obj.tile.length()",
            "func f() -> void:\n\tvar tile := Vector2i.ONE\n\n\nfunc g(tile: String) -> int:"
            "\n\treturn tile.length()",
            # A member of one class doesn't count in another (#2288).
            "class Inner:\n\tvar tile := Vector2i.ONE\n\n\nvar a := tile.length()",
            "var tile := Vector2i(1, 2)\n\n\nclass Inner:\n\tvar a := tile.length()",
        ):
            self.assertEqual(forbidden_lines(source), [], source)

    def test_members_declared_with_an_inferred_type_count_too(self) -> None:
        source = "\n".join(
            (
                "var tile := Vector2i.ZERO",
                "@export var home := Vector3i(1, 2, 3)",
                "static var spot := Vector4i(",
                "\t1, 2, 3, 4)",
                "const ORIGIN := Vector2i.ONE",
                "var x := Vector2i(1, 2).x",
                "var y := Vector2i.ONE.y",
                'var z := Vector2i(1, 2) if c else "x"',
                'var text := "x"',
                "func f() -> void:",
                "\tvar local := Vector2i.ONE",
            )
        )
        self.assertEqual(int_vector_members(source), {"tile", "home", "spot", "ORIGIN"})


    def test_a_call_to_a_function_returning_an_integer_vector_is_refused(self) -> None:
        # The script's own function, called on its own or on self (#2263).
        source = "func tile() -> Vector2i:\n\treturn Vector2i.ONE\n"
        for line in (
            "var a := tile().length()",
            "var a := self.tile().distance_to(b)",
            "var a := tile().abs().length()",
            "var a := tile ().length()",
        ):
            self.assertEqual(forbidden_lines(source + line), [f"3:{line}"], line)

    def test_a_call_to_another_scripts_integer_vector_function_is_refused(self) -> None:
        # One some rules script declares, called on any object, its arguments balanced (#2263).
        for line in (
            "var a := entity.tile_at(1, f(2)).length()",
            "var a := get_world().grid.tile_at(x).distance_to(b)",
            "var a := entities[0].tile_at((1 + 2) * 3).mini(4).length()",
            "var a := tile_at(x).length()",
            "var a := obj.tile_at (x).length()",
        ):
            self.assertEqual(forbidden_lines(line, functions={"tile_at"}), [f"1:{line}"], line)

    def test_a_call_to_any_other_function_stays_allowed(self) -> None:
        source = "func count() -> int:\n\treturn 1\nfunc name() -> String:\n\treturn \"\"\n"
        for line in (
            "var a := count().length()",
            "var a := name().length()",
            "var a := entity.name().length()",
        ):
            self.assertEqual(forbidden_lines(source + line), [], line)
        for line in (
            "var a := entity.tile_at_name(x).length()",
            "var a := entity.tile_at.length()",
            "var a := tile_at.length()",
            "var a := entity.tile_at(x).y.length()",
        ):
            self.assertEqual(forbidden_lines(line, functions={"tile_at"}), [], line)

    def test_the_scripts_own_function_of_another_type_wins_on_its_own_or_on_self(self) -> None:
        # Another script's tile() returns a Vector2i, this one's a String.
        source = "func tile() -> String:\n\treturn \"\"\n"
        for line, hit in (
            ("var a := tile().length()", []),
            ("var a := self.tile().length()", []),
            ("var a := entity.tile().length()", ["3:var a := entity.tile().length()"]),
        ):
            self.assertEqual(forbidden_lines(source + line, functions={"tile"}), hit, line)

    def test_a_bare_or_self_call_reaches_its_own_classs_functions_only(self) -> None:
        # An inner class reaches an outer class's static func only through its name (#2263).
        for source, hit in (
            ("func tile() -> Vector2i:\n\treturn Vector2i.ONE\n\n\nclass Inner:"
             "\n\tfunc f() -> int:\n\t\treturn tile().length()", []),
            ("class Inner:\n\tfunc tile() -> Vector2i:\n\t\treturn Vector2i.ONE"
             "\n\n\nvar a := tile().length()", []),
            ("class A:\n\tfunc tile() -> Vector2i:\n\t\treturn Vector2i.ONE\n\n\nclass B:"
             "\n\tfunc tile() -> String:\n\t\treturn \"\"\n\n\tfunc f() -> int:"
             "\n\t\treturn self.tile().length()", []),
            ("class Inner:\n\tfunc tile() -> Vector2i:\n\t\treturn Vector2i.ONE"
             "\n\n\tfunc f() -> int:\n\t\treturn self.tile().length()",
             ["6:\t\treturn self.tile().length()"]),
            ("class Inner:\n\tfunc tile() -> Vector2i:\n\t\treturn Vector2i.ONE"
             "\n\tvar a := tile().length()", ["4:\tvar a := tile().length()"]),
            ("static func tile() -> Vector2i:\n\treturn Vector2i.ONE\n\n\nclass Inner:"
             "\n\tfunc f() -> int:\n\t\treturn Outer.tile().length()",
             ["7:\t\treturn Outer.tile().length()"]),
            ("class A:\n\tfunc tile() -> Vector2i:\n\t\treturn Vector2i.ONE\n\n\nclass B:"
             "\n\tfunc tile() -> String:\n\t\treturn \"\"\n\n\tfunc f(a: A) -> int:"
             "\n\t\treturn a.tile().length()", ["11:\t\treturn a.tile().length()"]),
        ):
            self.assertEqual(forbidden_lines(source), hit, source)

    def test_functions_are_those_declared_to_return_an_integer_vector(self) -> None:
        source = "\n".join(
            (
                "func tile() -> Vector2i:",
                "\treturn Vector2i.ONE",
                "static func home(a: int, b: String = \"(\") -> Vector3i:",
                "\treturn Vector3i.ONE",
                "func spot(",
                "\ta: Vector2i,",
                "\tb: int,",
                ")  ->  Vector4i:",
                "\treturn Vector4i.ONE",
                "func count() -> int:",
                "\treturn 1",
                "func tiles() -> Array[Vector2i]:",
                "\treturn []",
                "func of(at: Vector2i) -> void:",
                "\tvar f: Callable = func(x: int) -> Vector2i: return Vector2i(x, x)",
                "class A:",
                "\tfunc inner() -> Vector2i:",
                "\t\treturn Vector2i.ZERO",
            )
        )
        self.assertEqual(int_vector_functions(source), {"tile", "home", "spot", "inner"})


class OwnTestTest(unittest.TestCase):
    def test_a_test_module_without_tests_does_not_pass(self) -> None:
        with mock.patch(
            "determinism_check.unittest.defaultTestLoader.loadTestsFromName",
            return_value=unittest.TestSuite(),
        ):
            self.assertFalse(own_test_passes())


if __name__ == "__main__":
    unittest.main()
