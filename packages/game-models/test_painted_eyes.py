"""Tests lib/marked_eyes.py's `painted`, which check_painted_eyes.py runs (#1688), on a textured
ball for a head: two flat black ovals or two glowing ones painted on its texture fail; a plain
texture passes, and so does one where our own eyes sit (pieces of plain dark colour joined in,
whose texels on the texture are black too), since only the texture's own faces count. A beast's
own way of marking them (marked_eyes.BEASTS, #1719) finds what `DARK` and `GLOW` miss: Fohossa's
pale eyes on a head weighted under HEAD_WEIGHT, the Frostfire Hound's amber and ice ones on an ice
blue head off the middle. And each predicate picks the colours it should, and not its neighbours'.
A fragment left beyond a pair (#1756), a dim spot by one eye only, fails too
(marked_eyes.fragments), while a shade only a little darker than the skin passes; so does a dim
speck a few texels across that lies between the head's samples, where no sample reads it (#1764),
while a single dim texel passes; and a dim patch two texels square on a coarse texture over a
low ball, whose texels lie farther apart on the surface than `fragments` groups by, fails as one
spot (#1781), while two dim texels on each of two islands side by side on the texture, far apart
on the head, pass: neither is a spot of FRAGMENT_TEXELS.
A two-tone head whose right half is dark basalt, as the Kavrikka's, passes: that half is a tone of
its own paint (#1782); a dim fragment on its pale half or a black one on its basalt fails.
`fit` sets our eyes where the marks it was given are, mirrored across the middle they were found
across (#1735): on a ball centred on x = 0 with `DARK`'s ovals, and on one off the middle with the
hound's.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_painted_eyes.py

It prints each case and `PAINTED EYES TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import eyes, marked_eyes  # noqa: E402

# The head: a ball this big, its texture this many texels square.
RADIUS, SIZE = 0.5, 256
# The skin's colour, a painted eye's flat black and its glow (sRGB).
SKIN, BLACK, GLOW = (0.55, 0.4, 0.3), (0.05, 0.05, 0.05), (1.0, 0.6, 0.1)
# A fragment's dim colour, darker than marked_eyes.FRAGMENT_RATIO of the skin but not `DARK`'s black,
# and a shade of the skin only a little darker.
DIM, SHADE = (0.3, 0.22, 0.16), (0.45, 0.33, 0.25)
# Fohossa's: its warm grey skin and pale lantern eyes.
GREY, PALE = (0.84, 0.81, 0.78), (0.98, 0.95, 0.9)
# The Frostfire Hound's (frostfire_hound.py): its ice blue skin, its amber eye and its ice one.
ICE, AMBER, ICE_EYE = (0.36, 0.60, 0.88), (1.0, 0.78, 0.30), (0.62, 0.96, 1.0)
# Where the left eye sits (the model faces -Y, its left is +X; the right one mirrors it), and how
# far around it the paint reaches.
EYE, EYE_RADIUS = Vector((0.35, -1.0, 0.3)).normalized() * RADIUS, 0.09
FOHOSSA = "assets/fohossa/fohossa.glb"
HOUND = "assets/frostfire_hound/frostfire_hound.glb"
# A texture this many texels square, whose texels the ball's triangles cover far more of than the
# head samples (#1764), and the dim specks laid between those samples, each this many texels
# square, with whether the check passes it.
SPECK_SIZE = 2048
SPECKS = {"dim_speck": (3, False), "dim_texel": (1, True)}
# A coarse texture this many texels square on a low ball of this many segments around and up, each
# texel wider on the surface than two of the cells `fragments` groups by, and the dim patch this many
# texels square on it, which must fail.
COARSE_SIZE, COARSE_SEGMENTS, COARSE_ACROSS = 32, (8, 4), 2
# A texture so coarse that the patch is more than marked_eyes.TONE_SHARE of the texels the head
# touches: still a fragment, not a tone of the head's paint (#1782).
TINY_SIZE = 6
# Two islands on a texture of COARSE_SIZE texels: flat squares facing forward at either side of the
# head, the left one's UVs ending a little short of texel column ISLAND_EDGE and the right one's
# starting a little past it, so their texels touch on the texture. Each has two dim texels at that
# edge, on rows ISLAND_ROWS.
ISLAND_EDGE, ISLAND_ROWS = 10, (4, 5)
# A two-tone head (#1782), as lib/frostfire.py paints the Kavrikka: its right half (-X) dark basalt.
BASALT = (0.17, 0.11, 0.10)
# Name: (what is painted by the left eye and by the right one (on the basalt), each None or a
# colour, and whether the check passes it).
TWO_TONES = {
    "two_tone": (None, None, True),
    "two_tone_dim_fragment": (DIM, None, False),
    "two_tone_black_fragment": (None, BLACK, False),
}

# Name: (the paint on the left eye and the right one (either may be None), or None, whether our eyes are joined in,
# the head's weight to "head", the skin's colour, the beast in BEASTS whose own marking the check
# adds, or None, and whether the check passes it).
CASES = {
    "plain": (None, False, 1.0, SKIN, None, True),
    "black_ovals": ((BLACK, BLACK), False, 1.0, SKIN, None, False),
    "glowing_eyes": ((GLOW, GLOW), False, 1.0, SKIN, None, False),
    "our_eyes": (None, True, 1.0, SKIN, None, True),
    # Pale eyes are neither black nor saturated: only Fohossa's own marking sees them, and only
    # with its lower head weight.
    "pale_eyes_unlisted": ((PALE, PALE), False, 0.4, GREY, None, True),
    "pale_eyes_fohossa": ((PALE, PALE), False, 0.4, GREY, FOHOSSA, False),
    "plain_fohossa": (None, False, 0.4, GREY, FOHOSSA, True),
    # The ice blue glows all over, so `GLOW` sees one spot across the middle and no pair; the
    # hound's own marking sees its amber eye and its ice one, mirrored across its middle.
    "hound_eyes_unlisted": ((ICE_EYE, AMBER), False, 1.0, ICE, None, True),
    "hound_eyes": ((ICE_EYE, AMBER), False, 1.0, ICE, HOUND, False),
    "plain_hound": (None, False, 1.0, ICE, HOUND, True),
    # No pair: only the fragments see a dim spot by one eye, and a shade isn't one.
    "dim_fragment": ((DIM, None), True, 1.0, SKIN, None, False),
    "shade": ((SHADE, None), True, 1.0, SKIN, None, True),
}

# Name: (the paint on the left eye and the right one, the skin's colour, and the beast in BEASTS
# whose own marking finds them, or None for `DARK`): `fit` must set our eyes on these marks.
FITS = {
    "fit_middle": ((BLACK, BLACK), SKIN, None),
    # Off the middle, mirrored across x = 0.068: our eyes mirrored across x = 0 would land that far
    # off theirs (#1735).
    "fit_hound": ((ICE_EYE, AMBER), ICE, HOUND),
}
# How far our eye's iris may lie from its mark's middle, as a share of the mark's width: the iris
# stands a little out from the surface, and `clear` may move it a little further.
FIT_NEAR = 0.2

# Predicate: (colours it picks, colours it leaves).
PICKS = {
    "DARK": (marked_eyes.DARK, [BLACK], [SKIN, GREY, ICE]),
    "GLOW": (marked_eyes.GLOW, [GLOW, AMBER, ICE], [SKIN, GREY, PALE, BLACK]),
    "PALE": (marked_eyes.PALE, [PALE, (1.0, 1.0, 1.0)], [GREY, SKIN, ICE_EYE, AMBER, BLACK]),
    "fohossa": (marked_eyes.BEASTS[FOHOSSA], [PALE], [GREY, SKIN, BLACK]),
    # The amber one and the ice one, not the ice skin, the amber cracks' red rim, nor a red or a
    # green glow.
    "hound": (marked_eyes.BEASTS[HOUND], [AMBER, ICE_EYE],
              [ICE, (0.42, 0.67, 0.92), (0.95, 0.38, 0.08), (1.0, 0.2, 0.2), (0.3, 1.0, 0.3), PALE]),
}


def material(name, image=None, colour=(0.0, 0.0, 0.0)):
    """A material whose base colour is `image`, or the plain `colour`."""
    made = bpy.data.materials.new(name)
    shader = made.node_tree.nodes["Principled BSDF"]
    if image is None:
        shader.inputs["Base Color"].default_value = colour + (1.0,)
    else:
        node = made.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        made.node_tree.links.new(node.outputs["Color"], shader.inputs["Base Color"])
    return made


def ball(name, radius, at, weight=1.0, segments=(64, 32)):
    """A UV ball mesh object of `radius` at `at`, of `segments` around and up, its every vertex
    weighted `weight` to "head".
    The mesh itself is moved there and the object left at the origin, as an adopted skin is (the
    eyes look for the skin's surface in its own space)."""
    mesh = bpy.data.meshes.new(name)
    built = bmesh.new()
    built.loops.layers.uv.new("UVMap")
    bmesh.ops.create_uvsphere(built, u_segments=segments[0], v_segments=segments[1], radius=radius, calc_uvs=True)
    built.to_mesh(mesh)
    built.free()
    mesh.transform(Matrix.Translation(at))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.vertex_groups.new(name="head").add(range(len(mesh.vertices)), weight, "REPLACE")
    return obj


def build(paint, ours, weight, colour, middle, size=SIZE, segments=(64, 32)):
    """The head: a ball of `colour`, weighted `weight` to "head" and centred on x = `middle`, with
    its texture, `paint`'s left and right colours laid over the eyes' spots on it (or nothing), and
    our eyes joined in when `ours`, their UVs on a black texel of the texture (`size` texels square);
    the ball has `segments` around and up."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    image = bpy.data.images.new("skin", size, size)
    pixels = numpy.empty((size, size, 4), dtype=numpy.float32)
    pixels[:, :] = colour + (1.0,)
    pixels[0, 0] = BLACK + (1.0,)
    image.pixels.foreach_set(pixels.ravel())
    skin = ball("Head", RADIUS, (middle, 0.0, 0.0), weight, segments)
    skin.data.materials.append(material("skin", image))
    spots = [Vector((middle + EYE.x, EYE.y, EYE.z)), Vector((middle - EYE.x, EYE.y, EYE.z))]
    if paint is not None:
        head = marked_eyes.Head(skin, "head", weight)
        rows, columns, texels = marked_eyes._texels(head, numpy.ones(len(head.spots), dtype=bool))
        for eye, colour in ((eye, colour) for eye, colour in zip(spots, paint) if colour is not None):
            inside = numpy.sqrt(((texels - numpy.array(eye)) ** 2).sum(axis=1)) <= EYE_RADIUS
            head.pixels[rows[inside], columns[inside], :3] = colour
        image.pixels.foreach_set(head.pixels.ravel())
    if ours:
        dark = material("dark", colour=BLACK)
        pieces = [ball("Eye", EYE_RADIUS, eye) for eye in spots]
        for piece in pieces:
            piece.data.materials.append(dark)
            for loop in piece.data.uv_layers.active.data:
                loop.uv = (0.5 / size, 0.5 / size)
        bpy.ops.object.select_all(action="DESELECT")
        for piece in pieces:
            piece.select_set(True)
        skin.select_set(True)
        bpy.context.view_layer.objects.active = skin
        bpy.ops.object.join()
    return skin


def speck(name, across, passes):
    """Whether the check passes a plain ball as it should with a dim speck `across` texels square
    by the left eye, where no head sample reads it (#1764)."""
    skin = build(None, False, 1.0, SKIN, 0.0, SPECK_SIZE)
    head = marked_eyes.Head(skin, "head")
    rows, columns, texels = marked_eyes._texels(head, numpy.ones(len(head.spots), dtype=bool))
    # A texel each speck may start at: near the eye, with no sample reading any texel of the speck.
    sampled = numpy.zeros((SPECK_SIZE + across, SPECK_SIZE + across), dtype=numpy.int64)
    numpy.add.at(sampled, (head.texels[0], head.texels[1]), 1)
    seen = sum(sampled[row:row + SPECK_SIZE, column:column + SPECK_SIZE]
               for row in range(across) for column in range(across))
    near = numpy.sqrt(((texels - numpy.array(EYE)) ** 2).sum(axis=1)) <= EYE_RADIUS
    free = near & (seen[rows, columns] == 0) & (rows < SPECK_SIZE - across) & (columns < SPECK_SIZE - across)
    if not free.any():
        log.error("FAIL %s: no texel by the eye lies between the head's samples" % name)
        return False
    # The lowest such texel, row first: the head's triangles come in no fixed order.
    row, column = min(zip(rows[free].tolist(), columns[free].tolist()))
    head.pixels[row:row + across, column:column + across, :3] = DIM
    head.image.pixels.foreach_set(head.pixels.ravel())
    found = sorted(marked_eyes.painted(skin)) + (["FRAGMENTS"] if marked_eyes.fragments(skin) else [])
    ok = (not found) == passes
    (log.info if ok else log.error)("%s %s: %s at texel (%d, %d), %s" % (
        "ok" if ok else "FAIL", name, "found " + ", ".join(found) if found else "nothing found", row, column,
        "should pass" if passes else "should fail"))
    return ok


def coarse(name, size):
    """Whether the check fails a dim patch COARSE_ACROSS texels square by the left eye on a coarse
    texture `size` texels square over a low ball, whose texels lie farther apart than `fragments`
    groups by on the surface (#1781): side by side on the texture, they are one spot."""
    skin = build(None, False, 1.0, SKIN, 0.0, size, COARSE_SEGMENTS)
    head = marked_eyes.Head(skin, "head")
    rows, columns, texels = marked_eyes._texels(head, numpy.ones(len(head.spots), dtype=bool))
    nearest = numpy.sqrt(((texels - numpy.array(EYE)) ** 2).sum(axis=1)).argmin()
    # The patch stays on the texture.
    row, column = (min(int(at), size - COARSE_ACROSS) for at in (rows[nearest], columns[nearest]))
    head.pixels[row:row + COARSE_ACROSS, column:column + COARSE_ACROSS, :3] = DIM
    head.image.pixels.foreach_set(head.pixels.ravel())
    found = marked_eyes.fragments(skin)
    ok = bool(found)
    (log.info if ok else log.error)("%s %s: %s at texel (%d, %d), should fail" % (
        "ok" if ok else "FAIL", name, "found %s texels" % [mark.count for mark in found] if found else "nothing found",
        row, column))
    return ok


def islands():
    """Whether the check passes two islands side by side on the texture that lie far apart on the
    head, each with two dim texels where they touch (#1781): neither is a spot of FRAGMENT_TEXELS."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    size = COARSE_SIZE
    image = bpy.data.images.new("skin", size, size)
    pixels = numpy.empty((size, size, 4), dtype=numpy.float32)
    pixels[:, :] = SKIN + (1.0,)
    for row in ISLAND_ROWS:
        for column in (ISLAND_EDGE - 1, ISLAND_EDGE):
            pixels[row, column, :3] = DIM
    image.pixels.foreach_set(pixels.ravel())
    near, far = (ISLAND_EDGE - 0.1) / size, (ISLAND_EDGE + 0.1) / size
    squares = [(-0.5, -0.3, 0.0, near), (0.3, 0.5, far, 2.0 * ISLAND_EDGE / size)]
    corners, faces, uvs = [], [], []
    for left, right, start, end in squares:
        first = len(corners)
        corners += [(left, -0.5, 0.0), (right, -0.5, 0.0), (right, -0.5, 0.2), (left, -0.5, 0.2)]
        faces.append((first, first + 1, first + 2, first + 3))
        uvs += [(start, 0.0), (end, 0.0), (end, ISLAND_EDGE / size), (start, ISLAND_EDGE / size)]
    mesh = bpy.data.meshes.new("Head")
    mesh.from_pydata(corners, [], faces)
    mesh.uv_layers.new(name="UVMap")
    for loop, uv in zip(mesh.uv_layers.active.data, uvs):
        loop.uv = uv
    skin = bpy.data.objects.new("Head", mesh)
    bpy.context.scene.collection.objects.link(skin)
    skin.vertex_groups.new(name="head").add(range(len(corners)), 1.0, "REPLACE")
    skin.data.materials.append(material("skin", image))
    found = marked_eyes.fragments(skin)
    ok = not found
    (log.info if ok else log.error)("%s islands: %s, should pass" % (
        "ok" if ok else "FAIL", "found %s texels" % [mark.count for mark in found] if found else "nothing found"))
    return ok


def two_tone(name, left, right, passes):
    """Whether the check passes as it should a ball whose right half is basalt, a tone of its own
    paint (#1782), with `left` painted by the left eye and `right` by the right one, each over half
    the eye's reach, if not None."""
    skin = build(None, False, 1.0, SKIN, 0.0)
    head = marked_eyes.Head(skin, "head")
    rows, columns, texels = marked_eyes._texels(head, numpy.ones(len(head.spots), dtype=bool))
    head.pixels[rows[texels[:, 0] < 0.0], columns[texels[:, 0] < 0.0], :3] = BASALT
    for colour, eye in ((left, EYE), (right, Vector((-EYE.x, EYE.y, EYE.z)))):
        if colour is not None:
            near = numpy.sqrt(((texels - numpy.array(eye)) ** 2).sum(axis=1)) <= EYE_RADIUS / 2.0
            head.pixels[rows[near], columns[near], :3] = colour
    head.image.pixels.foreach_set(head.pixels.ravel())
    found = sorted(marked_eyes.painted(skin)) + (["FRAGMENTS"] if marked_eyes.fragments(skin) else [])
    ok = (not found) == passes
    (log.info if ok else log.error)("%s %s: %s, %s" % (
        "ok" if ok else "FAIL", name, "found " + ", ".join(found) if found else "nothing found",
        "should pass" if passes else "should fail"))
    return ok


def fits(name, paint, colour, beast):
    """Whether `fit` sets our left eye on the left mark and our right one on the right mark, on a
    ball centred on the marking's middle, painted with `paint`."""
    marked = marked_eyes.BEASTS[beast] if beast else marked_eyes.DARK
    skin = build(paint, False, 1.0, colour, marked.middle)
    marks = marked_eyes.find(marked_eyes.Head(skin, "head", marked.weight), marked)
    mats = {"dark": material("dark", colour=BLACK), "glow": material("glow", colour=GLOW),
            "skin": material("lid", colour=colour)}
    pieces = marked_eyes.fit(skin, marks, mats, "head", middle=marked.middle)
    ok = True
    for side, mark in zip("LR", marks):
        iris = eyes.spot([piece for piece in pieces if piece.name.startswith("Eye.%s." % side)])
        off = float(numpy.sqrt(((numpy.array(iris) - mark.middle) ** 2).sum()))
        near = off <= FIT_NEAR * mark.width
        ok = ok and near
        (log.info if near else log.error)("%s %s: eye %s at %s, its mark at %s, %.3f off (at most %.3f)" % (
            "ok" if near else "FAIL", name, side, tuple(round(v, 3) for v in iris),
            tuple(round(float(v), 3) for v in mark.middle), off, FIT_NEAR * mark.width))
    return ok


def main():
    passed = True
    for name, (picks, yes, no) in PICKS.items():
        got = picks(numpy.array(yes + no, dtype=float))
        ok = got.tolist() == [True] * len(yes) + [False] * len(no)
        passed = passed and ok
        (log.info if ok else log.error)("%s %s picks %s" % ("ok" if ok else "FAIL", name, got.tolist()))
    for name, (paint, ours, weight, colour, beast, passes) in CASES.items():
        own = marked_eyes.BEASTS[beast] if beast else None
        skin = build(paint, ours, weight, colour, own.middle if own else 0.0)
        found = marked_eyes.painted(skin, own=own)
        if marked_eyes.fragments(skin, weight=own.weight if own else marked_eyes.HEAD_WEIGHT):
            found["FRAGMENTS"] = ()
        ok = (not found) == passes
        passed = passed and ok
        line = "%s %s: %s, %s" % ("ok" if ok else "FAIL", name, "found " + ", ".join(sorted(found)) if found
                                  else "nothing found", "should pass" if passes else "should fail")
        (log.info if ok else log.error)(line)
    for name, (across, passes) in SPECKS.items():
        passed = speck(name, across, passes) and passed
    passed = coarse("coarse_patch", COARSE_SIZE) and passed
    passed = coarse("tiny_patch", TINY_SIZE) and passed
    passed = islands() and passed
    for name, (left, right, passes) in TWO_TONES.items():
        passed = two_tone(name, left, right, passes) and passed
    for name, (paint, colour, beast) in FITS.items():
        passed = fits(name, paint, colour, beast) and passed
    log.info("PAINTED EYES TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
