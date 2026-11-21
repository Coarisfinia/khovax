"""Tests lib/footprint.py's judgement on models built here (#1641): boxes standing on the hex,
each as a monster (rigged, with a Walk clip) or a prop (rigged with only an Idle clip, or static),
inside their hex or too big for it, and static boxes on the edge between two hexes (#1907), which
fit both or reach past them. The ones that fit pass; an oversized one fails whatever it
is, and a prop whose clip spreads past the hex's edge fails, even one it calls Attack, though a
monster may do so (props have limits of their own, never an exemption).

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python src/game-models/test_footprint.py

A crowned tile decoration (#1999) is a static trunk box and a crown box above it, named as the
game finds the crown: the trunk within its hex and the crown within the ring around it pass; a
trunk too big for its hex, a crown past the ring, one pushed past it by how far the decoration
may stand off its tile's middle, and a model without a crown fail.

It also reads a pack's model's views from a small Godot project of its own (lib/views.py, #1652):
views naming its id in the default resource pack (#1864) at a scale, one through another class's
constants. It prints each model's report and `FOOTPRINT TEST: PASS` or `FAIL` (and exits 1
on a fail)."""

import os
import sys
import tempfile

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import footprint, views  # noqa: E402

# A square box `width` metres across reaches width / 2 * (cos 30° + sin 30°) / the inradius of
# the hex: 1.10 m reaches 0.87 (inside), 2.0 m reaches 1.58 (far past it).
FITS, OVERSIZED = 1.10, 2.0
# How much a clip widens the fitting box: 1.18 times reaches 1.02, past a prop's clip limit (1.00)
# but within a monster's (1.05).
SPREAD = 1.18

# A trunk thin enough to stay in its hex when its decoration stands off its tile's middle.
THIN = 0.5

# How much a figure's standing clip shrinks the oversized box: to the fitting box's width, the
# way a figure's idle pose draws in its T-pose's arms.
STANDS = FITS / OVERSIZED

# Name: (box width, clips as {name: how much it widens}, or None for a static model, whether the
# check passes it, and optionally the clips a view plays (None for every clip) and the clip it
# stands in, as check_footprint.py passes them for a pack's model, #1652).
MODELS = {
    "monster_fits": (FITS, {"Walk": SPREAD}, True),
    "monster_oversized": (OVERSIZED, {"Walk": 1.0}, False),
    "prop_fits": (FITS, {"Idle": 1.0}, True),
    "prop_oversized": (OVERSIZED, {"Idle": 1.0}, False),
    "prop_spreads": (FITS, {"Idle": SPREAD}, False),
    "prop_attacks": (FITS, {"Attack": SPREAD}, False),
    "static_fits": (FITS, None, True),
    "static_oversized": (OVERSIZED, None, False),
    "figure_stands": (OVERSIZED, {"Idle": STANDS}, True, ["Idle"], "Idle"),
    "figure_plays_only_its_clips": (OVERSIZED, {"Idle": STANDS, "Spin": 1.0}, True, ["Idle"], "Idle"),
    "figure_plays_its_clips": (OVERSIZED, {"Idle": STANDS, "Spin": 1.0}, False, ["Idle", "Spin"], "Idle"),
    "figure_plays_none": (FITS, {"Idle": SPREAD}, True, [], None),
    "figure_lacks_a_clip": (FITS, {"Idle": 1.0}, False, ["Run"], None),
    "figure_lacks_its_stance": (FITS, {"Idle": 1.0}, False, None, "Stand"),
}

# Pieces on the edge between two hexes (#1907), static boxes `length` along X (the line between the
# hexes' centres) and `depth` along Y, centred on the shared edge's middle: (length, depth, whether
# two hexes pass it, whether one hex does). 2.6 by 0.6 reaches 0.75 of two hexes but 1.47 of one;
# 3.6 long reaches past both hexes' far edges (1.04) and 2.0 deep past the notches at the shared
# edge's ends (2.00). 1.6 by 1.2 has its corners inside (0.71), but its edges cross those notches
# (1.20 there), so it fails though no vertex lies outside; so does a box that fits one hex, stood
# on the shared edge (1.10).
TWO_HEXES = {
    "two_hexes_fits": (2.6, 0.6, True, False),
    "two_hexes_too_long": (3.6, 0.6, False, False),
    "two_hexes_too_deep": (2.6, 2.0, False, False),
    "two_hexes_across_the_notch": (1.6, 1.2, False, False),
    "two_hexes_one_hex_box": (FITS, FITS, False, True),
}

