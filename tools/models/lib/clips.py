"""Clips: poses keyed into one action per clip, and a quadruped's standard set (Idle, Walk, Run,
Attack, Hit, Faint) that any model built on quadruped.armature can use or adjust. A pose is
{bone: (rx, ry, rz)} in radians about the bone's own axes (quadruped: X bends, Z sways), plus
"root_loc" for the root's (sideways, up, forward) shift in the model's unscaled metres: the root
bone points up, so its own Y axis is up and its Z axis forward."""

import math

import bpy

from . import ground, motion, scene


def cycle_frames(speed, stride, fps):
    """How many frames one gait cycle takes so the feet don't slide: `stride` (metres the body
    moves in one cycle, at the game's size) at `speed` (metres a second the game moves it)."""
    return max(4, round(stride / speed * fps))


class Clip:
    """A clip's keys, [(frame, pose)], and whether the game loops it. A looping clip's last key
    is its first pose again, one cycle on."""

    def __init__(self, keys, loop=False):
        self.keys = keys
        self.loop = loop


# The legs' phases in a cycle, as ("front"|"hind", "L"|"R"): 0..1. A walk is four beats, each
# foot down alone in turn (hind, fore on the same side, then the other side); a trot moves the
# diagonal pairs together; a gallop lands the fore pair just apart, then the hind pair.
WALK = {("hind", "L"): 0.0, ("front", "L"): 0.25, ("hind", "R"): 0.5, ("front", "R"): 0.75}
TROT = {("front", "L"): 0.0, ("hind", "R"): 0.0, ("front", "R"): 0.5, ("hind", "L"): 0.5}
GALLOP = {("front", "L"): 0.0, ("front", "R"): 0.1, ("hind", "L"): 0.5, ("hind", "R"): 0.6}


def _step(u, duty, sweep):
    """Where a paw is along the ground (metres ahead of under its hip) at `u` (0..1) of its own
    cycle, and how far it's raised (0..1). On the ground (the first `duty` of the cycle) it runs
    back at the body's speed, so it doesn't slide; then it swings forward, leaving and landing at
    that speed."""
    if u < duty:
        return sweep * (0.5 - u / duty), 0.0
    s = (u - duty) / (1.0 - duty)
    slope = -sweep * (1.0 - duty) / duty
    ahead = ((2 * s ** 3 - 3 * s ** 2 + 1) * -sweep / 2 + (s ** 3 - 2 * s ** 2 + s) * slope
             + (-2 * s ** 3 + 3 * s ** 2) * sweep / 2 + (s ** 3 - s ** 2) * slope)
    # It lifts a little early and lands a little softer: the fold peaks before halfway.
    return ahead, math.sin(math.pi * (s + 0.25 * s * (1.0 - s))) ** 2


def _leg(points):
    """A leg's reach from its top joint to its paw's tip, and how far it leans forward at rest
    (radians from straight down; the model faces -Y)."""
    top, tip = points[0], points[-1]
    return math.dist(top, tip), math.atan2(top[1] - tip[1], top[2] - tip[2])


def _sink(reach, lean, slant, bob):
    """How far a planted leg slanted `slant` from straight down lets the body sink, `bob` of the
    way (below its height at rest; less than nothing raises it)."""
    return bob * reach * (math.cos(lean) - math.cos(slant))


