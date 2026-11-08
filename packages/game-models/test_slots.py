"""Tests that the model tools play the slot of a clip that the rig plays (#2145), as check_motion.py
does (lib/imported.py's `slot`), on a clip whose first slot is another object's: one glTF animation
that moves an empty and a rig imports as one action with a slot each, the empty's first.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_slots.py

- ground: the rig's slot lowers its body into the ground, so check_ground.py's report says it
  sinks; with the empty's slot on, the rig would stand still and pass.
- planted feet: a standing clip plays on the rig in the rig's slot while its feet are planted.
- clip sources: a clip source's clip goes into a clip library on the slot its rig played; stashing
  a clip with several slots picks the rig's; a clip that never moves the rig doesn't load (#2152),
  nor does a second animation that moves only another object (#2159).

It prints each case and `SLOT TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import os
import sys
import tempfile

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import clip_sources, ground, planted_feet  # noqa: E402


def rig(name):
    """An armature of one upright bone, 10 cm long, standing on the ground."""
    armature = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, armature)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bone = armature.edit_bones.new("body")
    bone.head, bone.tail = (0.0, 0.0, 0.0), (0.0, 0.0, 0.1)
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def model(glb, rig_moves=True, empty_clip=None):
    """Exports to `glb` an empty and a rig skinning a 10 cm box, and one clip, Sink, moving both:
    the empty sideways, the rig's bone 5 cm down, so the box sinks into the ground. The importer
    lists the objects by name, so the empty's slot comes first. Without `rig_moves`, the clip moves
    the empty alone. With `empty_clip`, the empty's keys are a second animation of that name."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    holder = bpy.data.objects.new("a_holder", None)
    bpy.context.scene.collection.objects.link(holder)
    body = rig("b_rig")
    bpy.ops.mesh.primitive_cube_add(size=0.1, location=(0.0, 0.0, 0.05))
    box = bpy.context.active_object
    box.vertex_groups.new(name="body").add(list(range(len(box.data.vertices))), 1.0, "REPLACE")
    box.modifiers.new("Armature", "ARMATURE").object = body
    box.parent = body
    action = bpy.data.actions.new("Sink")
    moved = [(holder, holder, 0, 0.1)]
    if rig_moves:
        moved.append((body, body.pose.bones["body"], 1, -0.05))
    for obj, target, axis, far in moved:
        obj.animation_data_create()
        own_clip = empty_clip and obj is holder
        obj.animation_data.action = bpy.data.actions.new(empty_clip) if own_clip else action
        for frame in (0, 10):
            target.location[axis] = far * frame / 10
            target.keyframe_insert("location", frame=frame)
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_animation_mode="ACTIONS")


def opened(glb):
    """`glb` imported into an empty scene: its rig, its one clip and the rig's slot of it."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    obj = next(found for found in bpy.data.objects if found.type == "ARMATURE")
    action = bpy.data.actions["Sink"]
    own = next(found for found in action.slots if obj in found.users())
    if action.slots[0] == own:
        raise RuntimeError("the rig's slot comes first: the cases would test nothing")
    return obj, action, own


def grounded(glb):
    obj, _action, _own = opened(glb)
    lines, passed = ground.report(obj, ground.skinned(bpy.data.objects), 0.005)
    return not passed, "; ".join(lines)


def planted(glb):
    obj, action, own = opened(glb)
    with planted_feet._playing(obj, action):
        played = obj.animation_data.action_slot
    return played == own, "plays %s, the rig's is %s" % (played.identifier, own.identifier)


def sourced(glb):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    library = rig("library")
    _source, action = clip_sources.load(glb)
    own = next(found for found in action.slots if found.identifier.endswith("b_rig"))
    clip_sources.stash(library, action, "Sink")
    played = library.animation_data.nla_tracks["Sink"].strips[0].action_slot
    return played.identifier == own.identifier, "stashed on %s, the rig's is %s" % (
        played.identifier, own.identifier)


def stashed(glb):
    obj, action, own = opened(glb)
    clip_sources.stash(obj, action, "Stashed")
    played = obj.animation_data.nla_tracks["Stashed"].strips[0].action_slot
    return played == own, "%d slots, stashed on %s, the rig's is %s" % (
        len(action.slots), played.identifier, own.identifier)


def load_refusal(other, names):
    """Whether loading the .glb at `other` fails, naming each of `names`, and the details."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        _source, action = clip_sources.load(other)
    except RuntimeError as error:
        return all(name in str(error) for name in names), str(error)
    return False, "loaded, with clip %s" % (action.name if action else None)


def refused(glb):
    other = os.path.join(os.path.dirname(glb), "empty_only.glb")
    model(other, rig_moves=False)
    return load_refusal(other, ["Sink"])


def second_clip(glb):
    other = os.path.join(os.path.dirname(glb), "two_clips.glb")
    model(other, empty_clip="Drift")
    return load_refusal(other, ["Sink", "Drift"])


# Case: (what it checks, what it does with the model's .glb and returns as (right, details)).
CASES = {
    "ground": ("the ground check measures the rig's slot and says the box sinks", grounded),
    "planted": ("planting a clip's feet plays the rig's slot", planted),
    "sources": ("a clip source's clip is stashed on its rig's slot", sourced),
    "stash": ("stashing a clip with several slots picks the rig's", stashed),
    "no-slot": ("a clip that never moves the rig fails to load, naming the clip", refused),
    "second-clip": ("a second animation moving only another object fails to load, naming both",
                    second_clip),
}


def main():
    passed = True
    with tempfile.TemporaryDirectory() as folder:
        glb = os.path.join(folder, "two_slots.glb")
        model(glb)
        for name, (says, run) in CASES.items():
            right, details = run(glb)
            passed = passed and right
            line = "SLOT TEST %s %s: %s (%s)" % ("ok" if right else "FAIL", name, says, details)
            if right:
                log.info(line)
            else:
                log.error(line)
    log.info("SLOT TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