# Crowned decorations (#1999): (trunk width, crown width or None for no crown, rings, metres off
# the tile's middle, whether the check passes it), each box square. A 3.0 m crown reaches 2.37 of
# the hex, within one ring (2.95); 4.0 m reaches 3.15, past it; 3.4 m reaches 2.68, and 0.3 m off
# the middle (0.35 of the hex) pushes it to 3.03, past the ring, though two rings (4.95) still
# hold it. A thin trunk (0.5 m, 0.39) stays within its hex that far off.
CROWNED = {
    "crowned_fits": (FITS, 3.0, 1, 0.0, True),
    "crowned_trunk_oversized": (OVERSIZED, 3.0, 1, 0.0, False),
    "crowned_crown_past_its_ring": (FITS, 4.0, 1, 0.0, False),
    "crowned_off_its_middle": (THIN, 3.4, 1, 0.3, False),
    "crowned_off_its_middle_two_rings": (THIN, 3.4, 2, 0.3, True),
    "crowned_without_a_crown": (FITS, None, 1, 0.0, False),
}


def box(width, depth=None):
    """A box mesh `width` metres across (along X) and `depth` deep (along Y, `width` when None),
    standing on the ground at the hex's centre."""
    mesh = bpy.data.meshes.new("box")
    built = bmesh.new()
    shape = Matrix.Diagonal(Vector((1.0, (width if depth is None else depth) / width, 1.0, 1.0)))
    bmesh.ops.create_cube(built, size=width, matrix=Matrix.Translation(Vector((0, 0, width / 2.0))) @ shape)
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
        for frame, share in ((1, 1.0 if widen >= 1.0 else widen), (5, widen)):
            pose.scale = Vector((share, 1.0, share))
            pose.keyframe_insert("scale", frame=frame)
    pose.scale = Vector((1.0, 1.0, 1.0))
    return rig, [skin]


