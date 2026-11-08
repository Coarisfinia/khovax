"""Smoothing a clip source's curves (#2128): Meshy's clips pop and snap now and then, a joint's turn
changing speed abruptly from one frame to the next, which the motion check reads as jitter. `smooth`
runs every bone's channels through a Gaussian of a few frames and keys the clip on every frame
again, so a pop evens out while a move as long as a few frames keeps its shape."""

import math

import bpy
from mathutils import Quaternion, Vector

CHANNELS = (("location", 3), ("rotation_quaternion", 4), ("scale", 3))


def _curves(action):
    """The action's curves by (data path, index)."""
    found = {}
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    found[(curve.data_path, curve.array_index)] = curve
    return found


def _gauss(values, sigma, zero):
    """`values` through a Gaussian of `sigma` frames, the ends held (a one-shot clip)."""
    reach = int(math.ceil(3.0 * sigma))
    weights = [math.exp(-0.5 * (offset / sigma) ** 2) for offset in range(-reach, reach + 1)]
    total = sum(weights)
    out = []
    for index in range(len(values)):
        mixed = zero.copy()
        for offset, weight in zip(range(-reach, reach + 1), weights):
            mixed += values[min(max(index + offset, 0), len(values) - 1)] * weight
        out.append(mixed * (1.0 / total))
    return out


def smooth(rig, action, sigma):
    """Every bone's channels of one-shot `action` (keyed on every frame from 0, as Meshy's and the
    motion capture's are) through a Gaussian of `sigma` frames, keyed on every frame again."""
    found = _curves(action)
    first, last = (int(round(frame)) for frame in action.frame_range)
    if first != 0:
        raise RuntimeError("%s starts at frame %d, not 0" % (action.name, first))
    frames = range(last + 1)
    for pose in rig.pose.bones:
        values = {}
        for path, size in CHANNELS:
            curves = [found.get(('pose.bones["%s"].%s' % (pose.name, path), index)) for index in range(size)]
            if None in curves:
                continue
            kind = Quaternion if size == 4 else Vector
            values[path] = (curves, [kind([curve.evaluate(frame) for curve in curves]) for frame in frames])
        if "rotation_quaternion" in values:
            turns = values["rotation_quaternion"][1]
            for index in range(1, len(turns)):
                # The same turn either way round: keep each next to the last, so they average.
                if turns[index].dot(turns[index - 1]) < 0.0:
                    turns[index].negate()
        for path, (curves, samples) in values.items():
            zero = Quaternion((0.0, 0.0, 0.0, 0.0)) if path == "rotation_quaternion" else Vector((0.0, 0.0, 0.0))
            smoothed = _gauss(samples, sigma, zero)
            if path == "rotation_quaternion":
                smoothed = [turn.normalized() for turn in smoothed]
            for index, curve in enumerate(curves):
                curve.keyframe_points.clear()
                curve.keyframe_points.add(len(smoothed))
                for frame, value in zip(frames, smoothed):
                    point = curve.keyframe_points[frame]
                    point.co = (frame, value[index])
                    point.interpolation = "LINEAR"
                curve.update()
    bpy.context.view_layer.update()
