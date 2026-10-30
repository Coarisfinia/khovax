"""A model's .glb read back into Blender as the game imports it, for the checks and plots: its
clip rate and its looping clips from the Godot .import beside it, and its clips one at a time."""

import re

import bpy


def settings(glb):
    """The clip rate and the names of the looping clips, from the .import file beside the model."""
    fps, loops, clip = 30, set(), None
    with open(glb + ".import", encoding="utf-8") as lines:
        for line in lines:
            line = line.strip()
            rate = re.match(r"animation/fps=(\d+)", line)
            if rate:
                fps = int(rate.group(1))
            name = re.match(r'^"([^"/]+)": \{$', line)
            if name:
                clip = name.group(1)
            mode = re.match(r'^"settings/loop_mode": (\d+)', line)
            if mode and clip and int(mode.group(1)) != 0:
                loops.add(clip)
    return fps, loops


def load(glb, fps):
    """Imports the model into an empty scene at the clip rate (the importer turns the clips'
    seconds into frames at the scene's rate) and returns its armature."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = fps
    bpy.ops.import_scene.gltf(filepath=glb)
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    rig.animation_data.use_nla = False
    return rig


def load_view(glb, fps, scale=1.0):
    """The model in an empty scene at the clip rate, drawn at `scale` as a view's node would, and
    its armature (None for a static one)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = fps
    bpy.ops.import_scene.gltf(filepath=glb)
    if scale != 1.0:
        holder = bpy.data.objects.new("view", None)
        bpy.context.scene.collection.objects.link(holder)
        holder.scale = (scale, scale, scale)
        for obj in bpy.data.objects:
            if obj.parent is None and obj is not holder:
                obj.parent = holder
        bpy.context.view_layer.update()
    rig = next((obj for obj in bpy.data.objects if obj.type == "ARMATURE"), None)
    if rig is not None and rig.animation_data is not None:
        rig.animation_data.use_nla = False
    return rig


def play(rig, action):
    """Puts `action` on the rig and returns its first and last frames."""
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    start, end = (int(round(value)) for value in action.frame_range)
    return start, end
