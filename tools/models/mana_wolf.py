"""Builds the mana wolf (#990): a wolf-like quadruped with crystal growths and a glowing accent,
rigged and animated, and exports it as a glTF binary for the game.

Run headless with Blender 5.2 (the model pipeline in AGENTS.md):

    blender --background --factory-startup --python tools/models/mana_wolf.py -- \
        assets/mana-wolf/mana_wolf.glb

The body is a skin-modifier mesh grown along the same joints the armature is built from, then
subdivided and skinned with automatic weights. The parts that must stay rigid (jaw, ears, crystals,
eyes, rune bands) are separate pieces weighted whole to one bone each, then joined in. Blender is
Z-up and the wolf faces -Y, which the glTF export turns into Godot's Y-up, facing +Z.
"""

import math
import sys

import bpy
from mathutils import Vector

FPS = 30
# The joints below are laid out at a large wolf's size; the model is shrunk by this to stand on
# one hex tile, about as big as the figures beside it.
SCALE = 0.75

# Materials: the fur in two shades, and the mana glow (crystals, eyes, rune bands) that the comic
# look keeps bright.
FUR = (0.11, 0.12, 0.27, 1.0)
FUR_LIGHT = (0.60, 0.64, 0.86, 1.0)
GLOW = (0.10, 0.75, 1.0, 1.0)
GLOW_STRENGTH = 1.2

# The joints, in metres: the spine from the tail's tip to the nose, and one side's legs (the other
# side mirrors them across X).
TAIL = [(0.0, 1.62, 0.70), (0.0, 1.38, 0.86), (0.0, 1.12, 0.98), (0.0, 0.86, 1.04)]
HIPS = (0.0, 0.62, 1.02)
SPINE_MID = (0.0, 0.22, 1.06)
CHEST = (0.0, -0.22, 1.10)
NECK = (0.0, -0.52, 1.18)
HEAD = (0.0, -0.74, 1.42)
SNOUT = (0.0, -1.06, 1.37)
NOSE = (0.0, -1.26, 1.35)
FRONT_LEG = [(0.20, -0.40, 0.98), (0.24, -0.36, 0.58), (0.24, -0.42, 0.18), (0.24, -0.58, 0.085)]
HIND_LEG = [
    (0.20, 0.56, 0.96),
    (0.25, 0.34, 0.60),
    (0.25, 0.62, 0.28),
    (0.25, 0.56, 0.09),
    (0.25, 0.40, 0.085),
]

# The skin's thickness at each joint: a deep chest and a bushy tail, slim legs.
RADII = {
    TAIL[0]: 0.04,
    TAIL[1]: 0.12,
    TAIL[2]: 0.15,
    TAIL[3]: 0.11,
    HIPS: 0.28,
    SPINE_MID: 0.31,
    CHEST: 0.40,
    NECK: 0.27,
    HEAD: 0.26,
    SNOUT: 0.13,
    NOSE: 0.07,
}
FRONT_RADII = [0.21, 0.11, 0.065, 0.085]
HIND_RADII = [0.25, 0.14, 0.07, 0.065, 0.085]


def mirrored(point):
    return (-point[0], point[1], point[2])


def body_mesh():
    """The body: a skin modifier along the joints, subdivided and applied."""
    points = []
    edges = []
    radii = []

    def add(point, radius):
        points.append(point)
        radii.append(radius)
        return len(points) - 1

    spine = TAIL + [HIPS, SPINE_MID, CHEST, NECK, HEAD, SNOUT, NOSE]
    spine_ids = [add(p, RADII[p]) for p in spine]
    edges += list(zip(spine_ids, spine_ids[1:]))
    chest_id = spine_ids[spine.index(CHEST)]
    hips_id = spine_ids[spine.index(HIPS)]
    for side in (lambda p: p, mirrored):
        for leg, leg_radii, attach in (
            (FRONT_LEG, FRONT_RADII, chest_id),
            (HIND_LEG, HIND_RADII, hips_id),
        ):
            ids = [add(side(p), r) for p, r in zip(leg, leg_radii)]
            edges += [(attach, ids[0])] + list(zip(ids, ids[1:]))

    mesh = bpy.data.meshes.new("ManaWolfBody")
    mesh.from_pydata(points, edges, [])
    body = bpy.data.objects.new("ManaWolf", mesh)
    bpy.context.collection.objects.link(body)
    skin = body.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    for vertex, radius in zip(mesh.skin_vertices[0].data, radii):
        vertex.radius = (radius, radius)
    mesh.skin_vertices[0].data[spine_ids[spine.index(SPINE_MID)]].use_root = True
    subsurf = body.modifiers.new("Subdivision", "SUBSURF")
    subsurf.levels = 2
    subsurf.render_levels = 2
    # Back to medium-poly: the subdivided skin is smooth but denser than the camera needs.
    decimate = body.modifiers.new("Decimate", "DECIMATE")
    decimate.ratio = 0.6
    select_only(body)
    for modifier in ("Skin", "Subdivision", "Decimate"):
        bpy.ops.object.modifier_apply(modifier=modifier)
    return body


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def material(name, color, glow=False):
    mat = bpy.data.materials.new(name)
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = 0.8
    if glow:
        shader.inputs["Emission Color"].default_value = color
        shader.inputs["Emission Strength"].default_value = GLOW_STRENGTH
    return mat


