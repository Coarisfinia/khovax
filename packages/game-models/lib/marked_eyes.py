"""Our own eyes in place of the ones a generator painted (#1682, #1683). Every prompt for a
generated beast carries the fixed sentence "Two small, plain, flat black oval eyes." (the model
skill), which only marks where its eyes go and how big they are. On import, the model script
calls `replace` on its adopted rig and skin, which:

- **finds** the two marked ovals on the head (`find`): spots of the base colour that `DARK` (or,
  for a beast imported with glowing eyes before the rule, `GLOW`) picks out, grouped where they
  lie, the pair that mirror each other across the middle best;
- **repaints** them (`repaint`): every texel over each oval, with a margin for its soft edge, takes
  the colour of the skin around it, blended from that ring by distance, so no painted eye shows
  past ours;
- **fits our eyes** there (`fit`, lib/eyes.py): their position, size, height and spacing from the
  marks, mirrored, each with a lid on a bone of its own (`eyes.Lids`), joined into the skin.

The lids shut in Sleep, over Faint's fall and in a blink now and then in Idle: `replace` returns
the `eyes.Lids`, whose `shut` goes into `clips.animate`'s overlays, and the eye points for
`attachments.add`.

Blender is Z-up and the model faces -Y; its left is +X. Rig space is world space (the adopted
rig is flattened, rigged.flatten), the skin at the identity. Only + - * / run per texel, so a
build on another machine paints the same bytes (as lib/starfield.py)."""

import bpy
import numpy
from mathutils import Vector

from . import eyes, materials, scene

# A marked eye's flat black: every channel at or below this (sRGB, 0..1).
DARK_VALUE = 0.2
# A painted glowing eye (as inspect_meshy.py finds them): bright and saturated.
GLOW_VALUE, GLOW_SATURATION = 0.75, 0.3
# A vertex is the head's when its weight to the head bone is at least this.
HEAD_WEIGHT = 0.5
# How finely each triangle is sampled: a grid of this many steps along each side.
STEPS = 6
# Grid cells the head's longest side is cut into to group the marked samples into spots.
CELLS = 40
# A spot with fewer samples is noise (a speck of shadow in the paint), not an eye.
MIN_SAMPLES = 8
# How far apart the left mark and the right one mirrored may lie, as a share of their mean width,
# and how much wider one may be than the other.
MIRROR, WIDER = 0.6, 2.0
# The repaint, in the oval's own radii (1 at its edge): every texel inside FILL is painted over,
# blended from the skin's samples between RING_IN and RING_OUT.
FILL, RING_IN, RING_OUT = 1.35, 1.5, 2.3
# How many texels the repaint blends at once.
CHUNK = 1024
# The eye's front, which the head's skin must not cover (`buried`): at most BURIED of its
# vertices may lie under it (a vertex or two at the iris's very edge, where it meets the skin), and
# `clear` tries the eye further out and across the head in STEPs of its size, at most OUT out and
# SHIFT across.
FRONT = (".iris", ".pupil")
BURIED, STEP, OUT, SHIFT = 0.02, 0.05, 0.5, 0.2
# Which way our eyes look, blended with the head's surface there (eyes.eye): ahead and a little
# out on the left (+X); the right mirrors it.
FORWARD = (0.25, -1.0, 0.0)
# How round our eye is at most and least (eyes.eye's `almond`: 1 is round).
ALMOND = (0.5, 1.0)


def DARK(colours):
    """Which of `colours` (rows of sRGB) are a marked eye's flat black."""
    return colours.max(axis=1) <= DARK_VALUE


def GLOW(colours):
    """Which of `colours` are a painted glowing eye's (bright and saturated)."""
    value = colours.max(axis=1)
    saturation = (value - colours.min(axis=1)) / numpy.maximum(value, 1e-6)
    return (value >= GLOW_VALUE) & (saturation >= GLOW_SATURATION)


