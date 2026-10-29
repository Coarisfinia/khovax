"""Tests lib/footprint.py's judgement on models built here (#1641): boxes standing on the hex,
each as a monster (rigged, with a Walk clip) or a prop (rigged with only an Idle clip, or static),
inside their hex or too big for it. The ones that fit pass; an oversized one fails whatever it
is, and a prop whose clip spreads past the hex's edge fails, even one it calls Attack, though a
monster may do so (props have limits of their own, never an exemption).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_footprint.py

It also reads a pack's model's views from a small Godot project of its own (lib/views.py, #1652):
a script that preloads it at a scale, and a scene that instances it under a view using another
class's constants. It prints each model's report and `FOOTPRINT TEST: PASS` or `FAIL` (and exits 1
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


# A tiny Godot project: a figure view with its constants, a chest view that preloads its model at a
# scale and shares the figure's hidden parts, and a scene that instances the figure under the view.
PROJECT = {
    "figure_view.gd": (
        'class_name FigureView\n'
        'const IDLE: StringName = &"Idle"\n'
        'const MOVE: StringName = &"Run"  # moving\n'
        'const CLIPS: Array[StringName] = [IDLE, MOVE]\n'
        'const HIDDEN_PARTS: Array[String] = [\n\t"Knife",\n\t"Bow",\n]\n'),
    "chest_view.gd": (
        'const MODEL: PackedScene = preload("res://assets/chest.glb")\n'
        'const MODEL_SCALE: float = 0.5\n'
        'func _hide() -> void:\n\tfor part: String in FigureView.HIDDEN_PARTS:\n\t\tpass\n'),
    "main.tscn": (
        '[ext_resource type="Script" path="res://figure_view.gd" id="1_view"]\n'
        '[ext_resource type="PackedScene" path="res://assets/figure.glb" id="2_figure"]\n\n'
        '[node name="Main" type="Node3D"]\n\n'
        '[node name="Player" type="Node3D" parent="."]\nscript = ExtResource("1_view")\n\n'
        '[node name="Model" parent="Player" instance=ExtResource("2_figure")]\n'
        'transform = Transform3D(2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0)\n'),
}
# Per model: what its views read as (name, scale, clips, standing clip, hidden parts).
VIEWS = {
    "figure": [("figure_view", 2.0, ["Idle", "Run"], "Idle", ["Knife", "Bow"])],
    "chest": [("chest_view", 0.5, [], None, ["Knife", "Bow"])],
    "pebble": [],
}


def views_read():
    """Whether lib/views.py reads the tiny project's views as `VIEWS` says."""
    passed = True
    with tempfile.TemporaryDirectory() as game:
        for name, text in PROJECT.items():
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
    return passed


def main():
    passed = views_read()
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
