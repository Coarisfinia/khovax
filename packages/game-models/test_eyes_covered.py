"""Tests lib/covered.py, which check_eyes_covered.py runs (#1758), on a ball for a head with our
eyes (eyes.eye, with brows and lids in the ball's own material, as a hand-built beast has them)
set clear of its skin as marked_eyes.clear sets them with `rim`: they pass. Planted cases fail: the eyes
pushed half their size into the ball, so the skin cuts across them, and a loose patch of skin (an
open surface, as a generated model's loose pieces are) lying over the lower half of an eye, as on
the Wobulumu (#1747), or a loose closed lump of it there, which only a brow over the eye may be.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_eyes_covered.py

It prints each case and `EYES COVERED TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

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
from lib import attachments, covered, eyes, marked_eyes, scene  # noqa: E402

# The head: a ball this big; our eye this big, where the left one sits (the model faces -Y, its
# left is +X; the right one mirrors it).
RADIUS, SIZE = 0.5, 0.06
EYE = Vector((0.35, -1.0, 0.3)).normalized() * RADIUS
# The check's tolerance, as check_eyes_covered.py's default.
TOLERANCE = 0.01
# Name: (how far the eyes are pushed into the ball, in their size; the loose piece of skin lying
# over the left one's lower half, if any: "open" a patch, "closed" a lump; whether the check
# passes it).
CASES = {
    "clear": (0.0, None, True),
    "pushed_in": (0.5, None, False),
    "loose_patch": (0.0, "open", False),
    "loose_lump": (0.0, "closed", False),
}


def material(name, colour):
    made = bpy.data.materials.new(name)
    made.diffuse_color = colour
    return made


def patch(at, look, size, mat, kind):
    """A loose piece of skin `size` across, its own island, a little in front of the eye at `at`
    and over its lower half: an "open" flat square facing the way the eye looks, or a "closed"
    ball, which a brow is too, but under the eye."""
    mesh = bpy.data.meshes.new("Patch")
    built = bmesh.new()
    if kind == "open":
        bmesh.ops.create_grid(built, x_segments=4, y_segments=4, size=size / 2.0)
    else:
        bmesh.ops.create_uvsphere(built, u_segments=12, v_segments=6, radius=size / 3.0)
    built.to_mesh(mesh)
    built.free()
    turn = look.to_track_quat("Z", "Y").to_matrix().to_4x4()
    mesh.transform(Matrix.Translation(at + look * SIZE * 0.8 - Vector((0.0, 0.0, size * 0.4))) @ turn)
    obj = bpy.data.objects.new("Patch", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.vertex_groups.new(name="head").add(range(len(mesh.vertices)), 1.0, "REPLACE")
    return obj


def build(pushed, loose):
    """The ball with our eyes, pushed `pushed` of their size into it, and with `loose`, a loose
    piece of skin of that kind over the left one; returns the rig and the skin."""
    scene.reset(30)
    bpy.ops.object.armature_add(location=(0.0, 0.0, 0.0))
    rig = bpy.context.object
    rig.name = "Rig"
    bpy.ops.object.mode_set(mode="EDIT")
    rig.data.edit_bones[0].name = "head"
    bpy.ops.object.mode_set(mode="OBJECT")
    mats = {"dark": material("dark", (0.02, 0.02, 0.02, 1.0)), "glow": material("glow", (1.0, 0.8, 0.2, 1.0)),
            "skin": material("skin", (0.5, 0.4, 0.3, 1.0))}
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=RADIUS)
    skin = bpy.context.object
    skin.name = "Skin"
    skin.data.materials.append(mats["skin"])
    skin.vertex_groups.new(name="head").add(range(len(skin.data.vertices)), 1.0, "REPLACE")
    left = eyes.eye(skin, "Eye.L", tuple(EYE), marked_eyes.FORWARD, SIZE, mats, "head", lid=eyes.LID + "L",
                    pupil=(0.4, 0.5), brow_size=0.4)
    marked_eyes.clear(skin, left, SIZE, rim=True)
    look = eyes.look(left)
    for piece in left:
        piece.location -= look * SIZE * pushed
        if "hinge" in piece:
            piece["hinge"] = tuple(Vector(piece["hinge"]) - look * SIZE * pushed)
    bpy.context.view_layer.update()
    pieces = left + eyes.mirrored(left)
    points = {}
    for side in ("L", "R"):
        mine = [piece for piece in pieces if piece.name.startswith("Eye.%s." % side)]
        points[side] = (tuple(eyes.spot(mine)), "head", tuple(eyes.look(mine)))
    eyes.Lids(rig, pieces, "head", (0, 1))
    if loose:
        pieces.append(patch(eyes.spot(left), look, SIZE * 1.6, mats["skin"], loose))
    scene.select_only(skin)
    for piece in pieces:
        piece.select_set(True)
    bpy.ops.object.join()
    attachments.add(rig, points, [((0.0, -RADIUS, 0.0), "head")])
    return rig, skin


def main():
    passed = True
    for name, (pushed, loose, passes) in CASES.items():
        rig, skin = build(pushed, loose)
        lines, ok = covered.report(rig, [skin], TOLERANCE)
        good = ok == passes
        passed = passed and good
        say = log.info if good else log.error
        say("%s %s: %s, expected to %s" % ("ok" if good else "FAIL", name, "; ".join(lines),
                                             "pass" if passes else "fail"))
    log.info("EYES COVERED TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
