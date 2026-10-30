"""The tentacle gate (#1634): a stone arch with an eye at its crown, a dark, starry portal in its
opening and four tentacles curling out from its feet onto the ground. Its mesh and colour come from
the owner's generated model (`sources/tentacle_gate.glb`, made by import_source.py from the
download at `scale` 2.2: see the asset's SOURCE.md). That made it two hexes wide, far too big for
the game (the owner, on #1636), so the script shrinks it by SCALE: like every model, it stands
within its hex, tentacles and all (a prop's limits in lib/footprint.py, #1641).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/tentacle_gate.py -- packages/game/assets/tentacle_gate/tentacle_gate.glb

The generator rigged it as a character (#1634): one chain holds both left tentacles, and the arch's
crown is taken for a leg. A gate needs neither, so this script drops that rig and builds its own
from the mesh's pieces: a still `root` holding the arch, a chain along each tentacle and a `portal`
bone in the portal's middle. It plays one clip, `Idle`, a slow loop: the tentacles sway and curl up
a little, a wave running along each, and the portal turns and swells gently about its middle while
its rim stays in the arch.

Blender is Z-up and the gate faces -Y (the game's +Z); its left is +X.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import scene  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "tentacle_gate.glb")
FPS = 30
# Its kind on the world's scale (lib/world_scale.py): a gate on one hex the player walks through
# (#1634).
WORLD_SCALE = "portal"
# The loop's length (frames): slow, so the gate breathes rather than fidgets.
LOOP = 180
# How much the source is shrunk, so the gate's rest pose reaches within a prop's limit on its hex
# with lib/footprint.py's slack and its tentacles' sway stays inside it (check_footprint.py).
SCALE = 0.37

# The portal is the smallest of the mesh's pieces (a thin slab behind the arch's opening), the
# arch the largest; the other two each hold one side's pair of tentacles.
# How often the portal slab's edges are cut, so its turn and swell bend it smoothly.
PORTAL_CUTS = 6
# The portal's weight falls from its middle to its rim (a share of its half width and half height,
# as an ellipse), so the rim stays in the arch while the middle turns and swells.
PORTAL_FULL, PORTAL_RIM = 0.2, 0.85
# Its slow turn about its own facing (radians), its swell in its plane (a share of its size) and
# how far its middle bulges out to the front (metres, at the source's size).
PORTAL_TURN, PORTAL_SWELL, PORTAL_BULGE = math.radians(12.0), 0.05, 0.03 * SCALE

# Each tentacle's chain: bones laid through the middle of equal bands of the tentacle, from where
# it leaves the arch's foot (ROOT_DEPTH, how far it lies before or behind the arch, a share of the
# gate's depth) to its tip.
TENTACLE_BONES = 4
ROOT_DEPTH = 0.27
# Its weights blend into the root over this share of the first band, so its base bends softly
# where it joins the arch's foot.
ROOT_BLEND = 0.6
# How far (radians) each bone of a tentacle sways about the upright and curls its tip up (never
# down, so no tip sinks into the ground), and how far behind its parent each bone's wave runs (a
# share of the loop). Each tentacle starts its wave a quarter of the loop after the one before.
SWAY, CURL, LAG = math.radians(3.0), math.radians(2.5), 0.08
TENTACLES = (("front", "L", 0.0), ("hind", "R", 0.25), ("front", "R", 0.5), ("hind", "L", 0.75))


def islands(skin):
    """The mesh's pieces, as lists of vertex indices, welded by position (the export splits a
    vertex where its UVs part), largest first."""
    keys = {}
    for vertex in skin.data.vertices:
        keys.setdefault(tuple(round(value, 5) for value in vertex.co), []).append(vertex.index)
    parent = list(range(len(skin.data.vertices)))

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def join(first, second):
        first, second = find(first), find(second)
        if first != second:
            parent[max(first, second)] = min(first, second)

    for same in keys.values():
        for index in same[1:]:
            join(same[0], index)
    for edge in skin.data.edges:
        join(*edge.vertices)
    pieces = {}
    for vertex in skin.data.vertices:
        pieces.setdefault(find(vertex.index), []).append(vertex.index)
    return sorted(pieces.values(), key=lambda piece: (-len(piece), piece[0]))


def cut_portal(skin, piece):
    """Cuts the portal slab's edges into a grid, so it bends smoothly."""
    inside = set(piece)
    mesh = bmesh.new()
    mesh.from_mesh(skin.data)
    mesh.verts.ensure_lookup_table()
    edges = [edge for edge in mesh.edges if all(vertex.index in inside for vertex in edge.verts)]
    # The cuts lay out their new vertices in an order that differs between machines (#1634):
    # scene.export_glb sorts every mesh's vertices before it writes them (#1639).
    bmesh.ops.subdivide_edges(mesh, edges=edges, cuts=PORTAL_CUTS, use_grid_fill=True)
    mesh.to_mesh(skin.data)
    mesh.free()


