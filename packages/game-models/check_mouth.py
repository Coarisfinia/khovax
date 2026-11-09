"""Checks that every creature model has a mouth that opens (#2190, #2191): a `jaw` bone with skin
on it, turned wide open in Attack and in ChannelStart, the clip that opens it for a channel (the
model skill's step 24). It reads the .glb without Blender and says nothing about how the mouth
looks: the renders of step 24 still show that. CI runs it on every push.

    uv run --locked --package khovax-game-models packages/game-models/check_mouth.py

A creature model is one check_clip_set.py checks. One designed without a mouth is let off in
MOUTHLESS with its reason, and one still waiting for its mouth in KNOWN with its issue
(lib/known.py's way: a fix takes it off, and the check fails a listed model that passes). Each
failure is an error annotation on its .glb (game_shared.log, #1115)."""

import math
import os
import sys
from pathlib import Path

from check_clip_set import NOT_CREATURES
from check_rebuild import read_glb, values
from game_shared import log
from game_shared.git_files import git_files

JAW = "jaw"
# The clips that open the mouth (lib/clips.py keys `jaw` in them; Channel only holds it open).
OPENING_CLIPS = ("Attack", "ChannelStart")
# How far the jaw must turn from its rest: less reads as a shut mouth at the game's distance.
MIN_OPEN_DEGREES = 15.0
FLOAT = 5126

# Creatures designed without a mouth, from the game's folder, each with why.
MOUTHLESS = {
    "assets/drakkudor/drakkudor.glb": "a cracked bone plate for a face, with no mouth (#1476)",
    "assets/tikazzelu/tikazzelu.glb": "a ball of ribbons round a glowing core, with no mouth (#1732)",
}

# Creatures whose mouth doesn't open yet, each with the issue that decides it.
KNOWN = {
    "assets/fohossa/fohossa.glb": "#2187",
    "assets/frostfire_hound/frostfire_hound.glb": "#2183",
    "assets/kalvrakkor_magma/kalvrakkor_magma.glb": "#2185",
    "assets/kavrikka/kavrikka.glb": "#2184",
    "assets/nuvvoluvvo/nuvvoluvvo.glb": "#2188",
    "assets/ombulumo/ombulumo.glb": "#2195",
    "assets/ombuwomo/ombuwomo.glb": "#2195",
    "assets/tolvakkor/tolvakkor.glb": "#2186",
    "assets/wobulumu/wobulumu.glb": "#2195",
}


def chunks(flat, width):
    return [flat[start:start + width] for start in range(0, len(flat), width)]


def skinned_vertices(gltf, binary, jaw):
    """How many vertices of the model's skinned meshes the bone at node `jaw` moves."""
    count = 0
    for node in gltf["nodes"]:
        if "mesh" not in node or "skin" not in node:
            continue
        joints = gltf["skins"][node["skin"]]["joints"]
        if jaw not in joints:
            continue
        slot = joints.index(jaw)
        for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
            attributes = primitive["attributes"]
            bones = chunks(values(gltf, binary, gltf["accessors"][attributes["JOINTS_0"]]), 4)
            weights = chunks(values(gltf, binary, gltf["accessors"][attributes["WEIGHTS_0"]]), 4)
            count += sum(
                any(bone == slot and weight > 0 for bone, weight in zip(vertex, shares))
                for vertex, shares in zip(bones, weights))
    return count


def widest_turn(gltf, binary, animation, jaw):
    """The most degrees `animation` turns the bone at node `jaw` from its rest, 0 without a key, or
    None when its keys aren't floats (Blender's export writes floats, so this model needs a look)."""
    rest = gltf["nodes"][jaw].get("rotation", [0.0, 0.0, 0.0, 1.0])
    widest = 0.0
    for channel in animation.get("channels", []):
        target = channel["target"]
        if target.get("node") != jaw or target["path"] != "rotation":
            continue
        sampler = animation["samplers"][channel["sampler"]]
        accessor = gltf["accessors"][sampler["output"]]
        if accessor["componentType"] != FLOAT:
            return None
        keys = chunks(values(gltf, binary, accessor), 4)
        # A cubic spline stores each key between its two tangents, which aren't rotations.
        for key in keys[1::3] if sampler.get("interpolation") == "CUBICSPLINE" else keys:
            alignment = min(1.0, abs(sum(a * b for a, b in zip(rest, key))))
            widest = max(widest, 2.0 * math.degrees(math.acos(alignment)))
    return widest


def problem(gltf, binary):
    """What's wrong with a creature's mouth, or None."""
    nodes = gltf["nodes"]
    joints = [index for skin in gltf["skins"] for index in skin["joints"]]
    jaw = next((index for index in joints if nodes[index].get("name") == JAW), None)
    if jaw is None:
        return "no `jaw` bone"
    if not skinned_vertices(gltf, binary, jaw):
        return "its `jaw` bone moves no skin"
    clips = {animation.get("name"): animation for animation in gltf.get("animations", [])}
    for name in OPENING_CLIPS:
        turn = widest_turn(gltf, binary, clips[name], jaw) if name in clips else 0.0
        if turn is None:
            return f"{name}'s `jaw` keys aren't floats"
        if turn < MIN_OPEN_DEGREES:
            return f"{name} opens the `jaw` only {turn:.1f} degrees (at least {MIN_OPEN_DEGREES:g})"
    return None


def main() -> int:
    # The game's project folder (#1101): the paths below are relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    failed = 0
    checked = 0
    for path in git_files("assets/*.glb"):
        gltf, binary = read_glb(Path(path))
        if not gltf.get("skins") or path in NOT_CREATURES:
            continue
        checked += 1
        found = problem(gltf, binary)
        if path in MOUTHLESS:
            if found is None:
                failed += 1
                log.error("listed in MOUTHLESS but has a mouth that opens: take it off the list", path)
        elif path in KNOWN:
            if found is None:
                failed += 1
                log.error("its mouth opens now: take it off KNOWN (%s)" % KNOWN[path], path)
            else:
                log.info(f"{path}: {found}, known ({KNOWN[path]})")
        elif found is not None:
            failed += 1
            log.error(found + ": give it a mouth that opens (the model skill's step 24), or list it in MOUTHLESS", path)
        else:
            log.info(f"{path}: its mouth opens")
    # Models that moved must not silence the check (#2199).
    if not checked:
        failed += 1
        log.error("found no creature model to check: has their folder moved?")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