def texture(skin):
    """The one base colour image `skin`'s materials share (import_source.py keeps only that)."""
    found = set()
    for material in skin.data.materials:
        shader = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
        if shader is not None and shader.inputs["Base Color"].links:
            node = shader.inputs["Base Color"].links[0].from_node
            if node.type == "TEX_IMAGE" and node.image is not None:
                found.add(node.image)
    if len(found) != 1:
        raise ValueError("%s: expected one base colour texture, found %d" % (skin.name, len(found)))
    return found.pop()


class Head:
    """The faces of `skin` that `bone` moves (each corner weighted to it at least HEAD_WEIGHT),
    sampled: every sample's spot, its colour on the base colour texture and its face's normal,
    and the texture's pixels (rows from the bottom, as Blender's run)."""

    def __init__(self, skin, bone):
        data = skin.data
        self.image = texture(skin)
        width, height = self.image.size
        pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
        self.image.pixels.foreach_get(pixels)
        self.pixels = pixels.reshape(height, width, 4)
        group = skin.vertex_groups[bone].index
        heads = numpy.array([any(item.group == group and item.weight >= HEAD_WEIGHT for item in vertex.groups)
                             for vertex in data.vertices])
        matrix = numpy.array(skin.matrix_world)
        corners = numpy.array([vertex.co[:] for vertex in data.vertices])
        corners = corners @ matrix[:3, :3].T + matrix[:3, 3]
        uvs = data.uv_layers.active.data
        data.calc_loop_triangles()
        mine = [triangle for triangle in data.loop_triangles if heads[list(triangle.vertices)].all()]
        if not mine:
            raise ValueError("%s: no faces weighted to %s" % (skin.name, bone))
        # Each head triangle's corners: spot and UV.
        self.spots = corners[numpy.array([triangle.vertices[:] for triangle in mine])]
        self.uvs = numpy.array([[uvs[loop].uv[:] for loop in triangle.loops] for triangle in mine])
        normals = numpy.array([triangle.normal[:] for triangle in mine])
        weights = numpy.array([(i, j, STEPS - i - j) for i in range(STEPS + 1) for j in range(STEPS + 1 - i)],
                              dtype=float) / STEPS
        self.points = numpy.einsum("ws,tsk->twk", weights, self.spots).reshape(-1, 3)
        self.normals = numpy.repeat(normals, len(weights), axis=0)
        self.colours = self.look(numpy.einsum("ws,tsk->twk", weights, self.uvs).reshape(-1, 2))

    def look(self, uv):
        """The texture's colour (sRGB) at each of `uv`, its nearest texel."""
        height, width = self.pixels.shape[:2]
        columns = numpy.clip(numpy.floor(uv[:, 0] * width), 0, width - 1).astype(numpy.int64)
        rows = numpy.clip(numpy.floor(uv[:, 1] * height), 0, height - 1).astype(numpy.int64)
        return self.pixels[rows, columns, :3].astype(float)


class Mark:
    """One marked eye: its middle, the head's outward normal there, its sideways and upward axes
    across the surface, and its width and height along them."""

    def __init__(self, points, normals):
        self.middle = points.mean(axis=0)
        normal = normals.mean(axis=0)
        self.normal = normal / numpy.sqrt((normal * normal).sum())
        side = numpy.cross((0.0, 0.0, 1.0), self.normal)
        self.side = side / numpy.sqrt((side * side).sum())
        self.up = numpy.cross(self.normal, self.side)
        offset = points - self.middle
        # The samples lie inside the oval: its edge is a little past the outermost, by about the
        # gap between two samples, which the repaint's margin (FILL) takes in.
        self.width = numpy.ptp(offset @ self.side)
        self.height = numpy.ptp(offset @ self.up)
        self.count = len(points)

    def radii(self, points):
        """How far out each of `points` lies, in the oval's own radii (1 on its edge), measured
        across the surface and through it alike."""
        offset = points - self.middle
        across = (offset @ self.side) / (self.width / 2.0)
        upward = (offset @ self.up) / (self.height / 2.0)
        through = (offset @ self.normal) / (self.width / 2.0)
        return numpy.sqrt(across * across + upward * upward + through * through)


