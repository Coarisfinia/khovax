"""Ground contact: nothing a clip poses may sink into the ground (z = 0 at the origin, where the
game stands the model on its tile). `lowest` measures a pose, `settle` lifts the root wherever a
clip's pose sinks, eased, and `report` samples every frame of every clip, for check_ground.py."""

import bpy

# How far above the ground (metres) a pose's lowest point is lifted to: room for the export's
# resampling.
CLEARANCE = 0.005
# The words that name a foot bone in any rig: paws, feet, hooves.
FOOT_WORDS = ("paw", "foot", "hoof")


def foot_bones(rig, words=FOOT_WORDS):
    return [bone.name for bone in rig.pose.bones if any(word in bone.name.lower() for word in words)]


def skinned(objects):
    """The meshes an armature deforms (not, say, an importer's bone display shapes)."""
    return [obj for obj in objects if obj.type == "MESH" and any(m.type == "ARMATURE" for m in obj.modifiers)]


def owned(obj, bones):
    """Per bone, the vertices of `obj` it moves most: its part of the mesh (a paw and its claws)."""
    names = {group.index: group.name for group in obj.vertex_groups}
    found = {name: [] for name in bones}
    for vertex in obj.data.vertices:
        if vertex.groups:
            top = max(vertex.groups, key=lambda g: g.weight)
            name = names.get(top.group)
            if name in found:
                found[name].append(vertex.index)
    return found


def lowest(rig, meshes, bones, ignore=()):
    """The lowest point of the deformed `meshes` (but for the parts the bones in `ignore` move
    most), and of the part of them each bone in `bones` moves most (a paw), in world z."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    low = float("inf")
    feet = {name: float("inf") for name in bones}
    for obj in meshes:
        parts = owned(obj, bones)
        skipped = {index for indices in owned(obj, ignore).values() for index in indices}
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        world = evaluated.matrix_world
        heights = [(world @ vertex.co).z for vertex in mesh.vertices]
        low = min([low] + [height for index, height in enumerate(heights) if index not in skipped])
        for name, indices in parts.items():
            feet[name] = min([feet[name]] + [heights[index] for index in indices])
        evaluated.to_mesh_clear()
    return low, feet


def envelope(needs, spread, loop):
    """A smooth curve never below `needs`: each value raised to the largest within `spread`
    frames, then averaged over as many, so a lift eases in and out instead of kinking. A loop
    wraps around its seam (its last frame is its first)."""
    count = len(needs) - 1 if loop else len(needs)

    def at(values, index):
        if loop:
            return values[index % count]
        return values[min(max(index, 0), count - 1)]

    widest = [max(at(needs, index + shift) for shift in range(-spread, spread + 1)) for index in range(count)]
    smooth = [sum(at(widest, index + shift) for shift in range(-spread, spread + 1)) / (2 * spread + 1)
              for index in range(count)]
    return smooth + smooth[:1] if loop else smooth


def settle(rig, meshes, root, frames, loop=False, up=1, clearance=None, spread=2, ignore=()):
    """Lifts `root` (its location's `up` axis, keyed on every one of `frames` of the active action)
    wherever the mesh would sink below the ground, so its lowest point rests `clearance` above it
    (room for the export's resampling). The lift eases in and out over `spread` frames either
    side, so the body doesn't jerk up; the root only moves the whole body, so one pass does it.
    The parts the bones in `ignore` move most don't count (planted paws, which the root doesn't
    move). Returns the lift on each frame."""
    scene = bpy.context.scene
    clearance = CLEARANCE if clearance is None else clearance
    needs = []
    for frame in frames:
        scene.frame_set(frame)
        low, _feet = lowest(rig, meshes, [], ignore)
        needs.append(max(0.0, clearance - low))
    bone = rig.pose.bones[root]
    lifts = envelope(needs, spread, loop)
    for frame, lift in zip(frames, lifts):
        if lift > 0.0:
            scene.frame_set(frame)
            bone.location[up] += lift
            bone.keyframe_insert("location", frame=frame)
    return lifts


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
