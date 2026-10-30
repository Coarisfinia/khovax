"""Tests lib/volume.py on a model built here (#1680): an upright neck and head, a tube of skin
deeper (front to back) than wide, the neck leaning a little to one side as the Frostfire Hound's
does. A nod of the head keeps the tube's girth and passes, which it didn't while the cross
section's axes came from the world's up, almost along an upright neck, and swung around the
neck as the head nodded. A neck squeezed to 60 % of its girth still fails.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_volume.py

It prints the report and `VOLUME TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import volume  # noqa: E402

# The neck's lean to the side from upright, and its and the head's length (metres).
LEAN = math.radians(15)
LENGTH = 0.2
# The tube's half depth (front to back, along the world's Y) and half width (X), in metres.
DEPTH, WIDTH = 0.17, 0.09
# Clip: (the head's nod and the neck's squeeze at its last frame, whether the check passes it).
CLIPS = {
    "Nod": (math.radians(40), 1.0, True),
    "Squeeze": (0.0, 0.6, False),
}


def tube(tip):
    """The skin: rings of an ellipse up the neck and head, from below the neck's base to the
    head's tip, each centred on the bones; the neck's skin is the neck's, the head's the head's,
    blended across the joint."""
    mesh = bpy.data.meshes.new("body")
    built = bmesh.new()
    rings, sides = 13, 24
    joint = Vector((math.sin(LEAN), 0.0, math.cos(LEAN))) * LENGTH
    heights = [-0.1 + (tip.z + 0.2) * row / (rings - 1) for row in range(rings)]
    for z in heights:
        # On the neck's line below the joint, straight up above it.
        x = z * math.tan(LEAN) if z < joint.z else joint.x
        for side in range(sides):
            angle = 2.0 * math.pi * side / sides
            built.verts.new((x + WIDTH * math.cos(angle), DEPTH * math.sin(angle), z))
    built.verts.ensure_lookup_table()
    for row in range(rings - 1):
        for side in range(sides):
            corners = [row * sides + side, row * sides + (side + 1) % sides,
                       (row + 1) * sides + (side + 1) % sides, (row + 1) * sides + side]
            built.faces.new([built.verts[index] for index in corners])
    built.to_mesh(mesh)
    built.free()
    obj = bpy.data.objects.new("body", mesh)
    bpy.context.scene.collection.objects.link(obj)
    neck, head = obj.vertex_groups.new(name="neck"), obj.vertex_groups.new(name="head")
    for vertex in mesh.vertices:
        # 0 up to 5 cm below the joint, 1 from 5 cm above it.
        share = min(1.0, max(0.0, (vertex.co.z - joint.z + 0.05) / 0.1))
        neck.add([vertex.index], 1.0 - share, "REPLACE")
        head.add([vertex.index], share, "REPLACE")
    return obj


def build():
    """The rig, its skin and a clip per entry in CLIPS."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    armature = bpy.data.armatures.new("rig")
    rig = bpy.data.objects.new("rig", armature)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    neck = armature.edit_bones.new("neck")
    neck.head, neck.tail = Vector(), Vector((math.sin(LEAN), 0.0, math.cos(LEAN))) * LENGTH
    head = armature.edit_bones.new("head")
    head.head, head.tail = neck.tail, neck.tail + Vector((0.0, 0.0, LENGTH))
    head.parent, head.use_connect = neck, True
    tip = head.tail.copy()
    bpy.ops.object.mode_set(mode="OBJECT")
    obj = tube(tip)
    modifier = obj.modifiers.new("rig", "ARMATURE")
    modifier.object = rig
    rig.animation_data_create()
    neck, head = rig.pose.bones["neck"], rig.pose.bones["head"]
    head.rotation_mode = "XYZ"
    for name, (nod, squeeze, _passes) in CLIPS.items():
        rig.animation_data.action = bpy.data.actions.new(name)
        for frame, share in ((1, 0.0), (5, 1.0)):
            # Bone space: a bone's Y runs along it, X and Z across it.
            head.rotation_euler = (nod * share, 0.0, 0.0)
            across = 1.0 + (squeeze - 1.0) * share
            neck.scale = Vector((across, 1.0, across))
            head.keyframe_insert("rotation_euler", frame=frame)
            neck.keyframe_insert("scale", frame=frame)
    head.rotation_euler = (0.0, 0.0, 0.0)
    neck.scale = Vector((1.0, 1.0, 1.0))
    return rig, [obj]


def main():
    rig, meshes = build()
    lines, _passed = volume.report(rig, meshes)
    passed = True
    for line in lines:
        log.info("VOLUME test %s" % line)
    verdicts = {line.split(" ", 2)[1].rstrip(":"): line.startswith("ok ") for line in lines
                if line.startswith(("ok ", "FAIL "))}
    for name, (_nod, _squeeze, passes) in sorted(CLIPS.items()):
        if verdicts.get(name) != passes:
            passed = False
            log.error("VOLUME test: %s should %s" % (name, "pass" if passes else "fail"), __file__)
    log.info("VOLUME TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