def _spots(points, cell):
    """`points` grouped where they lie in touching cells of a `cell`-sized grid: lists of
    indices, in a fixed order (by their lowest index)."""
    keys = [tuple(key) for key in numpy.floor(points / cell).astype(numpy.int64)]
    cells = {}
    for index, key in enumerate(keys):
        cells.setdefault(key, []).append(index)
    parent = {key: key for key in cells}

    def root(key):
        while parent[key] != key:
            parent[key] = parent[parent[key]]
            key = parent[key]
        return key

    for key in sorted(cells):
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    near = (key[0] + dx, key[1] + dy, key[2] + dz)
                    if near in cells:
                        low, high = sorted((root(key), root(near)))
                        parent[high] = low
    groups = {}
    for key in sorted(cells):
        groups.setdefault(root(key), []).extend(cells[key])
    return sorted((sorted(group) for group in groups.values()), key=lambda group: group[0])


def find(head, marked=DARK):
    """The two marked eyes on `head` (a `Head`), left (+X) then right: of the spots `marked`
    picks out, off the middle, the pair that mirror each other across it with the most samples.
    Raises when there is none."""
    picked = numpy.flatnonzero(marked(head.colours))
    points = head.points[picked]
    if len(points) == 0:
        raise ValueError("no marked eye on the head's colour")
    cell = numpy.ptp(head.points, axis=0).max() / CELLS
    marks = [Mark(points[group], head.normals[picked][group]) for group in _spots(points, cell)
             if len(group) >= MIN_SAMPLES]
    # A spot across the middle (a mouth, a nose) is no eye.
    marks = [mark for mark in marks if abs(mark.middle[0]) > mark.width / 2.0]
    best = None
    for left in (mark for mark in marks if mark.middle[0] > 0.0):
        for right in (mark for mark in marks if mark.middle[0] < 0.0):
            mirrored = right.middle * (-1.0, 1.0, 1.0) - left.middle
            width = (left.width + right.width) / 2.0
            close = numpy.sqrt((mirrored * mirrored).sum()) <= MIRROR * width
            alike = max(left.width, right.width) <= WIDER * min(left.width, right.width)
            if close and alike and (best is None or left.count + right.count > best[0].count + best[1].count):
                best = (left, right)
    if best is None:
        raise ValueError("no pair of marked eyes mirroring each other on the head (%d spots)" % len(marks))
    return best


def _texels(head, near):
    """The texels the head's triangles `near` (a mask) cover: their rows, columns and spots."""
    height, width = head.pixels.shape[:2]
    rows, columns, spots = [], [], []
    for uv, corners in zip(head.uvs[near], head.spots[near]):
        uv = uv * (width, height) - 0.5
        low = numpy.maximum(numpy.floor(uv.min(axis=0)).astype(int), 0)
        high = numpy.minimum(numpy.ceil(uv.max(axis=0)).astype(int), (width - 1, height - 1))
        if (high < low).any():
            continue
        column, row = numpy.meshgrid(numpy.arange(low[0], high[0] + 1), numpy.arange(low[1], high[1] + 1))
        column, row = column.ravel(), row.ravel()
        (ax, ay), (bx, by), (cx, cy) = uv
        area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if area == 0.0:
            continue
        first = ((bx - column) * (cy - row) - (cx - column) * (by - row)) / area
        second = ((cx - column) * (ay - row) - (ax - column) * (cy - row)) / area
        third = 1.0 - first - second
        # A little slack takes in the texels the triangle's edges cross.
        inside = (first >= -0.02) & (second >= -0.02) & (third >= -0.02)
        share = numpy.clip(numpy.stack([first, second, third], axis=1)[inside], 0.0, None)
        share = share / share.sum(axis=1, keepdims=True)
        rows.append(row[inside])
        columns.append(column[inside])
        spots.append(share @ corners)
    if not rows:
        return numpy.zeros(0, dtype=int), numpy.zeros(0, dtype=int), numpy.zeros((0, 3))
    return numpy.concatenate(rows), numpy.concatenate(columns), numpy.concatenate(spots)


