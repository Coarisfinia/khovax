"""The scene: a clean start, selection, scaling and the glTF export the game imports."""

import bmesh
import bpy
import numpy


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

    Vertices are sorted by where they lie, then by their corners (every UV and colour layer, their
    faces' material, shading and facing), their skin weights and their neighbours' positions.
    Faces are then sorted by material and by their (sorted) vertices, each face read from its
    lowest vertex on, keeping its winding, and each face's corners are turned to start there too
    (start_faces_at_lowest, #1662). Two vertices or faces alike in all of that would keep
    whatever order the operators left them in, so a mesh with such a pair is refused. The sorting
    goes through BMesh, which carries the skin weights, UVs, materials and smooth shading across;
    shape keys and custom normals no model has yet, so a mesh with them is refused rather than
    trusted to come back unchanged."""
    if obj.data.shape_keys is not None or obj.data.has_custom_normals:
        raise RuntimeError("%s: sort_mesh doesn't keep shape keys or custom normals yet" % obj.name)
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    mesh.verts.index_update()
    mesh.faces.index_update()
    uvs = list(mesh.loops.layers.uv.values())
    colors = list(mesh.loops.layers.float_color.values()) + list(mesh.loops.layers.color.values())
    deform = mesh.verts.layers.deform.active

    def corner(loop):
        return (tuple(tuple(loop[layer].uv) for layer in uvs), tuple(tuple(loop[layer]) for layer in colors),
                loop.face.material_index, loop.face.smooth, tuple(loop.face.normal))

    def vertex_key(vertex):
        return (tuple(vertex.co),
                sorted(corner(loop) for loop in vertex.link_loops),
                sorted(vertex[deform].items()) if deform else [],
                sorted(tuple(edge.other_vert(vertex).co) for edge in vertex.link_edges))

    # BMesh sorts by a number, so each element's key becomes its rank.
    rank = unique_rank(obj, "vertices", mesh.verts, vertex_key)
    mesh.verts.sort(key=lambda vertex: rank[vertex.index])
    mesh.verts.index_update()
    mesh.faces.index_update()

    def face_key(face):
        corners = [vert.index for vert in face.verts]
        first = corners.index(min(corners))
        return (face.material_index, corners[first:] + corners[:first])

    rank = unique_rank(obj, "faces", mesh.faces, face_key)
    mesh.faces.sort(key=lambda face: rank[face.index])
    mesh.to_mesh(obj.data)
    mesh.free()
    start_faces_at_lowest(obj.data)
    obj.data.update()


# Each corner attribute's type: how many numbers a corner holds, the field foreach_get reads and
# the array type that holds them. BYTE_COLOR is read as sRGB, which comes back as the same bytes.
CORNER_TYPES = {
    "FLOAT": (1, "value", numpy.float32), "INT": (1, "value", numpy.int32),
    "INT8": (1, "value", numpy.int32), "BOOLEAN": (1, "value", bool),
    "FLOAT2": (2, "vector", numpy.float32), "INT16_2D": (2, "value", numpy.int32),
    "INT32_2D": (2, "value", numpy.int32), "FLOAT_VECTOR": (3, "vector", numpy.float32),
    "FLOAT_COLOR": (4, "color", numpy.float32), "BYTE_COLOR": (4, "color_srgb", numpy.float32),
    "QUATERNION": (4, "value", numpy.float32), "FLOAT4X4": (16, "value", numpy.float32),
}


def start_faces_at_lowest(mesh):
    """Turns each face's corners so they start at its lowest vertex, keeping its winding (#1662).
    The exporter splits a face into triangles from its first corner on, so a face whose corners
    an operator started elsewhere (on another machine, say) would be written as other triangles,
    though sort_mesh gives it the same place. Every corner attribute (the corners' vertices and
    edges, UVs, colours, UV selection) is turned with them, so each corner keeps its data."""
    count = len(mesh.loops)
    corner_verts = numpy.empty(count, dtype=numpy.int32)
    mesh.attributes[".corner_vert"].data.foreach_get("value", corner_verts)
    order = numpy.arange(count)
    for face in mesh.polygons:
        start, total = face.loop_start, face.loop_total
        first = int(numpy.argmin(corner_verts[start:start + total]))
        order[start:start + total] = numpy.roll(order[start:start + total], -first)
    if (order == numpy.arange(count)).all():
        return
    for attribute in list(mesh.attributes):
        if attribute.domain != "CORNER":
            continue
        if attribute.data_type not in CORNER_TYPES:
            raise RuntimeError("%s: start_faces_at_lowest can't carry %s's %s corners"
                               % (mesh.name, attribute.name, attribute.data_type))
        width, field, kind = CORNER_TYPES[attribute.data_type]
        values = numpy.empty(count * width, dtype=kind)
        attribute.data.foreach_get(field, values)
        attribute.data.foreach_set(field, values.reshape(count, width)[order].ravel())


def unique_rank(obj, what, elements, key):
    """Each element's place (by its index) when sorted by `key`; refuses two elements with one key,
    because their order would be left to chance."""
    keyed = sorted(((key(element), element.index) for element in elements), key=lambda pair: pair[0])
    for (first, _), (second, _) in zip(keyed, keyed[1:]):
        if first == second:
            raise RuntimeError("%s: two %s can't be told apart, so their order would vary" % (obj.name, what))
    return {index: place for place, (_, index) in enumerate(keyed)}
