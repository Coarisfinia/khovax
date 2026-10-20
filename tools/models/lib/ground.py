"""Ground contact: nothing a clip poses may sink into the ground (z = 0 at the origin, where the
game stands the model on its tile). `lowest` measures a pose, `settle` lifts the root wherever a
clip's pose sinks, and `report` samples every frame of every clip, for check_ground.py."""

import bpy

# The words that name a foot bone in any rig: paws, feet, hooves.
FOOT_WORDS = ("paw", "foot", "hoof")
# How often settle may go over a clip before it gives up: each pass only adds keys where a frame
# still sinks, so it settles in one or two.
MAX_PASSES = 8


def foot_bones(rig, words=FOOT_WORDS):
    return [bone.name for bone in rig.pose.bones if any(word in bone.name.lower() for word in words)]


def skinned(objects):
    """The meshes an armature deforms (not, say, an importer's bone display shapes)."""
    return [obj for obj in objects if obj.type == "MESH" and any(m.type == "ARMATURE" for m in obj.modifiers)]


def _owned(obj, bones):
    """Per bone, the vertices of `obj` it moves most: its part of the mesh (a paw and its claws)."""
    names = {group.index: group.name for group in obj.vertex_groups}
    owned = {name: [] for name in bones}
    for vertex in obj.data.vertices:
        if vertex.groups:
            top = max(vertex.groups, key=lambda g: g.weight)
            name = names.get(top.group)
            if name in owned:
                owned[name].append(vertex.index)
    return owned


def lowest(rig, meshes, bones):
    """The lowest point of the deformed `meshes`, and of the part of them each bone in `bones`
    moves most (a paw), in world z."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    low = float("inf")
    feet = {name: float("inf") for name in bones}
    for obj in meshes:
        owned = _owned(obj, bones)
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        world = evaluated.matrix_world
        heights = [(world @ vertex.co).z for vertex in mesh.vertices]
        low = min([low] + heights)
        for name, indices in owned.items():
            feet[name] = min([feet[name]] + [heights[index] for index in indices])
        evaluated.to_mesh_clear()
    return low, feet


def settle(rig, meshes, root, frames, up=1, clearance=0.005):
    """Lifts `root` (its location's `up` axis) and keys it at every frame of the active action
    where the mesh sinks below the ground, so the lowest point rests `clearance` above it (room for
    the export's resampling, which can dip a few millimetres between keys). A new key reshapes
    the curve between its neighbours, so it repeats until no frame sinks."""
    scene = bpy.context.scene
    for _pass in range(MAX_PASSES):
        lifted = False
        for frame in frames:
            scene.frame_set(frame)
            low, _feet = lowest(rig, meshes, [])
            if low < 0.0:
                lifted = True
                bone = rig.pose.bones[root]
                bone.location[up] += clearance - low
                bone.keyframe_insert("location", frame=frame)
        if not lifted:
            return
    raise RuntimeError("%s still sinks after %d passes" % (rig.animation_data.action.name, MAX_PASSES))


def report(rig, meshes, tolerance):
    """For every action: the lowest mesh point and each foot's (the part of the mesh its foot bone
    moves most; an imported rig's bone tails are guesses, so the mesh is what's measured) over all
    its frames, and whether anything sinks deeper than `tolerance`. Returns (lines, passed)."""
    scene = bpy.context.scene
    feet_names = foot_bones(rig)
    rig.animation_data.use_nla = False
    lines = []
    passed = True
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        rig.animation_data.action = action
        if action.slots:
            rig.animation_data.action_slot = action.slots[0]
        start, end = (int(round(value)) for value in action.frame_range)
        mesh_low = float("inf")
        feet_low = {name: float("inf") for name in feet_names}
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            low, feet = lowest(rig, meshes, feet_names)
            mesh_low = min(mesh_low, low)
            for name, z in feet.items():
                feet_low[name] = min(feet_low[name], z)
        # A foot that moves no part of the mesh can't be measured: that fails too, rather than
        # passing unseen.
        unmeasured = any(z == float("inf") for z in feet_low.values())
        sinks = unmeasured or mesh_low < -tolerance or any(z < -tolerance for z in feet_low.values())
        passed = passed and not sinks
        feet_text = ", ".join("%s %.3f" % (name, z) for name, z in sorted(feet_low.items()))
        lines.append("%s %s: mesh %.3f; %s" % ("SINKS" if sinks else "ok", action.name, mesh_low, feet_text))
    return lines, passed
