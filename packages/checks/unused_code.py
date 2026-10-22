"""Fails on code that nothing uses (#315). Godot already fails the script check on unused locals,
parameters, private class variables and signals (project.godot); what it can't see across files is
a function, class variable, constant, enum or class that no other line in the project names.
This lists every one declared at a script's top level (and every function of an inner class) and
fails when its name appears nowhere but in its own declaration. Comments don't count as a use
(gdscript_code.py strips them); strings do (a method called by name, a scene's property), and so
does a scene naming a script's path for a class. A name shared with something else counts as used,
so it never fails wrongly. Engine callbacks are used by the engine, so they're left out.

    uv run --locked packages/checks/unused_code.py
"""

import os
import re
import sys
from collections import Counter
from pathlib import Path

from gdscript_code import without_comments
from git_files import git_files

# Methods the engine calls itself.
ENGINE = re.compile(
    r"_(ready|process|physics_process|init|static_init|notification|enter_tree|exit_tree"
    r"|initialize|finalize|input|unhandled_input|unhandled_key_input|shortcut_input|gui_input"
    r"|input_event|mouse_enter|mouse_exit|draw|to_string|get|set|get_property_list"
    r"|validate_property|property_can_revert|property_get_revert|get_configuration_warnings"
    r"|get_minimum_size|get_drag_data|can_drop_data|drop_data|make_custom_tooltip|has_point"
    r"|integrate_forces|log_error|log_message)"
)
# A declaration: annotations first (`@export_range(0, 12)`, `@onready`, `@rpc("any_peer")`), then
# `static`, then the keyword and the name, taken right after its keyword, never from a default
# value further on. Functions may be indented, inside an inner class.
DECLARATION = re.compile(
    r"((@[a-z_]+(\([^)]*\))?) )*(static )?(?P<kind>var|const|func|class_name|class|enum)"
    r" (?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"|\s+(static )?(?P<kind_inside>func) (?P<name_inside>[A-Za-z_][A-Za-z0-9_]*)"
)
# A word, which counts as a name when it starts with a letter or _ and holds only ASCII.
WORD = re.compile(r"\w+")
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
SCRIPT_PATH = re.compile(r'res://([^"\n]*\.gd)')


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    scripts = {file: Path(file).read_text(encoding="utf-8") for file in git_files("*.gd")}
    # Every script's code without its comments, and the scenes and settings as they are.
    code = [without_comments(source) for source in scripts.values()] + [
        Path(file).read_text(encoding="utf-8")
        for file in git_files("*.tscn", "*.tres", "*.godot", "*.cfg")
    ]
    # How often every name appears in the whole project, and every script named by its path.
    count = Counter(
        word for text in code for word in WORD.findall(text) if NAME.fullmatch(word)
    )
    attached = {path for text in code for path in SCRIPT_PATH.findall(text)}

    unused = []
    for file, source in scripts.items():
        for number, line in enumerate(source.split("\n"), 1):
            declared = DECLARATION.match(line)
            if declared is None:
                continue
            kind = declared["kind"] or declared["kind_inside"]
            name = declared["name"] or declared["name_inside"]
            if (
                ENGINE.fullmatch(name)
                or count[name] > 1
                or (kind == "class_name" and file in attached)
            ):
                continue
            unused.append(f"::error file={file},line={number}::{name} is declared but never used")
    if unused:
        print("\n".join(unused))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
