"""The props' shared texture set (#1853): a few CC0 textures (stone, sandstone, wood, moss),
each reduced to a few flat tones for the game's cel shading by `prop_textures.py` and kept in
`textures/`, which every world prop paints itself from. A prop generated as a bare shape (5
credits, the owner's pick on #1846) needs no texture of its own, only the mapping of its parts
onto the set.

**The mapping** needs no UVs from anyone: `box_uv` projects the textures onto each face from the
side it faces most (triplanar, baked into the UVs, so the glTF needs no shader of its own), at
the same size on every prop. `mossiness` says where moss grows (faces pointing up, with a wobbly
edge) and `darkness` where the stone is shaded (crevices from `occlusion`, a darker foot);
`contour` cuts the faces along each edge, so the moss and the shaded step are clean flat areas,
each a material of the set (a shaded step is the texture times a grey factor).

Everything per vertex is + - * / and floor on numpy arrays, and the noise's lattice is an integer
hash, so a build on another machine gives the same bytes. Blender is Z-up; the ground is z = 0."""

import math
import os

import bmesh
import bpy
import numpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

# The set, made by prop_textures.py: one PNG per material.
TEXTURES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "textures")
# Metres one repeat of a texture covers, the same on every prop, so props side by side match.
REPEAT = 0.9


