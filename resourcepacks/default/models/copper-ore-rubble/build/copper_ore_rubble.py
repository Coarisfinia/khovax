"""Copper ore rubble (#2572): the heap of broken stone left once a player broke the copper out of
copper ore by hand (#1929). It is derived from the ore outcrop's own model (the model skill's
"after" rule, #2489), so it matches it exactly: the derive step (lib/derive.py) reads
`ore_outcrop.glb` as one shape, splits it into chunks (a Voronoi split), and lets them slump into a
lower heap, the higher chunks tipping out over the lower. The copper is gone, so the stone is
painted as the outcrop's is (the props' shared stone, lib/prop_paint.py, CC0 textures, with its
darker shaded step) but without the veins. A static prop: no rig and no clips.

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python resourcepacks/default/models/copper-ore-rubble/build/copper_ore_rubble.py -- \
        resourcepacks/default/models/copper-ore-rubble/copper_ore_rubble.glb

When the ore outcrop changes, rebuild this too: CI checks it whenever it does (changed_models.py).
Blender is Z-up; the origin is at the heap's foot, in the middle of its hex, as the outcrop's.
"""

import math
import os
import sys

import bpy
import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
# The model library, src/game-models/lib/, from this model's build folder (#2438).
sys.path.insert(0, os.path.normpath(os.path.join(HERE, *[os.pardir] * 5, "src", "game-models")))

from lib import derive, fixed_order, prop_paint, scene  # noqa: E402

# The model this one is derived from, from the repository's root (#2572).
ORIGINAL = "resourcepacks/default/models/ore-outcrop/ore_outcrop.glb"
FPS = 30
# Where the outcrop breaks: COLUMNS places across it, drawn with SEED, each split into the LAYERS
# (seeds at these shares of its height), so it breaks across as well as down (a Voronoi split).
COLUMNS = 5
SEED = 2572
LAYERS = (0.15, 0.7)
# How far in from the outcrop's sides the columns lie, as a share of its half width.
INSIDE = 0.6
# How the chunks fall (derive.slump): out from the middle, as a share of how far from it they
# stood; out and down as they slide off the chunks below, per metre their foot stood above the
# ground; how much of that height their foot keeps; and how far the highest tips.
SPREAD = 0.2
SLIDE = 0.8
KEEP = 0.3
TILT = math.radians(30.0)
# Edges sharper than this stay sharp in the shading, as on the outcrop: the broken facets.
SHARP = math.radians(40.0)
# The materials, in their slots.
STONE, SHADED = range(2)
# How far a crack's darkness looks, in metres: as on the outcrop.
REACH = 0.08


def seeds(shape):
    """The chunks' seeds: COLUMNS places drawn inside the outcrop's bounds, each at every height of
    LAYERS."""
    where = derive.points(shape)
    low, high = where.min(axis=0), where.max(axis=0)
    middle, half = (low + high) / 2.0, (high - low) / 2.0
    draws = numpy.random.default_rng(SEED).uniform(-1.0, 1.0, (COLUMNS, 2))
    return [(float(middle[0] + INSIDE * half[0] * x), float(middle[1] + INSIDE * half[1] * y),
             float(low[2] + layer * (high[2] - low[2])))
            for x, y in draws for layer in LAYERS]


def paint(rubble):
    """The outcrop's stone and its shaded step, on the crevices between the chunks and their foot."""
    mesh = rubble.data
    mesh.materials.clear()
    mesh.materials.append(prop_paint.material("stone", "stone"))
    mesh.materials.append(prop_paint.material("stone_shaded", "stone", prop_paint.Weathering.shade))
    points = derive.points(rubble)
    normals = fixed_order.vertex_normals(mesh, angle=True)
    shut = prop_paint.occlusion(rubble, points, normals, 2.0 * REACH)
    dark = prop_paint.contour(mesh, prop_paint.darkness(points, shut), prop_paint.Weathering.shaded)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, dark, prop_paint.Weathering.shaded)):
        polygon.material_index = SHADED if above else STONE
    prop_paint.box_uv(mesh)


def build(out):
    shape = derive.whole(ORIGINAL, FPS, "CopperOreRubble")
    height = float(derive.points(shape)[:, 2].max())
    chunks = derive.fracture(shape, seeds(shape))
    if len(chunks) < 3:
        raise SystemExit("expected the outcrop to break into several chunks, got %d" % len(chunks))
    drops = derive.slump(chunks, SPREAD, SLIDE, KEEP, TILT)
    print("CHUNKS %d, dropped %s" % (len(chunks), ", ".join("%.3f" % drop for drop in drops)))
    bpy.ops.object.select_all(action="DESELECT")
    for chunk in chunks:
        chunk.select_set(True)
    bpy.context.view_layer.objects.active = chunks[0]
    bpy.ops.object.join()
    rubble = chunks[0]
    rubble.name = rubble.data.name = "CopperOreRubble"
    scene.select_only(rubble)
    bpy.ops.object.shade_smooth_by_angle(angle=SHARP)
    paint(rubble)
    where = derive.points(rubble)
    counts = numpy.bincount([polygon.material_index for polygon in rubble.data.polygons], minlength=2)
    print("BUDGET triangles", scene.triangles(rubble), "materials", len(rubble.data.materials),
          "height %.3f (the outcrop's %.3f)" % (where[:, 2].max(), height),
          "reach %.3f" % float(numpy.linalg.norm(where[:, :2], axis=1).max()),
          "faces per material", dict(zip([m.name for m in rubble.data.materials], counts.tolist())))
    scene.export_glb(out)


build(sys.argv[sys.argv.index("--") + 1])
