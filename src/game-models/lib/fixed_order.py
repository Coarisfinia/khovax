"""Mesh steps that come out alike on any count of Blender's threads (#2301, #2317).

Some of Blender's own steps run on several threads, and what they hand back changes with the
count: `bmesh.ops.remove_doubles` picks other survivors, `bmesh.ops.bisect_plane` hands back its
faces in another order, each starting at another corner, and a vertex's normal, summed from its
faces on several threads, differs in the last bits. A later step follows them (a cap's triangles,
a paint's cut), so a build on a machine with another count of cores would differ from the committed
.glb (check_rebuild.py builds on two counts to catch it). These do the same in a fixed order:

- `weld` joins vertices by position, in place of `remove_doubles`.
- `canonical` rebuilds a bmesh in a fixed order, its vertices by position and its faces by their
  vertices, each starting at its lowest one.
- `cut` is `bisect_plane` with its cut closed, from and to that fixed order.
- `vertex_normals` sums each vertex's normal from its faces' in their order, by area or by angle.
- `snap` puts a mesh's vertices on a fine grid, where another machine's float maths lands alike.
"""

import bmesh
import numpy


def weld(work, decimals=5):
    """Joins the vertices of the bmesh `work` that meet on a grid of `decimals` (the seam splits),
    so the surface shades whole, not island by island. The first vertex at a place stays."""
    first = {}
    targets = {}
    for vert in work.verts:
        key = tuple(round(value, decimals) for value in vert.co)
        if key in first:
            targets[vert] = first[key]
        else:
            first[key] = vert
    bmesh.ops.weld_verts(work, targetmap=targets)


def canonical(work, decimals=6):
    """Rebuilds the bmesh `work` in a fixed order: its vertices by position (on a grid of
    `decimals`), its faces by their vertices, each starting at its lowest one. A sliver whose
    corners met on the grid is dropped. Only positions and faces are kept."""
    points = sorted({tuple(round(value, decimals) for value in vert.co) for vert in work.verts})
    index = {point: place for place, point in enumerate(points)}
    faces = set()
    for face in work.faces:
        ring = [index[tuple(round(value, decimals) for value in vert.co)] for vert in face.verts]
        ring = [place for step, place in enumerate(ring) if place != ring[step - 1]]
        if len(set(ring)) < 3 or len(set(ring)) != len(ring):
            continue
        start = ring.index(min(ring))
        faces.add(tuple(ring[start:] + ring[:start]))
    work.clear()
    verts = [work.verts.new(point) for point in points]
    for face in sorted(faces):
        work.faces.new([verts[place] for place in face])
    work.verts.index_update()
    work.faces.index_update()


def cut(work, point, normal):
    """Cuts the bmesh `work` at the plane through `point`, keeping the side `normal` points away
    from, and closes the cut with flat faces; `work` comes out in `canonical` order."""
    canonical(work)
    bmesh.ops.bisect_plane(work, geom=work.verts[:] + work.edges[:] + work.faces[:], dist=1e-6,
                           plane_co=point, plane_no=normal, clear_outer=True)
    canonical(work)
    filled = bmesh.ops.holes_fill(work, edges=[edge for edge in work.edges if edge.is_boundary])
    # Ear clipping, not "beauty": a flat cap's beauty flips hang on ties between equal angles.
    bmesh.ops.triangulate(work, faces=filled["faces"], quad_method="FIXED", ngon_method="EAR_CLIP")
    canonical(work)


def vertex_normals(mesh, decimals=None, angle=False):
    """Each vertex's normal of `mesh` (n, 3), summed from its faces' normals in the faces' order,
    and rounded to `decimals` when given. Each face counts by its area, or with `angle` by its
    corner's angle at the vertex, as Blender weighs its own (so they match it but for float noise)."""
    points = numpy.array([vertex.co[:] for vertex in mesh.vertices])
    normals = numpy.zeros((len(mesh.vertices), 3))
    for polygon in mesh.polygons:
        ring = list(polygon.vertices)
        normal = numpy.array(polygon.normal[:])
        for step, index in enumerate(ring):
            if angle:
                before = points[ring[step - 1]] - points[index]
                after = points[ring[(step + 1) % len(ring)]] - points[index]
                lengths = numpy.linalg.norm(before) * numpy.linalg.norm(after)
                if lengths == 0.0:
                    continue  # a corner on a collapsed edge has no angle to weigh
                cosine = numpy.dot(before, after) / lengths
                normals[index] += normal * numpy.arccos(numpy.clip(cosine, -1.0, 1.0))
            else:
                normals[index] += normal * polygon.area
    lengths = numpy.linalg.norm(normals, axis=1, keepdims=True)
    normals = normals / numpy.maximum(lengths, 1e-12)
    return normals if decimals is None else numpy.round(normals, decimals)


def snap(mesh, decimals):
    """Puts every vertex of `mesh` on a grid of `decimals` (metres)."""
    points = numpy.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", points)
    mesh.vertices.foreach_set("co", numpy.round(points, decimals))
    mesh.update()
