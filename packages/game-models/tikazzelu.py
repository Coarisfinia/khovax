"""The Tikazzelu (#1732): the Tikazzir's first form, a ribbon sprite. A ball of pale ribbons wound
round and round, two stiff ribbon loops on its top for wings, standing on two thin legs. Its mesh
and colour come from the owner's generated model (`sources/tikazzelu.glb`, made by
import_source.py from the download: see the asset's SOURCE.md). The generator couldn't rig it, so
this script builds a flutterer's rig (lib/flutter.py) and animates every creature clip: it stands
on its feet and flies to move. It has no eyes, by design (the owner, on #1732), and a slight violet
shine at its centre: a small glowing core inside the ribbons, swelling as it strikes and while it
channels (lib/pulse.py).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/tikazzelu.py -- packages/game/assets/tikazzelu/tikazzelu.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes. `NAME=value`
after the output path sets one of its GAIT values (lib/tuning.py), for the gait sweep
(sweep_gait.py).

Blender is Z-up and it faces -Y (the game's +Z). The joints below, and the clips' shifts, are in
the source's metres once it stands on the ground; SCALE shrinks the source onto its hex first,
and the rig is built at that size.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import attachments, clips, flutter, metrics, parts, pulse, scene, tuning  # noqa: E402
from lib.materials import palette  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "tikazzelu.glb")
FPS = 30
# A baby, smaller than the Tikazzir it grows into, well inside its hex.
SCALE = 0.8
# Raises the source onto its feet: the download's origin is at its middle.
LIFT = 0.476


def placed(point):
    return (point[0], point[1], point[2] + LIFT)


# Its joints (the left side; the right mirrors it), read off the mesh: the legs hang from inside
# the ball's bottom, the ball's middle is where its upper half turns against its lower, and each
# wing loop rises from the ball's upper side out to its tip.
BODY = flutter.Body(
    hips=placed((0.0, 0.0, -0.17)),
    middle=placed((0.0, 0.0, 0.07)),
    top=placed((0.0, 0.0, 0.35)),
    wing=[placed(point) for point in ((0.09, 0.005, 0.27), (0.19, 0.01, 0.38), (0.325, 0.014, 0.43))],
    leg=[placed(point) for point in ((0.08, 0.01, -0.14), (0.092, 0.02, -0.32), (0.10, 0.0, -0.43),
                                     (0.10, -0.075, -0.47))],
)
WINGS, LEGS = len(BODY.wing) - 1, len(BODY.leg) - 1

# The violet shine at its centre: a small glowing core inside the ribbon cage, clear of every
# ribbon, a soft glow rather than a light (the owner, on #1732).
CORE, CORE_RADIUS = placed((0.0, -0.02, 0.07)), 0.065
COLORS = {"core": ((0.5, 0.22, 1.0, 1.0), 1.0)}
# It strikes with its ball's front.
STRIKE = placed((0.0, -0.24, 0.07))

# No eyes and no measured proportions yet: its measures print as notes until the owner approves
# its look (lib/metrics.py).
REFERENCE = {}

# The game's speeds (metres a second): a wild monster glides a tile (sqrt(3) apart) in 0.8 s, a
# companion follows at a tile every 0.3 s. It flies, so no foot slides: each gait's frames a loop,
# its hover (source metres), its wing beat and its lean (radians).
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_FRAMES, WALK_HOVER, WALK_BEAT, WALK_PITCH = 24, 0.10, 0.45, 0.15
RUN_FRAMES, RUN_HOVER, RUN_BEAT, RUN_PITCH = 16, 0.13, 0.6, 0.3
GAIT = ("WALK_FRAMES", "WALK_HOVER", "WALK_BEAT", "WALK_PITCH", "RUN_FRAMES", "RUN_HOVER", "RUN_BEAT", "RUN_PITCH")


def core(rig):
    """The glowing core on a pulse bone of its own, hung from the body: it swells as the attack
    strikes and twice in each long attack's loop."""
    centre = tuple(SCALE * value for value in CORE)
    beat = pulse.Pulse(rig, "core", centre, flutter.BODY, {
        "Attack": [21], "ChannelStart": [24], "Channel": [1, 31, 61], "ChannelEnd": [1],
    }, amount=1.35, rise=4, fall=12)
    mat = palette(COLORS)["core"]
    sphere = parts.part("uv_sphere", "Core", centre, (SCALE * CORE_RADIUS,) * 3, mat=mat, bone=beat.name,
                        segments=16, ring_count=8)
    return beat, sphere


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    skin.name = "Tikazzelu"
    scene.select_only(skin)
    # The import keeps the file's normals as custom ones; smooth normals from the faces shade the
    # same and bend with the skin (scene.sort_mesh keeps no custom normals).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    skin.location = (0.0, 0.0, LIFT)
    scene.apply_scale([skin], SCALE)
    body = flutter.scaled(BODY, SCALE)
    rig = flutter.armature("TikazzeluRig", body)
    homes = flutter.bind(skin, rig, body)
    print("PIECES", ", ".join("%d:%s" % item for item in sorted(homes.items())))
    beat, sphere = core(rig)
    attachments.add(rig, {}, [(tuple(SCALE * value for value in STRIKE), flutter.BODY)])
    # The core joins the skin, its weights with it (one mesh, as the game's views expect).
    bpy.ops.object.select_all(action="DESELECT")
    sphere.select_set(True)
    skin.select_set(True)
    bpy.context.view_layer.objects.active = skin
    bpy.ops.object.join()
    clips.animate(rig, {
        "Idle": flutter.idle(WINGS, LEGS),
        "Walk": flutter.fly(WINGS, LEGS, WALK_FRAMES, WALK_HOVER, WALK_BEAT, WALK_PITCH),
        "Run": flutter.fly(WINGS, LEGS, RUN_FRAMES, RUN_HOVER, RUN_BEAT, RUN_PITCH, trail=0.6),
        "Attack": flutter.attack(WINGS, LEGS),
        "Hit": flutter.hit(WINGS, LEGS),
        "Faint": flutter.faint(WINGS, LEGS),
        **flutter.channel(WINGS, LEGS),
        "Feed": flutter.feed(WINGS, LEGS),
        "Sleep": flutter.sleep(WINGS, LEGS),
    }, SCALE, ground_meshes=[skin], chains=flutter.follow(WINGS, LEGS), limbs=(), overlays=[beat.beat])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(tuning.arguments(globals(), GAIT))
