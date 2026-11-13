"""Fails when the simulation could stop being deterministic (AGENTS.md, "Architecture"). core/ and
every slice's rules/ hold the rules: plain RefCounted classes (or classes of the rules, e.g.
Feature) without nodes, input, time, engine or OS state, global randomness, frame delta, floats
(float-backed engine types such as Vector2 or Color too; Vector2i and Rect2i stay allowed), or file
and JSON access (#572: reading happens before a tick, never inside one).
Comments are stripped first (gdscript_code.py), so the rules can be explained in them; floats, float
maths and randomness methods are looked for with strings stripped too (#2210).
A whole file is exempt while its top comment lines carry the marker below with a reason in
parentheses (owner, #515). It marks a workaround to fix later; a marker without a reason fails:
  # TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (why this file can't pass yet)

    uv run --locked --package khovax-game-checks src/game-checks/determinism_check.py
"""

import os
import re
import sys
import unittest
from pathlib import Path

from game_shared import log
from game_shared.gdscript_code import Kind, code_only, tokens, without_comments

# What the rules never use, one alternation per kind; add a kind as its own line.
FORBIDDEN = re.compile(
    "|".join(
        (
            r"\b(Node|Node2D|Node3D|CanvasItem|Control|Window|Viewport|Resource)\b",
            r"\b(Input|InputMap|Time|Engine|OS|DisplayServer|RenderingServer|ProjectSettings)\.",
            r"\bdelta\b",
            r"\b(FileAccess|DirAccess|JSON)\b",
            r"\b(Vector2|Vector3|Vector4|Color|Rect2|AABB|Plane|Basis|Quaternion|Transform2D"
            r"|Transform3D|Projection)\b",
            # Runs code from a string, where the patterns read with strings removed can't see it.
            r"\bExpression\b",
        )
    )
)
# The same, read with strings removed too, for what a string may legitimately spell out. The bare
# float forms need a number on their own: `v2.x`, `items[1].y` and `2.foo()` are member accesses.
FORBIDDEN_IN_CODE = re.compile(
    "|".join(
        (
            r"\b(randf|randi|randf_range|randi_range|randfn|randomize|seed|rand_from_seed)"
            r"\s*\(",
            r"\b(shuffle|pick_random)\s*\(|\.(shuffle|pick_random)\b",
            r"\bRandomNumberGenerator\b",
            r"\bfloat\b|[0-9]\.[0-9]|(?<![\w.])[0-9][0-9_]*[eE][-+]?[0-9]",
            r"(?<![\w)\]])\.[0-9]",
            r"(?<![\w.])[0-9][0-9_]*\.(?:[eE][-+]?[0-9]|(?!\w))",
            # Global functions only: `vi.snapped(x)` is an integer method of Vector2i (#2216).
            r"(?<!\.)\b(sqrt|sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh|exp|log|pow|fmod"
            r"|fposmod"
            r"|lerp|lerpf|lerp_angle|inverse_lerp|remap|smoothstep|move_toward|deg_to_rad"
            r"|rad_to_deg|floor|ceil|round|floorf|ceilf|roundf|absf|signf|maxf|minf"
            r"|clampf|snapped|snappedf|wrapf|is_nan|is_inf|is_finite|is_equal_approx"
            r"|is_zero_approx|ease|pingpong|asinh|acosh|atanh|angle_difference|rotate_toward"
            r"|bezier_interpolate|bezier_derivative|cubic_interpolate|cubic_interpolate_angle"
            r"|cubic_interpolate_in_time|cubic_interpolate_angle_in_time|db_to_linear"
            r"|linear_to_db)\s*\(",
            r"\bto_float\s*\(",
            r"\b(PI|TAU|INF|NAN)\b",
            r"\.aspect\s*\(|\bPackedFloat(32|64)Array\b|\b(str_to_var|bytes_to_var"
            r"|bytes_to_var_with_objects)\s*\(",
            r"\bPacked(Vector2|Vector3|Vector4|Color)Array\b",
            # Float members of PackedByteArray and String (#2223).
            r"\.(decode_half|decode_float|decode_double|decode_var|to_float32_array"
            r"|to_float64_array|similarity)\s*\(",
            r"\bTYPE_FLOAT\b",
            # The float-backed types' own constants, which type_convert() builds them from (#2247):
            # `\b` keeps their integer twins (TYPE_VECTOR2I, TYPE_RECT2I) allowed.
            r"\bTYPE_(VECTOR[234]|RECT2|TRANSFORM[23]D|PLANE|QUATERNION|AABB|BASIS|PROJECTION"
            r"|COLOR|PACKED_(FLOAT32|FLOAT64|VECTOR[234]|COLOR)_ARRAY)\b",
        )
    )
)
# An integer vector's length() and distance_to() are floats, a String's length() a whole number,
# and a pattern can't see types: so they count on a Vector2i, Vector3i or Vector4i written out or on
# a name declared as one. Scripts type every declaration (AGENTS.md); a dictionary entry's value
# (`a: Vector2i(1, 2)`, `a: Vector2i.ONE`, `a: Vector2i`) declares nothing (#2264).
INT_VECTOR_ARGUMENTS = r"\((?:[^()]|\([^()]*\))*\)"  # A call inside them, one level deep.
INT_VECTOR_RECEIVER = rf"\bVector[234]i(?:{INT_VECTOR_ARGUMENTS}|\.[A-Z_]+)"
# What an integer vector's own methods return is an integer vector again.
INT_VECTOR_CHAIN = (
    rf"(?:\.(?:abs|clamp|clampi|max|maxi|min|mini|sign|snapped|snappedi){INT_VECTOR_ARGUMENTS})*"
)
INT_VECTOR_DECLARED = re.compile(r"\b(\w+)\s*:\s*Vector[234]i\b(?!\s*[.(])")
# An Array[Vector2i]'s elements are integer vectors too: a subscript of it (brackets inside, one
# level deep) and a loop variable over it (#2261).
INT_VECTOR_ARRAY_DECLARED = re.compile(r"\b(\w+)\s*:\s*Array\[\s*Vector[234]i\s*\]")
SUBSCRIPT = r"\[(?:[^\[\]]|\[[^\[\]]*\])*\]"
FOR_LOOP = re.compile(r"\bfor\s+(\w+)\s+in\s+(?:self\.)?(\w+)\s*:")
# A function's parameters and locals count in its body only, any other declaration in the whole
# file (#2264); a function ends at the next line indented no deeper than its func.
FUNCTION = re.compile(r"\s*(static\s+)?func\b")
# Reaching a randomness method by name, with call() or a Callable: read on the whole of
# code_with_random_names, which keeps that string, so a call split over lines is seen too (#2223).
RANDOM_NAMES = ("shuffle", "pick_random")
# A raw string's r stays code like a StringName's &, so it is part of the name (#2254).
RANDOM_NAME = re.compile(rf"""(?:&|\br)?["']({"|".join(RANDOM_NAMES)})["']""")
# What opens the call the name is an argument of: call()'s first, or any of a Callable's.
CALL_BY_NAME = re.compile(r"\.(call|callv|call_deferred)\s*\(\s*$")
CALLABLE = re.compile(r"\bCallable(\.create)?\s*\($")
# A conversion the name may be wrapped in: the call around it counts then.
CONVERSION = re.compile(r"\b(StringName|String)\s*\($")
# Grouping parentheses the name may sit in, which no name or closing bracket opens (#2254).
GROUPING = re.compile(r"(?<![\w)\]\s])\s*\($")
# What ends a wrapper around the name, and what ends the whole argument (#2254).
WRAPPER_END = re.compile(r"\s*\)")
ARGUMENT_END = re.compile(r"\s*[,)]")
MARKER = "# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK"
MARKER_WITH_REASON = re.compile(re.escape(MARKER) + r" \(.*[^ )].*\)")
HEADER_LINE = re.compile(r"\s*(#|$)")


