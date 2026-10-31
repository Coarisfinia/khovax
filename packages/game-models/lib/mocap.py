"""Motion capture in the ASF/AMC format (the CMU database's, #1951), retargeted onto a rig of ours.

The ASF file is the performer's skeleton: each bone's direction and length at rest, in the
capture's world (Y up, the performer facing +Z), the frame its motion turns in (`axis`) and which
of its turns the motion keys (`dof`). The AMC file is the motion, every frame each bone's turns in
degrees. A bone's turn in the world is its parent's with C M C⁻¹ on top: C its axis frame, M its
keyed turn (Rz Ry Rx for `rx ry rz`).

`retarget` moves that motion onto a rig with other bones and another rest pose (Meshy's A-pose
against the capture's T-pose) by direction, not by angle: each mapped bone of the rig is first
turned so it points the way its capture bone points at rest, then turned as that bone turns
from its rest in the world. So an arm held out level in the capture is held out level on the rig,
whatever their rest poses. The hips take the root's height, scaled by the two hip heights, and
its drift across the ground from where it starts; the clip is turned so its last frame faces the
rig's front."""

import math

from mathutils import Matrix, Vector

# The capture's world (Y up, facing +Z) to Blender's (Z up, a model facing -Y).
TO_BLENDER = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)))
# An ASF `length 0.45` unit is 1/0.45 inches.
INCH = 0.0254


class Skeleton:
    """The performer's skeleton from an ASF file."""

    def __init__(self, path):
        self.bones, self.children, self.root_order = {}, {}, []
        self.scale = 1.0
        section, bone = None, None
        with open(path, encoding="utf-8", errors="replace") as lines:
            for raw in lines:
                line = raw.split("#", 1)[0].strip()
                if not line:
                    continue
                if line.startswith(":"):
                    section = line.split()[0]
                    continue
                words = line.split()
                if section == ":units" and words[0] == "length":
                    self.scale = INCH / float(words[1])
                elif section == ":root" and words[0] == "order":
                    self.root_order = [word.lower() for word in words[1:]]
                elif section == ":bonedata":
                    if words[0] == "begin":
                        bone = {"dof": []}
                    elif words[0] == "end":
                        self.bones[bone["name"]] = bone
                    elif words[0] == "name":
                        bone["name"] = words[1]
                    elif words[0] == "direction":
                        bone["direction"] = Vector([float(word) for word in words[1:4]])
                    elif words[0] == "length":
                        bone["length"] = float(words[1])
                    elif words[0] == "axis":
                        bone["axis"] = _turn([float(word) for word in words[1:4]], ["rx", "ry", "rz"])
                    elif words[0] == "dof":
                        bone["dof"] = [word.lower() for word in words[1:]]
                elif section == ":hierarchy" and words[0] not in ("begin", "end"):
                    self.children[words[0]] = words[1:]
        self.parents = {child: parent for parent, kids in self.children.items() for child in kids}

    def order(self):
        """Every bone, parents before children, the root first."""
        found, queue = [], ["root"]
        while queue:
            bone = queue.pop(0)
            found.append(bone)
            queue += self.children.get(bone, [])
        return found

    def rest_heads(self):
        """Where each bone starts at rest, in the capture's world, in metres."""
        heads = {"root": Vector((0.0, 0.0, 0.0))}
        tails = {"root": Vector((0.0, 0.0, 0.0))}
        for bone in self.order()[1:]:
            data = self.bones[bone]
            heads[bone] = tails[self.parents[bone]]
            tails[bone] = heads[bone] + data["direction"] * data["length"] * self.scale
        return heads


def read_motion(path):
    """Every frame of an AMC file: {bone: [values]}, in the order the file lists them."""
    frames, frame = [], None
    with open(path, encoding="utf-8", errors="replace") as lines:
        for raw in lines:
            line = raw.strip()
            if not line or line.startswith(("#", ":")):
                continue
            words = line.split()
            if len(words) == 1 and words[0].isdigit():
                frame = {}
                frames.append(frame)
            elif frame is not None:
                frame[words[0]] = [float(word) for word in words[1:]]
    return frames


def _turn(degrees, axes):
    """The turn of `degrees` about `axes` in turn (the first applied first)."""
    turn = Matrix.Identity(3)
    for value, axis in zip(degrees, axes):
        turn = Matrix.Rotation(math.radians(value), 3, axis[1].upper()) @ turn
    return turn


