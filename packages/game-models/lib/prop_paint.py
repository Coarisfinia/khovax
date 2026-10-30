"""The props' shared texture set (#1853): one small atlas of flat matte tones that every world
prop paints itself from, so a prop generated as a bare shape (5 credits, the owner's pick on
#1846) needs no texture of its own, only the mapping of its parts onto the set.

**The set** (`SET`, `MOSS`) is one tile per material (stone, sandstone, wood, rope, iron), each a
lookup table rather than a picture: across it (u) its tones in flat bands, light to dark; up it (v)
bare in the lower half and moss in the upper half, the moss in its own bands. `atlas` draws it
from the tones alone, so the set is this file and nothing else, the same for every prop (the
sandstone wall, turret and floor match by construction), with no painted shading: the game's cel
shading does the light.

**The mapping** gives every vertex a material, a **tone** (0 light .. 1 dark) and a **cover**
(0 bare .. 1 moss), and `uv` turns those into the vertex's spot on its tile. A triangle between a
light vertex and a dark one runs through the bands between them, so a band's edge falls where the
tone crosses it, a clean line inside the triangle rather than a jagged one along its edges: the
bands read as flat colour areas, as a toon ramp does. `weathered` is the stone's recipe: tones
from darker crevices (`occlusion`), chips (`chips`), weathering streaks running down (`noise`,
stretched) and a darker foot; moss where faces point up.

Everything per vertex is + - * / and floor on numpy arrays, the noise's lattice is an integer
hash and the chips' points come from Python's own seeded generator (lib/repaint.py's `Cells`),
so a build on another machine gives the same bytes. Blender is Z-up; the ground is z = 0."""

import math

import bpy
import numpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import repaint

# The atlas: tiles of TILE texels square, COLUMNS across and ROWS up. A tile's outer GUTTER texels
# repeat its edge's colour and no UV reaches into them, so a mipmap blends a tile only with itself
# until far away.
TILE = 64
GUTTER = 4
COLUMNS, ROWS = 4, 2
WIDTH, HEIGHT = TILE * COLUMNS, TILE * ROWS

