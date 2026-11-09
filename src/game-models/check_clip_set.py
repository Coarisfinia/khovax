"""Checks that every creature model carries every creature clip (#1157), the set named once in
lib/clip_set.py, which the build (clips.animate) reads too. CI runs it on every push.

    uv run --locked --package khovax-game-models src/game-models/check_clip_set.py

A creature model is every skinned .glb under the default pack's models/ except the figures in
NOT_CREATURES, so a new skinned model is checked unless it's listed there with its reason. Each
one lacking a clip is an error annotation on its .glb naming the missing clips (game_shared.log,
#1115)."""

import os
import sys
from pathlib import Path

from check_rebuild import read_glb
from game_shared import log
from game_shared.git_files import pack_models, stale_entries
from lib import clip_set

# Skinned figures that aren't creatures, from the game's folder, each with why.
NOT_CREATURES = {
    "resourcepacks/default/models/kaykit-adventurers/Rogue.glb": "the people's humanoid figure, with clips of its own",
    "resourcepacks/default/models/player/player_body.glb": "the player's body, which plays the player's clip library (#1827)",
    "resourcepacks/default/models/player/player_clips.glb": "the player's clip library, its clips on a stand-in rig without a body (#1935)",
    "resourcepacks/default/models/tentacle_gate/tentacle_gate.glb": "a gate, a prop of the world that only idles (#1634)",
}


def main() -> int:
    # The game's project folder (#1101): the paths below are relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    models = pack_models()
    failed = stale_entries(models, NOT_CREATURES=NOT_CREATURES)
    for path in models:
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
