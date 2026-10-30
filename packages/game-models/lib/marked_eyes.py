"""Our own eyes in place of the ones a generator painted (#1682, #1683). Every prompt for a
generated beast carries the fixed sentence "Two small, plain, flat black oval eyes." (the model
skill), which only marks where its eyes go and how big they are. On import, the model script
calls `replace` on its adopted rig and skin, which:

- **finds** the two marked ovals on the head (`find`): spots of the base colour that `DARK` (or,
  for a beast imported with its generator's eyes before the rule, its own `Marked` in `BEASTS`)
  picks out, grouped where they lie, the pair that mirror each other across the middle best;
- **repaints** them (`repaint`): every texel over each oval, with a margin for its soft edge, takes
  the colour of the skin around it, blended from that ring by distance, so no painted eye shows
  past ours;
- **fits our eyes** there (`fit`, lib/eyes.py): their position, size, height and spacing from the
  marks, mirrored across the same middle `find` paired them across (the `Marked`'s, #1735), each
  with a lid on a bone of its own (`eyes.Lids`), joined into the skin.

A generator that modelled its eyes as pieces of their own (glowing balls set in the head, as the
Frostfire Hound's and its pup's, #1733) gets them taken out first: the caller `find`s the marks,
removes the pieces they lie on (`modelled`), paints its skin as it will, and hands the marks to
`replace`, which then only fits ours.

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
from . import repaint as _repaint

# A marked eye's flat black: every channel at or below this (sRGB, 0..1).
DARK_VALUE = 0.2
# A painted glowing eye (as inspect_meshy.py finds them): bright and saturated.
GLOW_VALUE, GLOW_SATURATION = 0.75, 0.3
# A painted pale eye (Fohossa's lanterns, #1719): near white, barely tinted.
PALE_VALUE, PALE_SATURATION = 0.93, 0.2
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
# A fragment of a generator's eye (`fragments`, #1756): a spot of at least FRAGMENT_TEXELS of the
# texels the head touches (#1764), each darker than FRAGMENT_RATIO of their median; a lone texel or
# a few are a speck of shading in the paint (clean heads have single ones, the generator's
# fragments a hundred).
FRAGMENT_RATIO, FRAGMENT_TEXELS = 0.6, 4
# A dark spot of at least this share of the texels the head touches is a tone of its own paint (a
# two-tone head's basalt half, #1782, about 0.4 of the Kavrikka's), not an eye's leftovers (an eye
# covers a few hundredths of a head): it is searched again against its own median. A spot is one
# where it runs on across the surface, whatever UV islands it spans; a beast's own dark marks in
# pieces apart, each smaller, are #1765's. A dim fragment touching the tone, or a tone covering
# half the head or more, still hides (#1799).
# On a texture so coarse that a fragment's few texels are that share, a tone also needs at least
# TONE_TEXELS (an eye's leftovers are about a hundred, the Kavrikka's basalt about 49000).
TONE_SHARE, TONE_TEXELS = 0.1, 1000
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


class Marked:
    """How a head's eyes are marked on its texture: `picks` says which of some colours (rows of
    sRGB, 0..1) are an eye's, and `find` looks for them on the faces weighted at least `weight` to
    the head bone, as a pair mirroring each other across the plane x = `middle` within `mirror`
    (MIRROR's share of their width). Calling it calls `picks`. `name` is what the check prints."""

    def __init__(self, name, picks, weight=HEAD_WEIGHT, middle=0.0, mirror=MIRROR):
        self.name, self.picks, self.weight, self.middle, self.mirror = name, picks, weight, middle, mirror

    def __call__(self, colours):
        return self.picks(colours)


def _value_saturation(colours):
    """Each of `colours`' value and saturation (as HSV's)."""
    value = colours.max(axis=1)
    return value, (value - colours.min(axis=1)) / numpy.maximum(value, 1e-6)


def _hue(colours):
    """Each of `colours`' hue, in degrees (0 red, 120 green, 240 blue); 0 for a grey."""
    red, green, blue = colours[:, 0], colours[:, 1], colours[:, 2]
    value, low = colours.max(axis=1), colours.min(axis=1)
    span = numpy.maximum(value - low, 1e-6)
    hue = numpy.where(value == red, (green - blue) / span,
                      numpy.where(value == green, 2.0 + (blue - red) / span, 4.0 + (red - green) / span))
    return numpy.where(value > low, (hue * 60.0) % 360.0, 0.0)


def _dark(colours):
    return colours.max(axis=1) <= DARK_VALUE


def _glow(colours):
    value, saturation = _value_saturation(colours)
    return (value >= GLOW_VALUE) & (saturation >= GLOW_SATURATION)


def _pale(colours):
    value, saturation = _value_saturation(colours)
    return (value >= PALE_VALUE) & (saturation <= PALE_SATURATION)


def glow(*hues):
    """Which of some colours are a glowing eye's (`GLOW`) with a hue inside one of `hues`, each a
    (low, high) span in degrees: an eye whose glow the head's own saturated colour around it would
    swallow, as the Frostfire Hound's amber one on its ice blue (#1719)."""
    def picks(colours):
        hue = _hue(colours)
        return _glow(colours) & numpy.any([(hue >= low) & (hue <= high) for low, high in hues], axis=0)
    return picks


# A marked eye's flat black, the generators' eyes since the rule (the model skill).
DARK = Marked("DARK", _dark)
# A painted glowing eye: bright and saturated.
GLOW = Marked("GLOW", _glow)
# A painted pale eye: near white and barely tinted.
PALE = Marked("PALE", _pale)

# The beasts imported with their generator's eyes before the rule (#1684), each with how its own
# are marked: what the model script hands `replace` and check_painted_eyes.py looks for, keyed by
# the .glb's path in the game's project folder.
BEASTS = {
    "assets/drakkudor/drakkudor.glb": GLOW,
    # Pale lanterns, weighted only 0.41 to the head (the muzzle and neck hold the rest).
    "assets/fohossa/fohossa.glb": Marked("PALE", _pale, weight=0.3),
    # Two eye pieces painted by frostfire_hound.py, MAGMA_EYE's amber and ICE_EYE's pale cyan on a
    # head of ice blue (hue about 210) and amber cracks. The generator set them off the middle, one
    # ahead of the other: they mirror each other only roughly, across x = 0.068.
    "assets/frostfire_hound/frostfire_hound.glb": Marked("AMBER/ICE", glow((36.0, 46.0), (180.0, 195.0)),
                                                         middle=0.068, mirror=1.0),
}


class Unpainted(ValueError):
    """A skin or head without a textured face: nothing painted on it."""


def image(material):
    """The image `material`'s base colour comes from, or None (a plain colour, as our eyes')."""
    if material is None or material.node_tree is None:
        return None
    shader = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if shader is not None and shader.inputs["Base Color"].links:
        node = shader.inputs["Base Color"].links[0].from_node
        if node.type == "TEX_IMAGE":
            return node.image
    return None


class Head:
    """The faces of `skin` that `bone` moves (each corner weighted to it at least `weight`)
    and the base colour texture paints (not our eyes' plain colours, once joined in), sampled:
    every sample's spot, its colour on the texture and its face's normal, and the texture's pixels
    (rows from the bottom, as Blender's run)."""

    def __init__(self, skin, bone, weight=HEAD_WEIGHT):
        data = skin.data
        group = skin.vertex_groups[bone].index
        heads = numpy.array([any(item.group == group and item.weight >= weight for item in vertex.groups)
                             for vertex in data.vertices])
        matrix = numpy.array(skin.matrix_world)
        corners = numpy.array([vertex.co[:] for vertex in data.vertices])
        corners = corners @ matrix[:3, :3].T + matrix[:3, 3]
        data.calc_loop_triangles()
        images = [image(material) for material in data.materials] or [None]
        mine = [triangle for triangle in data.loop_triangles
                if images[min(triangle.material_index, len(images) - 1)] is not None
                and heads[list(triangle.vertices)].all()]
        if not mine:
            raise Unpainted("%s: no textured faces weighted to %s" % (skin.name, bone))
        uvs = data.uv_layers.active.data
        # The texture the head's own faces take (a skin's body may use others).
        found = {images[min(triangle.material_index, len(images) - 1)] for triangle in mine}
        if len(found) != 1:
            raise ValueError("%s: expected one base colour texture on %s's faces, found %d" % (
                skin.name, bone, len(found)))
        self.image = found.pop()
        width, height = self.image.size
        pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
        self.image.pixels.foreach_get(pixels)
        self.pixels = pixels.reshape(height, width, 4)
        # Each head triangle's corners: spot and UV.
        self.spots = corners[numpy.array([triangle.vertices[:] for triangle in mine])]
        self.uvs = numpy.array([[uvs[loop].uv[:] for loop in triangle.loops] for triangle in mine])
        normals = numpy.array([triangle.normal[:] for triangle in mine])
        weights = numpy.array([(i, j, STEPS - i - j) for i in range(STEPS + 1) for j in range(STEPS + 1 - i)],
                              dtype=float) / STEPS
        # Every triangle takes the same samples, `per_triangle` of them, one after another.
        self.per_triangle = len(weights)
        self.points = numpy.einsum("ws,tsk->twk", weights, self.spots).reshape(-1, 3)
        self.normals = numpy.repeat(normals, self.per_triangle, axis=0)
        # Each sample's texel (rows, columns), which its colour is read from.
        self.texels = self.texel(numpy.einsum("ws,tsk->twk", weights, self.uvs).reshape(-1, 2))
        self.colours = self.pixels[self.texels[0], self.texels[1], :3].astype(float)

    def texel(self, uv):
        """The nearest texel to each of `uv`: (rows, columns)."""
        height, width = self.pixels.shape[:2]
        columns = numpy.clip(numpy.floor(uv[:, 0] * width), 0, width - 1).astype(numpy.int64)
        rows = numpy.clip(numpy.floor(uv[:, 1] * height), 0, height - 1).astype(numpy.int64)
        return rows, columns


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
    """The two marked eyes on `head` (a `Head`), left (+X) then right: of the spots `marked` (a
    `Marked`) picks out, off its middle, the pair that mirror each other across it with the most
    samples. Raises when there is none."""
    picked = numpy.flatnonzero(marked(head.colours))
    points = head.points[picked]
    if len(points) == 0:
        raise ValueError("no marked eye on the head's colour")
    cell = numpy.ptp(head.points, axis=0).max() / CELLS
    marks = [Mark(points[group], head.normals[picked][group]) for group in _spots(points, cell)
             if len(group) >= MIN_SAMPLES]
    middle = marked.middle
    # A spot across the middle (a mouth, a nose) is no eye.
    marks = [mark for mark in marks if abs(mark.middle[0] - middle) > mark.width / 2.0]
    best = None
    for left in (mark for mark in marks if mark.middle[0] > middle):
        for right in (mark for mark in marks if mark.middle[0] < middle):
            mirrored = right.middle * (-1.0, 1.0, 1.0) + (2.0 * middle, 0.0, 0.0) - left.middle
            width = (left.width + right.width) / 2.0
            close = numpy.sqrt((mirrored * mirrored).sum()) <= marked.mirror * width
            alike = max(left.width, right.width) <= WIDER * min(left.width, right.width)
            if close and alike and (best is None or left.count + right.count > best[0].count + best[1].count):
                best = (left, right)
    if best is None:
        raise ValueError("no pair of marked eyes mirroring each other on the head (%d spots)" % len(marks))
    return best


def painted(skin, bone="head", own=None):
    """The generator's eye areas still showing on `skin`'s texture over the head that `bone` moves
    (#1688): for each way they are marked (`DARK`'s flat black ovals, `GLOW`'s painted glowing
    eyes, and the beast's `own` `Marked` from BEASTS if it has one, #1719), the pair `find` picks
    out, as {its name: (left, right)}. Our own eyes are plain colours, not the texture, so they
    never count. Empty for a skin with no `bone` or no textured face on the head: nothing painted
    there."""
    if bone not in skin.vertex_groups:
        return {}
    heads = {}
    found = {}
    for marked in [DARK, GLOW] + ([own] if own is not None else []):
        if marked.weight not in heads:
            try:
                heads[marked.weight] = Head(skin, bone, marked.weight)
            except Unpainted:
                heads[marked.weight] = None
        if heads[marked.weight] is None:
            continue
        try:
            found[marked.name] = find(heads[marked.weight], marked)
        except ValueError:
            pass
    return found


def _texels(head, near):
    """The texels the head's triangles `near` (a mask) cover: their rows, columns and spots."""
    return _cover(head, near)[:3]


def _cover(head, near, touching=False):
    """The texels the head's triangles `near` (a mask) cover, as `_texels`, and the triangle (its
    index among the head's) each belongs to. With `touching`, every texel any part of a triangle
    lies on, not only those whose middle it holds: at an island's edge a texture's filtering reads
    them too (#1764)."""
    height, width = head.pixels.shape[:2]
    rows, columns, spots, triangles = [], [], [], []
    for triangle, uv, corners in zip(numpy.flatnonzero(near), head.uvs[near], head.spots[near]):
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
        if touching:
            # Each side's half-plane pushed out by half a texel's extent across it: the texels the
            # triangle touches.
            reach = [0.5 * (abs(y1 - y2) + abs(x2 - x1)) / abs(area)
                     for (x1, y1), (x2, y2) in (((bx, by), (cx, cy)), ((cx, cy), (ax, ay)), ((ax, ay), (bx, by)))]
            inside = (first >= -reach[0]) & (second >= -reach[1]) & (third >= -reach[2])
        else:
            # A little slack takes in the texels the triangle's edges cross.
            inside = (first >= -0.02) & (second >= -0.02) & (third >= -0.02)
        share = numpy.clip(numpy.stack([first, second, third], axis=1)[inside], 0.0, None)
        share = share / share.sum(axis=1, keepdims=True)
        rows.append(row[inside])
        columns.append(column[inside])
        spots.append(share @ corners)
        triangles.append(numpy.full(int(inside.sum()), triangle))
    if not rows:
        return (numpy.zeros(0, dtype=int), numpy.zeros(0, dtype=int), numpy.zeros((0, 3)),
                numpy.zeros(0, dtype=int))
    return (numpy.concatenate(rows), numpy.concatenate(columns), numpy.concatenate(spots),
            numpy.concatenate(triangles))


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
        # A sliver of a triangle whose UVs straddle the texture (a seam's) reads texels far from
        # its own island, which the triangles' fill misses (#1737): the texel each sample within
        # FILL reads is painted over too, so no sample there reads the mark any more.
        sampled = reach <= FILL
        rows = numpy.concatenate([rows[inside], head.texels[0][sampled]])
        columns = numpy.concatenate([columns[inside], head.texels[1][sampled]])
        spots = numpy.concatenate([spots[inside], head.points[sampled]])
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


def fragments(skin, bone="head", weight=HEAD_WEIGHT):
    """What's left of the generator's eyes on `skin`'s texture over the head that `bone` moves,
    beyond a mirrored pair (#1756): of every texel the head's triangles touch (#1764: not only
    those its samples read, so a speck between them shows too), those darker than FRAGMENT_RATIO
    of their median, grouped where they lie or sit side by side on the texture, each spot of at
    least FRAGMENT_TEXELS distinct texels as a `Mark` whose `count` is that number (a sliver across
    an island's seam, a pupil on an island of its own, a dark speck by the eye). A spot of at least
    TONE_SHARE of the head's texels and of TONE_TEXELS is a tone of the head's own paint (#1782: a
    two-tone head's dark half), not reported but searched the same way against its own median, so
    eye paint left on it still shows. The ratio is below `scrub`'s, so a head `scrub` has cleaned,
    whose filled texels may sit a little under its own threshold, passes. Our own eyes are plain
    colours, not the texture, so they never count. The head is the faces weighted at least
    `weight` to `bone` (a beast's own `Marked`'s,
    as `painted` takes). Empty for a skin with no `bone` or no textured face on the head."""
    if bone not in skin.vertex_groups:
        return []
    try:
        head = Head(skin, bone, weight)
    except Unpainted:
        return []
    rows, columns, spots, triangles = _cover(head, numpy.ones(len(head.spots), dtype=bool), touching=True)
    # A texel two triangles touch (along their shared side) counts once.
    texels = rows * head.pixels.shape[1] + columns
    value = head.pixels[rows, columns, :3].max(axis=1)
    # Each triangle's normal: the one its samples carry.
    normals = head.normals[::head.per_triangle][triangles]
    islands = _islands(head)[triangles]
    cell = numpy.ptp(head.points, axis=0).max() / CELLS
    tone = max(TONE_SHARE * len(numpy.unique(texels)), TONE_TEXELS)
    marks = []
    # The parts of the head searched, each against its own median: the whole head first, then each
    # tone of its own paint found dark in it (#1782). Each part's dark texels are fewer than its own,
    # so the search ends.
    parts = [numpy.arange(len(texels))]
    while parts:
        part = parts.pop(0)
        distinct = numpy.unique(texels[part], return_index=True)[1]
        dark = part[value[part] < FRAGMENT_RATIO * float(numpy.median(value[part][distinct]))]
        for group in _touching(_spots(spots[dark], cell), texels[dark], islands[dark], head.pixels.shape[1]):
            spot = dark[group]
            count = len(numpy.unique(texels[spot]))
            if count >= tone:
                parts.append(spot)
            elif count >= FRAGMENT_TEXELS:
                mark = Mark(spots[spot], normals[spot])
                mark.count = count
                marks.append(mark)
    return marks


def _islands(head):
    """Each of the head's triangles' UV island, as a number: triangles that share a corner, at
    the same spot and the same UV, lie on the same one."""
    corners = numpy.concatenate([head.spots, head.uvs], axis=2).reshape(-1, 5)
    corners = numpy.unique(numpy.round(corners, 6), axis=0, return_inverse=True)[1].reshape(-1)
    parent = list(range(len(head.spots)))

    def root(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    first = {}
    for corner, triangle in zip(corners.tolist(), numpy.repeat(numpy.arange(len(head.spots)), 3).tolist()):
        low, high = sorted((root(first.setdefault(corner, triangle)), root(triangle)))
        parent[high] = low
    return numpy.array([root(triangle) for triangle in range(len(head.spots))])


def _touching(groups, texels, islands, width):
    """`groups` (lists of indices into `texels`, keys row * `width` + column, on the UV island
    `islands` gives each) joined wherever a texel of one is the same as, or beside, a texel of
    another on the same island (#1781): a coarse texture's texels lie farther apart on the surface
    than `_spots`' cells, yet a patch of them is one spot, while two islands side by side on the
    texture may lie far apart on the head. In a fixed order (by their lowest index)."""
    parent = list(range(len(groups)))

    def root(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    owners = {}
    for number, group in enumerate(groups):
        for key, island in set(zip(texels[group].tolist(), islands[group].tolist())):
            owners.setdefault((key, island), set()).add(number)
    for key, island in sorted(owners):
        row, column = divmod(key, width)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if 0 <= column + dx < width:
                    for other in owners.get(((row + dy) * width + column + dx, island), ()):
                        for number in owners[(key, island)]:
                            low, high = sorted((root(number), root(other)))
                            parent[high] = low
    joined = {}
    for number, group in enumerate(groups):
        joined.setdefault(root(number), []).extend(group)
    return sorted((sorted(group) for group in joined.values()), key=lambda group: group[0])


def scrub(skin, bone="head", below=DARK_VALUE, ratio=0.75, reach=6, grow=3, weight=HEAD_WEIGHT):
    """Paints out what's left of the generator's eyes on `skin`'s head texture (#1737), for a
    creature whose own colours have no black: the generator paints its eyes over many of the
    texture's islands, and fragments `repaint` misses (a sliver across an island's seam, a pupil
    on an island of its own, a dark smudge under the eye) still show where the old eyes were.
    Every near-black texel (its brightest channel under `below`, sRGB) goes, and so does every
    texel within `reach` of a sample of the head darker than `ratio` of the head's median, if it
    is that dark too; with `grow` texels around each, they take the colour of the texels around
    them, filled in from the edges inward. The head is the faces weighted at least `weight` to
    `bone`, as `fragments` takes it. Returns how many texels it painted."""
    head = Head(skin, bone, weight)
    pixels = head.pixels
    height, width = pixels.shape[:2]
    value = pixels[:, :, :3].max(axis=2)
    dim = ratio * float(numpy.median(head.colours.max(axis=1)))
    near = numpy.zeros((height, width), dtype=bool)
    darker = head.colours.max(axis=1) < dim
    near[head.texels[0][darker], head.texels[1][darker]] = True
    for _ in range(reach):
        near = _spread(near)
    hole = (value < below) | (near & (value < dim))
    for _ in range(grow):
        hole = _spread(hole)
    painted = int(hole.sum())
    while hole.any():
        known = ~hole
        total = numpy.zeros((height, width, 3), dtype=numpy.float32)
        count = numpy.zeros((height, width), dtype=numpy.float32)
        for step in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            total += numpy.roll(pixels[:, :, :3] * known[:, :, None], step, axis=(0, 1))
            count += numpy.roll(known, step, axis=(0, 1))
        edge = hole & (count > 0)
        if not edge.any():
            break
        pixels[edge, :3] = total[edge] / count[edge][:, None]
        hole &= ~edge
    head.image.pixels.foreach_set(pixels.ravel())
    head.image.update()
    return painted


def _spread(mask):
    """`mask` grown by one texel to each side."""
    grown = mask.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        grown |= numpy.roll(mask, (dy, dx), axis=(0, 1))
    return grown


def fit(skin, marks, mats, bone, forward=FORWARD, ridge=True, middle=0.0, upright=False,
        grow=1.0, **shape):
    """Our eyes (eyes.eye, with lids) on `skin` where `marks` (left, right) are: the left one's
    position and size the mean of the left mark's and the right one's mirrored across the plane
    x = `middle` (the `Marked`'s that `find` paired them across, #1735), so the two mirror each
    other exactly across it (eyes.mirrored); as wide as the marks, as high against that as
    ALMOND allows, `grow` times as large (for a mark smaller than the eye it stands for, as a
    painted one under an eye the generator set on the face, #1738). With `upright`, a mark taller
    than it is wide (an upright oval, #1737) gives a rounder eye, as wide as the mark's mean of
    width and height, since ours is never taller than it is wide: as wide as the mark, it would be
    half the eye the generator drew (and as tall, its top would show above its brow,
    check_brows.py). `ridge=False` leaves out the brow; `shape` goes on to eyes.eye (`tilt`,
    `pupil`, `brow_size`, ...). Returns the pieces, weighted to `bone` and the lids' bones."""
    left, right = marks
    spot = (left.middle + right.middle * (-1.0, 1.0, 1.0) + (2.0 * middle, 0.0, 0.0)) / 2.0
    width = grow * (left.width + right.width) / 2.0
    height = grow * (left.height + right.height) / 2.0
    almond = min(max(height / width, ALMOND[0]), ALMOND[1])
    size = max(width, (width + height) / 2.0 if upright else width) / 2.0
    pieces = []
    for piece in eyes.eye(skin, "Eye.L", tuple(spot), forward, size, mats, bone, almond=almond,
                          lid=eyes.LID + "L", middle=middle, **shape):
        if not ridge and piece.name.endswith(".brow"):
            bpy.data.objects.remove(piece, do_unlink=True)
        else:
            pieces.append(piece)
    clear(skin, pieces, size, middle)
    return pieces + eyes.mirrored(pieces, middle)


def buried(skin, pieces, middle=0.0):
    """The share of the vertices on the face of an eye's front (its iris and pupil among
    `pieces`, the halves facing the way it looks) that lie under `skin`'s surface: the head's
    skin cutting across the eye (#1690). For a left eye (left of the plane x = `middle`), the worse
    of it and its mirror image across that plane on the right (eyes.mirrored makes the right eye
    so), since a generated head is rarely symmetric."""
    look = eyes.look(pieces)
    spots = []
    for piece in (piece for piece in pieces if piece.name.endswith(FRONT)):
        centre = piece.matrix_world.translation
        # Its face toward the way the eye looks: the side of it that shows.
        spots += [spot for spot in (piece.matrix_world @ vertex.co for vertex in piece.data.vertices)
                  if (spot - centre).dot(look) > 0.0]
    if centre.x <= middle:
        return _under(skin, spots)
    return max(_under(skin, spots),
               _under(skin, [Vector((2.0 * middle - spot.x, spot.y, spot.z)) for spot in spots]))


def _under(skin, spots):
    """The share of `spots` under `skin`'s surface."""
    under = 0
    for spot in spots:
        found, location, normal, _index = skin.closest_point_on_mesh(spot)
        under += found and (spot - location).dot(normal) < 0.0
    return under / len(spots)


def clear(skin, pieces, size, middle=0.0):
    """Sets a left eye (`pieces`, its lid's hinge with it) where the head's skin covers the least
    of its front and its mirror image's (buried): first up to OUT of its size further out along
    the way it looks, in STEPs, the nearest such spot of the least. When that still leaves more
    than BURIED covered (a head that isn't symmetric can bury the right eye), it tries up to SHIFT
    of its size across the head too (sideways and up or down), the nearest spot within BURIED.
    So on a curved head or a sculpted socket the skin doesn't cut across either eye. The right
    eye is the left one's mirror image across the plane x = `middle`. Raises when more than
    BURIED stays covered."""
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
        return buried(skin, pieces, middle)

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


def modelled(skin, marks):
    """Takes the pieces of `skin` that `marks` (left, right, from `find`) lie on out of it: eyes the
    generator modelled as pieces of their own (a glowing ball set in the head), which no repaint
    could hide. A piece is one `repaint.pieces` tells apart (never the largest, the body) whose
    bounds hold a mark's middle, give or take half its width; each mark grows to its piece's width
    and height across the head, the whole eye the generator drew, for `fit`. Returns how many
    faces went; raises when a mark lies on no such piece."""
    piece = _repaint.pieces(skin.data)
    bounds = {}
    for face, number in piece.items():
        if number:
            corners = numpy.array([skin.data.vertices[index].co[:] for index in skin.data.polygons[face].vertices])
            low, high = bounds.get(number, (corners.min(axis=0), corners.max(axis=0)))
            bounds[number] = (numpy.minimum(low, corners.min(axis=0)), numpy.maximum(high, corners.max(axis=0)))
    gone = set()
    for mark in marks:
        slack = mark.width / 2.0
        under = {number for number, (low, high) in bounds.items()
                 if (mark.middle >= low - slack).all() and (mark.middle <= high + slack).all()}
        if not under:
            raise ValueError("the marked eye at %s lies on no piece of its own" % (tuple(mark.middle.round(3)),))
        gone |= under
        # The mark is only the glowing part of the generator's eye that `find` picked out; the
        # piece is the whole eye it drew, so ours take its size across the head.
        points = numpy.array([skin.data.vertices[index].co[:] for face, number in piece.items() if number in under
                              for index in skin.data.polygons[face].vertices])
        offset = points - mark.middle
        mark.width = max(mark.width, numpy.ptp(offset @ mark.side))
        mark.height = max(mark.height, numpy.ptp(offset @ mark.up))
    faces = sorted(face for face, number in piece.items() if number in gone)
    scene.select_only(skin)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for face in faces:
        skin.data.polygons[face].select = True
        for index in skin.data.polygons[face].vertices:
            skin.data.vertices[index].select = True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="VERT")
    bpy.ops.object.mode_set(mode="OBJECT")
    print("EYES took out %d pieces of %d faces, the generator's modelled eyes" % (len(gone), len(faces)))
    return len(faces)


def replace(rig, skin, mats, faint, bone="head", marked=DARK, grow=1.0, marks=None, **shape):
    """Our eyes in place of the ones `marked` (a `Marked`, a beast's own from BEASTS) picks out on
    an adopted `rig` and its weighted `skin` (`find`, `repaint`, `fit`), joined into the skin,
    their lids on bones of their own hung from `bone`, `grow` times as large as the marks (fit).
    With `marks` (left, right) the caller has found them and dealt with what showed there
    (`modelled`): only ours are fitted.
    `mats` needs "dark" and "glow" (eyes.eye); "skin", the lids' and brows', is the
    skin's colour around the marks unless given (and must be, with `marks`). `faint` is Faint's
    (first frame, last frame) the lids shut over (eyes.Lids). Returns the `eyes.Lids`, whose
    `shut` goes into clips.animate's overlays, and the eye points {side: (spot, bone, look)} for
    attachments.add."""
    if marks is None:
        head = Head(skin, bone, marked.weight)
        marks = find(head, marked)
        around = repaint(head, marks, marked)
        if "skin" not in mats:
            mats = dict(mats, skin=materials.material("EyeSkin", linear(around)))
    elif "skin" not in mats:
        raise ValueError("found marks need the lids' colour: mats has no \"skin\"")
    pieces = fit(skin, marks, mats, bone, middle=marked.middle, grow=grow, **shape)
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