def pointing(direction):
    """The rotation that turns a primitive's +Z toward `direction`."""
    return Vector(direction).to_track_quat("Z", "Y").to_euler()


def part(kind, name, location, scale, rotation=(0.0, 0.0, 0.0), mat=None, bone=None, **shape):
    """A rigid piece: a primitive placed, shaped and weighted whole to `bone`."""
    getattr(bpy.ops.mesh, "primitive_%s_add" % kind)(location=location, rotation=rotation, **shape)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if mat is not None:
        obj.data.materials.append(mat)
    if bone is not None:
        group = obj.vertex_groups.new(name=bone)
        group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    return obj


def crystal(name, location, height, tilt, bone, mat):
    """A six-sided mana crystal growing out at `tilt` (radians about X, then Y)."""
    return part(
        "cone",
        name,
        location,
        (0.25 * height, 0.25 * height, height),
        rotation=tilt,
        mat=mat,
        bone=bone,
        vertices=6,
        radius1=1.0,
        radius2=0.0,
        depth=1.0,
    )


def rigid_parts(mats):
    """Jaw, ears, eyes, crystals and rune bands, each tied to the bone that carries it."""
    parts = [
        part("cube", "Jaw", (0.0, -1.0, 1.25), (0.08, 0.2, 0.04), (0.12, 0, 0), mats["fur"], "jaw"),
    ]
    for sign, side in ((1, "L"), (-1, "R")):
        parts.append(
            part(
                "cone",
                "Ear." + side,
                (0.12 * sign, -0.68, 1.70),
                (0.10, 0.05, 0.19),
                (0.15, -0.25 * sign, 0),
                mats["fur"],
                "ear." + side,
                vertices=8,
                radius1=1.0,
                radius2=0.0,
                depth=1.0,
            )
        )
        parts.append(
            part(
                "uv_sphere",
                "Eye." + side,
                (0.10 * sign, -0.93, 1.47),
                (0.035, 0.035, 0.025),
                mat=mats["glow"],
                bone="head",
                segments=12,
                ring_count=6,
            )
        )
        for leg, joint, bone in ((FRONT_LEG, 2, "forearm"), (HIND_LEG, 3, "hock")):
            a, b = Vector(leg[joint - 1]), Vector(leg[joint])
            spot = a.lerp(b, 0.7)
            parts.append(
                part(
                    "torus",
                    "Rune.%s.%s" % (bone, side),
                    (spot.x * sign, spot.y, spot.z),
                    (1.0, 1.0, 1.0),
                    mat=mats["glow"],
                    bone="%s.%s" % (bone, side),
                    major_radius=0.085,
                    minor_radius=0.018,
                    major_segments=16,
                    minor_segments=6,
                )
            )
    # The crystals: a crest along the back, one on the brow and a cluster on the tail's tip.
    for index, (y, z, height, bone) in enumerate(
        (
            (-0.30, 1.44, 0.55, "spine_02"),
            (-0.04, 1.38, 0.45, "spine_02"),
            (0.22, 1.32, 0.35, "spine_01"),
            (0.46, 1.27, 0.25, "hips"),
        )
    ):
        parts.append(crystal("Crest.%d" % index, (0.0, y, z), height, (0.35, 0, 0), bone, mats["glow"]))
        if index < 2:
            for sign in (1, -1):
                parts.append(
                    crystal(
                        "Flank.%d.%d" % (index, sign),
                        (0.12 * sign, y + 0.08, z - 0.08),
                        height * 0.6,
                        (0.3, 0.55 * sign, 0),
                        bone,
                        mats["glow"],
                    )
                )
    # A mane of pale tufts around the neck: the wolf's silhouette, and value contrast from above.
    for index in range(9):
        angle = math.pi * (index / 8 - 0.5) * 1.5
        out = Vector((math.sin(angle), 0.0, math.cos(angle)))
        parts.append(
            part(
                "cone",
                "Mane.%d" % index,
                Vector((0.0, -0.36, 1.24)) + out * 0.36,
                (0.11, 0.06, 0.42),
                pointing(out * 0.6 + Vector((0.0, 1.0, 0.0))),
                mats["fur_light"],
                "neck",
                vertices=6,
                radius1=1.0,
                radius2=0.0,
                depth=1.0,
            )
        )
    parts.append(crystal("Brow", (0.0, -0.86, 1.66), 0.2, (-0.5, 0, 0), "head", mats["glow"]))
    for sign in (0, 1, -1):
        parts.append(
            crystal(
                "TailTip.%d" % sign,
                (0.03 * sign, 1.56, 0.76),
                0.28 - 0.08 * abs(sign),
                (-1.4, 0.4 * sign, 0),
                "tail_04",
                mats["glow"],
            )
        )
    return parts