def world_turns(skeleton, frame):
    """Each bone's turn from its rest in the capture's world on `frame`, and the root's place."""
    values = frame.get("root", [0.0] * 6)
    root = dict(zip(skeleton.root_order, values))
    turns = {"root": _turn([root.get(axis, 0.0) for axis in ("rx", "ry", "rz")], ["rx", "ry", "rz"])}
    place = Vector([root.get(axis, 0.0) for axis in ("tx", "ty", "tz")]) * skeleton.scale
    for bone in skeleton.order()[1:]:
        data = skeleton.bones[bone]
        keyed = dict(zip(data["dof"], frame.get(bone, [])))
        motion = _turn([keyed.get(axis, 0.0) for axis in ("rx", "ry", "rz")], ["rx", "ry", "rz"])
        axis = data["axis"]
        turns[bone] = turns[skeleton.parents[bone]] @ axis @ motion @ axis.inverted()
    return turns, place


def _yaw(turn):
    """The turn about Blender's Z that brings a figure turned by `turn` to face -Y again."""
    front = turn @ Vector((0.0, -1.0, 0.0))
    return Matrix.Rotation(math.atan2(-front.x, -front.y), 3, "Z")


def retarget(skeleton, frames, rig, bones, step):
    """Keys `rig` with `frames` (every `step`th), each of its bones in `bones` ({rig bone: capture
    bone}) following its capture bone, the others following their parents. Returns how many frames
    it keyed."""
    rests = {bone.name: bone.matrix_local.to_3x3() for bone in rig.data.bones}
    heads = skeleton.rest_heads()
    hips = next(name for name, source in bones.items() if source == "root")
    # The capture's hip height: its root above its lowest rest point (the toes).
    floor = min(head.y for head in heads.values())
    ratio = rig.data.bones[hips].head_local.z / -floor
    # Each mapped bone turned to point the way its capture bone points at rest.
    aims = {}
    for name, source in bones.items():
        bone = rig.data.bones[name]
        if source == "root":
            aims[name] = Matrix.Identity(3)
            continue
        want = TO_BLENDER @ skeleton.bones[source]["direction"]
        have = (bone.tail_local - bone.head_local).normalized()
        aims[name] = have.rotation_difference(want.normalized()).to_matrix()
    sampled = frames[::step]
    # The clip faces the way the performer faces on its last frame: a throw's follow-through
    # faces where it threw, while its wind-up turns away.
    last_turns, _ = world_turns(skeleton, sampled[-1])
    face = _yaw(TO_BLENDER @ last_turns["root"] @ TO_BLENDER.inverted())
    start = face @ TO_BLENDER @ world_turns(skeleton, sampled[0])[1]
    order = [bone for bone in rig.data.bones if bone.parent is None]
    ordered = []
    while order:
        bone = order.pop(0)
        ordered.append(bone)
        order += list(bone.children)
    for number, frame in enumerate(sampled):
        turns, place = world_turns(skeleton, frame)
        worlds = {}
        for bone in ordered:
            name, parent = bone.name, bone.parent
            if name in bones:
                delta = face @ TO_BLENDER @ turns[bones[name]] @ TO_BLENDER.inverted()
                worlds[name] = delta @ aims[name] @ rests[name]
            else:
                worlds[name] = worlds[parent.name] @ rests[parent.name].inverted() @ rests[name]
            pose = rig.pose.bones[name]
            if parent is None:
                basis = rests[name].inverted() @ worlds[name]
            else:
                basis = (rests[name].inverted() @ rests[parent.name] @ worlds[parent.name].inverted()
                         @ worlds[name])
            pose.rotation_mode = "QUATERNION"
            pose.rotation_quaternion = basis.to_quaternion()
            pose.keyframe_insert("rotation_quaternion", frame=number)
            if name == hips:
                # The root's TY is its height above the capture's floor, not an offset from its
                # rest, so the scaled height is the hips' height on the rig.
                at = face @ TO_BLENDER @ place
                head = Vector(((at.x - start.x) * ratio, (at.y - start.y) * ratio, at.z * ratio))
                pose.location = rests[name].inverted() @ (head - bone.head_local)
                pose.keyframe_insert("location", frame=number)
    return len(sampled)

