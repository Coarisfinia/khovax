"""The scene: a clean start, selection, scaling and the glTF export the game imports."""

import bpy


def reset(fps):
    """An empty scene at the game's clip rate."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = fps


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_scale(objects, scale):
    """Shrinks every object about the origin by `scale` and bakes it in, so the export carries
    no object scale (a skinned mesh under a scaled node deforms wrongly in some importers)."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.scale = (scale, scale, scale)
        obj.location = obj.location * scale
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)


def triangles(obj):
    return sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)


def export_glb(path):
    """Exports the scene as the game takes it: a binary glTF with the skin and every clip, one
    animation per NLA track (clips.animate stashes each there), Y up."""
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_skins=True,
        export_apply=False,
        export_yup=True,
    )
