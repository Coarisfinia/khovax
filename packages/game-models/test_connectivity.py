"""Tests lib/connectivity.py on a model built here (#1458): a box for the body and a small box
for a part on its top, partly sunk at rest like Ombulumo's fronds, each moved by a bone of its
own, with a clip each way the part can go. The part that stays passes; one that lifts off, and
one that sinks wholly into the body (which the gap alone counts as on it, #1440), fail.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_connectivity.py

It prints the report and `CONNECTIVITY TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import connectivity  # noqa: E402

# Clip: (how far the part's bone moves up at its last frame in metres, whether the check passes it).
CLIPS = {
    "Stays": (0.0, True),
    "Dips": (-0.02, True),
    "Lifts": (0.1, False),
    "Sinks": (-0.3, False),
}


def box(name, size, centre, bone):
    """A box mesh `size` metres wide around `centre`, wholly weighted to `bone`, each side cut in
    four rows, so that a share of its vertices can lie inside another mesh."""
    mesh = bpy.data.meshes.new(name)
    built = bmesh.new()
    bmesh.ops.create_cube(built, size=size, matrix=Matrix.Translation(centre))
    bmesh.ops.subdivide_edges(built, edges=built.edges[:], cuts=3, use_grid_fill=True)
    built.to_mesh(mesh)
    built.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    group = obj.vertex_groups.new(name=bone)
    group.add(range(len(mesh.vertices)), 1.0, "REPLACE")
    return obj


def build():
    """The rig, its two meshes and a clip per entry in CLIPS."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    armature = bpy.data.armatures.new("rig")
    rig = bpy.data.objects.new("rig", armature)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head in (("body", Vector((0, 0, 0))), ("part", Vector((0, 0, 0.51)))):
        bone = armature.edit_bones.new(name)
        bone.head, bone.tail = head, head + Vector((0, 0, 0.1))
    bpy.ops.object.mode_set(mode="OBJECT")
    # The body a metre wide around the origin; the part 0.1 m wide just above its top face, its
    # two lowest rows of vertices inside.
    meshes = [box("body", 1.0, Vector((0, 0, 0)), "body"), box("part", 0.1, Vector((0, 0, 0.51)), "part")]
    for obj in meshes:
        modifier = obj.modifiers.new("rig", "ARMATURE")
        modifier.object = rig
    rig.animation_data_create()
    bone = rig.pose.bones["part"]
    for name, (rise, _passes) in CLIPS.items():
        rig.animation_data.action = bpy.data.actions.new(name)
        # Bone space: a bone's Y runs along it, here up the world's Z.
        for frame, location in ((1, 0.0), (5, rise)):
            bone.location = Vector((0, location, 0))
            bone.keyframe_insert("location", frame=frame)
    bone.location = Vector()
    return rig, meshes


def main():
    rig, meshes = build()
    lines, _passed = connectivity.report(rig, meshes)
    passed = True
    for line in lines:
        log.info("CONNECTIVITY test %s" % line)
    verdicts = {line.split(" ", 2)[1].rstrip(":"): line.startswith("ok ") for line in lines[1:]}
    for name, (_rise, passes) in sorted(CLIPS.items()):
        if verdicts.get(name) != passes:
            passed = False
            log.error("CONNECTIVITY test: %s should %s" % (name, "pass" if passes else "fail"), __file__)
    log.info("CONNECTIVITY TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