def gait(frames, stride, body, phases, duty, lift, bob=0.4, roll=0.0, spine_flex=0.0):
    """A looping gait, posed on every frame: each leg plants its paw for `duty` of the cycle,
    sweeping it back `stride` x `duty` (`stride`: metres the body moves in one cycle, at
    `body`'s unscaled size, the quadruped.Proportions), then folds (`lift`) and swings it
    forward, at its phase. The hips and the shoulders sink as their planted legs lean (`bob`
    of the way: the legs' joints would take up the rest), the legs halfway through their step
    counting most (so they bob out of phase and the body pitches), the hips and the chest roll
    (`roll`, radians) toward the leg that bears the weight, and the head counters the bob."""
    legs = {"front": _leg(body.front_leg), "hind": _leg(body.hind_leg)}
    length = abs(body.hips[1] - body.front_leg[0][1])
    neck = math.dist(body.chest, body.nose)
    sweep = stride * duty
    edge = sweep / 2
    poses = []
    for step in range(frames + 1):
        t = step / frames
        angles, raised, drops = {}, {}, {"front": [0.0, 0.0], "hind": [0.0, 0.0]}
        for (leg, side), phase in phases.items():
            u = (t - phase) % 1.0
            ahead, up = _step(u, duty, sweep)
            reach, lean = legs[leg]
            # The paw's sweep is centred under the leg's top joint; a leg turns back about it.
            slant = math.asin(max(-1.0, min(1.0, ahead / reach)))
            angles[leg, side], raised[leg, side] = lean - slant, up
            if u < duty:
                # How much this leg holds the body up: none as it lands and lifts, most halfway.
                weight = math.sin(math.pi * u / duty)
                drops[leg][0] += weight * _sink(reach, lean, slant, bob)
                drops[leg][1] += weight
        # What the planted legs don't hold, the legs at the ends of their sweep do (as a paw
        # lands or lifts), so the body moves on smoothly as they take turns.
        hind, front = (
            (total + max(0.0, 1.0 - weight) * _sink(legs[leg][0], legs[leg][1], math.asin(edge / legs[leg][0]), bob))
            / max(1.0, weight)
            for leg, (total, weight) in (("hind", drops["hind"]), ("front", drops["front"])))
        pitch = (front - hind) / length
        hips_roll = -roll * math.cos(2 * math.pi * (t - phases["hind", "L"] - duty / 2))
        chest_roll = -roll * math.cos(2 * math.pi * (t - phases["front", "L"] - duty / 2))
        flex = spine_flex * math.sin(2 * math.pi * t)
        pose = {"root_loc": (0.0, -hind, 0.0), "hips": (pitch, hips_roll, 0.0), "spine_01": (flex, 0.0, 0.0),
                "spine_02": (0.0, chest_roll - hips_roll, 0.0)}
        for (leg, side), angle in angles.items():
            up = raised[leg, side]
            # The legs hang from the pitched and rolled body: they turn back by as much, so the
            # planted paws stay where they are.
            if leg == "front":
                pose["upper_arm." + side] = (angle - pitch - flex, 0.0, chest_roll)
                # A foreleg folds more than a hind one to clear the ground: it hangs straighter.
                pose["forearm." + side] = (-1.5 * lift * up, 0.0, 0.0)
                pose["front_paw." + side] = (0.8 * lift * up, 0.0, 0.0)
            else:
                pose["thigh." + side] = (angle - pitch, 0.0, hips_roll)
                pose["shin." + side] = (lift * up, 0.0, 0.0)
                pose["hock." + side] = (-lift * up * 0.9, 0.0, 0.0)
        # The neck lifts the head against most of the shoulders' bob, and the head stays level.
        lifted = -0.6 * front / neck - pitch - flex
        pose["neck"] = (lifted, 0.0, 0.0)
        pose["head"] = (-(pitch + flex + lifted), 0.0, 0.0)
        pose["tail_01"] = (0.15, 0.0, 0.18 * math.sin(2 * math.pi * (t - phases["hind", "L"])))
        poses.append((step + 1, pose))
    return Clip(poses, loop=True)


def _both(pose, bone, rotation):
    pose[bone + ".L"] = rotation
    pose[bone + ".R"] = rotation
    return pose


