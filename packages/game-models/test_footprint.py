"""Tests lib/footprint.py's judgement on models built here (#1641): boxes standing on the hex,
each as a monster (rigged, with a Walk clip) or a prop (rigged with only an Idle clip, or static),
inside their hex or too big for it. The ones that fit pass; an oversized one fails whatever it
is, and a prop whose clip spreads past the hex's edge fails, even one it calls Attack, though a
monster may do so (props have limits of their own, never an exemption).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_footprint.py

It prints each model's report and `FOOTPRINT TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import footprint  # noqa: E402

# A square box `width` metres across reaches width / 2 * (cos 30° + sin 30°) / the inradius of
# the hex: 1.10 m reaches 0.87 (inside), 2.0 m reaches 1.58 (far past it).
FITS, OVERSIZED = 1.10, 2.0
# How much a clip widens the fitting box: 1.18 times reaches 1.02, past a prop's clip limit (1.00)
# but within a monster's (1.05).
SPREAD = 1.18

# Name: (box width, clips as {name: how much it widens}, or None for a static model, whether the
# check passes it).
MODELS = {
    "monster_fits": (FITS, {"Walk": SPREAD}, True),
    "monster_oversized": (OVERSIZED, {"Walk": 1.0}, False),
    "prop_fits": (FITS, {"Idle": 1.0}, True),
    "prop_oversized": (OVERSIZED, {"Idle": 1.0}, False),
    "prop_spreads": (FITS, {"Idle": SPREAD}, False),
    "prop_attacks": (FITS, {"Attack": SPREAD}, False),
    "static_fits": (FITS, None, True),
    "static_oversized": (OVERSIZED, None, False),
}


def box(width):
    """A box mesh `width` metres across, standing on the ground at the hex's centre."""
    mesh = bpy.data.meshes.new("box")
    built = bmesh.new()
    bmesh.ops.create_cube(built, size=width, matrix=Matrix.Translation(Vector((0, 0, width / 2.0))))
    built.to_mesh(mesh)
    built.free()
    obj = bpy.data.objects.new("box", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build(width, clips):
    """The model in an empty scene: its box, and unless `clips` is None a rig with one bone that
    holds it and a clip per entry, widening it by its share. Returns (rig or None, meshes)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    skin = box(width)
    if clips is None:
        return None, [skin]
    armature = bpy.data.armatures.new("rig")
    rig = bpy.data.objects.new("rig", armature)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bone = armature.edit_bones.new("root")
    bone.head, bone.tail = Vector((0, 0, 0)), Vector((0, 0, 0.1))
    bpy.ops.object.mode_set(mode="OBJECT")
    group = skin.vertex_groups.new(name="root")
    group.add(range(len(skin.data.vertices)), 1.0, "REPLACE")
    modifier = skin.modifiers.new("rig", "ARMATURE")
    modifier.object = rig
    rig.animation_data_create()
    pose = rig.pose.bones["root"]
    for name, widen in clips.items():
        rig.animation_data.action = bpy.data.actions.new(name)
        # Bone space: the bone runs up the world's Z along its Y, so its X and Z are the ground's.
        for frame, share in ((1, 1.0), (5, widen)):
            pose.scale = Vector((share, 1.0, share))
            pose.keyframe_insert("scale", frame=frame)
    pose.scale = Vector((1.0, 1.0, 1.0))
    return rig, [skin]


def main():
    passed = True
    for name, (width, clips, passes) in sorted(MODELS.items()):
        rig, meshes = build(width, clips)
        lines, verdict = footprint.report(rig, meshes, footprint.limits(rig, large=False))
        for line in lines:
            log.info("FOOTPRINT test %s %s" % (name, line))
        if verdict != passes:
            passed = False
            log.error("FOOTPRINT test: %s should %s" % (name, "pass" if passes else "fail"), __file__)
    log.info("FOOTPRINT TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