# The bones: name, head, tail, parent. Every bone lies in its side's YZ plane, rolled so its local
# X axis is world X: rotating about X bends it like a dog's spine and legs bend, about Z sways it.
def bone_list():
    tail_points = list(reversed(TAIL))
    bones = [
        ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.3), None),
        ("hips", HIPS, (0.0, 0.32, 1.05), "root"),
        ("spine_01", (0.0, 0.32, 1.05), SPINE_MID, "hips"),
        ("spine_02", SPINE_MID, CHEST, "spine_01"),
        ("neck", CHEST, (0.0, -0.66, 1.36), "spine_02"),
        ("head", (0.0, -0.66, 1.36), NOSE, "neck"),
        ("jaw", (0.0, -0.80, 1.28), (0.0, -1.18, 1.23), "head"),
    ]
    parent = "hips"
    previous = HIPS
    for index, point in enumerate(tail_points):
        name = "tail_%02d" % (index + 1)
        bones.append((name, previous, point, parent))
        parent, previous = name, point
    for side, flip in (("L", lambda p: p), ("R", mirrored)):
        bones.append(("ear." + side, flip((0.10, -0.70, 1.58)), flip((0.12, -0.70, 1.78)), "head"))
        front = [flip(p) for p in FRONT_LEG]
        bones.append(("scapula." + side, flip((0.12, -0.18, 1.22)), front[0], "spine_02"))
        names = ["upper_arm", "forearm", "front_paw"]
        parent = "scapula." + side
        for index, name in enumerate(names):
            bones.append((name + "." + side, front[index], front[index + 1], parent))
            parent = name + "." + side
        hind = [flip(p) for p in HIND_LEG]
        names = ["thigh", "shin", "hock", "hind_paw"]
        parent = "hips"
        for index, name in enumerate(names):
            bones.append((name + "." + side, hind[index], hind[index + 1], parent))
            parent = name + "." + side
    return bones


def armature():
    data = bpy.data.armatures.new("ManaWolfRig")
    rig = bpy.data.objects.new("ManaWolfRig", data)
    bpy.context.collection.objects.link(rig)
    select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in bone_list():
        bone = data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        direction = (Vector(tail) - Vector(head)).normalized()
        bone.align_roll(Vector((1.0, 0.0, 0.0)).cross(direction))
        if parent is not None:
            bone.parent = data.edit_bones[parent]
            bone.use_connect = (Vector(bone.parent.tail) - Vector(head)).length < 1e-4
        bone.use_deform = name != "root"
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def skin(body, pieces, rig):
    """Weights the body automatically, joins the rigid pieces in and binds it all to the rig."""
    # The jaw and ears are separate pieces: the body's own skin near them follows the head.
    rigid = ("jaw", "ear.L", "ear.R")
    for name in rigid:
        rig.data.bones[name].use_deform = False
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for name in rigid:
        rig.data.bones[name].use_deform = True
    bpy.ops.object.select_all(action="DESELECT")
    for piece in pieces:
        piece.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    bpy.ops.object.shade_smooth()
    # At most four bones per vertex, as glTF carries them, summing to one.
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)


# The clips. Each pose is {bone: (rx, ry, rz)} in radians, plus "root_loc" for the root's
# (x, up, forward) shift; the clip keys each pose at its frame.
LEGS = ("upper_arm", "forearm", "front_paw", "thigh", "shin", "hock", "hind_paw")