def idle(frames=60):
    poses = []
    for step in range(0, frames + 1, frames // 6):
        t = step / frames
        wave = math.sin(2 * math.pi * t)
        pose = {
            "spine_02": (0.02 * wave, 0, 0),
            "neck": (-0.04 * wave, 0, 0),
            "head": (0.05 * wave, 0, 0.08 * math.sin(2 * math.pi * t + 1)),
            "tail_01": (0.1, 0, 0.2 * wave),
            "tail_02": (0, 0, 0.18 * math.sin(2 * math.pi * t - 0.8)),
            "tail_03": (0, 0, 0.15 * math.sin(2 * math.pi * t - 1.6)),
            "jaw": (0.05 + 0.05 * wave, 0, 0),
            "root_loc": (0, -0.01 + 0.01 * wave, 0),
        }
        if frames // 2 <= step < frames * 3 // 4:
            pose["ear.L"] = (0, 0, -0.3)
        poses.append((step + 1, pose))
    return Clip(poses, loop=True)


def attack():
    """Crouch, lunge with the jaw wide, bite, and back."""
    crouch = {"root_loc": (0, -0.12, -0.12), "hips": (-0.12, 0, 0), "neck": (0.25, 0, 0),
              "head": (-0.1, 0, 0), "tail_01": (-0.2, 0, 0)}
    for bone, angle in (("upper_arm", 0.25), ("forearm", -0.4), ("thigh", -0.3), ("shin", 0.5), ("ear", 0.4)):
        _both(crouch, bone, (angle, 0, 0))
    lunge = {"root_loc": (0, 0.05, 0.35), "hips": (0.08, 0, 0), "neck": (-0.15, 0, 0),
             "head": (0.2, 0, 0), "jaw": (0.6, 0, 0), "tail_01": (0.3, 0, 0),
             "upper_arm.L": (-0.55, 0, 0), "upper_arm.R": (-0.45, 0, 0),
             "thigh.L": (0.45, 0, 0), "thigh.R": (0.4, 0, 0)}
    _both(lunge, "ear", (0.4, 0, 0))
    bite = dict(lunge, jaw=(0.0, 0, 0))
    return Clip([(1, {}), (8, crouch), (13, lunge), (16, bite), (24, {})])


def hit():
    """Recoil from a blow: back, head up, ears flat, and back again."""
    recoil = {"root_loc": (0, -0.04, -0.14), "spine_01": (0.12, 0, 0.1), "spine_02": (0.1, 0, 0.1),
              "neck": (-0.3, 0, 0.15), "head": (-0.25, 0, 0.1), "jaw": (0.35, 0, 0),
              "tail_01": (-0.4, 0, 0)}
    _both(recoil, "ear", (0.6, 0, 0))
    _both(recoil, "upper_arm", (-0.2, 0, 0))
    return Clip([(1, {}), (5, recoil), (18, {})])


def faint(body_height):
    """The legs give way and it sinks onto its belly, `body_height` down, head on the ground and
    tail lying out behind (a hanging tail would hold the body off the ground once
    animate grounds the clip), and stays there."""
    sinking = {"root_loc": (0, -body_height * 0.45, 0), "neck": (0.2, 0, 0), "head": (0.1, 0, 0.1)}
    for bone, angle in (("upper_arm", 0.4), ("forearm", -0.7), ("thigh", -0.5), ("shin", 1.0), ("ear", 0.5)):
        _both(sinking, bone, (angle, 0, 0))
    lying = {"root_loc": (0, -body_height * 0.9, 0), "neck": (0.45, 0, 0), "head": (0.25, 0, 0.25),
             "jaw": (0.1, 0, 0), "thigh.L": (-1.0, 0, 0.15), "thigh.R": (-1.0, 0, -0.15),
             "ear.L": (0.7, 0, 0.2), "ear.R": (0.7, 0, -0.2), "tail_01": (0.45, 0, 0.3),
             "tail_02": (0.1, 0, 0.3)}
    for bone, angle in (("upper_arm", -1.1), ("forearm", -0.4), ("front_paw", 0.9), ("shin", 1.9), ("hock", -1.2)):
        _both(lying, bone, (angle, 0, 0))
    return Clip([(1, {}), (14, sinking), (30, lying), (40, lying)])


# Overlap and follow-through (motion.follow): which bones trail their parent, and how:
# (frequency in Hz, damping, response, how much the root's movement swings them). The chains
# run spine, neck, head (and its jaw and ears), and hips to the tail's tip, each looser than the
# bone before it; the legs keep their paws where the gait plants them.
FOLLOW = {
    "neck": (3.0, 0.6, 0.0, 0.2),
    "head": (3.0, 0.5, 0.0, 0.2),
    "jaw": (4.0, 0.4, 0.0, 0.0),
    "ear.L": (3.0, 0.35, 0.0, 0.12),
    "ear.R": (3.0, 0.35, 0.0, 0.12),
    "tail_01": (2.8, 0.5, 0.0, 0.15),
    "tail_02": (2.5, 0.45, 0.0, 0.15),
    "tail_03": (2.3, 0.45, 0.0, 0.15),
    "tail_04": (2.1, 0.45, 0.0, 0.15),
}


def _curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def animate(rig, clips, scale, ground_meshes=(), chains=FOLLOW):
    """Keys every clip (name: Clip) as its own action and stashes it on an NLA track the glTF
    export turns into a named animation. Each clip is filled in to every frame and its `chains`
    trail their parents (motion), so every bone moves on its own curve, and every bone is keyed
    on every frame, so each clip sets the whole pose. A looping clip's curves cycle (Blender's
    Cycles modifier), so they run on through the seam. `scale` is the model's
    (scene.apply_scale), which the root's shifts are scaled by. With `ground_meshes` (the bound
    body), every frame where they sink below the ground lifts the root onto it."""
    rig.animation_data_create()
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="POSE")
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
    shape = motion.Rig(rig)
    fps = bpy.context.scene.render.fps
    for name, clip in clips.items():
        poses = motion.follow(shape, motion.fill(clip.keys, clip.loop), chains, scale, fps, clip.loop)
        action = bpy.data.actions.new(name)
        rig.animation_data.action = action
        for frame, pose in poses:
            for bone in rig.pose.bones:
                bone.rotation_euler = pose.get(bone.name, (0.0, 0.0, 0.0))
                bone.keyframe_insert("rotation_euler", frame=frame)
                if bone.parent is None:
                    shift = pose.get("root_loc", (0.0, 0.0, 0.0))
                    bone.location = tuple(scale * value for value in shift)
                    bone.keyframe_insert("location", frame=frame)
        if clip.loop:
            for curve in _curves(action):
                curve.modifiers.new("CYCLES")
        if ground_meshes:
            root = next(bone.name for bone in rig.pose.bones if bone.parent is None)
            ground.settle(rig, ground_meshes, root, [frame for frame, _pose in poses], loop=clip.loop)
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.name = name
        rig.animation_data.action = None
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in rig.pose.bones:
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
