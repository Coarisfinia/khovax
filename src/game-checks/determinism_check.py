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
# A receiver written out, and the integer vector methods a chain may call on it: their arguments
# are matched as balanced parentheses, at any depth (#2223).
INT_VECTOR_RECEIVER = r"\bVector[234]i(?:(?=\()|\.[A-Z_]+)"
# What an integer vector's own methods return is an integer vector again.
INT_VECTOR_METHOD = re.compile(
    r"\.(?:abs|clamp|clampi|max|maxi|min|mini|sign|snapped|snappedi)(?=\()"
)
FLOAT_METHOD = re.compile(r"\.(?:length|distance_to)\s*\(")
INT_VECTOR_DECLARED = re.compile(r"\b(\w+)\s*:\s*Vector[234]i\b(?!\s*[.(])")
# An Array[Vector2i]'s elements are integer vectors too: a subscript of it (brackets inside, two
# levels deep), what its element methods return, and a loop variable over it or over the arrays its
# own methods return (#2261, #2287). So are a typed dictionary's values, read by subscript or get().
INT_VECTOR_ARRAY_DECLARED = re.compile(r"\b(\w+)\s*:\s*Array\[\s*Vector[234]i\s*\]")
INT_VECTOR_DICTIONARY_DECLARED = re.compile(
    r"\b(\w+)\s*:\s*Dictionary\[\s*[\w.]+(?:\[[^\[\]]*\])?\s*,\s*Vector[234]i\s*\]"
)
SUBSCRIPT = r"\[(?:[^\[\]]|\[(?:[^\[\]]|\[[^\[\]]*\])*\])*\]"
# An element method's arguments are matched as balanced parentheses by calls_float_method.
ARRAY_ELEMENT = (
    rf"(?:{SUBSCRIPT}|\.(?:front|back|pop_back|pop_front)\s*\(\s*\)|\.(?:get|pop_at)\s*(?=\())"
)
DICTIONARY_VALUE = rf"(?:{SUBSCRIPT}|\.get\s*(?=\())"
FOR_LOOP = re.compile(r"\bfor\s+(\w+)\s+in\s+(?:self\.)?(\w+)")
ARRAY_METHOD = re.compile(r"\.(?:slice|duplicate|filter)\s*(?=\()")
LOOP_END = re.compile(r"\s*:")
# A member a script declares as one, outside any function: another script reaches it as `obj.tile`,
# so the check gathers them from every rules script first (#2262). So are its Array[Vector2i] and
# typed dictionary members, with how another script reads their elements (#2299).
MEMBER = r"\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(?:var|const)\s+(\w+)\s*:\s*"
INT_VECTOR_MEMBER = re.compile(rf"{MEMBER}Vector[234]i\b(?!\s*[.(])")
INT_VECTOR_COLLECTION_MEMBERS = (
    (re.compile(rf"{MEMBER}Array\[\s*Vector[234]i\s*\]"), ARRAY_ELEMENT),
    (
        re.compile(rf"{MEMBER}Dictionary\[\s*[\w.]+(?:\[[^\[\]]*\])?\s*,\s*Vector[234]i\s*\]"),
        DICTIONARY_VALUE,
    ),
)
# A function's parameters and locals count in its body only (#2264), any other declaration in the
# class it is in: the file's own or an inner class, which don't reach each other's members. An inner
# class reaches the constants of the classes around it, though (Godot 4.7, #2288). A function or
# class ends at the next statement indented no deeper than its line. A line that starts inside a
# multi-line string or after a backslash continues its statement (#2271).
FUNCTION = re.compile(r"\s*(static\s+)?func\b")
CLASS = re.compile(r"\s*class\s")
# Annotations may come first, as in INT_VECTOR_MEMBER.
CONSTANT = re.compile(r"\s*(?:@\w+(?:\([^)]*\))?\s+)*const\s+(\w+)")
# A class has the members of the class it extends by bare name: an inner class of the same file or
# another rules class (#2306). A path in quotes is stripped with the strings, so it names none.
CLASS_NAMED = re.compile(r"\s*class\s+(\w+)")
CLASS_NAME = re.compile(r"class_name\s+(\w+)")
EXTENDS = re.compile(r"\s*(?:class(?:_name)?\s+\w+\s+)?extends\s+(\w+)\s*(?::|$)")
# Reaching a randomness method by name, with call() or a Callable: read on the whole of
# code_with_random_names, which keeps that string, so a call split over lines is seen too (#2223).
RANDOM_NAMES = ("shuffle", "pick_random")
# A raw string's r stays code like a StringName's &, so it is part of the name (#2254); its quotes
# are one or three of a kind (#2266).
RANDOM_NAME = re.compile(rf"""(?:&|\br)?("(?:"")?|'(?:'')?)({"|".join(RANDOM_NAMES)})\1""")
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


