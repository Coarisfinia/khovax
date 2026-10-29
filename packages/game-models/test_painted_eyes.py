"""Tests lib/marked_eyes.py's `painted`, which check_painted_eyes.py runs (#1688), on a textured
ball for a head: two flat black ovals or two glowing ones painted on its texture fail; a plain
texture passes, and so does one where our own eyes sit (pieces of plain dark colour joined in,
whose texels on the texture are black too), since only the texture's own faces count.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_painted_eyes.py

It prints each case and `PAINTED EYES TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import marked_eyes  # noqa: E402

# The head: a ball this big, its texture this many texels square.
RADIUS, SIZE = 0.5, 256
# The skin's colour, a painted eye's flat black and its glow (sRGB).
SKIN, BLACK, GLOW = (0.55, 0.4, 0.3), (0.05, 0.05, 0.05), (1.0, 0.6, 0.1)
# Where the left eye sits (the model faces -Y, its left is +X; the right one mirrors it), and how
# far around it the paint reaches.
EYE, EYE_RADIUS = Vector((0.35, -1.0, 0.3)).normalized() * RADIUS, 0.09

# Name: (the paint on the eyes, or None, whether our eyes are joined in, whether the check passes it).
CASES = {
    "plain": (None, False, True),
    "black_ovals": (BLACK, False, False),
    "glowing_eyes": (GLOW, False, False),
    "our_eyes": (None, True, True),
}


def material(name, image=None, colour=(0.0, 0.0, 0.0)):
    """A material whose base colour is `image`, or the plain `colour`."""
    made = bpy.data.materials.new(name)
    shader = made.node_tree.nodes["Principled BSDF"]
    if image is None:
        shader.inputs["Base Color"].default_value = colour + (1.0,)
    else:
        node = made.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        made.node_tree.links.new(node.outputs["Color"], shader.inputs["Base Color"])
    return made


def ball(name, radius, at):
    """A UV ball mesh object of `radius` at `at`, its every vertex weighted to "head"."""
    mesh = bpy.data.meshes.new(name)
    built = bmesh.new()
    built.loops.layers.uv.new("UVMap")
    bmesh.ops.create_uvsphere(built, u_segments=64, v_segments=32, radius=radius, calc_uvs=True)
    built.to_mesh(mesh)
    built.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = at
    bpy.context.scene.collection.objects.link(obj)
    obj.vertex_groups.new(name="head").add(range(len(mesh.vertices)), 1.0, "REPLACE")
    return obj


def build(paint, ours):
    """The head: a ball with its texture, `paint` laid over both eyes' spots on it (or nothing),
    and our eyes joined in when `ours`, their UVs on a black texel of the texture."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    image = bpy.data.images.new("skin", SIZE, SIZE)
    pixels = numpy.empty((SIZE, SIZE, 4), dtype=numpy.float32)
    pixels[:, :] = SKIN + (1.0,)
    pixels[0, 0] = BLACK + (1.0,)
    image.pixels.foreach_set(pixels.ravel())
    skin = ball("Head", RADIUS, (0.0, 0.0, 0.0))
    skin.data.materials.append(material("skin", image))
    if paint is not None:
        head = marked_eyes.Head(skin, "head")
        rows, columns, spots = marked_eyes._texels(head, numpy.ones(len(head.spots), dtype=bool))
        for eye in (EYE, Vector((-EYE.x, EYE.y, EYE.z))):
            inside = numpy.sqrt(((spots - numpy.array(eye)) ** 2).sum(axis=1)) <= EYE_RADIUS
            head.pixels[rows[inside], columns[inside], :3] = paint
        image.pixels.foreach_set(head.pixels.ravel())
    if ours:
        dark = material("dark", colour=BLACK)
        pieces = [ball("Eye", EYE_RADIUS, eye) for eye in (EYE, Vector((-EYE.x, EYE.y, EYE.z)))]
        for piece in pieces:
            piece.data.materials.append(dark)
            for loop in piece.data.uv_layers.active.data:
                loop.uv = (0.5 / SIZE, 0.5 / SIZE)
        bpy.ops.object.select_all(action="DESELECT")
        for piece in pieces:
            piece.select_set(True)
        skin.select_set(True)
        bpy.context.view_layer.objects.active = skin
        bpy.ops.object.join()
    return skin


def main():
    passed = True
    for name, (paint, ours, passes) in CASES.items():
        found = marked_eyes.painted(build(paint, ours))
        ok = (not found) == passes
        passed = passed and ok
        line = "%s %s: %s, %s" % ("ok" if ok else "FAIL", name, "found " + ", ".join(sorted(found)) if found
                                  else "nothing found", "should pass" if passes else "should fail")
        (log.info if ok else log.error)(line)
    log.info("PAINTED EYES TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
