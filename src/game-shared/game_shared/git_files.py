"""The tracked files, as the checks read them."""

import subprocess
from pathlib import Path

from game_shared import log
from game_shared.model_builds import is_build_file

# The resource packs' folder lies at the repository's root (#1978), and the game's project reaches
# it through its link, resourcepacks (src/game-build/link_resource_packs.py). Git lists those
# files by their real path, which is the same as the game's path through the link, but only from
# the root: from the game's folder, git sees no files under the link.
PACKS = "resourcepacks/"
# The default pack's models, one folder each. Git's `*` matches across folders, so this also
# matches the sources in a model's build folder, which pack_models leaves out (#2438).
PACK_MODELS = PACKS + "default/models/*.glb"


def _listed(*arguments: str) -> list[str]:
    listing = subprocess.run(
        ["git", "ls-files", "-z", *arguments], check=True, capture_output=True, text=True
    ).stdout
    return [path for path in listing.split("\0") if path]


def git_files(*pathspecs: str) -> list[str]:
    """The tracked files the pathspecs match, as git lists them. In the game's project, the files
    under its link to the resource packs (PACKS) are listed too, by the game's path; from the root,
    they are ordinary paths."""
    in_game = Path("project.godot").is_file()
    own = [spec for spec in pathspecs if not (in_game and spec.startswith(PACKS))]
    files = _listed("--", *own) if own or not pathspecs else []
    if in_game:
        # The same pathspecs matched from the root, kept only under the link: the paths there are
        # the game's.
        top = [f":(top){spec}" for spec in pathspecs] or [f":(top){PACKS}"]
        files += [path for path in _listed("--full-name", "--", *top) if path.startswith(PACKS)]
    return files


def pack_models() -> list[str]:
    """The default pack's tracked models, without the sources in their build folders (#2438). None
    at all stops the caller with an error, so a moved folder can't turn a check off silently (#2199,
    #2203)."""
    models = [path for path in git_files(PACK_MODELS) if not is_build_file(path)]
    if not models:
        log.error(f"no tracked model matches {PACK_MODELS}: has their folder moved?")
        raise SystemExit(1)
    return models


def stale_entries(models: list[str], **lists: dict[str, str]) -> int:
    """How many entries of the named `lists` of models aren't among `models`, each reported: an
    entry whose file has gone would otherwise do nothing, unnoticed."""
    stale = 0
    for name, entries in lists.items():
        for path in entries:
            if path not in models:
                stale += 1
                log.error(f"on {name}, but no such model is tracked: take it off the list", path)
    return stale