def bounds(points):
    low = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    high = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return low, high


def tentacle_joints(points, side, pair, depth):
    """A tentacle's joints, from where it leaves the arch's foot to its tip: the middle of each
    of TENTACLE_BONES equal bands of its vertices by how far they lie before or behind the arch
    (it runs out from the foot that way), and its tip's farthest middle."""
    x_sign = 1.0 if side == "L" else -1.0
    y_sign = -1.0 if pair == "front" else 1.0
    start = ROOT_DEPTH * depth
    own = [point for point in points if point.x * x_sign > 0.0 and point.y * y_sign > start]
    end = max(point.y * y_sign for point in own)
    width = (end - start) / TENTACLE_BONES
    joints = []
    for band in range(TENTACLE_BONES + 1):
        middle = start + band * width
        near = [point for point in own if abs(point.y * y_sign - middle) < width / 2.0]
        joints.append(sum(near, Vector()) / len(near))
    return joints, start, width


def armature(portal_middle, portal_size, tentacles):
    """The gate's rig: a root on the ground, the portal bone pointing out of the portal's front and
    each tentacle's chain, every bone named."""
    data = bpy.data.armatures.new("TentacleGateRig")
    rig = bpy.data.objects.new("TentacleGateRig", data)
    bpy.context.scene.collection.objects.link(rig)
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    root = data.edit_bones.new("root")
    root.head, root.tail = Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.3))
    portal = data.edit_bones.new("portal")
    portal.head = portal_middle
    portal.tail = portal_middle + Vector((0.0, -0.5 * portal_size.x, 0.0))
    portal.parent = root
    for (pair, side, _phase), (joints, _start, _width) in tentacles.items():
        parent = root
        for number in range(TENTACLE_BONES):
            bone = data.edit_bones.new(bone_name(pair, side, number))
            bone.head, bone.tail = joints[number], joints[number + 1]
            bone.parent = parent
            bone.use_connect = number > 0
            parent = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def bone_name(pair, side, number):
    return "tentacle_%s_%02d.%s" % (pair, number + 1, side)


def smoothstep(low, high, value):
    share = min(1.0, max(0.0, (value - low) / (high - low)))
    return share * share * (3.0 - 2.0 * share)


def segment_distance(point, head, tail):
    along = tail - head
    share = min(1.0, max(0.0, (point - head).dot(along) / along.length_squared))
    return (point - (head + share * along)).length


def bind(skin, rig, pieces, portal_middle, portal_half, tentacles):
    """Weights the arch to the root, the portal to its bone by how near its middle a vertex lies
    (the rest to the root) and each tentacle to its two nearest bones, its base blending into the
    root."""
    groups = {bone.name: skin.vertex_groups.new(name=bone.name) for bone in rig.data.bones}
    portal = set(pieces[-1])
    feet = set(pieces[1]) | set(pieces[2])
    for vertex in skin.data.vertices:
        point = vertex.co
        weights = {}
        if vertex.index in portal:
            spread = math.hypot((point.x - portal_middle.x) / portal_half.x,
                                (point.z - portal_middle.z) / portal_half.z)
            weights["portal"] = 1.0 - smoothstep(PORTAL_FULL, PORTAL_RIM, spread)
        elif vertex.index in feet:
            for (pair, side, _phase), (joints, start, width) in tentacles.items():
                x_sign = 1.0 if side == "L" else -1.0
                y_sign = -1.0 if pair == "front" else 1.0
                if point.x * x_sign <= 0.0 or point.y * y_sign <= start - width:
                    continue
                distances = sorted((segment_distance(point, joints[number], joints[number + 1]), number)
                                   for number in range(TENTACLE_BONES))
                (near, first), (far, second) = distances[0], distances[1]
                blend = far / (near + far) if near + far > 0.0 else 1.0
                share = smoothstep(start - width, start + ROOT_BLEND * width, point.y * y_sign)
                weights[bone_name(pair, side, first)] = share * blend
                weights[bone_name(pair, side, second)] = share * (1.0 - blend)
        weights["root"] = max(0.0, 1.0 - sum(weights.values()))
        for name, weight in weights.items():
            if weight > 0.0:
                groups[name].add([vertex.index], weight, "REPLACE")
    modifier = skin.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    skin.parent = rig


