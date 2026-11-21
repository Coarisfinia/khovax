"""Tests which models changed_models.py checks for a change (#2031): one model's own files check
that model, and a model derived from it (#2493), a change to what every model is built or checked
by checks them all, and anything else checks none.

    uv run --locked --package khovax-game-models src/game-models/test_changed_models.py

It prints `CHANGED MODELS TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import contextlib
import io
import sys

import changed_models

# The model scripts, in their build folders (#2438).
SCRIPTS = {"resourcepacks/default/models/mana-wolf/build/mana_wolf.py",
           "resourcepacks/default/models/kavrikka/build/kavrikka.py",
           "resourcepacks/default/models/player/build/player_clips.py",
           "resourcepacks/default/models/mana-gems/build/mana_gems.py",
           "resourcepacks/default/models/bare-rock/build/bare_rock.py",
           "resourcepacks/default/models/bare-rock/build/bare_rock_moss.py"}
# The models derived from another model's .glb (#2493), by stem: each derived one names its
# original. A derived model's own derived model follows it too.
ORIGINALS = {"bare_rock": "mana_gems", "bare_rock_moss": "bare_rock"}
CASES = [
    ("a model script", ["resourcepacks/default/models/mana-wolf/build/mana_wolf.py"], {"mana_wolf"}),
    ("its .glb and .import", ["resourcepacks/default/models/mana-wolf/mana_wolf.glb",
                              "resourcepacks/default/models/kavrikka/kavrikka.glb.import"], {"mana_wolf", "kavrikka"}),
    ("a model's source", ["resourcepacks/default/models/kavrikka/build/source.glb"], {"kavrikka"}),
    ("an original's script checks what is derived from it (#2493)",
     ["resourcepacks/default/models/mana-gems/build/mana_gems.py"], {"mana_gems", "bare_rock", "bare_rock_moss"}),
    ("an original's .glb checks what is derived from it (#2493)",
     ["resourcepacks/default/models/mana-gems/mana_gems.glb"], {"mana_gems", "bare_rock", "bare_rock_moss"}),
    ("a derived model alone checks only itself and what follows it",
     ["resourcepacks/default/models/bare-rock/build/bare_rock.py"], {"bare_rock", "bare_rock_moss"}),
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
    ("a deleted model script in its build folder", ["resourcepacks/default/models/gone/build/gone.py"], None),
    ("a source with no model script beside it", ["resourcepacks/default/models/gone/build/source.glb"], None),
    ("a build folder's .gdignore", ["resourcepacks/default/models/kavrikka/build/.gdignore"], None),
    ("a source of several clips", ["resourcepacks/default/models/player/build/clips/Walk.glb"], None),
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
    ("one model and the library", ["resourcepacks/default/models/mana-wolf/build/mana_wolf.py", "src/game-models/lib/eyes.py"], None),
]


def main() -> int:
    failures = 0
    # The derived models, as the scripts on disk would name them.
    changed_models.originals = lambda: dict(ORIGINALS)
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
