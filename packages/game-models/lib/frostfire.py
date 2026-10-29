"""The frost-and-fire line's paint (#1609, #1733): the Frostfire Hound and its pup, the Kavrikka,
painted alike from where each texel lies on the body (lib/repaint.py), as the owner asked of the
hound and then of its pup ("the same treatment, so its magma flows the way the hound's does"):

- **the magma side:** the whole right side (-X) is dark basalt split by glowing cracks;
- **the ice side:** the left side is pale blue ice with frosted cracks;
- **the border:** near the midline a cell is magma when its own middle lies on the right, so the
  border runs along the cracks and reads as one more crack, not a line drawn down the back;
- **the soles:** the underside of every paw is a plain pad of its side's colour.

`paint` takes the mesh's parts by face (`body`, and optionally `tail.R`, the magma tail, and
`tail.L`, the ice tail, and the eye pieces `eye.R` and `eye.L`, painted plain amber and pale
cyan) and a `Look` (the beast's size and its midline); `material` puts the colour and the glow
on the skin. The line's colours are the module's, so the two read as one line.

Blender is Z-up and the model faces -Y; its left is +X."""

import bpy
import numpy

from . import repaint

# Colours (sRGB): the ice in three tones by cell, its frosted cracks and its pads; the basalt in
# three tones, its glowing cracks (hot at the middle, cooling to the rim) and its pads.
ICE = ((0.36, 0.60, 0.88), (0.42, 0.67, 0.92), (0.31, 0.54, 0.83))
FROST = (0.86, 0.95, 1.00)
ICE_PAD = (0.20, 0.33, 0.55)
BASALT = ((0.17, 0.11, 0.10), (0.21, 0.13, 0.11), (0.13, 0.09, 0.09))
MAGMA_CORE = (1.00, 0.86, 0.42)
MAGMA_RIM = (0.95, 0.38, 0.08)
BASALT_PAD = (0.10, 0.07, 0.07)
# How strongly the magma's cracks glow on their own (the glow texture's scale).
MAGMA_GLOW = (1.00, 0.45, 0.10)
# The eyes: the magma eye burns amber and the ice eye shines pale cyan.
MAGMA_EYE = (1.00, 0.78, 0.30)
ICE_EYE = (0.62, 0.96, 1.00)
# A sole: a face this far off straight down at most (the cosine of the angle).
SOLE_FACING = -0.6


class Look:
    """One beast's paint: `name` its images', the texture's size (texels a side) and the glow's
    (coarser: only the cracks glow, and they are soft), the `midline` between the two sides
    (metres along X), one cell of rock or ice about `cell` wide (metres) from a fixed `seed`, a
    crack `crack` wide at its middle with the magma's glow reaching `glow_reach` into the rock
    beside it, and a sole no higher than `sole_height`."""

    def __init__(self, name, midline, cell, seed, crack, glow_reach, sole_height, texture=1024, glow_texture=512):
        self.name, self.midline, self.cell, self.seed = name, midline, cell, seed
        self.crack, self.glow_reach, self.sole_height = crack, glow_reach, sole_height
        self.texture, self.glow_texture = texture, glow_texture


def paint(skin, part, look):
    """The colour and the glow textures, painted from where each texel lies at rest; `part` is
    {face: part name}."""
    texels = repaint.Texels(skin.data, look.texture)
    spots = texels.spots
    low, high = spots.min(axis=0), spots.max(axis=0)
    cells = repaint.Cells(low, high, look.cell, look.seed)
    nearest, border = cells.near(spots)
    names = numpy.array([part[face] for face in texels.faces])
    # Near the midline a cell is magma when its own middle lies on the right; further out the side
    # alone decides, so no stray cell crosses over onto a leg.
    middle = numpy.abs(spots[:, 0] - look.midline) < look.cell / 2.0
    magma = numpy.where(middle, cells.points[nearest][:, 0] < look.midline, spots[:, 0] < look.midline)
    magma = numpy.where(names == "tail.R", True, numpy.where(names == "tail.L", False, magma))
    tone = nearest % 3
    rock = numpy.array(BASALT)[tone]
    ice = numpy.array(ICE)[tone]
    base = numpy.where(magma[:, None], rock, ice)
    # A crack's middle is 0 and its edge is `crack` out; the magma's rim glows a little beyond.
    depth = numpy.clip(1.0 - border / look.crack, 0.0, 1.0)
    rim = numpy.clip(1.0 - border / (look.crack + look.glow_reach), 0.0, 1.0)
    hot = numpy.array(MAGMA_RIM) + (numpy.array(MAGMA_CORE) - numpy.array(MAGMA_RIM)) * depth[:, None]
    lava = base + (hot - base) * numpy.maximum(depth, 0.5 * rim * rim)[:, None]
    frost = base + (numpy.array(FROST) - base) * (depth * depth)[:, None]
    colour = numpy.where(magma[:, None], lava, frost)
    glow = numpy.where(magma[:, None], numpy.array(MAGMA_GLOW) * numpy.maximum(depth, 0.5 * rim * rim)[:, None], 0.0)
    # The soles: plain pads, no cracks.
    sole = (texels.normals[:, 2] < SOLE_FACING) & (spots[:, 2] < look.sole_height) & (names == "body")
    colour = numpy.where(sole[:, None], numpy.where(magma[:, None], BASALT_PAD, ICE_PAD), colour)
    glow = numpy.where(sole[:, None], 0.0, glow)
    for name, eye in (("eye.R", MAGMA_EYE), ("eye.L", ICE_EYE)):
        mine = names == name
        colour[mine] = eye
        glow[mine] = eye
    covered = texels.covered()
    canvas = repaint.dilate(texels.paint(texels.canvas(ICE[0]), colour), covered, 4)
    shine = repaint.dilate(texels.paint(texels.canvas((0.0, 0.0, 0.0)), glow), covered, 4)
    # The glow's texture at its smaller size: the mean of each block.
    step = look.texture // look.glow_texture
    shine = shine.reshape(look.glow_texture, step, look.glow_texture, step, 3).mean(axis=(1, 3))
    print("PAINT texels %d of %d, magma %.0f%%, soles %d, cells %d" % (
        len(spots), look.texture * look.texture, 100.0 * magma[names == "body"].mean(), sole.sum(),
        len(set(nearest.tolist()))))
    return repaint.image(look.name, canvas), repaint.image(look.name + "_glow", shine)


def material(skin, name, colour, glow):
    """One material named `name`: the painted colour, the glow, matte and single-sided, in place
    of the skin's own."""
    out = bpy.data.materials.new(name)
    out.use_backface_culling = True
    nodes, links = out.node_tree.nodes, out.node_tree.links
    shader = nodes["Principled BSDF"]
    for image, socket in ((colour, "Base Color"), (glow, "Emission Color")):
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = image
        links.new(texture.outputs["Color"], shader.inputs[socket])
    shader.inputs["Emission Strength"].default_value = 1.0
    shader.inputs["Roughness"].default_value = 1.0
    shader.inputs["Metallic"].default_value = 0.0
    skin.data.materials.clear()
    skin.data.materials.append(out)
