"""Tests that the model checks refuse to pass on nothing (#2203): with no tracked model they fail,
so a moved folder can't turn them off silently (the mouth check went dark that way, #2199), and an
entry on a list of models fails when its file isn't tracked, and a model's sources in its build
folder (#2438) count as no model (the tails check's, run in Blender's
container without git, when its file isn't there, #2373). No model changing is still fine.

    uv run --locked --package khovax-game-models src/game-models/test_model_lists.py

It prints `MODEL LISTS TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import contextlib
import io
import os
import sys
import tempfile
from pathlib import Path

import game_shared.git_files as listing

import changed_models
import check_clip_set
import check_eyes
import check_mouth
import check_rebuild
import check_tails

# One creature with nothing wrong and on no list, so the only fault left is the lists' other entries.
ONE_MODEL = ["resourcepacks/default/models/mana-pup/mana_pup.glb"]
REAL_LISTED = listing._listed
# Only the sources in a model's build folder (#2438), which are no model of the pack's.
BUILD_ONLY = ["resourcepacks/default/models/kavrikka/build/source.glb",
              "resourcepacks/default/models/player/build/clips/Walk.glb"]
# A model that isn't there, from the game's folder.
GONE = "resourcepacks/default/models/gone/gone.glb"


def exit_code(call):
    """What `call` exits with, kept quiet: a check's own return, or its SystemExit's."""
    start = Path.cwd()
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        try:
            return call()
        except SystemExit as stop:
            return 1 if stop.code not in (0, None) else 0
        finally:
            os.chdir(start)


def tracked(models):
    """Makes git list only `models`, whatever it's asked for."""
    listing._listed = lambda *_arguments: list(models)


def rebuild():
    check_rebuild.scripted_models()
    return 0


def selection(out):
    """changed_models.py's main, on a change that touches no model."""
    changed_models.changed_paths = lambda _base: []
    sys.argv = ["changed_models.py", "origin/main", str(out)]
    return changed_models.main()


def tails(extra):
    """check_tails.py's main with `extra` added to its TAILS, on one model it doesn't list, so only
    its list is left to fail it. It reads the files, not git: Blender's container has no git."""
    real = check_tails.TAILS
    check_tails.TAILS = {**real, **extra}
    sys.argv = ["check_tails.py", "--", *ONE_MODEL]
    try:
        return check_tails.main()
    finally:
        check_tails.TAILS = real


def main() -> int:
    checks = {"the clip set check": check_clip_set.main, "the eye check": check_eyes.main,
              "the mouth check": check_mouth.main}
    failures = []
    with tempfile.TemporaryDirectory(prefix="test_model_lists_") as scratch:
        out = Path(scratch) / "listed"
        for models, what in (([], "no tracked model"), (BUILD_ONLY, "only build folders' sources tracked")):
            tracked(models)
            for name, check in {**checks, "the rebuild check": rebuild,
                                "the changed models": lambda: selection(out)}.items():
                if exit_code(check) == 0:
                    failures.append(f"{name} passes with {what}")
        tracked(ONE_MODEL)
        for name, check in checks.items():
            if exit_code(check) == 0:
                failures.append(f"{name} passes with list entries whose files aren't tracked")
        listing._listed = REAL_LISTED
        if exit_code(lambda: tails({})) != 0:
            failures.append("the tails check refuses its own list")
        if exit_code(lambda: tails({GONE: 9})) == 0:
            failures.append("the tails check passes with an entry whose file is gone")
        if exit_code(lambda: selection(out)) != 0 or out.read_text():
            failures.append("the changed models refuses a change that touches no model")
    for failure in failures:
        print("FAIL " + failure)
    print("MODEL LISTS TEST: " + ("FAIL" if failures else "PASS"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
