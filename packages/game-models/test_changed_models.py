"""Tests which models changed_models.py checks for a change (#2031): one model's own files check
that model, a change to what every model is built or checked by checks them all, and anything
else checks none.

    uv run --locked --package khovax-game-models packages/game-models/test_changed_models.py

It prints `CHANGED MODELS TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import contextlib
import io
import sys

import changed_models

SCRIPTS = {"packages/game-models/mana_wolf.py", "packages/game-models/player_clips.py"}
CASES = [
    ("a model script", ["packages/game-models/mana_wolf.py"], {"mana_wolf"}),
    ("its .glb and .import", ["packages/game/assets/mana-wolf/mana_wolf.glb",
                              "packages/game/assets/kavrikka/kavrikka.glb.import"], {"mana_wolf", "kavrikka"}),
    ("a model's source", ["packages/game-models/sources/kavrikka.glb"], {"kavrikka"}),
    ("a .glb with no script", ["packages/game/assets/items/pebble.glb"], {"pebble"}),
    ("nothing the checks read", ["packages/game/core/tick.gd", "README.md", ".github/workflows/nightly.yml",
                                 "packages/game/assets/mana-wolf/SOURCE.md"], set()),
    ("the attached-part check", ["packages/game-models/check_connectivity.py"], None),
    ("the rebuild check", ["packages/game-models/check_rebuild.py"], None),
    ("the selection itself", ["packages/game-models/changed_models.py"], None),
    ("a check's test", ["packages/game-models/test_connectivity.py"], None),
    ("the shared rig and build code", ["packages/game-models/lib/rigged.py"], None),
    ("a script that isn't a model", ["packages/game-models/import_source.py"], None),
    ("a deleted or other model script", ["packages/game-models/gone.py"], None),
    ("a source of several clips", ["packages/game-models/sources/player/clips/Walk.glb"], None),
    ("the models' package", ["packages/game-models/pyproject.toml"], None),
    ("the shared tools", ["packages/game-shared/game_shared/log.py"], None),
    ("the lock file", ["uv.lock"], None),
    ("the workflow", [".github/workflows/ci.yml"], None),
    ("Blender's setup", [".github/actions/setup-blender/action.yml"], None),
    ("a view the footprint check reads", ["packages/game/slices/board/look/board_view.gd"], None),
    ("a scene", ["packages/game/game/main.tscn"], None),
    ("the default pack's manifest", ["packages/game/slices/resource_packs/data/default.jsonc"], None),
    ("one model and the library", ["packages/game-models/mana_wolf.py", "packages/game-models/lib/eyes.py"], None),
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
