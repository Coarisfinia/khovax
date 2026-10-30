"""Checks that no generator's eye area is left in a creature's texture (#1688): on the head of
each creature model, neither a flat black oval nor a painted glowing eye, next to or under our own
(check_eyes.py checks those are there). It samples the texture over the head's faces and looks
for a mirrored pair as lib/marked_eyes.py's `find` does on import, with `DARK`, with `GLOW` and
with the beast's own way its eyes are marked, if marked_eyes.BEASTS lists it (#1719); and for
fragments the repaint left beyond a pair, spots much darker than the head's median
(marked_eyes.fragments, #1756) among every texel the head's faces touch, not only the samples
(#1764), which `scrub` paints out.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_painted_eyes.py -- <model.glb> [<model.glb> ...]

A model without a rig, a creature check_clip_set.py's NOT_CREATURES leaves out (the tentacle
gate's eye is part of its design, #1642), and a skin without a texture or a head bone pass: nothing
painted there. A beast still waiting for our eyes is in KNOWN with the issue that gives them; it
doesn't fail, and fails once it passes until it's taken off (lib/known.py's way). A beast its
script paints whole (PAINTED_WHOLE) is searched for pairs only, never fragments. It prints a line
per model and `PAINTED EYES CHECK: PASS` or `FAIL` (and exits 1 on a fail), through
game_shared.log (#1115): a failing line is an error on the .glb. CI runs it on every .glb."""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from check_clip_set import NOT_CREATURES  # noqa: E402
from game_shared import log  # noqa: E402
from lib import ground, marked_eyes  # noqa: E402

# The game's project folder, which NOT_CREATURES' and KNOWN's paths start from.
GAME = os.path.join(os.path.dirname(HERE), "game")

# Beasts whose texture still shows the generator's eyes, each with the issue that gives them ours.
KNOWN = {
    "assets/drakkudor/drakkudor.glb": "#1684",
    "assets/fohossa/fohossa.glb": "#1684",
    "assets/frostfire_hound/frostfire_hound.glb": "#1684",
}

# Beasts whose script paints the whole texture from where each texel lies, so no generator paint
# is left, while a deliberately dark area (a basalt half) reads as fragments: only the pair search
# runs on them, each with the issue that teaches the fragment search such heads.
PAINTED_WHOLE = {
    "assets/kavrikka/kavrikka.glb": "#1782",
}

# How many of a head's fragments its line names, the largest first.
SHOWN = 5


def found(objects, path):
    """What the generator left on the head of each skin among `objects` (the model at `path`): a
    line per mirrored pair of marked spots, with where they are and how wide, and a line per skin
    with the fragments of its eyes left beyond a pair (#1756)."""
    lines = []
    own = marked_eyes.BEASTS.get(path)
    for skin in ground.skinned(objects):
        for kind, marks in marked_eyes.painted(skin, own=own).items():
            lines.append("%s: %s eyes at %s and %s, %.3f and %.3f wide" % (
                skin.name, kind, tuple(round(float(v), 3) for v in marks[0].middle),
                tuple(round(float(v), 3) for v in marks[1].middle), marks[0].width, marks[1].width))
        if path in PAINTED_WHOLE:
            continue
        weight = own.weight if own is not None else marked_eyes.HEAD_WEIGHT
        left = sorted(marked_eyes.fragments(skin, weight=weight), key=lambda mark: -mark.count)
        if left:
            lines.append("%s: %d dark fragments, the largest at %s" % (skin.name, len(left), ", ".join(
                "%s (%d texels)" % (tuple(round(float(v), 3) for v in mark.middle), mark.count)
                for mark in left[:SHOWN])))
    return lines


def main():
    glbs = [arg for arg in sys.argv[sys.argv.index("--") + 1:] if arg.endswith(".glb")]
    failed = 0
    for glb in glbs:
        path = os.path.relpath(os.path.abspath(glb), GAME).replace(os.sep, "/")
        if path in NOT_CREATURES:
            log.info("PAINTED EYES %s: not a creature (%s)" % (path, NOT_CREATURES[path]))
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=glb)
        try:
            lines = found(bpy.data.objects, path)
        except ValueError as error:
            # A head the check can't read (one taking two textures, say) fails its model, not the run.
            failed += 1
            log.error("PAINTED EYES can't check the head: %s" % error, glb)
            continue
        if path in KNOWN:
            if lines:
                log.info("PAINTED EYES %s: %s, known (%s)" % (path, "; ".join(lines), KNOWN[path]))
            else:
                failed += 1
                log.error("PAINTED EYES no generated eyes left: take it off KNOWN (%s)" % KNOWN[path], glb)
        elif lines:
            failed += 1
            log.error("PAINTED EYES %s: paint them over with lib/marked_eyes.py's `replace`, and fragments with `scrub`"
                      % "; ".join(lines), glb)
        else:
            log.info("PAINTED EYES %s: no generated eyes on the head" % path)
    verdict = "PASS" if glbs and not failed else "FAIL"
    log.info("PAINTED EYES CHECK: %s" % verdict)
    sys.exit(0 if verdict == "PASS" else 1)


main()
