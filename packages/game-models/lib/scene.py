"""The scene: a clean start, selection, scaling and the glTF export the game imports."""

import bmesh
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
    animation per NLA track (clips.animate stashes each there), Y up. Each animation starts at
    time 0: the clips are keyed from frame 1, and Godot's importer fills the gap before a late
    first key by holding it, a frame's pause on every loop (#1089). Every mesh's faces are put in
    a fixed order first, so an unchanged script exports the same bytes every time (#1085)."""
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            sort_faces(obj)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_anim_slide_to_zero=True,
        export_skins=True,
        export_apply=False,
        export_yup=True,
    )


def sort_faces(obj):
    """Puts the mesh's faces in an order that depends only on the mesh: by material, then by their
    vertices, each face read from its lowest vertex on, keeping its winding. Some of Blender's
    operators (a UV sphere's primitive, for one) lay out the same faces in a different order on
    every run, and the glTF exporter writes the triangles in face order, so without this two builds
    of one script differ in their index buffers (#1085). Vertices keep their order: no operator
    the models use varies it, and the exporter orders the glTF's vertices by their data anyway.
    The faces are sorted through BMesh, which carries the skin weights, UVs, materials and smooth
    shading across; shape keys and custom normals no model has yet, so a mesh with them is refused
    rather than trusted to come back unchanged."""
    if obj.data.shape_keys is not None or obj.data.has_custom_normals:
        raise RuntimeError("%s: sort_faces doesn't keep shape keys or custom normals yet" % obj.name)
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    mesh.verts.index_update()
    mesh.faces.index_update()

    def key(face):
        corners = [vert.index for vert in face.verts]
        first = corners.index(min(corners))
        return (face.material_index, corners[first:] + corners[:first])

    # BMesh sorts by a number, so each face's key becomes its rank.
    rank = {face.index: place for place, face in enumerate(sorted(mesh.faces, key=key))}
    mesh.faces.sort(key=lambda face: rank[face.index])
    mesh.to_mesh(obj.data)
    mesh.free()
    obj.data.update()