def material(name, texture_name=None, factor=1.0):
    """A material of the set: the texture `texture_name` (stone, sandstone, wood, moss; `name`
    when None) times a grey `factor` (linear: a darker step of it), matte and single-sided. Every
    prop's materials load the same files; the glTF keeps the factor as its base colour factor."""
    texture_name = texture_name or name
    image = bpy.data.images.get(texture_name) or bpy.data.images.load(os.path.join(TEXTURES, texture_name + ".png"))
    image.name = texture_name
    image.pack()
    mat = bpy.data.materials.new(name)
    mat.use_backface_culling = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes["Principled BSDF"]
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    if factor == 1.0:
        links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    else:
        mix = nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        links.new(texture.outputs["Color"], mix.inputs["A"])
        mix.inputs["B"].default_value = (factor, factor, factor, 1.0)
        links.new(mix.outputs["Result"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 1.0
    return mat


def box_uv(mesh, repeat=REPEAT):
    """Triplanar UVs: each face takes the texture from the axis its normal points along most,
    its corners' other two coordinates in metres over `repeat`."""
    layer = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        normal = polygon.normal
        axis = max(range(3), key=lambda index: abs(normal[index]))
        # The two other axes, turned so the texture isn't mirrored on the far side.
        first, second = {0: (1, 2), 1: (0, 2), 2: (0, 1)}[axis]
        flip = -1.0 if normal[axis] < 0.0 else 1.0
        if axis == 1:
            flip = -flip
        for loop in polygon.loop_indices:
            point = mesh.vertices[mesh.loops[loop].vertex_index].co
            layer.data[loop].uv = (flip * point[first] / repeat, point[second] / repeat)


def glow(name, colour):
    """A part that glows once the game turns it on (a savepoint's hole, #1854): a flat `colour`
    (sRGB, as the set's tones) with no emission in the file. The game finds it by `name` and sets
    its emission."""
    mat = bpy.data.materials.new(name)
    mat.use_backface_culling = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    # A node's colour is linear; the set's tones are sRGB.
    linear = [channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4 for channel in colour]
    shader.inputs["Base Color"].default_value = (*linear, 1.0)
    shader.inputs["Roughness"].default_value = 1.0
    shader.inputs["Emission Strength"].default_value = 0.0
    return mat


def _hash(ix, iy, iz, seed):
    """A value 0..1 per integer lattice point, from integer arithmetic alone."""
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = h & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def noise(points, size, seed, stretch=(1.0, 1.0, 1.0)):
    """Smooth value noise, -1..1, at `points` (n, 3): blobs about `size` across, each axis's
    size times its `stretch` (a long z stretch makes streaks running down)."""
    at = numpy.asarray(points, dtype=float) / (size * numpy.asarray(stretch, dtype=float))
    base = numpy.floor(at)
    frac = at - base
    ease = frac * frac * (3.0 - 2.0 * frac)
    base = base.astype(numpy.int64)
    total = numpy.zeros(len(at))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                weight = ((ease[:, 0] if dx else 1.0 - ease[:, 0]) * (ease[:, 1] if dy else 1.0 - ease[:, 1])
                          * (ease[:, 2] if dz else 1.0 - ease[:, 2]))
                total += weight * _hash(base[:, 0] + dx, base[:, 1] + dy, base[:, 2] + dz, seed)
    return total * 2.0 - 1.0


def directions(count):
    """`count` directions spread evenly over the upper unit hemisphere (a Fibonacci spiral)."""
    golden = math.pi * (3.0 - math.sqrt(5.0))
    out = []
    for index in range(count):
        z = 1.0 - (index + 0.5) / count
        ring = math.sqrt(1.0 - z * z)
        out.append((math.cos(golden * index) * ring, math.sin(golden * index) * ring, z))
    return numpy.array(out)


def occlusion(obj, points, normals, reach, rays=24):
    """How shut in each vertex is (0 open .. 1 shut): the share of `rays` directions around its
    normal that hit `obj`'s mesh (in its own space) within `reach`, a crevice's or a hole's darkness
    without a bake."""
    mesh = obj.data
    tree = BVHTree.FromPolygons([vertex.co[:] for vertex in mesh.vertices],
                                [tuple(polygon.vertices) for polygon in mesh.polygons])
    spread = directions(rays)
    shut = numpy.zeros(len(points))
    for index, (point, normal) in enumerate(zip(points, normals)):
        up = Vector(normal).normalized()
        turn = Vector((0.0, 0.0, 1.0)).rotation_difference(up)
        start = Vector(point) + up * 1e-3
        hits = 0
        for direction in spread:
            if tree.ray_cast(start, turn @ Vector(direction), reach)[0] is not None:
                hits += 1
        shut[index] = hits / rays
    return shut


def smoothstep(low, high, value):
    t = numpy.clip((value - low) / (high - low), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class Weathering:
    """The recipe's knobs (sizes in metres): a prop script changes only what differs."""

    seed = 1853
    crevice = 1.0        # darkness at full occlusion
    foot = 0.55          # darkness at the ground
    foot_height = 0.30   # where the foot's darkness has faded out
    foot_wobble = 0.10
    shaded = 0.30        # a vertex darker than this is in the shaded step
    shade = 0.45         # the shaded step's factor (linear: about 0.70 seen)
    moss_up = 0.55       # moss where the normal's upward share passes this
    moss_wobble = 0.15
    moss_size = 0.08


def darkness(points, shut, knobs=Weathering, foot=True):
    """Each vertex's darkness (0 lit ..): crevices and, with `foot`, near the ground, with a
    wobbly edge. `knobs.shaded` is the edge of the shaded step."""
    points = numpy.asarray(points, dtype=float)
    dark = knobs.crevice * numpy.asarray(shut, dtype=float)
    if foot:
        wobble = knobs.foot_wobble * noise(points, knobs.foot_height * 0.5, knobs.seed + 3)
        dark = dark + knobs.foot * (1.0 - smoothstep(0.0, knobs.foot_height, points[:, 2] + wobble))
    return dark


def mossiness(points, normals, knobs=Weathering):
    """Each vertex's moss (above 0 grows moss): how far its normal points up past `moss_up`, give
    or take a noise that wobbles the edge."""
    points = numpy.asarray(points, dtype=float)
    return numpy.asarray(normals, dtype=float)[:, 2] - knobs.moss_up + knobs.moss_wobble * noise(points, knobs.moss_size, knobs.seed + 4)


def contour(mesh, values, level):
    """Cuts `mesh`'s faces along where `values` (one per vertex, linear along each edge) cross
    `level`, so every face lies wholly on one side and a colour edge drawn there runs straight
    through the faces, not along their jagged edges. Returns the values of the new mesh's
    vertices (a cut's own at `level`)."""
    work = bmesh.new()
    work.from_mesh(mesh)
    layer = work.verts.layers.float.new("value")
    work.verts.ensure_lookup_table()
    for vert, value in zip(work.verts, values):
        vert[layer] = float(value)
    cut = set()
    for edge in sorted(work.edges, key=lambda item: tuple(sorted(vert.index for vert in item.verts))):
        first, second = edge.verts
        a, b = first[layer] - level, second[layer] - level
        if a * b < 0.0:
            share = a / (a - b)
            _edge, vert = bmesh.utils.edge_split(edge, first, share)
            vert[layer] = level
            cut.add(vert)
    for face in list(work.faces):
        ends = [vert for vert in face.verts if vert in cut]
        if len(ends) == 2 and not any(ends[1] in edge.verts for edge in ends[0].link_edges):
            bmesh.ops.connect_verts(work, verts=ends)
    bmesh.ops.triangulate(work, faces=[face for face in work.faces if len(face.verts) > 3])
    out = [vert[layer] for vert in work.verts]
    work.to_mesh(mesh)
    work.free()
    mesh.update()
    return numpy.array(out)


def side(mesh, values, level):
    """For each face, whether it lies above `level` (after `contour`: its corners' mean does)."""
    return numpy.array([numpy.mean([values[index] for index in polygon.vertices]) > level for polygon in mesh.polygons])