def header_of(lines: list[str]) -> list[str]:
    """The comment lines at the top of a file, before its first line of code."""
    header = []
    for line in lines:
        if not HEADER_LINE.match(line):
            break
        header.append(line)
    return header


def numbered(lines: list[str], hit: list[bool]) -> list[str]:
    return [f"{number}:{line}" for number, (line, h) in enumerate(zip(lines, hit), 1) if h]


def code_with_random_names(source: str) -> str:
    """The script's code and the strings that are only a randomness method's name."""
    return "".join(
        token.text
        if token.kind == Kind.CODE
        or (token.kind == Kind.STRING and token.text.strip("\"'") in RANDOM_NAMES)
        else "\n" * token.text.count("\n")
        for token in tokens(source)
    )


def called_by_name(before: str, after: str) -> bool:
    """Whether a name, between the code `before` and `after` it, is the method a call() or a
    Callable reaches: a whole argument, alone in any conversion or grouping parentheses."""
    depth = 0
    for at in range(len(before) - 1, -1, -1):
        if before[at] in ")]}":
            depth += 1
        elif before[at] in "([{":
            if depth == 0:
                opener = before[: at + 1]
                wrapper = CONVERSION.search(opener) or GROUPING.search(opener)
                if wrapper:
                    # Nothing but the name inside the wrapper, e.g. not ("shuffle" + "d").
                    end = WRAPPER_END.match(after)
                    return (
                        not before[at + 1 :].strip()
                        and end is not None
                        and called_by_name(opener[: wrapper.start()], after[end.end() :])
                    )
                return (
                    before[at] == "("
                    and ARGUMENT_END.match(after) is not None
                    and (
                        CALL_BY_NAME.search(before) is not None
                        or CALLABLE.search(opener) is not None
                    )
                )
            depth -= 1
    return False


