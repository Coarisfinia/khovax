"""Checks that every creature model has our own eyes (#1682, #1683): every eye point (`eye.<side>`,
attachments.add) has its lid's bone (`lid.<side>`, lib/eyes.py), so its eyes are built parts that
blink and shut in Sleep and Faint, never a generator's painted ones. A beast imported from a
generated model gets them from lib/marked_eyes.py. CI runs it on every push.

    uv run --locked --package khovax-game-models packages/game-models/check_eyes.py

A creature model is one check_clip_set.py checks. One designed without eyes is let off in
EYELESS with its reason, and one still waiting for ours in KNOWN with the issue that gives them
(lib/known.py's way: a fix takes it off, and the check fails a listed model that passes). Each
failure is an error annotation on its .glb (game_shared.log, #1115)."""

import os
import sys
from pathlib import Path

from check_clip_set import NOT_CREATURES
from check_rebuild import read_glb
from game_shared import log
from game_shared.git_files import git_files

# The attachment points' and the lids' bone names (lib/attachments.py's EYE, lib/eyes.py's LID;
# both import Blender, which this check runs without).
EYE, LID = "eye.", "lid."

# Creatures designed without eyes, from the game's folder, each with why.
EYELESS = {}

# Creatures whose eyes are still the generator's painted ones, each with the issue that gives them ours.
KNOWN = {
    "assets/drakkudor/drakkudor.glb": "#1684",
    "assets/fohossa/fohossa.glb": "#1684",
    "assets/frostfire_hound/frostfire_hound.glb": "#1684",
}


def problem(names):
    """What's wrong with a creature's eyes, from its joints' `names`, or None."""
    sides = sorted(name[len(EYE):] for name in names if name.startswith(EYE))
    if not sides:
        return "no eye points (eye.<side>)"
    lidless = [side for side in sides if LID + side not in names]
    if lidless:
        return "eyes without our lids: " + ", ".join(EYE + side for side in lidless)
    # A lid needs its eye's point too: the game places the eye's effects there.
    pointless = sorted(name for name in names if name.startswith(LID) and name[len(LID):] not in sides)
    if pointless:
        return "lids without their eye points: " + ", ".join(pointless)
    return None


def joints(gltf):
    """The names of the bones the model's skins carry: the game reads its eye points and lids as
    skeleton bones, so a node outside the skeleton named like one doesn't count."""
    nodes = gltf.get("nodes", [])
    return {nodes[index].get("name", "") for skin in gltf.get("skins", []) for index in skin.get("joints", [])}


def main() -> int:
    # The game's project folder (#1101): the paths below are relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    failed = 0
    for path in git_files("assets/*.glb"):
        gltf, _binary = read_glb(Path(path))
        if not gltf.get("skins") or path in NOT_CREATURES:
            continue
        names = joints(gltf)
        if path in EYELESS:
            if any(name.startswith((EYE, LID)) for name in names):
                failed += 1
                log.error("listed as eyeless (EYELESS) but has eyes: take it off the list", path)
            continue
        found = problem(names)
        if path in KNOWN:
            if found is None:
                failed += 1
                log.error("has our eyes now: take it off KNOWN (%s)" % KNOWN[path], path)
            else:
                log.info(f"{path}: {found}, known ({KNOWN[path]})")
        elif found is not None:
            failed += 1
            log.error(found + ": give it our eyes (lib/marked_eyes.py), or list it in EYELESS", path)
        else:
            log.info(f"{path}: our eyes, with lids")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
