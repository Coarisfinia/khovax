"""Fails when the simulation could stop being deterministic (AGENTS.md, "Architecture"). core/ and
every slice's rules/ hold the rules: plain RefCounted classes (or classes of the rules, e.g.
Feature) without nodes, input, time, engine or OS state, global randomness, frame delta, floats
(float-backed engine types such as Vector2 or Color too; Vector2i and Rect2i stay allowed), or file
and JSON access (#572: reading happens before a tick, never inside one).
Comments are stripped first (gdscript_code.py), so the rules can be explained in them.
A whole file is exempt while its top comment lines carry the marker below with a reason in
parentheses (owner, #515). It marks a workaround to fix later; a marker without a reason fails:
  # TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (why this file can't pass yet)

    uv run --locked tools/checks/determinism_check.py
"""

import os
import re
import sys
from pathlib import Path

from gdscript_code import without_comments

# What the rules never use, one alternation per kind; add a kind as its own line.
FORBIDDEN = re.compile(
    "|".join(
        (
            r"\b(Node|Node2D|Node3D|CanvasItem|Control|Window|Viewport|Resource)\b",
            r"\b(Input|InputMap|Time|Engine|OS|DisplayServer|RenderingServer|ProjectSettings)\.",
            r"\b(randf|randi|randf_range|randi_range|randfn|randomize|seed|rand_from_seed)\(",
            r"\bdelta\b",
            r"\bfloat\b|[0-9]\.[0-9]|[0-9][eE][-+]?[0-9]",
            r"\b(FileAccess|DirAccess|JSON)\b",
            r"\b(Vector2|Vector3|Vector4|Color|Rect2|AABB|Plane|Basis|Quaternion|Transform2D"
            r"|Transform3D|Projection)\b",
        )
    )
)
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


def main() -> int:
    os.chdir(Path(__file__).resolve().parents[2])
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
            print(
                f"::error file={file}::the exemption marker sits in the top comment lines, with a"
                f" reason: {MARKER} (reason)"
            )
            failed = True

        code = without_comments(source).rstrip("\n").split("\n")
        if not extends.intersection(code):
            print(f"::error file={file}::rules scripts extend RefCounted or a class of the rules")
            failed = True
        hits = numbered(code, [FORBIDDEN.search(line) is not None for line in code])
        if hits:
            print("\n".join(hits))
            print(f"::error file={file}::the rules must stay deterministic: see the lines above")
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
