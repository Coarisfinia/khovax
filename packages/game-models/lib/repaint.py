"""Paints a model's texture anew from where each texel lies on the body (#1609), for a generated
model whose own paint is messy: the generator's atlas is hundreds of scattered islands, so it
can't be painted over by hand, but every texel of it shows one spot of the mesh. `Texels` finds
that spot (and the face it's on) for every texel the mesh's UVs cover, so a model script colours
the texture by position on the body: one side one way and the other side another, a part all
one colour, the soles plain.

- `pieces`: the mesh's connected pieces (welded by position, through the export's seam splits),
  so a script can tell a tail or an eye from the body.
- `Texels`: every covered texel's spot, the face's normal and its piece, at rest.
- `Cells`: cellular (Worley) noise in 3D from a fixed seed: each spot's nearest feature point,
  and how far it lies from the border with the next, for cracked rock or ice whose cracks run
  across the islands' seams unbroken.
- `image`: the painted texels as a packed Blender image, the gaps between islands filled from
  their edges (`dilate`), so filtering and mipmaps never pull in a blank.

Only + - * / and square roots run per texel, and the feature points come from Python's own
seeded generator, so a build on another machine gives the same bytes (as lib/starfield.py).

Blender is Z-up and the model faces -Y; a part's left is +X."""

import random

import bpy
import numpy

# How many cubes out each way the cellular noise looks for a spot's nearest feature points.
REACH = 2
# Vertices closer than this are one spot: the export splits a vertex wherever its UVs part.
WELD = 5


def pieces(mesh):
    """{face index: piece number} for `mesh`'s polygons, faces joined where they share an edge
    (welded by position, through the export's seam splits; a piece only touching another at a
    point, as an eye set in its socket, stays apart), the pieces numbered by size, largest first
    (ties by their lowest face)."""
    spot = [tuple(round(value, WELD) for value in vertex.co) for vertex in mesh.vertices]
    parent = list(range(len(mesh.polygons)))

    def root(item):
        while parent[item] != item:
            parent[item] = parent[parent[item]]
            item = parent[item]
        return item

    edges = {}
    for polygon in mesh.polygons:
        corners = [spot[index] for index in polygon.vertices]
        for first, second in zip(corners, corners[1:] + corners[:1]):
            other = edges.setdefault((min(first, second), max(first, second)), polygon.index)
            low, high = sorted((root(other), root(polygon.index)))
            parent[high] = low
    groups = {}
    for polygon in mesh.polygons:
        groups.setdefault(root(polygon.index), []).append(polygon.index)
    order = sorted(groups.values(), key=lambda faces: (-len(faces), faces[0]))
    return {face: number for number, faces in enumerate(order) for face in faces}


class Texels:
    """Every texel of a `size`-square texture that `mesh`'s active UVs cover: its row and column
    (rows from the bottom, as Blender's pixels run), the spot on the mesh it shows, the normal of
    the face it's on and that face's index. Where islands overlap, the later face wins."""

    def __init__(self, mesh, size):
        self.size = size
        uvs = mesh.uv_layers.active.data
        mesh.calc_loop_triangles()
        owner = numpy.full((size, size), -1, dtype=numpy.int64)
        weights = numpy.zeros((size, size, 3))
        corners = []
        for number, triangle in enumerate(mesh.loop_triangles):
            uv = numpy.array([uvs[loop].uv[:] for loop in triangle.loops]) * size - 0.5
            corners.append([mesh.vertices[index].co[:] for index in triangle.vertices])
            low = numpy.maximum(numpy.floor(uv.min(axis=0)).astype(int), 0)
            high = numpy.minimum(numpy.ceil(uv.max(axis=0)).astype(int), size - 1)
            if (high < low).any():
                continue
            columns, rows = numpy.meshgrid(numpy.arange(low[0], high[0] + 1), numpy.arange(low[1], high[1] + 1))
            (ax, ay), (bx, by), (cx, cy) = uv
            area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
            if area == 0.0:
                continue
            # The texel centre's barycentric weights on the triangle; a little slack takes in
            # the texels its edges cross, so islands meet without a hairline gap.
            first = ((bx - columns) * (cy - rows) - (cx - columns) * (by - rows)) / area
            second = ((cx - columns) * (ay - rows) - (ax - columns) * (cy - rows)) / area
            third = 1.0 - first - second
            inside = (first >= -0.02) & (second >= -0.02) & (third >= -0.02)
            owner[rows[inside], columns[inside]] = number
            weights[rows[inside], columns[inside]] = numpy.stack(
                [first[inside], second[inside], third[inside]], axis=-1)
        self.rows, self.columns = numpy.nonzero(owner >= 0)
        triangles = owner[self.rows, self.columns]
        corners = numpy.array(corners)[triangles]
        share = numpy.clip(weights[self.rows, self.columns], 0.0, None)
        share = share / share.sum(axis=1, keepdims=True)
        self.spots = (corners * share[..., None]).sum(axis=1)
        self.faces = numpy.array([triangle.polygon_index for triangle in mesh.loop_triangles])[triangles]
        normals = numpy.array([polygon.normal[:] for polygon in mesh.polygons])
        self.normals = normals[self.faces]

    def canvas(self, colour):
        """A blank `size`-square RGB canvas filled with `colour`."""
        return numpy.broadcast_to(numpy.asarray(colour, dtype=float), (self.size, self.size, 3)).copy()

    def paint(self, canvas, colours):
        """Writes one colour a texel (an array in the texels' order) onto `canvas`."""
        canvas[self.rows, self.columns] = colours
        return canvas

    def covered(self):
        mask = numpy.zeros((self.size, self.size), dtype=bool)
        mask[self.rows, self.columns] = True
        return mask