def gait(frame_count, swing, lift, phases, bob, spine_flex=0.0):
    """A looping gait: each leg swings fore and back and folds as it lifts, at its own phase."""
    poses = []
    for step in range(0, frame_count + 1, max(1, frame_count // 8)):
        t = step / frame_count
        pose = {}
        for leg_side, phase in phases.items():
            leg, side = leg_side
            angle = 2 * math.pi * (t + phase)
            back = math.sin(angle)
            raised = max(0.0, -math.cos(angle))
            if leg == "front":
                pose["upper_arm." + side] = (swing * back, 0, 0)
                pose["forearm." + side] = (-lift * raised, 0, 0)
                pose["front_paw." + side] = (lift * raised * 0.8, 0, 0)
            else:
                pose["thigh." + side] = (swing * back, 0, 0)
                pose["shin." + side] = (lift * raised, 0, 0)
                pose["hock." + side] = (-lift * raised * 0.9, 0, 0)
        double = 4 * math.pi * t
        pose["root_loc"] = (0, bob * math.cos(double), 0)
        pose["spine_01"] = (spine_flex * math.sin(2 * math.pi * t), 0, 0)
        pose["neck"] = (0.04 * math.cos(double), 0, 0)
        pose["tail_01"] = (0.15, 0, 0.18 * math.sin(2 * math.pi * t))
        pose["tail_02"] = (0, 0, 0.15 * math.sin(2 * math.pi * t - 0.6))
        poses.append((step + 1, pose))
    return poses


def idle():
    poses = []
    for step in range(0, 61, 10):
        t = step / 60
        wave = math.sin(2 * math.pi * t)
        pose = {
            "spine_02": (0.02 * wave, 0, 0),
            "neck": (-0.04 * wave, 0, 0),
            "head": (0.05 * wave, 0, 0.08 * math.sin(2 * math.pi * t + 1)),
            "tail_01": (0.1, 0, 0.2 * wave),
            "tail_02": (0, 0, 0.18 * math.sin(2 * math.pi * t - 0.8)),
            "tail_03": (0, 0, 0.15 * math.sin(2 * math.pi * t - 1.6)),
            "jaw": (0.05 + 0.05 * wave, 0, 0),
            "root_loc": (0, -0.01 + 0.01 * wave, 0),
        }
        if step in (30, 40):
            pose["ear.L"] = (0, 0, -0.3)
        poses.append((step + 1, pose))
    return poses


def attack():
    crouch = {
        "root_loc": (0, -0.12, -0.12),
        "hips": (-0.12, 0, 0),
        "neck": (0.25, 0, 0),
        "head": (-0.1, 0, 0),
        "upper_arm.L": (0.25, 0, 0),
        "upper_arm.R": (0.25, 0, 0),
        "forearm.L": (-0.4, 0, 0),
        "forearm.R": (-0.4, 0, 0),
        "thigh.L": (-0.3, 0, 0),
        "thigh.R": (-0.3, 0, 0),
        "shin.L": (0.5, 0, 0),
        "shin.R": (0.5, 0, 0),
        "ear.L": (0.4, 0, 0),
        "ear.R": (0.4, 0, 0),
        "tail_01": (-0.2, 0, 0),
    }
    lunge = {
        "root_loc": (0, 0.05, 0.35),
        "hips": (0.08, 0, 0),
        "neck": (-0.15, 0, 0),
        "head": (0.2, 0, 0),
        "jaw": (0.6, 0, 0),
        "upper_arm.L": (-0.55, 0, 0),
        "upper_arm.R": (-0.45, 0, 0),
        "thigh.L": (0.45, 0, 0),
        "thigh.R": (0.4, 0, 0),
        "ear.L": (0.4, 0, 0),
        "ear.R": (0.4, 0, 0),
        "tail_01": (0.3, 0, 0),
    }
    bite = dict(lunge, jaw=(0.0, 0, 0))
    return [(1, {}), (8, crouch), (13, lunge), (16, bite), (24, {})]


def hit():
    recoil = {
        "root_loc": (0, -0.04, -0.14),
        "spine_01": (0.12, 0, 0.1),
        "spine_02": (0.1, 0, 0.1),
        "neck": (-0.3, 0, 0.15),
        "head": (-0.25, 0, 0.1),
        "jaw": (0.35, 0, 0),
        "ear.L": (0.6, 0, 0),
        "ear.R": (0.6, 0, 0),
        "tail_01": (-0.4, 0, 0),
        "upper_arm.L": (-0.2, 0, 0),
        "upper_arm.R": (-0.2, 0, 0),
    }
    return [(1, {}), (5, recoil), (18, {})]


def faint():
    """Legs give way and the wolf sinks onto its belly, head on the ground, and stays there."""
    sinking = {
        "root_loc": (0, -0.3, 0),
        "neck": (0.2, 0, 0),
        "head": (0.1, 0, 0.1),
        "upper_arm.L": (0.4, 0, 0),
        "upper_arm.R": (0.4, 0, 0),
        "forearm.L": (-0.7, 0, 0),
        "forearm.R": (-0.7, 0, 0),
        "thigh.L": (-0.5, 0, 0),
        "thigh.R": (-0.5, 0, 0),
        "shin.L": (1.0, 0, 0),
        "shin.R": (1.0, 0, 0),
        "ear.L": (0.5, 0, 0),
        "ear.R": (0.5, 0, 0),
    }
    lying = {
        "root_loc": (0, -0.62, 0),
        "neck": (0.45, 0, 0),
        "head": (0.25, 0, 0.25),
        "jaw": (0.1, 0, 0),
        "upper_arm.L": (-1.1, 0, 0),
        "upper_arm.R": (-1.1, 0, 0),
        "forearm.L": (-0.4, 0, 0),
        "forearm.R": (-0.4, 0, 0),
        "front_paw.L": (0.9, 0, 0),
        "front_paw.R": (0.9, 0, 0),
        "thigh.L": (-1.0, 0, 0.15),
        "thigh.R": (-1.0, 0, -0.15),
        "shin.L": (1.9, 0, 0),
        "shin.R": (1.9, 0, 0),
        "hock.L": (-1.2, 0, 0),
        "hock.R": (-1.2, 0, 0),
        "ear.L": (0.7, 0, 0.2),
        "ear.R": (0.7, 0, -0.2),
        "tail_01": (-0.6, 0, 0.3),
        "tail_02": (-0.2, 0, 0.3),
    }
    return [(1, {}), (14, sinking), (30, lying), (40, lying)]


def clips():
    walk_phases = {("front", "L"): 0.0, ("hind", "R"): 0.0, ("front", "R"): 0.5, ("hind", "L"): 0.5}
    run_phases = {("front", "L"): 0.0, ("front", "R"): 0.1, ("hind", "L"): 0.5, ("hind", "R"): 0.6}
    return {
        "Idle": idle(),
        "Walk": gait(24, 0.45, 0.6, walk_phases, 0.02),
        "Run": gait(14, 0.65, 0.9, run_phases, 0.06, spine_flex=0.15),
        "Attack": attack(),
        "Hit": hit(),
        "Faint": faint(),
    }


def animate(rig):
    """Keys every clip as its own action on every bone, so each clip sets the whole pose, and
    stashes it on an NLA track the glTF export turns into a named animation."""
    rig.animation_data_create()
    select_only(rig)
    bpy.ops.object.mode_set(mode="POSE")
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
    for name, poses in clips().items():
        action = bpy.data.actions.new(name)
        rig.animation_data.action = action
        for frame, pose in poses:
            for bone in rig.pose.bones:
                bone.rotation_euler = pose.get(bone.name, (0.0, 0.0, 0.0))
                bone.keyframe_insert("rotation_euler", frame=frame)
                if bone.name == "root":
                    shift = pose.get("root_loc", (0.0, 0.0, 0.0))
                    bone.location = tuple(SCALE * value for value in shift)
                    bone.keyframe_insert("location", frame=frame)
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.name = name
        rig.animation_data.action = None
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in rig.pose.bones:
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)


def build(out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    mats = {
        "fur": material("Fur", FUR),
        "fur_light": material("FurLight", FUR_LIGHT),
        "glow": material("ManaGlow", GLOW, glow=True),
    }
    body = body_mesh()
    body.data.materials.append(mats["fur"])
    pieces = rigid_parts(mats)
    rig = armature()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [body, rig] + pieces:
        obj.scale = (SCALE, SCALE, SCALE)
        obj.location = obj.location * SCALE
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    skin(body, pieces, rig)
    animate(rig)
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_skins=True,
        export_apply=False,
        export_yup=True,
    )
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print("MANA_WOLF", out, "triangles", tris, "bones", len(rig.data.bones))


build(sys.argv[sys.argv.index("--") + 1])