def repaint(head, marks, marked=DARK):
    """Paints over each of `marks` on the head's texture: every texel within FILL of its oval
    takes the skin's colour around it, the samples between RING_IN and RING_OUT (`marked` ones
    left out) blended by the inverse square of their distance. Returns the skin's mean colour
    around the marks (sRGB), for the lids and brows."""
    ring_colours = []
    for mark in marks:
        reach = mark.radii(head.points)
        ring = (reach >= RING_IN) & (reach <= RING_OUT) & ~marked(head.colours)
        if not ring.any():
            raise ValueError("no skin around the marked eye at %s" % numpy.round(mark.middle, 3))
        ring_points, colours = head.points[ring], head.colours[ring]
        ring_colours.append(colours)
        # The triangles any of whose samples (their corners among them) lie near the oval.
        near = (reach.reshape(len(head.spots), -1) <= RING_IN).any(axis=1)
        rows, columns, spots = _texels(head, near)
        inside = mark.radii(spots) <= FILL
        rows, columns, spots = rows[inside], columns[inside], spots[inside]
        # A CHUNK of texels at a time, so the texels-by-ring weights stay small on a large texture.
        for start in range(0, len(spots), CHUNK):
            offset = spots[start:start + CHUNK, None, :] - ring_points[None, :, :]
            weight = 1.0 / ((offset * offset).sum(axis=2) + 1e-12)
            head.pixels[rows[start:start + CHUNK], columns[start:start + CHUNK], :3] = (
                (weight @ colours) / weight.sum(axis=1, keepdims=True))
    head.image.pixels.foreach_set(head.pixels.ravel())
    head.image.update()
    return numpy.concatenate(ring_colours).mean(axis=0)


def linear(colour):
    """An sRGB colour (0..1) as the linear RGBA a material takes."""
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in colour) + (1.0,)


def fit(skin, marks, mats, bone, forward=FORWARD, ridge=True, **shape):
    """Our eyes (eyes.eye, with lids) on `skin` where `marks` (left, right) are: the left one's
    position and size the mean of the left mark's and the right one's mirrored, so the two
    mirror each other exactly (eyes.mirrored); as wide as the marks, as high against that as
    ALMOND allows. `ridge=False` leaves out the brow; `shape` goes on to eyes.eye (`tilt`,
    `pupil`, `brow_size`, ...). Returns the pieces, weighted to `bone` and the lids' bones."""
    left, right = marks
    middle = (left.middle + right.middle * (-1.0, 1.0, 1.0)) / 2.0
    width = (left.width + right.width) / 2.0
    height = (left.height + right.height) / 2.0
    almond = min(max(height / width, ALMOND[0]), ALMOND[1])
    pieces = []
    for piece in eyes.eye(skin, "Eye.L", tuple(middle), forward, width / 2.0, mats, bone, almond=almond,
                          lid=eyes.LID + "L", **shape):
        if not ridge and piece.name.endswith(".brow"):
            bpy.data.objects.remove(piece, do_unlink=True)
        else:
            pieces.append(piece)
    clear(skin, pieces, width / 2.0)
    return pieces + eyes.mirrored(pieces)


def buried(skin, pieces):
    """The share of the vertices on the face of an eye's front (its iris and pupil among
    `pieces`, the halves facing the way it looks) that lie under `skin`'s surface: the head's
    skin cutting across the eye (#1690). For a left eye, the worse of it and its mirror image on
    the right (eyes.mirrored makes the right eye so), since a generated head is rarely symmetric."""
    look = eyes.look(pieces)
    spots = []
    for piece in (piece for piece in pieces if piece.name.endswith(FRONT)):
        middle = piece.matrix_world.translation
        # Its face toward the way the eye looks: the side of it that shows.
        spots += [spot for spot in (piece.matrix_world @ vertex.co for vertex in piece.data.vertices)
                  if (spot - middle).dot(look) > 0.0]
    if middle.x <= 0.0:
        return _under(skin, spots)
    return max(_under(skin, spots), _under(skin, [Vector((-spot.x, spot.y, spot.z)) for spot in spots]))