class Cells:
    """Cellular noise: one feature point in each `cell`-sized cube of a grid over `low` to `high`
    (with a cube's margin), jittered from `seed`."""

    def __init__(self, low, high, cell, seed):
        self.cell = cell
        self.origin = numpy.asarray(low, dtype=float) - cell
        self.shape = tuple(int(n) for n in numpy.ceil((numpy.asarray(high) - self.origin) / cell) + 2)
        rolls = random.Random(seed)
        count = self.shape[0] * self.shape[1] * self.shape[2]
        jitter = numpy.array([[rolls.random() for _axis in range(3)] for _point in range(count)])
        grid = numpy.stack(numpy.meshgrid(*[numpy.arange(n) for n in self.shape], indexing="ij"), axis=-1)
        self.points = self.origin + (grid.reshape(-1, 3) + jitter) * cell

    def near(self, spots):
        """For each spot: the index of its nearest feature point, and how far it lies from the
        border with the next nearest (half the difference of their distances: 0 on a crack)."""
        base = numpy.floor((spots - self.origin) / self.cell).astype(int)
        first = numpy.full(len(spots), numpy.inf)
        second = numpy.full(len(spots), numpy.inf)
        nearest = numpy.zeros(len(spots), dtype=numpy.int64)
        nx, ny, nz = self.shape
        # Two cubes out each way: a jittered point two cubes away can be nearer than every one
        # beside the spot's own cube, the second nearest more often still.
        reach = range(-REACH, REACH + 1)
        for dx in reach:
            for dy in reach:
                for dz in reach:
                    at = numpy.clip(base + (dx, dy, dz), 0, numpy.array(self.shape) - 1)
                    index = (at[:, 0] * ny + at[:, 1]) * nz + at[:, 2]
                    offset = self.points[index] - spots
                    distance = numpy.sqrt((offset * offset).sum(axis=1))
                    closer = distance < first
                    second = numpy.where(closer, first, numpy.minimum(second, distance))
                    nearest = numpy.where(closer, index, nearest)
                    first = numpy.where(closer, distance, first)
        return nearest, (second - first) / 2.0


def dilate(canvas, covered, steps):
    """Spreads the covered texels' colours `steps` texels into the blank around them, each blank
    texel taking the mean of its covered neighbours."""
    canvas, covered = canvas.copy(), covered.copy()
    for _step in range(steps):
        total = numpy.zeros_like(canvas)
        count = numpy.zeros(covered.shape)
        # Padded rather than rolled, so nothing spreads across the texture's edge from the far side.
        cover = numpy.pad(covered, 1)
        paint = numpy.pad(canvas, ((1, 1), (1, 1), (0, 0)))
        height, width = covered.shape
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shifted = cover[1 + dy:1 + dy + height, 1 + dx:1 + dx + width]
            total += paint[1 + dy:1 + dy + height, 1 + dx:1 + dx + width] * shifted[..., None]
            count += shifted
        grow = ~covered & (count > 0)
        canvas[grow] = total[grow] / count[grow][:, None]
        covered = covered | grow
    return canvas


def image(name, canvas):
    """`canvas` (RGB rows from the bottom, sRGB 0..1) as a packed 8-bit Blender image."""
    size = canvas.shape[0]
    rgba = numpy.ones((size, canvas.shape[1], 4))
    rgba[..., :3] = numpy.clip(canvas, 0.0, 1.0)
    out = bpy.data.images.new(name, canvas.shape[1], size, alpha=False)
    out.pixels.foreach_set(rgba.astype(numpy.float32).ravel())
    out.file_format = "PNG"
    out.pack()
    return out