def crowned(trunk, crown):
    """A crowned decoration in an empty scene: a trunk box and, unless `crown` is None, a crown box
    `crown` metres across standing on the trunk's top. Returns its meshes."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    meshes = [box(trunk)]
    meshes[0].name = "Trunk"
    if crown is not None:
        top = box(crown)
        top.data.transform(Matrix.Scale(0.25, 4, Vector((0.0, 0.0, 1.0))))
        top.location = (0.0, 0.0, trunk)
        top.name = footprint.CROWN
        meshes.append(top)
    bpy.context.view_layer.update()
    return meshes


# A tiny Godot project: a figure view with its constants (a list over lines, with comments) and its
# model's id, a person view showing the same model through the figure's constants at its own scale,
# a chest view at a scale sharing the figure's hidden parts, a tool naming a model (no view), and
# the default resource pack's manifest, which gives each id its .glb (#1864).
PROJECT = {
    "slices/figures/look/figure_view.gd": (
        'class_name FigureView\n'
        'const MODEL: String = "model_figure"\n'
        'const MODEL_SCALE: float = 2.0\n'
        'const IDLE: StringName = &"Idle"\n'
        'const MOVE: StringName = &"Run"  # moving\n'
        'const CLIPS: Array[StringName] = [\n\tIDLE,  # standing, still\n\tMOVE,  # "moving", running\n]\n'
        'const HIDDEN_PARTS: Array[String] = [\n\t"Knife",\n\t"Bow",\n]\n'),
    "slices/people/look/person_view.gd": (
        'const MODEL: String = FigureView.MODEL\n'
        'const MODEL_SCALE: float = 1.5\n'
        'const CLIPS: Array[StringName] = FigureView.CLIPS\n'
        'func _stand() -> void:\n\tplay(FigureView.IDLE)\n'
        '\tfor part: String in FigureView.HIDDEN_PARTS:\n\t\tpass\n'),
    "slices/chests/look/chest_view.gd": (
        'const MODEL: String = "model_chest"\n'
        'const MODEL_SCALE: float = 0.5\n'
        'const CLIPS: Array[StringName] = []\n'
        'func _hide() -> void:\n\tfor part: String in FigureView.HIDDEN_PARTS:\n\t\tpass\n'),
    "tools/render_lamp.gd": 'const MODEL: String = "model_lamp"\n',
    "slices/tiles/look/tile_decorations.gd": (
        'class_name TileDecorations\nconst MODEL_SCALE: float = 0.8\nconst OFF_CENTER: float = 0.15\n'),
    # A tree whose crown reaches a ring, drawn at 1.25 times; a pebble's tile without a crown.
    "resourcepacks/default/tiles/grove.jsonc": '// A grove.\n{ "id": "grove", "model": "model_tree", "scale": 125, "reach": 1 }\n',
    "resourcepacks/default/tiles/gravel.jsonc": '{ "id": "gravel", "model": "model_pebble" } // no crown\n',
    "resourcepacks/default/pack.jsonc": (
        "// The tiny project's pack.\n"
        '{ "models": { "model_figure": "assets/figure.glb", "model_chest": "chest.glb",'
        ' "model_lamp": "lamp.glb", "model_pebble": "assets/pebble.glb", "model_tree": "tree.glb" },'
        ' "tiles": { "grove": "tiles/grove.jsonc", "gravel": "tiles/gravel.jsonc" } }\n'),
}
# Per model: what its views read as (name, scale, clips, standing clip, hidden parts).
VIEWS = {
    "figure": [
        ("figure_view", 2.0, ["Idle", "Run"], "Idle", ["Knife", "Bow"]),
        ("person_view", 1.5, ["Idle", "Run"], "Idle", ["Knife", "Bow"]),
    ],
    "chest": [("chest_view", 0.5, [], None, ["Knife", "Bow"])],
    # Only a view in a slice's look/ counts: a tool that names a model is no view.
    "lamp": [],
    "pebble": [],
}
# The crowned decorations TileDecorations draws, as (rings, scale, metres off the middle).
CROWNS = {"tree": (1, 1.0, 0.15)}


def views_read():
    """Whether lib/views.py reads the tiny project's views as `VIEWS` says."""
    passed = True
    with tempfile.TemporaryDirectory() as game:
        for name, text in PROJECT.items():
            os.makedirs(os.path.dirname(os.path.join(game, name)), exist_ok=True)
            with open(os.path.join(game, name), "w", encoding="utf-8") as out:
                out.write(text)
        for model, expected in sorted(VIEWS.items()):
            found = sorted(
                (view.name, view.scale, view.clips, view.standing, view.hidden)
                for view in views.find(game, model))
            log.info("FOOTPRINT test views %s: %s" % (model, found))
            if found != expected:
                passed = False
                log.error("FOOTPRINT test: %s's views should read %s" % (model, expected), __file__)
        found = {name: (crown.rings, round(crown.scale, 6), crown.off_centre)
                 for name, crown in views.crowned(game).items()}
        log.info("FOOTPRINT test crowned decorations: %s" % found)
        if found != CROWNS:
            passed = False
            log.error("FOOTPRINT test: the crowned decorations should read %s" % CROWNS, __file__)
    return passed


def main():
    passed = views_read()
    for name, (width, clips, passes, *view) in sorted(MODELS.items()):
        rig, meshes = build(width, clips)
        played, standing = view or (None, None)
        lines, verdict = footprint.report(rig, meshes, footprint.limits(rig, large=False), played, standing)
        for line in lines:
            log.info("FOOTPRINT test %s %s" % (name, line))
        if verdict != passes:
            passed = False
            log.error("FOOTPRINT test: %s should %s" % (name, "pass" if passes else "fail"), __file__)
    for name, (length, depth, on_two, on_one) in sorted(TWO_HEXES.items()):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        meshes = [box(length, depth)]
        for hexes, passes in ((2, on_two), (1, on_one)):
            lines, verdict = footprint.report(None, meshes, footprint.PROP, hexes=hexes)
            for line in lines:
                log.info("FOOTPRINT test %s on %d hex(es) %s" % (name, hexes, line))
            if verdict != passes:
                passed = False
                log.error("FOOTPRINT test: %s should %s on %d hex(es)" % (
                    name, "pass" if passes else "fail", hexes), __file__)
    for name, (trunk, crown, rings, off_centre, passes) in sorted(CROWNED.items()):
        lines, verdict = footprint.report_crowned(crowned(trunk, crown), rings, off_centre)
        for line in lines:
            log.info("FOOTPRINT test %s %s" % (name, line))
        if verdict != passes:
            passed = False
            log.error("FOOTPRINT test: %s should %s" % (name, "pass" if passes else "fail"), __file__)
    log.info("FOOTPRINT TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
