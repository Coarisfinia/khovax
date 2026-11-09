"""Tests which models changed_models.py checks for a change (#2031): one model's own files check
that model, a change to what every model is built or checked by checks them all, and anything
else checks none.

    uv run --locked --package khovax-game-models src/game-models/test_changed_models.py

It prints `CHANGED MODELS TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import contextlib
import io
import sys

import changed_models

SCRIPTS = {"src/game-models/mana_wolf.py", "src/game-models/player_clips.py"}
CASES = [
    ("a model script", ["src/game-models/mana_wolf.py"], {"mana_wolf"}),
    ("its .glb and .import", ["resourcepacks/default/models/mana-wolf/mana_wolf.glb",
                              "resourcepacks/default/models/kavrikka/kavrikka.glb.import"], {"mana_wolf", "kavrikka"}),
    ("a model's source", ["src/game-models/sources/kavrikka.glb"], {"kavrikka"}),
    ("a .glb with no script", ["resourcepacks/default/models/items/pebble.glb"], {"pebble"}),
    ("nothing the checks read", ["src/game/slices/quests/data/quests/x.jsonc", "README.md", ".github/workflows/nightly.yml",
                                 "resourcepacks/default/models/mana-wolf/SOURCE.md"], set()),
    ("the attached-part check", ["src/game-models/check_connectivity.py"], None),
    ("the rebuild check", ["src/game-models/check_rebuild.py"], None),
    ("the selection itself", ["src/game-models/changed_models.py"], None),
    ("a check's test", ["src/game-models/test_connectivity.py"], None),
    ("the shared rig and build code", ["src/game-models/lib/rigged.py"], None),
    ("a script that isn't a model", ["src/game-models/import_source.py"], None),
    ("a deleted or other model script", ["src/game-models/gone.py"], None),
    ("a source of several clips", ["src/game-models/sources/player/clips/Walk.glb"], None),
    ("the models' package", ["src/game-models/pyproject.toml"], None),
    ("the shared tools", ["src/game-shared/game_shared/log.py"], None),
    ("the lock file", ["uv.lock"], None),
    ("the workflow", [".github/workflows/ci.yml"], None),
    ("Blender's setup", [".github/actions/setup-blender/action.yml"], None),
    ("uv's setup", [".github/actions/setup-uv/action.yml"], None),
    ("a view the footprint check reads", ["src/game/slices/board/look/board_view.gd"], None),
    ("a scene", ["src/game/game/main.tscn"], None),
    ("a game script a view's settings may name (#2072)", ["src/game/slices/combat/rules/x.gd"], None),
    ("a core script (#2072)", ["src/game/core/tick.gd"], None),
    ("the default pack's manifest", ["resourcepacks/default/pack.jsonc"], None),
    ("a tile blueprint the footprint check reads (#2208)", ["resourcepacks/default/tiles/boulder.jsonc"], None),
    ("one model and the library", ["src/game-models/mana_wolf.py", "src/game-models/lib/eyes.py"], None),
]


def main() -> int:
    failures = 0
    for label, changed, expected in CASES:
        with contextlib.redirect_stdout(io.StringIO()):
            got = changed_models.select(changed, lambda path: path in SCRIPTS)
        if got != expected:
            failures += 1
            print(f"FAIL {label}: expected {'every model' if expected is None else sorted(expected)}, "
                  f"got {'every model' if got is None else sorted(got)}")
        else:
            print(f"ok {label}")
    print(f"CHANGED MODELS TEST: {'FAIL' if failures else 'PASS'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
