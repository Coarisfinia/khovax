"""Which models CI's model checks look at (#2031): on a pull request and in the merge queue only
the models it changes, and every model when it changes what all of them are built or checked by.

    uv run --locked --package khovax-game-models src/game-models/changed_models.py \
        <base> <list> [--every]

It reads what changed since `base` (`git diff --name-only`) and writes the game's .glb files to
check into `list`, separated by NUL bytes for `xargs -0`, named from the working directory as
`git ls-files` names them. It also writes `changed=true` or `false` to the step's outputs
(`GITHUB_OUTPUT`, or stdout without one): true when there is anything to check, even when no
.glb is left to list, such as a model script whose .glb was deleted, which the rebuild check
fails. `--every` lists every .glb whenever anything is to check, as CI does on `main`.

A model is named by its stem (mana_wolf for resourcepacks/default/models/mana-wolf/build/mana_wolf.py
and resourcepacks/default/models/mana-wolf/mana_wolf.glb, as check_rebuild.py pairs them). One
model's own files are its model script and its source, build/source.glb, in its build folder
(#2438), and its .glb and .glb.import in the pack; every other change in EVERY (the model library
and checks, Blender's setup, the workflow, the game's scripts, views and scenes, the pack's manifest
and tile blueprints the checks read, and a build folder's other files, such as the player's clip
sources) checks every model, and so does a diff that fails. Anything else checks nothing."""

import fnmatch
import os
import subprocess
import sys
from pathlib import Path

from game_shared import log
from game_shared.git_files import pack_models
from game_shared.model_builds import is_build_file, is_model_script as is_script

ROOT = Path(__file__).resolve().parents[2]
MODELS = "src/game-models/"
# A change to one of these, from the repository's root, checks every model: what every model is
# built or checked with, the workflow running the checks, and what the footprint and world-scale
# checks measure a model by (the views, the scenes, the default pack's manifest and its tile
# blueprints, whose "model" the footprint check leaves out as a decoration, #1651, #1652, #1864,
# #2208, and any game script, whose constants a view's settings may name, #2072).
EVERY = (
    MODELS + "*",
    "src/game-shared/*",
    "pyproject.toml",
    "uv.lock",
    ".github/actions/setup-blender/*",
    ".github/actions/setup-uv/*",
    ".github/workflows/ci.yml",
    "src/game/slices/*/look/*",
    "src/game/*.gd",
    "src/game/*.tscn",
    "resourcepacks/default/pack.jsonc",
    "resourcepacks/default/tiles/*",
    "resourcepacks/default/models/*/build/*",
)
# A model's imported source, in its build folder (#2438).
SOURCE = "source.glb"


def model_of(path: str, is_model_script) -> str | None:
    """The one model a changed path (from the root) belongs to, or None when it belongs to none."""
    name = os.path.basename(path)
    if is_build_file(path):
        if name.endswith(".py") and is_model_script(path):
            return name[:-3]
        if name != SOURCE:
            return None
        # A source belongs to the one model scripted beside it; none or several check every model.
        scripted = [script.stem for script in sorted((ROOT / os.path.dirname(path)).glob("*.py"))
                    if is_model_script(script.relative_to(ROOT).as_posix())]
        return scripted[0] if len(scripted) == 1 else None
    if path.startswith(MODELS):
        return None
    for ending in (".glb", ".glb.import"):
        if name.endswith(ending):
            return name[:-len(ending)]
    return None


def select(changed: list[str], is_model_script) -> set[str] | None:
    """The models the changed paths (from the root) check, or None for every model."""
    models = set()
    for path in changed:
        model = model_of(path, is_model_script)
        if model is not None:
            models.add(model)
        elif any(fnmatch.fnmatchcase(path, pattern) for pattern in EVERY):
            log.info(f"every model: {path} changed")
            return None
    return models


def is_model_script(path: str) -> bool:
    """Whether the path (from the root) is a model script: one in a build folder that exports
    through scene.export_glb. A deleted one isn't, so its change checks every model."""
    return is_script(str(ROOT / path))


def changed_paths(base: str) -> list[str] | None:
    """The paths changed since base, from the root, or None when the diff fails."""
    diff = subprocess.run(["git", "diff", "--name-only", "-z", base, "--"], capture_output=True, text=True)
    if diff.returncode != 0:
        log.warning(f"can't diff against {base!r}, so every model is checked: {diff.stderr.strip()}")
        return None
    return [path for path in diff.stdout.split("\0") if path]


def main() -> int:
    args = [arg for arg in sys.argv[1:] if arg != "--every"]
    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    base, out = args
    changed = changed_paths(base)
    models = None if changed is None else select(changed, is_model_script)
    glbs = pack_models()
    if models is None or (models and "--every" in sys.argv[1:]):
        listed = glbs
    else:
        listed = [glb for glb in glbs if Path(glb).name[:-4] in models]
        log.info(f"the models changed: {', '.join(sorted(models)) or 'none'}")
    Path(out).write_text("".join(f"{glb}\0" for glb in listed))
    line = f"changed={'true' if models is None or models else 'false'}\n"
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a") as handle:
            handle.write(line)
    else:
        print(line, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
