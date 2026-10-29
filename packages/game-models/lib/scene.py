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
    first key by holding it, a frame's pause on every loop (#1089). Every mesh's vertices and faces
    are put in a fixed order first, so an unchanged script exports the same bytes every time
    (#1085, #1639)."""
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            sort_mesh(obj)
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


def sort_mesh(obj):
    """Puts the mesh's vertices and faces in an order that depends only on the mesh, so two builds
    of one script export the same bytes (#1085, #1639). The glTF exporter writes the vertices in
    the mesh's vertex order and the triangles in its face order, and some of Blender's operators
    lay out the same geometry in a different order on every run (a UV sphere's primitive puts its
    faces in a new order each time) or on another machine (bmesh's subdivide_edges put its new
    vertices in another order on CI than here, #1634).

    Vertices are sorted by where they lie, then by their UVs, their faces' facing, their skin
    weights and their neighbours' positions; vertices alike in all of that keep the order they
    had. Faces are then sorted by material and by their (sorted) vertices, each face read from
    its lowest vertex on, keeping its winding. The sorting goes through BMesh, which carries the
    skin weights, UVs, materials and smooth shading across; shape keys and custom normals no model
    has yet, so a mesh with them is refused rather than trusted to come back unchanged."""
    if obj.data.shape_keys is not None or obj.data.has_custom_normals:
        raise RuntimeError("%s: sort_mesh doesn't keep shape keys or custom normals yet" % obj.name)
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    mesh.verts.index_update()
    uv = mesh.loops.layers.uv.active
    deform = mesh.verts.layers.deform.active

    def vertex_key(vertex):
        return (tuple(vertex.co),
                sorted(tuple(loop[uv].uv) for loop in vertex.link_loops) if uv else [],
                sorted(tuple(face.normal) for face in vertex.link_faces),
                sorted(vertex[deform].items()) if deform else [],
                sorted(tuple(edge.other_vert(vertex).co) for edge in vertex.link_edges),
                vertex.index)

    # BMesh sorts by a number, so each element's key becomes its rank.
    rank = {vertex.index: place for place, vertex in enumerate(sorted(mesh.verts, key=vertex_key))}
    mesh.verts.sort(key=lambda vertex: rank[vertex.index])
    mesh.verts.index_update()
    mesh.faces.index_update()

    def face_key(face):
        corners = [vert.index for vert in face.verts]
        first = corners.index(min(corners))
        return (face.material_index, corners[first:] + corners[:first])

    rank = {face.index: place for place, face in enumerate(sorted(mesh.faces, key=face_key))}
    mesh.faces.sort(key=lambda face: rank[face.index])
    mesh.to_mesh(obj.data)
    mesh.free()
    obj.data.update()
