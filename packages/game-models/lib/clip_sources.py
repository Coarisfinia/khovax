"""Clip sources (#1935): a rig and one clip, without the body, as import_clip.py takes them from a
Meshy export and a clip library's script (player_clips.py) merges them.

Meshy rigs one clip per export (#1934), each a whole copy of the body. A clip source keeps only
what a clip needs, the rig and its one clip, so the repository holds the body once however many
clips there are. A .glb carries a rig only as a skin, and a skin only on a mesh, so the rig keeps a
stand-in: one small triangle on its root bone, which nothing ever shows."""

import bpy

from lib import scene

# Meshy's clips are keyed at 30 frames a second, the game's clip rate too: imported at another
# rate, the export would sample them between their keys.
FPS = 30
# The stand-in triangle's size, in metres: small, so it never reaches out of the body.
STAND_IN = 0.01


def load(path):
    """Imports the .glb at `path` into the scene and returns its armature and its one clip (None
    when it has none), every other object it brought dropped."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    added = [obj for obj in bpy.data.objects if obj not in before]
    rigs = [obj for obj in added if obj.type == "ARMATURE"]
    if len(rigs) != 1:
        raise RuntimeError("%s: %d armatures, not one" % (path, len(rigs)))
    rig = rigs[0]
    for obj in added:
        if obj is not rig:
            bpy.data.objects.remove(obj, do_unlink=True)
    # The importer draws bones with shapes in a collection of its own.
    for collection in [c for c in bpy.data.collections if not c.objects and not c.children]:
        bpy.data.collections.remove(collection, do_unlink=True)
    data = rig.animation_data
    actions = [strip.action for track in data.nla_tracks for strip in track.strips] if data else []
    if data and data.action and data.action not in actions:
        actions.append(data.action)
    if len(actions) > 1:
        raise RuntimeError("%s: %d clips, not one: a clip source holds one" % (path, len(actions)))
    if data:
        for track in list(data.nla_tracks):
            data.nla_tracks.remove(track)
        data.action = None
    return rig, actions[0] if actions else None


def stash(rig, action, name):
    """Puts `action` on `rig` as the clip `name`: one NLA track, which scene.export_glb exports as
    one animation."""
    action.name = name
    if rig.animation_data is None:
        rig.animation_data_create()
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    start = int(action.frame_range[0])
    strip = track.strips.new(name, start, action)
    strip.name = name
    if action.slots:
        strip.action_slot = action.slots[0]


def stand_in(rig):
    """The stand-in triangle on `rig`'s root bone, skinned to it, so the export keeps the rig as a
    skin."""
    roots = [bone for bone in rig.data.bones if bone.parent is None]
    if len(roots) != 1:
        raise RuntimeError("%s: %d root bones, not one" % (rig.name, len(roots)))
    x, y, z = roots[0].head_local
    mesh = bpy.data.meshes.new("StandIn")
    mesh.from_pydata([(x, y, z), (x + STAND_IN, y, z), (x, y, z + STAND_IN)], [], [(0, 1, 2)])
    obj = bpy.data.objects.new("StandIn", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = rig
    group = obj.vertex_groups.new(name=roots[0].name)
    group.add([0, 1, 2], 1.0, "REPLACE")
    obj.modifiers.new("Armature", "ARMATURE").object = rig
    return obj


def prepare(rig):
    """Readies `rig` and its clips for scene.export_glb: the stand-in triangle on it, its pose at
    rest."""
    stand_in(rig)
    for pose in rig.pose.bones:
        pose.location = (0.0, 0.0, 0.0)
        pose.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose.scale = (1.0, 1.0, 1.0)


def write(rig, path):
    """Exports `rig` and its clips as a clip source (import_clip.py). A clip library's script calls
    prepare and scene.export_glb itself, which is how check_rebuild.py --all finds it."""
    prepare(rig)
    scene.export_glb(path)
