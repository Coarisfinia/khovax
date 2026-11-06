"""The tracked files, as the checks read them."""

import subprocess
from pathlib import Path

# The resource packs' folder lies at the repository's root (#1978), and the game's project reaches
# it through its link, resourcepacks (packages/game-build/link_resource_packs.py). Git lists those
# files by their real path, which is the same as the game's path through the link, but only from
# the root: from the game's folder, git sees no files under the link.
PACKS = "resourcepacks/"


def _listed(*arguments: str) -> list[str]:
    listing = subprocess.run(
        ["git", "ls-files", "-z", *arguments], check=True, capture_output=True, text=True
    ).stdout
    return [path for path in listing.split("\0") if path]


def git_files(*pathspecs: str) -> list[str]:
    """The tracked files the pathspecs match, as git lists them. In the game's project, the files
    under its link to the resource packs (PACKS) are listed too, by the game's path."""
    own = [spec for spec in pathspecs if not spec.startswith(PACKS)]
    files = _listed("--", *own) if own or not pathspecs else []
    if Path("project.godot").is_file():
        # The same pathspecs matched from the root, kept only under the link: the paths there are
        # the game's.
        top = [f":(top){spec}" for spec in pathspecs] or [f":(top){PACKS}"]
        files += [path for path in _listed("--full-name", "--", *top) if path.startswith(PACKS)]
    return files
