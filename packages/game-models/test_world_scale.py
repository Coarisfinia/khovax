"""Tests lib/world_scale.py's judgement on boxes (#1837): each box stands on the ground as a model of
a kind, sized to it or off its scale. The ones sized to their kind pass; one too tall or too low
fails, and an edge piece that doesn't span its hex edge fails.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_world_scale.py

It prints each box's report and `WORLD SCALE TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

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
from lib import footprint, world_scale  # noqa: E402

PLAYER, WALL, EDGE = world_scale.PLAYER_HEIGHT, world_scale.WALL_HEIGHT, world_scale.HEX_EDGE

# Name: (kind, length along X, height, whether the check passes it).
MODELS = {
    "wall_fits": ("wall", EDGE, WALL, True),
    "wall_too_low": ("wall", EDGE, PLAYER * 0.8, False),
    "wall_too_short": ("wall", EDGE * 0.8, WALL, False),
    "wall_too_long": ("wall", EDGE * 1.2, WALL, False),
    "gate_fits": ("gate", EDGE, PLAYER * 1.2, True),
    "gate_below_the_player": ("gate", EDGE, PLAYER * 0.9, False),
    "portal_below_the_player": ("portal", EDGE * 1.5, PLAYER * 0.6, False),
    "tower_fits": ("tower", EDGE * 0.6, WALL * 1.5, True),
    "tower_below_the_walls": ("tower", EDGE * 0.6, WALL * 0.9, False),
    "prop_fits": ("prop", EDGE * 1.2, PLAYER * 0.5, True),
    "prop_towers_over_the_player": ("prop", EDGE * 1.2, PLAYER * 2.0, False),
    "unknown_kind": ("house", EDGE, WALL, False),
}


def box(length, height):
    """A box `length` long along X, a tenth as deep and `height` tall, standing on the ground."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = bpy.data.meshes.new("box")
    built = bmesh.new()
    shape = Matrix.Diagonal(Vector((length, length / 10.0, height, 1.0)))
    bmesh.ops.create_cube(built, size=1.0, matrix=Matrix.Translation(Vector((0, 0, height / 2.0))) @ shape)
    built.to_mesh(mesh)
    built.free()
    obj = bpy.data.objects.new("box", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    return obj


def main():
    passed = True
    for name, (kind, length, height, expected) in MODELS.items():
        measured = world_scale.bounds(footprint.points([box(length, height)]))
        lines, verdict = world_scale.judge(kind, *measured)
        right = verdict == expected
        passed = passed and right
        for line in lines:
            log.info("WORLD SCALE %s %s" % (name, line))
        if not right:
            log.error("WORLD SCALE %s: the check %s it, but should %s" % (
                name, "passes" if verdict else "fails", "pass" if expected else "fail"))
    log.info("WORLD SCALE TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
