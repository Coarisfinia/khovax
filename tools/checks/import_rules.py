"""Fails when a script reaches a file the wrong way (#375, #526). Each boundary is checked by class
name (a class_name declared on the far side) and by path:
- The core never depends on a slice: no script under core/ names a slice's class or a slices/
  path in its code, with or without res://, so a path built from parts
  ("res://" + "slices/tiles/data/") is refused too (AGENTS.md, "Vertical slices").
- The rules stay pure: no script under core/ or a slice's rules/ names a class or a path of any
  look/, ui/, input/ or game/ folder, so the simulation never leans on what draws or drives it.
- Lasting data stays apart from what shows and drives the game (#827): no script in a slice's
  meta/ names a class or a path of any look/, ui/ or input/ folder; what ties lasting data to the
  running session lives beside what it ties (#831).
- The slices form no cycle (#821): SLICE_ORDER below declares their order once, and a slice's
  scripts, scenes and resources name only the classes and paths of slices before it. A new slice
  takes its place in the order. Today's back-edges wait in SLICE_EXEMPT, each with the issue that
  drops it, and an exemption no longer used fails too, so the list only shrinks.
- game/ is where the game is wired together, so it may reach any slice, and nothing but the tests
  and the tools reaches back into it (owner, #514): no script elsewhere names a game/ class or a
  game/ path, and no scene or resource outside game/ names a game/ file. The slices see the driver
  only as a Session.
- Nothing outside tests/ reaches the tests, and nothing outside tools/ and tests/ reaches the
  tools: no class of theirs, no tests/ or tools/ path.
The folder paths are refused where they start a string or follow a /, with or without res://, so a
path built from parts is caught too, while a message may still name a file in parentheses. The test
builds' mode takes its flow's path from the environment or a project setting (#551).
- Paths are absolute from res://: no string in a script starts with ./ or ../, no load or preload
  of a path without its scheme, and no scene or resource names a file by a relative path.
Comments don't count (gdscript_code.py strips them), so the rules can be explained in them.

    uv run --locked tools/checks/import_rules.py
"""

import os
import re
import subprocess
import sys
from collections.abc import Iterable
from fnmatch import fnmatchcase
from pathlib import Path

from gdscript_code import without_comments

# The slices, each after every slice it names (#821).
SLICE_ORDER: tuple[str, ...] = (
    "emoji_grid", "realms", "camera", "music", "credits", "hiding", "movement", "entering",
    "paths", "loot", "board", "exits", "fog", "action_buttons", "triggers", "species", "health",
    "players", "npcs", "trail", "wild_monsters", "tiles", "outbox", "controls",
    "settings", "texts", "factions",
    "survey", "menu",
    "domination", "enrage", "domination_loot", "companions", "gear", "chests", "damage_numbers",
    "harvest", "dialogs",
    "profile", "quests", "revive_items", "blueprints", "might",
)  # fmt: skip
# The back-edges still waiting ("slice>later slice": the issue that drops it).
SLICE_EXEMPT: dict[str, int] = {
    "board>blueprints": 851, "board>controls": 851, "board>profile": 851,
    "controls>profile": 851, "controls>revive_items": 851,
    "factions>menu": 851, "factions>profile": 851,
    "gear>profile": 851,
    "hiding>wild_monsters": 851,
    "loot>menu": 851, "loot>profile": 851,
    "menu>gear": 851, "menu>might": 851, "menu>profile": 851, "menu>quests": 851,
    "settings>damage_numbers": 851, "settings>menu": 851, "settings>survey": 851,
    "species>menu": 851, "species>profile": 851, "species>texts": 851,
    "survey>quests": 851,
    "texts>factions": 851, "texts>gear": 851,
    "wild_monsters>companions": 851, "wild_monsters>domination": 851,
}  # fmt: skip

THIS = "tools/checks/import_rules.py"
LATER_SLICE = "a slice names only the slices before it in SLICE_ORDER"
# Where a folder's path starts: at the start of a string, or after a /.
AT = r"(^|[/\"'])"
RELATIVE_STRING = re.compile(r"[\"']\.\.?/")
LOAD = re.compile(r"\b(pre)?load\s*\(\s*[\"'][^\"']*")
LOAD_WITH_SCHEME = re.compile(r"\(\s*[\"'][a-z]+://")
PATH_ATTRIBUTE = re.compile(r'\bpath="[^"]*"')
PATH_WITH_SCHEME = re.compile(r'\bpath="[a-z]+://')

type Lines = list[str]
type Pattern = re.Pattern[str] | None


