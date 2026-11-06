"""Which models CI's model checks look at (#2031): on a pull request and in the merge queue only
the models it changes, and every model when it changes what all of them are built or checked by.

    uv run --locked --package khovax-game-models packages/game-models/changed_models.py \
        <base> <list> [--every]

It reads what changed since `base` (`git diff --name-only`) and writes the game's .glb files to
check into `list`, separated by NUL bytes for `xargs -0`, named from the working directory as
`git ls-files` names them. It also writes `changed=true` or `false` to the step's outputs
(`GITHUB_OUTPUT`, or stdout without one): true when there is anything to check, even when no
.glb is left to list, such as a model script whose .glb was deleted, which the rebuild check
fails. `--every` lists every .glb whenever anything is to check, as CI does on `main`.

A model is named by its stem (mana_wolf for mana_wolf.py and assets/mana-wolf/mana_wolf.glb, as
check_rebuild.py pairs them). One model's own files are its model script, its source in sources/
and its .glb and .glb.import in the game; every other change in EVERY (the model library and
checks, Blender's setup, the workflow, the game's scripts, views and scenes and the pack the
checks read) checks every model, and so does a diff that fails. Anything else checks nothing."""

import fnmatch
import os
import subprocess
import sys
from pathlib import Path

from game_shared import log
from game_shared.git_files import git_files

from check_rebuild import EXPORT

ROOT = Path(__file__).resolve().parents[2]
MODELS = "packages/game-models/"
# A change to one of these, from the repository's root, checks every model: what every model is
# built or checked with, the workflow running the checks, and what the footprint and world-scale
# checks measure a model by (the views, the scenes and the default pack's manifest, #1651, #1652,
# #1864, and any game script, whose constants a view's settings may name, #2072).
EVERY = (
    MODELS + "*",
    "packages/game-shared/*",
    "pyproject.toml",
    "uv.lock",
    ".github/actions/setup-blender/*",
    ".github/workflows/ci.yml",
    "packages/game/slices/*/look/*",
    "packages/game/*.gd",
    "packages/game/*.tscn",
    "packages/game/slices/resource_packs/data/*",
)


def model_of(path: str, is_model_script) -> str | None:
    """The one model a changed path (from the root) belongs to, or None when it belongs to none."""
    name = os.path.basename(path)
    if path.startswith(MODELS):
        rest = path[len(MODELS):]
        if "/" not in rest and rest.endswith(".py") and is_model_script(path):
            return rest[:-3]
        if rest.startswith("sources/") and rest.count("/") == 1 and rest.endswith(".glb"):
            return name[:-4]
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
    """Whether the path (from the root) is a model script: one that exports through
    scene.export_glb. A deleted one isn't, so its change checks every model."""
    script = ROOT / path
    return script.is_file() and bool(EXPORT.search(script.read_text()))


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
    glbs = git_files(str(ROOT / "packages" / "game" / "*.glb"))
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