def innermost_opener(before: str) -> str:
    """The bracket still open at the end of the code `before`, or "" if none is."""
    depth = 0
    for char in reversed(before):
        if char in ")]}":
            depth += 1
        elif char in "([{":
            if depth == 0:
                return char
            depth -= 1
    return ""


def functions_of(lines: list[str]) -> list[int | None]:
    """The function each code line is in, as the index of its func line, or None outside one. A
    line inside brackets left open continues the line before it, e.g. a func's parameters."""
    owners: list[int | None] = []
    function: tuple[int, int] | None = None  # Its func line and that line's indentation.
    depth = 0
    for index, line in enumerate(lines):
        if depth == 0 and line.strip():
            indent = len(line) - len(line.lstrip())
            if function is not None and indent <= function[1]:
                function = None
            if function is None and FUNCTION.match(line):
                function = (index, indent)
        owners.append(None if function is None else function[0])
        opened = sum(line.count(char) for char in "([{")
        depth = max(0, depth + opened - sum(line.count(char) for char in ")]}"))
    return owners


def declared_int_vectors(
    bare: list[str], owners: list[int | None], declaration: re.Pattern[str] = INT_VECTOR_DECLARED
) -> dict[int | None, set[str]]:
    """The names declared as an integer vector (or what `declaration` declares), by the function
    they count in (None: the file)."""
    joined = "\n".join(bare)
    declared: dict[int | None, set[str]] = {}
    for hit in declaration.finditer(joined):
        before = joined[: hit.start()]
        # A dictionary entry, not a declaration: a key in braces, not a lambda's local in them.
        if innermost_opener(before) == "{" and before.rstrip().endswith(("{", ",")):
            continue
        owner = owners[joined.count("\n", 0, hit.start())]
        declared.setdefault(owner, set()).add(hit.group(1))
    return declared


