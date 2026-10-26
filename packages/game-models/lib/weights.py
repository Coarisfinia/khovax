"""Skin weights: automatic weights on the body, the parts joined in, at most four bones per
vertex (as glTF carries them), normalised."""

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

from . import scene

# The custom property `root` keeps a rooted piece's spot in until weights.bind weights it: as
# shares of the piece's bounds, which hold through scene.apply_scale.
ROOT = "weights_root"
ROOT_BONES = "weights_root_bones"


def root(piece, spot, bones):
    """Marks `piece` (a part with no bone) to move whole as the body's skin at `spot`, its root
    on the body (#1303): weights.bind gives every vertex of it the body's weights there. A
    crystal grown from the skin over two bones (the neck's root, where the spine's and the neck's
    shares meet) then stays on the skin as they bend, while a piece weighted to one of them lifts
    off it, and taking each vertex's own nearest weights would bend a stiff piece with the skin.
    It follows only `bones` there: the share of any other bone goes to the nearest of its
    parents among them. The skin on a back also follows the shoulder blades, which would rock a
    crest crystal at every step (the owner, on #1413), and the share it takes from them stays with
    the spine they hang from instead. Returns `piece`."""
    low, high = _bounds(piece)
    piece[ROOT] = [(c - a) / (b - a) if b > a else 0.0 for c, a, b in zip(spot, low, high)]
    piece[ROOT_BONES] = list(bones)
    return piece


def _bounds(piece):
    points = [piece.matrix_world @ vertex.co for vertex in piece.data.vertices]
    return ([min(point[axis] for point in points) for axis in range(3)],
            [max(point[axis] for point in points) for axis in range(3)])


def bind(body, rig, pieces, rigid_bones=(), reweigh=None):
    """Weights `body` to `rig` automatically and joins `pieces` into it. A piece already weighted
    to a bone (parts.part with `bone`) keeps that; a rooted one (`root`) moves whole as the skin
    at its root; any other takes the weights of the body under it, so patterns on the skin bend
    with it. `rigid_bones` (a jaw, ears) get none of the
    body's skin from the automatic weights; `reweigh`, given the body after them and before the
    pieces join it, may hand a rigid bone its share (a jaw the skin over it,
    muzzle.Snout.bind_jaw)."""
    for name in rigid_bones:
        rig.data.bones[name].use_deform = False
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for name in rigid_bones:
        rig.data.bones[name].use_deform = True
    if reweigh is not None:
        reweigh(body)
    rooted = [piece for piece in pieces if ROOT in piece]
    if rooted:
        _take_root_weights(rooted, body, rig)
    for piece in pieces:
        if not piece.vertex_groups:
            _take_weights(piece, body)
    bpy.ops.object.select_all(action="DESELECT")
    for piece in pieces:
        piece.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)


def _take_weights(piece, body):
    scene.select_only(piece)
    transfer = piece.modifiers.new("Weights", "DATA_TRANSFER")
    transfer.object = body
    transfer.use_vert_data = True
    transfer.data_types_verts = {"VGROUP_WEIGHTS"}
    transfer.vert_mapping = "POLYINTERP_NEAREST"
    bpy.ops.object.datalayout_transfer(modifier=transfer.name)
    bpy.ops.object.modifier_apply(modifier=transfer.name)


def _take_root_weights(pieces, body, rig):
    """Every vertex of each piece takes the body's weights at the piece's root (`root`): those
    of the corners of the body's face nearest it, blended by where the point nearest the root
    lies on it, each share given to the nearest of its bone and its parents among `bones`."""
    world = body.matrix_world
    corners = [world @ vertex.co for vertex in body.data.vertices]
    faces = [list(polygon.vertices) for polygon in body.data.polygons]
    tree = BVHTree.FromPolygons(corners, faces)
    names = {group.index: group.name for group in body.vertex_groups}
    for piece in pieces:
        low, high = _bounds(piece)
        spot = Vector([a + share * (b - a) for share, a, b in zip(piece[ROOT], low, high)])
        bones = set(piece[ROOT_BONES])
        del piece[ROOT]
        del piece[ROOT_BONES]
        # The root lies a little under the skin (a crystal grows from inside it): its weights are
        # those of the nearest point on the skin.
        location, _normal, face, _distance = tree.find_nearest(spot)
        indices = faces[face]
        shares = poly_3d_calc([corners[index] for index in indices], location)
        weights = {}
        for index, share in zip(indices, shares):
            for group in body.data.vertices[index].groups:
                bone = rig.data.bones.get(names[group.group])
                while bone is not None and bone.name not in bones:
                    bone = bone.parent
                if bone is not None:
                    weights[bone.name] = weights.get(bone.name, 0.0) + share * group.weight
        whole = sum(weights.values())
        if whole <= 0.0:
            raise ValueError("%s: none of %s moves the skin at its root" % (piece.name, sorted(bones)))
        everything = range(len(piece.data.vertices))
        for name, weight in sorted(weights.items()):
            if weight > 0.0:
                piece.vertex_groups.new(name=name).add(everything, weight / whole, "REPLACE")