def turn(bone, axis, angle):
    """A turn about `axis` (in the rig's space, as the bone lies at rest) as the bone's own
    quaternion."""
    local = bone.bone.matrix_local.to_3x3().inverted() @ axis
    return Matrix.Rotation(angle, 3, local.normalized()).to_quaternion()


def animate(rig):
    """Keys the Idle loop on every frame and stashes it on its NLA track (scene.export_glb)."""
    rig.animation_data_create()
    action = bpy.data.actions.new("Idle")
    rig.animation_data.action = action
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="POSE")
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
    portal = rig.pose.bones["portal"]
    for frame in range(1, LOOP + 2):
        time = 2.0 * math.pi * (frame - 1) / LOOP
        portal.rotation_quaternion = Matrix.Rotation(PORTAL_TURN * math.sin(time), 3, "Y").to_quaternion()
        swell = 1.0 + PORTAL_SWELL * math.sin(time + math.pi / 3.0)
        portal.scale = (swell, 1.0, swell)
        # Along the bone, which points out of the portal's front.
        portal.location = (0.0, PORTAL_BULGE * 0.5 * (1.0 - math.cos(time)), 0.0)
        for pair, side, phase in TENTACLES:
            for number in range(TENTACLE_BONES):
                bone = rig.pose.bones[bone_name(pair, side, number)]
                wave = time - 2.0 * math.pi * (phase + LAG * number)
                outward = bone.bone.tail_local - bone.bone.head_local
                outward.z = 0.0
                lift_axis = outward.normalized().cross(Vector((0.0, 0.0, 1.0)))
                sway = turn(bone, Vector((0.0, 0.0, 1.0)), SWAY * math.sin(wave))
                curl = turn(bone, lift_axis, CURL * 0.5 * (1.0 - math.cos(wave)))
                bone.rotation_quaternion = sway @ curl
        for bone in rig.pose.bones:
            bone.keyframe_insert("rotation_quaternion", frame=frame)
            bone.keyframe_insert("location", frame=frame)
            bone.keyframe_insert("scale", frame=frame)
    bpy.ops.object.mode_set(mode="OBJECT")
    track = rig.animation_data.nla_tracks.new()
    track.name = "Idle"
    strip = track.strips.new("Idle", 1, action)
    strip.name = "Idle"
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH"
                and not any("glTF_not_exported" in collection.name for collection in obj.users_collection))
    matrix = skin.matrix_world.copy()
    skin.parent = None
    skin.data.transform(Matrix.Scale(SCALE, 4) @ matrix)
    skin.matrix_world = Matrix.Identity(4)
    skin.modifiers.clear()
    skin.vertex_groups.clear()
    for obj in [obj for obj in bpy.data.objects if obj is not skin]:
        bpy.data.objects.remove(obj, do_unlink=True)
    skin.name = "TentacleGate"
    scene.select_only(skin)
    # The import keeps the file's normals as custom ones; smooth normals from the faces shade the
    # same and bend with the skin (scene.sort_mesh keeps no custom normals).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    pieces = islands(skin)
    if len(pieces) != 4:
        sys.exit("expected the arch, two pairs of tentacles and the portal, found %d pieces" % len(pieces))
    portal_low, portal_high = bounds([skin.data.vertices[index].co for index in pieces[-1]])
    cut_portal(skin, pieces[-1])
    # The cut portal is found again as the piece filling the slab's bounds, whatever order the
    # cuts left the vertices in; the arch stays the largest piece.
    pieces = islands(skin)
    portal = next(piece for piece in pieces[1:] if bounds([skin.data.vertices[index].co for index in piece])
                  == (portal_low, portal_high))
    pieces = [pieces[0]] + [piece for piece in pieces[1:] if piece is not portal] + [portal]
    points = [vertex.co.copy() for vertex in skin.data.vertices]
    low, high = bounds(points)
    portal_middle = (portal_low + portal_high) / 2.0
    portal_half = (portal_high - portal_low) / 2.0
    feet = [points[index] for piece in pieces[1:3] for index in piece]
    depth = (high.y - low.y) / 2.0
    tentacles = {key: tentacle_joints(feet, key[1], key[0], depth) for key in TENTACLES}
    rig = armature(portal_middle, 2.0 * portal_half, tentacles)
    bind(skin, rig, pieces, portal_middle, portal_half, tentacles)
    animate(rig)
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SIZE %.2f wide, %.2f deep, %.2f tall; portal %.2f wide, %.2f tall" % (
        high.x - low.x, high.y - low.y, high.z - low.z, 2.0 * portal_half.x, 2.0 * portal_half.z))


build(sys.argv[sys.argv.index("--") + 1])