def git_files(*pathspecs: str) -> list[str]:
    """The tracked files the pathspecs match, as git lists them."""
    listing = subprocess.run(
        ["git", "ls-files", "-z", "--", *pathspecs], check=True, capture_output=True, text=True
    ).stdout
    return [path for path in listing.split("\0") if path]


def lines_of(text: str) -> Lines:
    return text.rstrip("\n").split("\n")


def words(names: Iterable[str]) -> Pattern:
    """Any of the names as a whole word, or None for no names."""
    names = sorted(set(names))
    if not names:
        return None
    return re.compile(r"(?<!\w)(?:" + "|".join(map(re.escape, names)) + r")(?!\w)")


def matching(lines: Lines, pattern: Pattern) -> list[str]:
    """Each line the pattern matches, as `number:line`."""
    if pattern is None:
        return []
    return [f"{number}:{line}" for number, line in enumerate(lines, 1) if pattern.search(line)]


def inside(*folders: str) -> list[str]:
    """Globs for the scripts inside any folder of these names, at any depth."""
    return [glob for folder in folders for glob in (f"{folder}/*.gd", f"*/{folder}/*.gd")]


def any_match(lines: Lines, pattern: Pattern) -> bool:
    return pattern is not None and any(pattern.search(line) for line in lines)


class Check:
    def __init__(self) -> None:
        self.failed = False

    def fail(self, hits: list[str], error: str) -> None:
        for hit in hits:
            print(hit)
        print(error)
        self.failed = True

    def refuse(self, file: str, lines: Lines, classes: Pattern, path: Pattern, rule: str) -> None:
        """Fails a file whose code names one of the classes or matches the path pattern."""
        hits = matching(lines, classes) + matching(lines, path)
        if hits:
            self.fail(hits, f"::error file={file}::{rule}: see the lines above")


