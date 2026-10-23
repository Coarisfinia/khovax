"""Skin weights: automatic weights on the body, the parts joined in, at most four bones per
vertex (as glTF carries them), normalised."""

import bpy

from . import scene


def bind(body, rig, pieces, rigid_bones=(), reweigh=None):
    """Weights `body` to `rig` automatically and joins `pieces` into it. A piece already weighted
    to a bone (parts.part with `bone`) keeps that; one without takes the weights of the body
    under it, so patterns on the skin bend with it. `rigid_bones` (a jaw, ears) get none of the
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