def after_parentheses(line: str, at: int) -> int:
    """Where the balanced parentheses opening at `at` end in `line`, or -1 if they never close."""
    depth = 0
    for index in range(at, len(line)):
        if line[index] == "(":
            depth += 1
        elif line[index] == ")":
            depth -= 1
            if depth == 0:
                return index + 1
    return -1


def calls_float_method(line: str, receiver: re.Pattern[str]) -> bool:
    """Whether `line` calls length() or distance_to() on an integer vector `receiver` matches,
    directly or through a chain of the vector's own methods."""
    for hit in receiver.finditer(line):
        at = hit.end()
        if line.startswith("(", at):
            at = after_parentheses(line, at)
        while at >= 0 and (method := INT_VECTOR_METHOD.match(line, at)):
            at = after_parentheses(line, method.end())
        if at >= 0 and FLOAT_METHOD.match(line, at):
            return True
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


def continued_lines(source: str, bare: list[str]) -> set[int]:
    """The lines that continue the statement before them: those after a backslash, and those that
    start inside a string (code after a multi-line string's closing quotes)."""
    continued = {index + 1 for index, line in enumerate(bare) if line.rstrip().endswith("\\")}
    line = 0
    for token in tokens(source):
        breaks = token.text.count("\n")
        if token.kind == Kind.STRING:
            continued.update(range(line + 1, line + breaks + 1))
        line += breaks
    return continued


Scope = tuple[tuple[int, ...], int | None]


def scopes_of(lines: list[str], continued: set[int]) -> list[Scope]:
    """The inner classes and the function each code line is in: the index of each class's line,
    outermost first, and of its func line, or None outside one. A line inside brackets left open
    continues the line before it, e.g. a func's parameters, and so does each of `continued`."""
    scopes: list[Scope] = []
    blocks: list[tuple[int, int]] = []  # Each open class's or func's line and its indentation.
    function: int | None = None
    depth = 0
    for index, line in enumerate(lines):
        if depth == 0 and line.strip() and index not in continued:
            indent = len(line) - len(line.lstrip())
            while blocks and indent <= blocks[-1][1]:
                if blocks.pop()[0] == function:
                    function = None
            if function is None and (FUNCTION.match(line) or CLASS.match(line)):
                blocks.append((index, indent))
                if FUNCTION.match(line):
                    function = index
        scopes.append((tuple(at for at, _ in blocks if at != function), function))
        opened = sum(line.count(char) for char in "([{")
        depth = max(0, depth + opened - sum(line.count(char) for char in ")]}"))
    return scopes


def block_of(lines: list[str], start: int, continued: set[int]) -> range:
    """The lines of the statement at `start` and of the block it opens, e.g. a loop's body: up to
    the next statement indented no deeper than it. Lines inside brackets left open, and each of
    `continued`, continue the statement before them."""
    indent = len(lines[start]) - len(lines[start].lstrip())
    depth = 0
    for index in range(start, len(lines)):
        line = lines[index]
        if (
            index > start
            and depth == 0
            and line.strip()
            and index not in continued
            and len(line) - len(line.lstrip()) <= indent
        ):
            return range(start, index)
        opened = sum(line.count(char) for char in "([{")
        depth = max(0, depth + opened - sum(line.count(char) for char in ")]}"))
    return range(start, len(lines))


def declared_int_vectors(
    bare: list[str], owners: list[int | None], declaration: re.Pattern[str] = INT_VECTOR_DECLARED
) -> dict[int | None, set[str]]:
    """The names declared as an integer vector (or what `declaration` declares), by the function
    or class they count in (None: the file's own class)."""
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


