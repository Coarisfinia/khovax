"""Plots a clip's motion, bone by bone (model skill, #1071): stiffness and overlap read better
from a curve than from a GIF. One panel per bone, its turn from rest about its own three axes over
the clip's frames (degrees); given a second model, its curves are drawn faint behind, for a
before and after. A looping clip is drawn twice through, with its seam marked, so a stop or a
jump there shows.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/plot_motion.py -- \
        <out.png> <Clip> <model.glb> [<before.glb>] [--bones a,b,c]

The bones default to the chains a quadruped moves (BONES); the image is drawn with numpy and
Blender's own font, like render_views.py's sheet."""

import math
import os
import sys

import blf
import bpy
import imbuf
import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import imported  # noqa: E402

BONES = ["root", "hips", "spine_02", "neck", "head", "jaw", "ear.L", "tail_01", "tail_02", "tail_03", "tail_04",
         "thigh.L", "shin.L", "upper_arm.L", "forearm.L"]
COLUMNS = 3
PANEL_W, PANEL_H, PAD, LABEL = 440, 190, 14, 26
# The three axes, in a colour-blind safe order; text stays dark, the marks carry the colour.
AXES = [(0x2A, 0x78, 0xD6), (0xEB, 0x68, 0x34), (0x1B, 0xAF, 0x7A)]
INK, GRID, PAPER = (0.13, 0.13, 0.13), (0.86, 0.86, 0.84), (1.0, 1.0, 1.0)


def curves(glb, clip, bones):
    """Per bone, its turn from rest as (x, y, z) degrees on every frame (the root: its shift in
    centimetres), and whether the clip loops."""
    fps, loops = imported.settings(glb)
    rig = imported.load(glb, fps)
    start, end = imported.play(rig, bpy.data.actions[clip])
    out = {bone: [] for bone in bones if bone in rig.pose.bones}
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        for bone in out:
            pose = rig.pose.bones[bone]
            if pose.parent is None:
                out[bone].append(tuple(value * 100 for value in pose.location))
                continue
            axis, angle = pose.matrix_basis.to_quaternion().to_axis_angle()
            angle = angle if angle <= math.pi else angle - 2 * math.pi
            out[bone].append(tuple(math.degrees(value * angle) for value in axis))
    loop = clip in loops
    if loop:
        for bone, values in out.items():
            out[bone] = values + values[1:]
    return out, loop, end - start


def _line(pixels, points, color, width):
    """Draws a polyline into `pixels` (rows bottom-up) as dots dense enough to join up."""
    height, wide = pixels.shape[:2]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        steps = max(1, int(math.hypot(x1 - x0, y1 - y0) * 2))
        for index in range(steps + 1):
            x = round(x0 + (x1 - x0) * index / steps)
            y = round(y0 + (y1 - y0) * index / steps)
            pixels[max(0, y - width // 2):min(height, y + (width + 1) // 2),
                   max(0, x - width // 2):min(wide, x + (width + 1) // 2), :3] = color


def _mix(color, share):
    """`color` (0..255) faded toward the paper by `share`."""
    return tuple(c / 255 * (1 - share) + p * share for c, p in zip(color, PAPER))


def draw(path, clip, after, before, loop, period):
    bones = list(after[0])
    rows = math.ceil(len(bones) / COLUMNS)
    width = COLUMNS * (PANEL_W + PAD) + PAD
    height = rows * (PANEL_H + LABEL + PAD) + PAD + LABEL
    pixels = numpy.ones((height, width, 4), dtype=numpy.float32)
    labels = [(PAD, height - LABEL + 6, "%s: thin faint lines before, bold after; blue x, orange y, aqua z (degrees%s)"
               % (clip, "; root in cm" if "root" in bones else ""))]
    for index, bone in enumerate(bones):
        left = PAD + (index % COLUMNS) * (PANEL_W + PAD)
        bottom = height - LABEL - (index // COLUMNS + 1) * (PANEL_H + LABEL + PAD)
        series = [after[0][bone]] + ([before[0][bone]] if before and bone in before[0] else [])
        values = [v for s in series for frame in s for v in frame]
        low, high = min(values + [0.0]), max(values + [0.0])
        span = max(high - low, 1.0)
        frames = len(after[0][bone]) - 1

        def spot(share, value, low=low, span=span, left=left, bottom=bottom):
            return (left + share * PANEL_W, bottom + 6 + (value - low) / span * (PANEL_H - 12))

        pixels[bottom:bottom + PANEL_H, left:left + PANEL_W, :3] = (0.975, 0.975, 0.97)
        _line(pixels, [spot(0.0, 0.0), spot(1.0, 0.0)], GRID, 1)
        if loop:
            _line(pixels, [(left + period / frames * PANEL_W, bottom), (left + period / frames * PANEL_W,
                                                                         bottom + PANEL_H)], GRID, 2)
        for curve, fade, thick in ((series[1] if len(series) > 1 else None, 0.6, 1), (series[0], 0.0, 2)):
            if curve is None:
                continue
            for axis, color in enumerate(AXES):
                last = len(curve) - 1
                _line(pixels, [spot(f / last, value[axis]) for f, value in enumerate(curve)], _mix(color, fade), thick)
        labels.append((left, bottom + PANEL_H + 6, "%s  (%.0f to %.0f)" % (bone, low, high)))
    image = bpy.data.images.new("plot", width, height)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    buffer = imbuf.load(path)
    with blf.bind_imbuf(0, buffer):
        blf.size(0, 16)
        blf.color(0, *INK, 1)
        for x, y, text in labels:
            blf.position(0, x, y, 0)
            blf.draw_buffer(0, text)
    imbuf.write(buffer, filepath=path)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    bones = BONES
    if "--bones" in args:
        at = args.index("--bones")
        bones = args[at + 1].split(",")
        args = args[:at] + args[at + 2:]
    out, clip, glb = args[0], args[1], args[2]
    before = curves(args[3], clip, bones) if len(args) > 3 else None
    after = curves(glb, clip, bones)
    # Before and after may differ in length: each is drawn across the panel's full width.
    draw(out, clip, after, before, after[1], after[2])
    print("PLOT", out)


main()