# The set: each material's tones, light to dark, in sRGB (0..1). Stone is pale and weathered,
# with a cool grey for its chips and a deep grey for its crevices; the rest follow the same steps.
SET = {
    "stone": ((0.80, 0.78, 0.72), (0.70, 0.68, 0.63), (0.60, 0.59, 0.56), (0.48, 0.48, 0.47), (0.34, 0.34, 0.35)),
    "sandstone": ((0.90, 0.80, 0.62), (0.82, 0.70, 0.52), (0.72, 0.59, 0.42), (0.58, 0.46, 0.33), (0.42, 0.33, 0.25)),
    "wood": ((0.66, 0.50, 0.34), (0.56, 0.41, 0.27), (0.46, 0.33, 0.21), (0.36, 0.25, 0.16), (0.25, 0.17, 0.11)),
    "rope": ((0.86, 0.76, 0.56), (0.77, 0.66, 0.46), (0.66, 0.55, 0.37), (0.53, 0.43, 0.29), (0.40, 0.32, 0.22)),
    "iron": ((0.56, 0.58, 0.60), (0.45, 0.47, 0.50), (0.36, 0.37, 0.40), (0.27, 0.28, 0.30), (0.19, 0.19, 0.21)),
}
# The moss over any material, light to dark: its top fringe catches the light, its body is a
# deep green.
MOSS = ((0.58, 0.66, 0.30), (0.42, 0.53, 0.22), (0.30, 0.41, 0.17))
# Each material's tile, (column, row), in the order of SET.
SLOTS = {name: (index % COLUMNS, index // COLUMNS) for index, name in enumerate(SET)}


def atlas():
    """The set as an RGB canvas (HEIGHT rows from the bottom, as Blender's pixels run, by WIDTH),
    sRGB 0..1. An empty slot is the stone's base tone."""
    canvas = numpy.empty((HEIGHT, WIDTH, 3))
    canvas[:] = SET["stone"][2]
    inner = TILE - 2 * GUTTER
    # Each texel column's tone and each texel row's cover, measured inside the gutter and
    # clamped to it, so the gutter repeats the edge.
    along = numpy.clip((numpy.arange(TILE) + 0.5 - GUTTER) / inner, 0.0, 1.0 - 1e-9)
    for name, (column, row) in SLOTS.items():
        tones = numpy.array(SET[name])
        moss = numpy.array(MOSS)
        bare = tones[(along * len(tones)).astype(int)]
        mossy = moss[(along * len(moss)).astype(int)]
        tile = numpy.where((along >= 0.5)[:, None, None], mossy[None, :, :], bare[None, :, :])
        canvas[row * TILE:(row + 1) * TILE, column * TILE:(column + 1) * TILE] = tile
    return canvas


def uv(name, tone, cover):
    """The UVs (n, 2) of vertices of material `name` with `tone` and `cover` (each n values, 0..1)
    on its tile. A cover of 0.5 is moss's edge, so a mapping keeps bare vertices at or below
    `BARE` and mossy ones at or above `MOSSY`, away from the edge, and lets the edge fall between."""
    column, row = SLOTS[name]
    inner = TILE - 2 * GUTTER
    u = (column * TILE + GUTTER + numpy.clip(tone, 0.0, 1.0) * inner) / WIDTH
    v = (row * TILE + GUTTER + numpy.clip(cover, 0.0, 1.0) * inner) / HEIGHT
    return numpy.stack([u, v], axis=1)


# How far from moss's edge (0.5) a vertex's cover sits, either side.
BARE, MOSSY = 0.25, 0.75


def material(name="prop_textures"):
    """The one material every prop's painted parts share: the atlas, matte and single-sided."""
    canvas = atlas()
    image = repaint.image(name, canvas)
    mat = bpy.data.materials.new(name)
    mat.use_backface_culling = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes["Principled BSDF"]
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 1.0
    return mat


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


def chips(points, size, share, seed, low, high):
    """1 where a vertex lies in a chip, else 0: the stone broken into cells about `size` across
    (lib/repaint.py's `Cells`), a `share` of them chipped."""
    cells = repaint.Cells(low, high, size, seed)
    nearest, _border = cells.near(numpy.asarray(points, dtype=float))
    index = numpy.arange(len(cells.points), dtype=numpy.int64)
    picks = _hash(index, numpy.zeros_like(index), numpy.zeros_like(index), seed)
    return (picks[nearest] < share).astype(float)


def smoothstep(low, high, value):
    t = numpy.clip((value - low) / (high - low), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class Weathering:
    """The stone recipe's knobs (sizes in metres): a prop script changes only what differs."""

    seed = 1853
    base = 0.30          # the open face's tone, between the light and the base band
    patches = 0.07       # large light and dark patches across the faces
    patch_size = 0.40
    streaks = 0.28       # weathering streaks running down
    streak_size = 0.035
    streak_stretch = 12.0
    chip = 0.32          # a chip's extra darkness
    chip_size = 0.10
    chip_share = 0.20
    crevice = 0.9        # darkness at full occlusion
    foot = 0.32          # darkness at the ground
    foot_height = 0.16   # where the foot's darkness has faded out
    foot_wobble = 0.05
    moss_up = 0.62       # moss where the normal's upward share passes this
    moss_wobble = 0.12
    moss_size = 0.08
    moss_fringe = 0.08   # how far past moss's edge its light fringe reaches, in upward share


def weathered(points, normals, shut, knobs=Weathering, moss=True):
    """The stone's tone and cover per vertex (each n values, 0..1) from its spot, normal and
    occlusion: open faces in light and dark patches with streaks running down, darker chips, crevices
    and foot; and with `moss`, moss where faces point up."""
    points = numpy.asarray(points, dtype=float)
    normals = numpy.asarray(normals, dtype=float)
    low, high = points.min(axis=0), points.max(axis=0)
    tone = numpy.full(len(points), knobs.base)
    tone += knobs.patches * noise(points, knobs.patch_size, knobs.seed)
    tone += knobs.streaks * noise(points, knobs.streak_size, knobs.seed + 1, (1.0, 1.0, knobs.streak_stretch))
    tone += knobs.chip * chips(points, knobs.chip_size, knobs.chip_share, knobs.seed + 2, low, high)
    tone += knobs.crevice * shut
    wobble = knobs.foot_wobble * noise(points, knobs.foot_height, knobs.seed + 3)
    tone += knobs.foot * (1.0 - smoothstep(0.0, knobs.foot_height, points[:, 2] + wobble))
    cover = numpy.full(len(points), BARE)
    if moss:
        edge = normals[:, 2] + knobs.moss_wobble * noise(points, knobs.moss_size, knobs.seed + 4)
        # Mapped steeply around the edge, so a triangle's moss line falls where `edge` crosses
        # moss_up and the moss's own bands follow it inward.
        cover = numpy.clip(0.5 + (edge - knobs.moss_up) * 4.0, 0.0, 1.0)
        # The moss's own tones: a light fringe along its edge, its body in patches, darker where
        # it is shut in.
        fringe = 1.0 - smoothstep(knobs.moss_up, knobs.moss_up + knobs.moss_fringe, edge)
        mossy = 0.5 + 0.3 * noise(points, knobs.moss_size * 2.0, knobs.seed + 5) + 0.5 * shut - 0.45 * fringe
        tone = numpy.where(cover >= 0.5, mossy, tone)
    return numpy.clip(tone, 0.0, 1.0), cover


def apply(mesh, uvs_per_vertex, faces=None):
    """Writes each vertex's UV onto every face corner of it (all faces, or only `faces`)."""
    layer = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    wanted = None if faces is None else set(faces)
    for polygon in mesh.polygons:
        if wanted is not None and polygon.index not in wanted:
            continue
        for loop in polygon.loop_indices:
            layer.data[loop].uv = tuple(uvs_per_vertex[mesh.loops[loop].vertex_index])