def over_array(line: str, at: int) -> bool:
    """Whether a loop's source, from `at` in `line` after an array's name, is that array or what a
    chain of its own array-returning methods makes of it, up to the loop's colon."""
    while at >= 0 and (method := ARRAY_METHOD.match(line, at)):
        at = after_parentheses(line, method.end())
    return at >= 0 and LOOP_END.match(line, at) is not None


def int_vector_members(source: str, own_class_only: bool = False) -> set[str]:
    """The members a script declares as an integer vector, outside its functions, in any class (or
    its own class only): a vector's name, and an integer vector array's or typed dictionary's with
    how its element is read (#2299), as receivers on another object."""
    bare = code_only(source).split("\n")
    members: set[str] = set()
    for line, (classes, function) in zip(bare, scopes_of(bare, continued_lines(source, bare))):
        if function is not None or (own_class_only and classes):
            continue
        if hit := INT_VECTOR_MEMBER.match(line):
            members.add(hit.group(1))
        for declaration, element in INT_VECTOR_COLLECTION_MEMBERS:
            if hit := declaration.match(line):
                members.add(rf"{hit.group(1)}{element}")
    return members


def inherited_members(sources: list[str]) -> dict[str, set[str]]:
    """The integer vector members each rules class has by bare name, by its class_name: its own
    class's and those of the rules classes it extends (#2306)."""
    own: dict[str, set[str]] = {}
    parents: dict[str, str] = {}
    for source in sources:
        bare = code_only(source).split("\n")
        name = next((hit.group(1) for line in bare if (hit := CLASS_NAME.match(line))), None)
        if name is None:
            continue
        own[name] = int_vector_members(source, own_class_only=True)
        parent = next((hit.group(1) for line in bare if (hit := EXTENDS.match(line))), None)
        if parent is not None:
            parents[name] = parent

    def of(name: str | None, seen: set[str]) -> set[str]:
        if name is None or name not in own or name in seen:
            return set()
        return own[name] | of(parents.get(name), seen | {name})

    return {name: of(name, set()) for name in own}


def receiver_in(names: set[str], members: set[str]) -> re.Pattern[str]:
    """An integer vector written out or one of `names`, as length()'s receiver: the name itself or
    the script's own member, not another object's (`obj.tile`, #2264). A name may end in a
    subscript, which `\b` can't follow (#2261). On another object, one of `members` counts: the
    rules' integer vector members and their elements (#2262, #2299)."""
    own = (rf"(?<![\w.])(?:self\.)?{name}(?!\w)" for name in sorted(names))
    other = (rf"(?<=[\w)\]])\.{name}(?!\w)" for name in sorted(members))
    return re.compile("|".join([INT_VECTOR_RECEIVER, *own, *other]))


