"""Bare rock (#2493): the low rock the mana gems stand on, left once a player harvested their
crystals (#696). It is derived from the mana gems' own model (the model skill's "after" rule,
#2489), so it matches it exactly: the derive step (lib/derive.py) reads `mana_gems.glb`, keeps its
rock as it is and breaks each crystal off just above the rock, leaving a short capped stub that
still glows. A static prop: no rig and no clips.

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python resourcepacks/default/models/bare-rock/build/bare_rock.py -- \
        resourcepacks/default/models/bare-rock/bare_rock.glb

When the mana gems change, rebuild this too: CI checks it whenever they do (changed_models.py).
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# The model library, src/game-models/lib/, from this model's build folder (#2438).
sys.path.insert(0, os.path.normpath(os.path.join(HERE, *[os.pardir] * 5, "src", "game-models")))

from lib import derive, scene  # noqa: E402

# The model this one is derived from, from the repository's root (#2493).
ORIGINAL = "resourcepacks/default/models/mana-gems/mana_gems.glb"
FPS = 30
# The original's material that stays whole: the rock. Every part in another (the crystals) breaks.
ROCK = "rock"
# How far a stub rises above the rock's top, in the original's units (the rock is 0.28 tall).
STUB = 0.035
# How far each break is tilted off square to its crystal, alternating sides crystal by crystal.
TILT = math.radians(12.0)


def build(out):
    parts = derive.original(ORIGINAL, FPS)
    rocks = [obj for obj in parts.values() if obj.data.materials[0].name == ROCK]
    crystals = [obj for name, obj in sorted(parts.items()) if obj not in rocks]
    if len(rocks) != 1 or not crystals:
        raise SystemExit("expected one rock and its crystals in %s, found %s" % (ORIGINAL, sorted(parts)))
    top = float(derive.points(rocks[0])[:, 2].max()) + STUB
    for index, crystal in enumerate(crystals):
        reach = derive.stub(crystal, top, TILT if index % 2 == 0 else -TILT)
        print("STUB %s: %.3f along its axis" % (crystal.name, reach))
    triangles = sum(scene.triangles(obj) for obj in bpy.data.objects if obj.type == "MESH")
    print("BARE ROCK: %d crystals broken to stubs, %d triangles" % (len(crystals), triangles))
    scene.export_glb(out)


build(sys.argv[sys.argv.index("--") + 1])
