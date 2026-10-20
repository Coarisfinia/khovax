"""Clips: poses keyed into one action per clip, and a quadruped's standard set (Idle, Walk, Run,
Attack, Hit, Faint) that any model built on quadruped.armature can use or adjust. A pose is
{bone: (rx, ry, rz)} in radians about the bone's own axes (quadruped: X bends, Z sways), plus
"root_loc" for the root's (sideways, up, forward) shift in the model's unscaled metres: the root
bone points up, so its own Y axis is up and its Z axis forward."""

import math

import bpy

from . import ground, scene


def cycle_frames(speed, stride, fps):
    """How many frames one gait cycle takes so the feet don't slide: `stride` (metres the body
    moves in one cycle, at the game's size) at `speed` (metres a second the game moves it)."""
    return max(4, round(stride / speed * fps))


def gait(frames, swing, lift, phases, bob, spine_flex=0.0):
    """A looping gait: each leg swings fore and back and folds as it lifts, at its phase
    ({("front"|"hind", "L"|"R"): 0..1}). It starts and ends on the same pose."""
    poses = []
    for step in range(0, frames + 1, max(1, frames // 8)):
        t = step / frames
        pose = {}
        for (leg, side), phase in phases.items():
            angle = 2 * math.pi * (t + phase)
            back = math.sin(angle)
            raised = max(0.0, -math.cos(angle))
            if leg == "front":
                pose["upper_arm." + side] = (swing * back, 0, 0)
                pose["forearm." + side] = (-lift * raised, 0, 0)
                pose["front_paw." + side] = (lift * raised * 0.8, 0, 0)
            else:
                pose["thigh." + side] = (swing * back, 0, 0)
                pose["shin." + side] = (lift * raised, 0, 0)
                pose["hock." + side] = (-lift * raised * 0.9, 0, 0)
        double = 4 * math.pi * t
        pose["root_loc"] = (0, bob * math.cos(double), 0)
        pose["spine_01"] = (spine_flex * math.sin(2 * math.pi * t), 0, 0)
        pose["neck"] = (0.04 * math.cos(double), 0, 0)
        pose["tail_01"] = (0.15, 0, 0.18 * math.sin(2 * math.pi * t))
        pose["tail_02"] = (0, 0, 0.15 * math.sin(2 * math.pi * t - 0.6))
        poses.append((step + 1, pose))
    return poses


WALK = {("front", "L"): 0.0, ("hind", "R"): 0.0, ("front", "R"): 0.5, ("hind", "L"): 0.5}
GALLOP = {("front", "L"): 0.0, ("front", "R"): 0.1, ("hind", "L"): 0.5, ("hind", "R"): 0.6}


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
    return poses


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
    return [(1, {}), (8, crouch), (13, lunge), (16, bite), (24, {})]


def hit():
    """Recoil from a blow: back, head up, ears flat, and back again."""
    recoil = {"root_loc": (0, -0.04, -0.14), "spine_01": (0.12, 0, 0.1), "spine_02": (0.1, 0, 0.1),
              "neck": (-0.3, 0, 0.15), "head": (-0.25, 0, 0.1), "jaw": (0.35, 0, 0),
              "tail_01": (-0.4, 0, 0)}
    _both(recoil, "ear", (0.6, 0, 0))
    _both(recoil, "upper_arm", (-0.2, 0, 0))
    return [(1, {}), (5, recoil), (18, {})]


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
    return [(1, {}), (14, sinking), (30, lying), (40, lying)]


def animate(rig, clips, scale, ground_meshes=()):
    """Keys every clip as its own action on every bone, so each clip sets the whole pose, and
    stashes it on an NLA track the glTF export turns into a named animation. `scale` is the
    model's (scene.apply_scale), which the root's shifts are scaled by. With `ground_meshes`
    (the bound body), every frame where they sink below the ground lifts the root onto it."""
    rig.animation_data_create()
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="POSE")
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
    for name, poses in clips.items():
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
        if ground_meshes:
            root = next(bone.name for bone in rig.pose.bones if bone.parent is None)
            last = max(frame for frame, _pose in poses)
            ground.settle(rig, ground_meshes, root, range(1, last + 1))
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.name = name
        rig.animation_data.action = None
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in rig.pose.bones:
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