def forbidden_lines(
    source: str, members: set[str] | None = None, bases: dict[str, set[str]] | None = None
) -> list[str]:
    """The numbered lines of a script that use something the rules never use. `members` are the
    integer vector members the rules declare, in any script (int_vector_members), and `bases` those
    each rules class has by bare name (inherited_members)."""
    code = without_comments(source).rstrip("\n").split("\n")
    bare = code_only(source).split("\n")
    continued = continued_lines(source, bare)
    scopes = scopes_of(bare, continued)
    # The function or class each line's declarations count in.
    owners = [
        function if function is not None else (classes or (None,))[-1]
        for classes, function in scopes
    ]
    declared = declared_int_vectors(bare, owners)
    arrays = declared_int_vectors(bare, owners, INT_VECTOR_ARRAY_DECLARED)
    dictionaries = declared_int_vectors(bare, owners, INT_VECTOR_DICTIONARY_DECLARED)
    # Each class's constants, which its inner classes reach: integer vectors, arrays and
    # dictionaries of them.
    constants: dict[int | None, set[str]] = {}
    array_constants: dict[int | None, set[str]] = {}
    for line, (_, function), owner in zip(bare, scopes, owners):
        constant = CONSTANT.match(line)
        if function is None and constant:
            name = constant.group(1)
            if name in declared.get(owner, ()):
                constants.setdefault(owner, set()).add(name)
            if name in arrays.get(owner, ()):
                array_constants.setdefault(owner, set()).add(name)
            if name in dictionaries.get(owner, ()):
                constants.setdefault(owner, set()).add(rf"{name}{DICTIONARY_VALUE}")
    # A loop variable counts on its loop's lines only: after the loop, the name is another (#2300).
    loops: dict[int, set[str]] = {}
    for index, (line, (classes, _), owner) in enumerate(zip(bare, scopes, owners)):
        *outers, own = None, *classes
        visible = arrays.get(own, set()) | arrays.get(owner, set())
        visible = visible.union(*(array_constants.get(outer, set()) for outer in outers))
        for loop in FOR_LOOP.finditer(line):
            if loop.group(2) in visible and over_array(line, loop.end()):
                for at in block_of(bare, index, continued):
                    loops.setdefault(at, set()).add(loop.group(1))
    for owner, names in array_constants.items():
        constants.setdefault(owner, set()).update(rf"{name}{ARRAY_ELEMENT}" for name in names)
    for owner, names in arrays.items():
        declared.setdefault(owner, set()).update(rf"{name}{ARRAY_ELEMENT}" for name in names)
    for owner, names in dictionaries.items():
        declared.setdefault(owner, set()).update(rf"{name}{DICTIONARY_VALUE}" for name in names)

    # Each inner class's line and the classes around it, by its name, and the class each class
    # extends.
    inner: dict[str, list[tuple[int, tuple[int, ...]]]] = {}
    parents: dict[int | None, str] = {}
    for index, (line, (classes, function), owner) in enumerate(zip(bare, scopes, owners)):
        if function is None and (named_class := CLASS_NAMED.match(line)):
            inner.setdefault(named_class.group(1), []).append((index, classes[:-1]))
        if function is None and (base := EXTENDS.match(line)):
            parents[owner] = base.group(1)

    def resolved(base: str, owner: int | None) -> int | None:
        """The inner class `base` names in `owner`'s extends: the nearest one around it."""
        around = () if owner is None else scopes[owner][0][:-1]
        visible = [
            (len(outer), at) for at, outer in inner.get(base, []) if around[: len(outer)] == outer
        ]
        return max(visible)[1] if visible else None

    def inherited(owner: int | None, seen: set[int | None]) -> set[str]:
        """What a class has from the classes it extends: in this file, or another rules class."""
        base = parents.get(owner)
        if base is None:
            return set()
        at = resolved(base, owner)
        if at is None:
            return set((bases or {}).get(base, set()))
        if at in seen:
            return set()
        return declared.get(at, set()) | inherited(at, seen | {at})

    def names_in(scope: Scope) -> set[str]:
        """Its function's names, its class's, those its class inherits and the constants of the
        classes around that."""
        classes, function = scope
        *outers, own = None, *classes
        names = declared.get(own, set()) | inherited(own, {own})
        if function is not None:
            names |= declared.get(function, set())
        for outer in outers:
            names |= constants.get(outer, set())
        return names

    receivers: dict[tuple[Scope, frozenset[str]], re.Pattern[str]] = {}

    def receiver_on(index: int) -> re.Pattern[str]:
        """The receivers on a line: its scope's names and the loop variables of its loops."""
        key = (scopes[index], frozenset(loops.get(index, set())))
        if key not in receivers:
            receivers[key] = receiver_in(names_in(key[0]) | key[1], members or set())
        return receivers[key]

    named = code_with_random_names(source)
    # The line of each randomness method's name.
    by_name = {
        named.count("\n", 0, hit.start(2))
        for hit in RANDOM_NAME.finditer(named)
        if called_by_name(named[: hit.start()], named[hit.end() :])
    }
    return numbered(
        code,
        [
            FORBIDDEN.search(line) is not None
            or FORBIDDEN_IN_CODE.search(bare_line) is not None
            or calls_float_method(bare_line, receiver_on(index))
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
    sources = [Path(file).read_text(encoding="utf-8") for file in scripts]
    members = set().union(*(int_vector_members(source) for source in sources))
    bases = inherited_members(sources)
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
        hits = forbidden_lines(source, members, bases)
        if hits:
            print("\n".join(hits))
            log.error("the rules must stay deterministic: see the lines above", file)
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