def main() -> int:
    os.chdir(Path(__file__).resolve().parents[2])
    check = Check()
    scripts = git_files("*.gd")
    code = {
        file: lines_of(without_comments(Path(file).read_text(encoding="utf-8"))) for file in scripts
    }
    declared = {
        file: [
            line.split()[1]
            for line in Path(file).read_text(encoding="utf-8").split("\n")
            if line.startswith("class_name ") and len(line.split()) > 1
        ]
        for file in scripts
    }

    def classes_in(*globs: str) -> list[str]:
        """The class_names declared in the scripts any glob matches (a * spans folders)."""
        return [
            name
            for file in scripts
            if any(fnmatchcase(file, glob) for glob in globs)
            for name in declared[file]
        ]

    slice_classes = words(classes_in("slices/*.gd"))
    presentation_classes = words(classes_in(*inside("look", "ui", "input", "game")))
    view_classes = words(classes_in(*inside("look", "ui", "input")))

    # Per slice: its own classes, and the later slices' classes and folder names it may not name.
    own_classes = {slice_: classes_in(f"slices/{slice_}/*.gd") for slice_ in SLICE_ORDER}
    later_classes: dict[str, Pattern] = {}
    later_paths: dict[str, Pattern] = {}
    later_scene_paths: dict[str, Pattern] = {}
    back_edges: set[str] = set()
    for index, slice_ in enumerate(SLICE_ORDER):
        later = []
        for later_slice in SLICE_ORDER[index + 1 :]:
            if f"{slice_}>{later_slice}" in SLICE_EXEMPT:
                back_edges.add(f"{slice_}>{later_slice}")
            else:
                later.append(later_slice)
        later_classes[slice_] = words(
            name for later_slice in later for name in own_classes[later_slice]
        )
        alternation = "|".join(later)
        later_paths[slice_] = re.compile(f"{AT}slices/({alternation})/") if later else None
        later_scene_paths[slice_] = re.compile(f"res://slices/({alternation})/") if later else None
    exemption_used: set[str] = set()

    def exemptions_of(slice_: str) -> list[tuple[str, str]]:
        return [
            (exempt, exempt.split(">")[1])
            for exempt in SLICE_EXEMPT
            if exempt.split(">")[0] == slice_
        ]

    game_classes = words(classes_in("game/*.gd"))
    test_classes = words(classes_in("tests/*.gd"))
    tool_classes = words(classes_in("tools/*.gd"))

    def under(file: str, *globs: str) -> bool:
        return any(fnmatchcase(file, glob) for glob in globs)

    for file in scripts:
        lines = code[file]
        if under(file, "core/*"):
            check.refuse(
                file,
                lines,
                slice_classes,
                re.compile("slices/"),
                "the core never depends on a slice",
            )
        if under(file, "core/*", "slices/*/rules/*"):
            check.refuse(
                file,
                lines,
                presentation_classes,
                re.compile(f"{AT}(look|ui|input|game)/"),
                "the rules never depend on what draws or drives them",
            )
        if under(file, "slices/*/meta/*"):
            check.refuse(
                file,
                lines,
                view_classes,
                re.compile(f"{AT}(look|ui|input)/"),
                "lasting data never depends on what shows or drives the game",
            )
        if under(file, "slices/*"):
            slice_ = file.split("/")[1]
            if slice_ in own_classes:
                check.refuse(
                    file,
                    lines,
                    later_classes[slice_],
                    later_paths[slice_],
                    LATER_SLICE,
                )
                for exempt, later in exemptions_of(slice_):
                    if any_match(lines, words(own_classes.get(later, []))) or any_match(
                        lines, re.compile(f"{AT}slices/{later}/")
                    ):
                        exemption_used.add(exempt)
        if not under(file, "game/*", "tests/*", "tools/*"):
            check.refuse(
                file,
                lines,
                game_classes,
                re.compile(f"{AT}game/"),
                "nothing outside game/ reaches game/",
            )
        if not under(file, "tests/*"):
            check.refuse(
                file,
                lines,
                test_classes,
                re.compile(f"{AT}tests/"),
                "nothing outside tests/ reaches the tests",
            )
        if not under(file, "tests/*", "tools/*"):
            check.refuse(
                file,
                lines,
                tool_classes,
                re.compile(f"{AT}tools/"),
                "the game never reaches tools/",
            )
        # Any string starting with ./ or ../, and every load or preload of a literal path that
        # doesn't start with its scheme (res://, user://, uid://), each found on its own.
        loads = [
            f"{number}:{found.group()}"
            for number, line in enumerate(lines, 1)
            for found in LOAD.finditer(line)
            if not LOAD_WITH_SCHEME.search(found.group())
        ]
        relative = matching(lines, RELATIVE_STRING) + loads
        if relative:
            check.fail(
                relative,
                f"::error file={file}::paths are absolute from res://: see the lines above",
            )

    scenes = {
        file: lines_of(Path(file).read_text(encoding="utf-8"))
        for file in git_files("*.tscn", "*.tres")
    }
    relative = [
        f"{file}:{number}:{line}"
        for file, lines in scenes.items()
        for number, line in enumerate(lines, 1)
        if PATH_ATTRIBUTE.search(line) and not PATH_WITH_SCHEME.search(line)
    ]
    if relative:
        check.fail(
            relative,
            "::error::scenes and resources name files absolute from res://: see the lines above",
        )

    for file, lines in scenes.items():
        if not file.startswith("slices/"):
            continue
        slice_ = file.split("/")[1]
        hits = matching(lines, later_scene_paths.get(slice_))
        if hits:
            check.fail(
                hits,
                f"::error file={file}::{LATER_SLICE}: see the lines above",
            )
        for exempt, later in exemptions_of(slice_):
            if any(f"res://slices/{later}/" in line for line in lines):
                exemption_used.add(exempt)

    # Every slice has its place in the order, every place a slice, and every exemption is in use.
    slice_folders = sorted(
        path.name
        for path in Path("slices").iterdir()
        if path.is_dir() and not path.name.startswith(".")
    )
    for slice_ in slice_folders:
        if slice_ not in own_classes:
            check.fail([], f"::error::slices/{slice_} has no place in SLICE_ORDER ({THIS})")
    for slice_ in SLICE_ORDER:
        if not Path("slices", slice_).is_dir():
            check.fail(
                [], f"::error::SLICE_ORDER names slices/{slice_}, which doesn't exist ({THIS})"
            )
    for exempt in SLICE_EXEMPT:
        if exempt not in exemption_used or exempt not in back_edges:
            check.fail(
                [], f"::error::SLICE_EXEMPT's {exempt} is no longer needed: drop it ({THIS})"
            )

    reaching_game = [
        f"{file}:{number}:{line}"
        for file, lines in scenes.items()
        if not under(file, "game/*", "tests/*", "tools/*")
        for number, line in enumerate(lines, 1)
        if "res://game/" in line
    ]
    if reaching_game:
        check.fail(
            reaching_game, "::error::nothing outside game/ reaches game/: see the lines above"
        )

    return 1 if check.failed else 0


if __name__ == "__main__":
    sys.exit(main())
