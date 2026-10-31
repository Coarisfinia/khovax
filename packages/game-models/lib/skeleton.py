"""A rig's skeleton as its .glb holds it, read without Blender, so clips made on one rig can be told
apart from clips made on another (#1935). Meshy rigs one clip per export (#1934), and every clip
of one figure must come from the same rig, or merged onto one model it plays on bones that aren't
there or bends them from another rest pose.

A skeleton is its skin's joints, each with its parent joint and its rest pose relative to it (the
node's translation, rotation and scale), the same numbers Godot builds its Skeleton3D from. Two
skeletons are the same when they have the same bones, under the same parents, at rest within
`TOLERANCE`."""

import json
import math
import struct

# How far a rest pose's numbers may part (metres, quaternion parts, scale factors) and still be
# the same rig: float noise from Blender's import and export, far below a moved joint.
TOLERANCE = 1e-4


def read(path):
    """The skeleton of the .glb at `path`: {bone: (parent or None, translation, rotation, scale)}
    for the joints of its one skin."""
    with open(path, "rb") as glb:
        data = glb.read()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    skins = gltf.get("skins", [])
    if len(skins) != 1:
        raise ValueError("%s: %d skins, not one" % (path, len(skins)))
    nodes = gltf["nodes"]
    joints = set(skins[0]["joints"])
    parents = {child: index for index, node in enumerate(nodes) for child in node.get("children", [])}
    bones = {}
    for joint in sorted(joints):
        node = nodes[joint]
        parent = parents.get(joint)
        bones[node["name"]] = (
            nodes[parent]["name"] if parent in joints else None,
            tuple(node.get("translation", (0.0, 0.0, 0.0))),
            tuple(node.get("rotation", (0.0, 0.0, 0.0, 1.0))),
            tuple(node.get("scale", (1.0, 1.0, 1.0))),
        )
    return bones


def differences(expected, found, tolerance=TOLERANCE):
    """How the skeleton `found` differs from `expected`, one line each: a bone missing or extra,
    under another parent, or at another rest pose. Nothing when they're the same rig."""
    lines = ["lacks the bone %s" % bone for bone in sorted(expected.keys() - found.keys())]
    lines += ["has the extra bone %s" % bone for bone in sorted(found.keys() - expected.keys())]
    for bone in sorted(expected.keys() & found.keys()):
        (parent, *rest), (other_parent, *other_rest) = expected[bone], found[bone]
        if parent != other_parent:
            lines.append("%s hangs from %s, not %s" % (bone, other_parent, parent))
        for what, want, got in zip(("translation", "rotation", "scale"), rest, other_rest):
            if what == "rotation" and _dot(want, got) < 0.0:
                # q and -q are the same turn.
                got = tuple(-value for value in got)
            off = max(abs(a - b) for a, b in zip(want, got))
            if not math.isfinite(off) or off > tolerance:
                lines.append("%s's rest %s is off by %.5f" % (bone, what, off))
    return lines


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))
