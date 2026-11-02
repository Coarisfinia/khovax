"""Tests lib/tails.py's judgement on a stand-in beast (#1771): a body with three tails, of thin rings
without faces, each tail on its own chain, or all on one chain as a generator's auto-rig does, or
never moving in its clip. Only the first passes.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_tails.py

It prints each case's report and `TAILS TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import tails  # noqa: E402

RINGS = 12
RADIUS = 0.04
HIPS = Vector((0.0, 0.2, 0.5))
# Where each tail runs to, from the hips.
TIPS = (Vector((-1.0, 0.6, 1.0)), Vector((0.0, 0.8, 1.4)), Vector((1.0, 0.6, 1.0)))
# (name, whether each tail has its own chain, whether its clip moves them, how many tails the model
# says it has, whether it passes)
CASES = (
    ("own chains", True, True, 3, True),
    ("one chain for all", False, True, 3, False),
    ("still in a clip", True, False, 3, False),
    ("a tail short", True, True, 4, False),
)


def _ring(centre):
    return [centre + Vector((x, 0.0, z)) for x, z in ((RADIUS, 0.0), (0.0, RADIUS), (-RADIUS, 0.0), (0.0, -RADIUS))]


def _beast():
    """The mesh's vertices and edges, the vertices along each tail by ring, from the hips to the tip."""
    points, edges = [], []

    def tube(start, end, rings, first=None):
        made = []
        for index in range(rings):
            ring = _ring(start.lerp(end, (index + 1) / rings))
            base = len(points)
            points.extend(ring)
            edges.extend((base + corner, base + (corner + 1) % 4) for corner in range(4))
            made.append(list(range(base, base + 4)))
            if first is not None:
                edges.extend((a, b) for a, b in zip(first, made[-1]))
            first = made[-1]
        return made

    hub = tube(Vector((0.0, -0.8, 0.5)), HIPS, 8)[-1]
    return points, edges, [tube(HIPS, tip, RINGS, hub) for tip in TIPS]


def _model(own, moves):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    points, edges, rows = _beast()
    mesh = bpy.data.meshes.new("beast")
    mesh.from_pydata([tuple(point) for point in points], edges, [])
    skin = bpy.data.objects.new("beast", mesh)
    bpy.context.scene.collection.objects.link(skin)
    armature = bpy.data.objects.new("rig", bpy.data.armatures.new("rig"))
    bpy.context.scene.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    hips = armature.data.edit_bones.new("hips")
    hips.head, hips.tail = HIPS, HIPS + Vector((0.0, -0.5, 0.0))
    chains = []
    for number, tip in enumerate(TIPS if own else TIPS[:1]):
        parent, names = hips, []
        for index in range(4):
            bone = armature.data.edit_bones.new("tail_%d_%d" % (number, index))
            bone.head, bone.tail = HIPS.lerp(tip, index / 4.0), HIPS.lerp(tip, (index + 1) / 4.0)
            bone.parent, parent = parent, bone
            names.append(bone.name)
        chains.append(names)
    bpy.ops.object.mode_set(mode="OBJECT")
    skin.parent = armature
    skin.modifiers.new("rig", "ARMATURE").object = armature
    for name in ["hips"] + [name for names in chains for name in names]:
        skin.vertex_groups.new(name=name)
    tailed = {index for row in rows for ring in row for index in ring}
    skin.vertex_groups["hips"].add([index for index in range(len(points)) if index not in tailed], 1.0, "REPLACE")
    for number, row in enumerate(rows):
        names = chains[number if own else 0]
        for at, ring in enumerate(row):
            skin.vertex_groups[names[at * len(names) // len(row)]].add(ring, 1.0, "REPLACE")
    armature.animation_data_create()
    action = bpy.data.actions.new("Idle")
    armature.animation_data.action = action
    for frame in (1, 10, 20):
        for names in chains:
            bone = armature.pose.bones[names[0]]
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = (1.0, 0.3 if moves and frame == 10 else 0.0, 0.0, 0.0)
            bone.keyframe_insert("rotation_quaternion", frame=frame)
    armature.animation_data.action = None
    return armature


def main():
    passed = True
    for name, own, moves, count, expected in CASES:
        rig = _model(own, moves)
        lines, ok = tails.report(rig, bpy.data.objects, count)
        for line in lines:
            log.info("%s: %s" % (name, line))
        if ok != expected:
            passed = False
            log.error("%s: the check said %s, not %s" % (name, ok, expected))
    log.info("TAILS TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