def _under(skin, spots):
    """The share of `spots` under `skin`'s surface."""
    under = 0
    for spot in spots:
        found, location, normal, _index = skin.closest_point_on_mesh(spot)
        under += found and (spot - location).dot(normal) < 0.0
    return under / len(spots)


def clear(skin, pieces, size):
    """Sets a left eye (`pieces`, its lid's hinge with it) where the head's skin covers the least
    of its front and its mirror image's (buried): first up to OUT of its size further out along
    the way it looks, in STEPs, the nearest such spot of the least. When that still leaves more
    than BURIED covered (a head that isn't symmetric can bury the right eye), it tries up to SHIFT
    of its size across the head too (sideways and up or down), the nearest spot within BURIED.
    So on a curved head or a sculpted socket the skin doesn't cut across either eye. Raises when
    more than BURIED stays covered."""
    look = eyes.look(pieces)
    side = look.cross(Vector((0.0, 0.0, 1.0))).normalized()
    up = side.cross(look).normalized()
    at = Vector()

    def place(move):
        nonlocal at
        spot = (look * move[0] + side * move[1] + up * move[2]) * (size * STEP)
        shift, at = spot - at, spot
        for piece in pieces:
            piece.location += shift
            if "hinge" in piece:
                piece["hinge"] = tuple(Vector(piece["hinge"]) + shift)
        bpy.context.view_layer.update()
        return buried(skin, pieces)

    out = range(round(OUT / STEP) + 1)
    best = min((place((step, 0, 0)), (step, 0, 0)) for step in out)
    if best[0] > BURIED:
        reach = range(-round(SHIFT / STEP), round(SHIFT / STEP) + 1)
        for move in sorted(((step, across, upward) for step in out for across in reach for upward in reach),
                           key=lambda move: (sum(axis * axis for axis in move), move)):
            covered = place(move)
            if covered < best[0]:
                best = (covered, move)
            if covered <= BURIED:
                break
    place(best[1])
    if best[0] > BURIED:
        raise ValueError("the head's skin covers %.0f%% of the eyes' front at best" % (100 * best[0]))
    print("EYES moved %s steps of %.2f their size (out, across, up); the skin covers at most %.1f%% of "
          "either one's front" % (best[1], STEP, 100 * best[0]))


def replace(rig, skin, mats, faint, bone="head", marked=DARK, **shape):
    """Our eyes in place of the marked ones on an adopted `rig` and its weighted `skin` (`find`,
    `repaint`, `fit`), joined into the skin, their lids on bones of their own hung from `bone`.
    `mats` needs "dark" and "glow" (eyes.eye); "skin", the lids' and brows', is the
    skin's colour around the marks unless given. `faint` is Faint's (first frame, last frame) the
    lids shut over (eyes.Lids). Returns the `eyes.Lids`, whose `shut` goes into clips.animate's
    overlays, and the eye points {side: (spot, bone, look)} for attachments.add."""
    head = Head(skin, bone)
    marks = find(head, marked)
    around = repaint(head, marks, marked)
    if "skin" not in mats:
        mats = dict(mats, skin=materials.material("EyeSkin", linear(around)))
    pieces = fit(skin, marks, mats, bone, **shape)
    points = {}
    for side in ("L", "R"):
        mine = [piece for piece in pieces if piece.name.startswith("Eye.%s." % side)]
        points[side] = (tuple(eyes.spot(mine)), bone, tuple(eyes.look(mine)))
    lids = eyes.Lids(rig, pieces, bone, faint)
    scene.select_only(skin)
    for piece in pieces:
        piece.select_set(True)
    bpy.ops.object.join()
    print("EYES marked at %s and %s, %.3f and %.3f wide, %.3f apart" % (
        tuple(round(float(v), 3) for v in marks[0].middle), tuple(round(float(v), 3) for v in marks[1].middle),
        marks[0].width, marks[1].width, float(marks[0].middle[0] - marks[1].middle[0])))
    return lids, points
