"""Checks that every creature model carries every creature clip (#1157), the set named once in
lib/clip_set.py, which the build (clips.animate) reads too. CI runs it on every push.

    uv run --locked --package khovax-game-models packages/game-models/check_clip_set.py

A creature model is every skinned .glb under the game's assets/ except the figures in
NOT_CREATURES, so a new skinned model is checked unless it's listed there with its reason. Each
one lacking a clip is an error annotation on its .glb naming the missing clips (game_shared.log,
#1115)."""

import os
import sys
from pathlib import Path

from check_rebuild import read_glb
from game_shared import log
from game_shared.git_files import git_files
from lib import clip_set

# Skinned figures that aren't creatures, from the game's folder, each with why.
NOT_CREATURES = {
    "assets/kaykit-adventurers/Rogue.glb": "the players' and NPCs' humanoid figure, with clips of its own",
}


def main() -> int:
    # The game's project folder (#1101): the paths below are relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    failed = 0
    for path in git_files("assets/*.glb"):
        gltf, _binary = read_glb(Path(path))
        if not gltf.get("skins") or path in NOT_CREATURES:
            continue
        lacking = clip_set.missing([clip.get("name") for clip in gltf.get("animations", [])])
        if lacking:
            failed += 1
            log.error("creature model lacks the clips " + ", ".join(lacking) + " (lib/clip_set.py)", path)
        else:
            log.info(f"{path}: every creature clip")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