def float_length_in(names: set[str]) -> re.Pattern[str]:
    """An integer vector's length() or distance_to(), on a vector written out or on one of `names`:
    the name itself or the script's own member, not another object's (`obj.tile`, #2264). A name
    may end in a subscript, which `\b` can't follow."""
    own = (rf"(?<![\w.])(?:self\.)?{name}(?!\w)" for name in sorted(names))
    receivers = [INT_VECTOR_RECEIVER, *own]
    return re.compile(
        rf"(?:{'|'.join(receivers)}){INT_VECTOR_CHAIN}\.(?:length|distance_to)\s*\("
    )


def forbidden_lines(source: str) -> list[str]:
    """The numbered lines of a script that use something the rules never use."""
    code = without_comments(source).rstrip("\n").split("\n")
    bare = code_only(source).split("\n")
    owners = functions_of(bare)
    declared = declared_int_vectors(bare, owners)
    arrays = declared_int_vectors(bare, owners, INT_VECTOR_ARRAY_DECLARED)
    for index, line in enumerate(bare):
        for loop in FOR_LOOP.finditer(line):
            if loop.group(2) in arrays.get(None, set()) | arrays.get(owners[index], set()):
                declared.setdefault(owners[index], set()).add(loop.group(1))
    for owner, names in arrays.items():
        declared.setdefault(owner, set()).update(rf"{name}{SUBSCRIPT}" for name in names)
    in_file = declared.get(None, set())
    float_length = {
        owner: float_length_in(in_file | declared.get(owner, set())) for owner in set(owners)
    }
    named = code_with_random_names(source)
    # The line of each randomness method's name.
    by_name = {
        named.count("\n", 0, hit.start(1))
        for hit in RANDOM_NAME.finditer(named)
        if called_by_name(named[: hit.start()], named[hit.end() :])
    }
    return numbered(
        code,
        [
            FORBIDDEN.search(line) is not None
            or FORBIDDEN_IN_CODE.search(bare_line) is not None
            or float_length[owners[index]].search(bare_line) is not None
            or index in by_name
            for index, (line, bare_line) in enumerate(zip(code, bare))
        ],
    )


def own_test_passes() -> bool:
    """Runs test_determinism_check.py, so CI's step for this check covers its patterns too (#2210)."""
    suite = unittest.defaultTestLoader.loadTestsFromName("test_determinism_check")
    result = unittest.TextTestRunner().run(suite)
    # A module without tests is successful too, and would prove nothing (#2216).
    return result.wasSuccessful() and result.testsRun > 0


def main() -> int:
    if not own_test_passes():
        log.error("the check's own test fails: see above", __file__)
        return 1

    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    rules = [Path("core"), *sorted(path for path in Path("slices").rglob("rules") if path.is_dir())]
    scripts = sorted({str(file) for folder in rules for file in folder.rglob("*.gd")})
    rule_classes = {
        line.split()[1]
        for file in scripts
        for line in Path(file).read_text(encoding="utf-8").split("\n")
        if line.startswith("class_name ") and len(line.split()) > 1
    }
    extends = {f"extends {name}" for name in rule_classes | {"RefCounted"}}
    failed = False

    for file in scripts:
        source = Path(file).read_text(encoding="utf-8")
        lines = source.rstrip("\n").split("\n")
        # Exempt while its header carries the marker with a reason, and no other marker sits
        # anywhere in it. A marker without a reason, or one below the header, fails the file.
        with_marker = ["IGNORE_DETERMINISM_CHECK" in line for line in lines]
        if sum(with_marker) == 1 and any(
            MARKER_WITH_REASON.fullmatch(line) for line in header_of(lines)
        ):
            continue
        if any(with_marker):
            print("\n".join(numbered(lines, with_marker)))
            log.error(
                "the exemption marker sits in the top comment lines, with a reason:"
                f" {MARKER} (reason)",
                file,
            )
            failed = True

        code = without_comments(source).rstrip("\n").split("\n")
        if not extends.intersection(code):
            log.error("rules scripts extend RefCounted or a class of the rules", file)
            failed = True
        hits = forbidden_lines(source)
        if hits:
            print("\n".join(hits))
            log.error("the rules must stay deterministic: see the lines above", file)
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
