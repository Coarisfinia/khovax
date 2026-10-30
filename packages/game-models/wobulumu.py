"""The Wobulumu (#1737): the Ombulumo's first form, a tadpole. A round head-and-body as one, pale
underneath with glowing spots along its sides, and a tail ending in a soft fin; it wriggles over
the ground on its belly. Its mesh and colour come from the owner's generated model
(`sources/wobulumu.glb`, made by import_source.py from the download with `static`: see the
asset's SOURCE.md). The generator rigged it with one chain bent back on itself at the tail's tip,
so this script drops that rig and builds a limbless one (lib/limbless.py), swaps the painted eyes
for ours (lib/marked_eyes.py) and animates every creature clip.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/wobulumu.py -- packages/game/assets/wobulumu/wobulumu.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes. `NAME=value`
after the output path sets one of its GAIT values (lib/tuning.py), for the gait sweep
(sweep_gait.py).

Blender is Z-up and it faces -Y (the game's +Z). The joints below, and the clips' shifts, are in
the source's metres; SCALE shrinks the source onto its hex first, and the rig is built at that size.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import attachments, clips, limbless, marked_eyes, metrics, scene, tuning  # noqa: E402
from lib.materials import material, palette  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "wobulumu.glb")
FPS = 30
# How much the source is shrunk, so its rest pose lies within its hex with room for its tail's
# swing (check_footprint.py): a baby, smaller than the Ombulumo it grows into.
SCALE = 0.33

# Its joints, along the middle of the mesh: the head's tip at the front, the head's base where the
# eyes' brow gives way to the body, the body's back where the tail starts, and the tail's joints
# along its middle, bending off to its left (+X) toward the fin, as the owner's model lies.
BODY = limbless.Body(
    nose=(0.0, -1.88, 0.86),
    head_base=(0.0, -0.95, 0.86),
    back=(0.0, 0.05, 0.82),
    tail=[(0.0, 0.45, 0.84), (0.02, 0.85, 0.89), (0.20, 1.22, 0.92), (0.60, 1.80, 0.98)],
)
TAIL = len(BODY.tail)

# Our eyes' colours: the dark eyeball and pupil, and a soft lime glow like the Ombulumo's.
COLORS = {
    "dark": ((0.02, 0.03, 0.03, 1.0), 0.0),
    "glow": ((0.62, 1.0, 0.18, 1.0), 1.0),
}
# A round, gentle baby's eyes: a wide round pupil and a soft brow, sized up to the generator's
# upright oval marks, their rims kept clear of the skin (marked_eyes.fit).
EYE_SHAPE = {"pupil": (0.4, 0.5), "brow_size": 0.4, "upright": True, "rim": True}
# It butts with its snout's front.
SNOUT = (0.0, -1.80, 0.70)

# Its eyes mirror each other (lib/metrics.py); the rest of its proportions are measured as notes
# until the owner approves its look.
REFERENCE = {
    "eye.R/eye.L height": 0.0,
    "eye.R/eye.L depth": 0.0,
    "eye.R/eye.L sides": 0.0,
}

# The game's speeds (metres a second): a wild monster glides a tile (sqrt(3) apart) in 0.8 s, a
# companion follows at a tile every 0.3 s. It has no feet to slide, so its wriggle's pace is its
# own: each gait's frames a loop, the wave's sway (radians) and its hop (source metres).
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_FRAMES, WALK_SWAY, WALK_HOP = 24, 0.28, 0.08
RUN_FRAMES, RUN_SWAY, RUN_HOP = 14, 0.36, 0.16
GAIT = ("WALK_FRAMES", "WALK_SWAY", "WALK_HOP", "RUN_FRAMES", "RUN_SWAY", "RUN_HOP")

# Faint's frames over which the lids shut (eyes.Lids): as it tips over.
FAINT_LIDS = (14, 32)


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    skin.name = "Wobulumu"
    scene.select_only(skin)
    # The import keeps the file's normals as custom ones; smooth normals from the faces shade the
    # same and bend with the skin (scene.sort_mesh keeps no custom normals).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    # Sized first: the eyes are fitted to the marks on the skin and bound to the rig at once, so
    # the rig is built at the game's size around the shrunk skin.
    scene.apply_scale([skin], SCALE)
    rig = limbless.armature("WobulumuRig", limbless.scaled(BODY, SCALE))
    limbless.bind(skin, rig)
    head = marked_eyes.Head(skin, limbless.HEAD)
    marks = marked_eyes.find(head)
    around = marked_eyes.repaint(head, marks)
    # Its colours have no black: every dark fragment of the generator's eyes goes too, after
    # they've been found by it (the owner, on #1747: "those should be removed fully"), while the
    # skin is still whole.
    print("SCRUBBED", marked_eyes.scrub(skin, limbless.HEAD), "texels")
    # The generator modelled a loose piece of skin round each of its eyes, which lay over the
    # lower half of ours (the owner, on #1747; check_eyes_covered.py): it goes, the marks keeping
    # their size.
    sizes = [(mark.width, mark.height) for mark in marks]
    marked_eyes.modelled(skin, marks)
    for mark, (width, height) in zip(marks, sizes):
        mark.width, mark.height = width, height
    mats = dict(palette(COLORS), skin=material("EyeSkin", marked_eyes.linear(around)))
    lids, eyes = marked_eyes.replace(rig, skin, mats, FAINT_LIDS, marks=marks, **EYE_SHAPE)
    attachments.add(rig, eyes, [(tuple(SCALE * value for value in SNOUT), limbless.HEAD)])
    clips.animate(rig, {
        "Idle": limbless.idle(TAIL),
        "Walk": limbless.wriggle(TAIL, WALK_FRAMES, WALK_SWAY, WALK_HOP),
        "Run": limbless.wriggle(TAIL, RUN_FRAMES, RUN_SWAY, RUN_HOP, surge=0.06),
        "Attack": limbless.attack(TAIL),
        "Hit": limbless.hit(TAIL),
        "Faint": limbless.faint(TAIL),
        **limbless.channel(TAIL),
        "Feed": limbless.feed(TAIL),
        "Sleep": limbless.sleep(TAIL),
    }, SCALE, ground_meshes=[skin], chains=limbless.follow(TAIL), limbs=(), overlays=[lids.shut])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(tuning.arguments(globals(), GAIT))
