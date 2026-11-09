"""Checks that a model's clips move cleanly (model skill, #1071): per clip, foot sliding, the loop
seam and jitter, as numbers with limits that fail the build.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_motion.py -- \
        <model.glb> [<Clip>=<speed> ...] [--speeds <folder>] [--summary]

- **Foot sliding:** how fast a paw moves over the ground while it stands on it (its lowest point
  within CONTACT of the ground), in metres a second. The ground runs back under the model at the
  speed the game moves it while it plays the clip (`Walk=2.17`, metres a second; none given is
  standing still). The limit holds for every clip: the legs plant their paws (#1073).
- **Loop seam** (the clips the model's .import loops): how far the last frame's pose is from the
  first's (degrees, and the largest shift of any bone, in millimetres, naming the bone: the
  root, or a wisp its `loc.` channel places, #1170), and how rough the curves run through it
  (below). A loop that eases to a stop at its ends shows here.
- **Jitter:** how rough a joint's curve runs: how much its change of speed from one frame to the
  next (the second difference of its angle, degrees a frame per frame) departs from the frames
  either side, at the roughest frame of any joint, across the seam too on a loop. A fast move
  that bends smoothly passes; a pop, a snap or a stall doesn't.

- **Joins** (#1158): a loop played between a lead-in and a lead-out, named after it (`Channel`
  between `ChannelStart` and `ChannelEnd`): how far the lead-in's last pose is from the loop's
  first, and the loop's first from the lead-out's first, under the seam's limits, so the game
  can hand over from one to the next at any loop's end.
- **Start:** a clip must start at time 0; Godot holds a late first key from 0 until then, a
  pause at every loop's seam.

It prints a line per clip and `MOTION CHECK: PASS` or `FAIL` (and exits 1 on a fail), through
game_shared.log (#1115): a failing line is an error on the .glb. With `--summary` (#1524) it prints
only each limit a clip misses and by how much, one line each (lib/summary.py). The clip rate and the loops come
from the .glb's .import, as the game imports it.

`--speeds <folder>` (#2117) also takes the speeds from `<folder>/<model.glb>.speeds`, which
check_rebuild.py's `--keep` writes from each build's `SPEEDS` line, so CI checks every model at
the speeds its build prints; a model without one (a prop, the third-party Rogue) is checked
standing still. A model with a Walk or Run clip but no speed for it fails there (#2128): CI would
check its gait standing still. A foot no frame finds on the ground (no part of the mesh follows
it) fails its clip rather than passing unseen (#2128), also beside a weighted one: only a bone
named as a control (CONTROLS, the Rogue's IK-foot and control-foot-roll) is skipped, and named
(#2142); a rig without a body, such as the player's
clip library, is measured by its feet's joints instead. A model without a rig or clips passes:
nothing moves; one with clips whose rig has no animation data to play them on fails (#2132). Each
rig is checked on the clips it plays, so a model's second rig counts too, and a clip that drives
only shape keys passes, as nothing for bones to measure; a clip that moves neither a rig nor shape
keys fails, beside the clips a rig plays too (#2141). A clip or join that still fails today waits
in KNOWN with the issue that fixes it (lib/known.py's way; not with `--summary`, whose verdict is
the raw one): it prints its numbers and doesn't fail the check, and fails once it passes until
it's taken off. CI runs it on every .glb."""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import ground, imported, known, summary  # noqa: E402

# A paw this close to the ground (metres) stands on it.
CONTACT = 0.02
# The limits: paw speed over the ground (m/s), the seam's pose (degrees) and any bone's shift
# (metres, the root's or a wisp's), and how rough a curve may run anywhere, the seam included
# (degrees a frame per frame, see roughness).
SLIDE_LIMIT = 0.2
SEAM_POSE_LIMIT = 0.5
SEAM_SHIFT_LIMIT = 0.002
JITTER_LIMIT = 15.0
# The clips the game glides a model at while they play: each needs the speed its build prints.
GAITS = ("Walk", "Run")
# The prefixes that name a rig's foot controls rather than its feet (an IK target, a foot roll:
# the Rogue's IK-foot.l and control-foot-roll.l, #2142), in lower case. A bone named like a foot
# that moves no vertex is still a foot, one that lost its weights, and fails as unmeasured.
CONTROLS = ("ik-", "control-")
# A clip line's note on the feet no frame measures: a failure KNOWN never excuses, since a check
# that can't see a foot says nothing about it.
UNMEASURED = "; unmeasured (no part of the mesh follows the bone): "

# (model, clip) that fails today, with the issue that fixes it; that issue takes its entries off.
# A join is named after its lead with " join" (`("mana_wolf", "WalkStart join")`).
KNOWN = {
    ("fohossa", "Run"): 1629,
    ("frostfire_hound", "Walk"): 2171,
    ("kavrikka", "Attack"): 1780,
    ("kavrikka", "Run"): 1780,
    ("kavrikka", "Walk"): 1780,
    # The third-party Rogue's every clip (#2129).
    **{("Rogue", clip): 2129 for clip in (
        "1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Slice_Horizontal",
        "1H_Melee_Attack_Stab", "1H_Ranged_Aiming", "1H_Ranged_Reload", "1H_Ranged_Shoot",
        "1H_Ranged_Shooting", "2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice", "2H_Melee_Attack_Spin",
        "2H_Melee_Attack_Spinning", "2H_Melee_Attack_Stab", "2H_Ranged_Aiming", "2H_Ranged_Shoot",
        "2H_Ranged_Shooting", "Block", "Block_Attack", "Cheer", "Death_A", "Death_B", "Dodge_Backward",
        "Dodge_Forward", "Dodge_Left", "Dodge_Right", "Dualwield_Melee_Attack_Chop",
        "Dualwield_Melee_Attack_Slice", "Dualwield_Melee_Attack_Stab", "Hit_A", "Hit_B", "Lie_Down",
        "Lie_StandUp", "Running_A", "Running_B", "Running_Strafe_Left", "Running_Strafe_Right",
        "Sit_Chair_Down", "Sit_Floor_Down", "Sit_Floor_StandUp", "Spellcast_Long", "Spellcast_Raise",
        "Spellcast_Shoot", "Throw", "Unarmed_Melee_Attack_Kick", "Unarmed_Melee_Attack_Punch_A",
        "Unarmed_Melee_Attack_Punch_B", "Walking_A", "Walking_B", "Walking_Backwards", "Walking_C",
    )},
}


def spin(a, b):
    """The rotation from quaternion `a` to `b`, as a vector in degrees (axis times angle)."""
    turn = a.rotation_difference(b)
    if turn.w < 0.0:
        turn.negate()
    axis, angle = turn.to_axis_angle()
    return axis * math.degrees(angle)


def joints(rig, foot):
    """A foot's joints: its bone and every bone below it (the toes and their tips)."""
    bone = rig.pose.bones[foot]
    return [bone] + list(bone.children_recursive)


def jointed(rig, feet):
    """Per foot, from its joints (a rig without a body, such as the player's clip library, #2128):
    the lowest joint's height above its rest height, and their centre. Such a rig stands on the
    floor at rest (lib/planted_feet.py), so a joint at its rest height is on the ground."""
    spots = {}
    for name in feet:
        bones = joints(rig, name)
        world = rig.matrix_world
        heights = [(world @ bone.head).z - (world @ bone.bone.head_local).z for bone in bones]
        centre = sum((world @ bone.head for bone in bones), Vector()) / len(bones)
        spots[name] = (min(heights), centre.x, centre.y)
    return spots


def weighs(obj, bone):
    """Whether any vertex of `obj` carries some of `bone`'s weight."""
    group = obj.vertex_groups.get(bone)
    return group is not None and any(
        entry.group == group.index and entry.weight > 0.0 for vertex in obj.data.vertices for entry in vertex.groups)


def foot_bones(rig, meshes):
    """The rig's feet, and whether it has no body to measure them on. A bone named like a foot
    whose name starts like a control (CONTROLS) is skipped, and named; a rig whose feet all move
    no vertex has no body (the player's clip library, its stand-in only, #2128), and its feet are
    measured by their joints. A foot that moves no vertex beside one that does stays a foot: no
    frame measures it, and its clips fail (#2142)."""
    named = ground.foot_bones(rig)
    controls = [name for name in named if name.lower().startswith(CONTROLS)]
    if controls:
        log.info("MOTION rig %s: not feet but controls: %s" % (rig.name, ", ".join(sorted(controls))))
    feet = [name for name in named if name not in controls]
    bodiless = bool(feet) and not any(weighs(obj, name) for name in feet for obj in meshes)
    return feet, bodiless


def sample(rig, meshes, feet, bodiless, start, end):
    """Every frame's local bone rotations and translations (metres: the model is built at its
    scale) and, per foot, its lowest point and centre: of the part of the mesh it moves most or,
    on a rig without a body, of its joints."""
    scene = bpy.context.scene
    depsgraph = bpy.context.evaluated_depsgraph_get()
    parts = {obj.name: ground.owned(obj, feet) for obj in meshes}
    frames = []
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        turns = {bone.name: bone.matrix_basis.to_quaternion() for bone in rig.pose.bones}
        places = {bone.name: bone.location.copy() for bone in rig.pose.bones}
        points = {name: [] for name in feet}
        for obj in meshes:
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            world = evaluated.matrix_world
            for name, indices in parts[obj.name].items():
                points[name] += [world @ mesh.vertices[index].co for index in indices]
            evaluated.to_mesh_clear()
        if bodiless:
            frames.append((turns, places, jointed(rig, feet)))
            continue
        # A foot may be split over several meshes: all of its parts count.
        spots = {}
        for name, found in points.items():
            if found:
                centre = sum(found, found[0] * 0.0) / len(found)
                spots[name] = (min(point.z for point in found), centre.x, centre.y)
        frames.append((turns, places, spots))
    return frames


def standing(height):
    """On the ground: within CONTACT of it (a paw sunk deeper is the ground check's failure)."""
    return -CONTACT < height < CONTACT


def sliding(frames, feet, fps, speed):
    """The fastest and the mean paw speed over the ground while standing, and each paw's fastest.
    The model faces -Y, so the ground runs toward +Y under it."""
    fastest = {name: 0.0 for name in feet}
    speeds = []
    for (_t0, _r0, now), (_t1, _r1, after) in zip(frames, frames[1:]):
        for name in feet:
            if name in now and name in after and standing(now[name][0]) and standing(after[name][0]):
                dx = (after[name][1] - now[name][1]) * fps
                dy = (after[name][2] - now[name][2]) * fps - speed
                slide = math.hypot(dx, dy)
                speeds.append(slide)
                fastest[name] = max(fastest[name], slide)
    mean = sum(speeds) / len(speeds) if speeds else 0.0
    return max(speeds, default=0.0), mean, fastest


def spins(frames):
    """Per bone, its rotation from each frame to the next (the last frame of a loop is its first)."""
    bones = frames[0][0].keys()
    return {bone: [spin(a[0][bone], b[0][bone]) for a, b in zip(frames, frames[1:])] for bone in bones}


def roughness(turns, loop):
    """Per bone, how much each frame's change of speed (the second difference of its angle)
    departs from the frames either side, by frame: a curve that bends smoothly changes its speed
    smoothly, while a pop, a snap or a stall stands out. A loop wraps around its seam."""
    out = {}
    for bone, steps in turns.items():
        if loop:
            steps = steps[-2:] + steps + steps[:2]
        bends = [after - before for before, after in zip(steps, steps[1:])]
        rough = [(bend - (before + after) / 2).length for before, bend, after in zip(bends, bends[1:], bends[2:])]
        out[bone] = rough if loop else [0.0, 0.0] + rough + [0.0, 0.0]
    return out


def jitter(rough, start):
    """The roughest frame of any joint: (degrees a frame per frame, bone, frame)."""
    return max(((value, bone, start + index) for bone, values in rough.items() for index, value in enumerate(values)),
               default=(0.0, "", start))


def seam(frames, rough):
    """How far a loop's last pose is from its first (see apart), and how rough its curves run
    through the seam (the first frame), with the roughest bone."""
    pose, shift, shifted = apart(frames[0], frames[-1])
    speed, bone = max((values[0], bone) for bone, values in rough.items())
    return pose, shift, shifted, speed, bone


def apart(a, b):
    """How far pose `b` is from pose `a`: the most any bone turns (degrees), and the most any bone
    shifts (metres) with that bone's name."""
    pose = max(spin(a[0][bone], b[0][bone]).length for bone in a[0])
    shift, shifted = max(((b[1][bone] - a[1][bone]).length, bone) for bone in a[1])
    return pose, shift, shifted


def joins(ends, loops, misses):
    """Each loop's joins to its lead-in (<loop>Start) and lead-out (<loop>End), from `ends` (each
    clip's first and last frame): lines and whether they pass; `misses` collects the limits a join
    misses."""
    lines, passed = [], True
    for loop in sorted(name for name in loops if name in ends):
        first = ends[loop][0]
        pairs = []
        if loop + "Start" in ends:
            pairs.append((loop + "Start", ends[loop + "Start"][1], first))
        if loop + "End" in ends:
            pairs.append((loop + "End", first, ends[loop + "End"][0]))
        for lead, before, after in pairs:
            pose, shift, shifted = apart(before, after)
            fails = pose > SEAM_POSE_LIMIT or shift > SEAM_SHIFT_LIMIT
            misses.above(lead, "join-pose", pose, SEAM_POSE_LIMIT, "deg")
            misses.above(lead, "join-shift", shift, SEAM_SHIFT_LIMIT, "mm", 1000)
            passed = passed and not fails
            lines.append("%s %s join: %.2f deg, shift %.1f mm (%s)" % (
                "FAIL" if fails else "ok", lead, pose, shift * 1000, shifted))
    return lines, passed


def check(rig, actions, meshes, fps, loops, speeds, misses):
    """Lines per clip (of `actions`, the rig's) and join, and whether every one passes; `misses`
    (summary.Misses) collects each limit a clip misses."""
    feet, bodiless = foot_bones(rig, meshes)
    lines, passed, ends = [], True, {}
    for action in actions:
        start, end = imported.play(rig, action)
        # A clip that starts after time 0 holds its first pose until then in the game: a pause
        # at every loop's seam (#1089).
        late = start != 0
        loop = action.name in loops
        frames = sample(rig, meshes, feet, bodiless, start, end)
        # A foot no frame measures can't be seen to slide: that fails too (#2128).
        unmeasured = sorted(name for name in feet if not any(name in spots for _t, _p, spots in frames))
        ends[action.name] = (frames[0], frames[-1])
        slide, mean, fastest = sliding(frames, feet, fps, speeds.get(action.name, 0.0))
        rough = roughness(spins(frames), loop)
        shake, shaking, at = jitter(rough, start)
        fails = late or bool(unmeasured) or shake > JITTER_LIMIT or slide > SLIDE_LIMIT
        if late:
            misses.flag(action.name, "late-start")
        for name in unmeasured:
            misses.flag(action.name, name + "-unmeasured")
        misses.above(action.name, "slide", slide, SLIDE_LIMIT, "m/s")
        misses.above(action.name, "jitter", shake, JITTER_LIMIT, "deg/frame^2")
        text = "slide %.2f m/s (mean %.2f; %s)" % (
            slide, mean, ", ".join("%s %.2f" % (name, value) for name, value in sorted(fastest.items())))
        if loop:
            pose, shift, shifted, speed, jumping = seam(frames, rough)
            fails = fails or pose > SEAM_POSE_LIMIT or shift > SEAM_SHIFT_LIMIT
            misses.above(action.name, "seam-pose", pose, SEAM_POSE_LIMIT, "deg")
            misses.above(action.name, "seam-shift", shift, SEAM_SHIFT_LIMIT, "mm", 1000)
            text += "; seam %.2f deg, shift %.1f mm (%s), rough %.2f deg/frame^2 (%s)" % (
                pose, shift * 1000, shifted, speed, jumping)
        text += "; jitter %.2f deg/frame^2 (%s, frame %d)" % (shake, shaking, at)
        if unmeasured:
            text += UNMEASURED + ", ".join(unmeasured)
        if late:
            text += "; starts at frame %d, not 0: the game holds its first pose until then" % start
        passed = passed and not fails
        lines.append("%s %s%s: %s" % ("FAIL" if fails else "ok", action.name, " (loop)" if loop else "", text))
    joined, joins_pass = joins(ends, loops, misses)
    return lines + joined, passed and joins_pass


def shapes_only(action):
    """Whether `action` drives only shape keys (a mesh's, not a bone)."""
    return bool(action.slots) and all(found.target_id_type == "KEY" for found in action.slots)


def sorted_clips(rigs):
    """Per rig that plays clips, the rig, its clips and the meshes it deforms; the clips that
    drive only shape keys; and the clips nothing of either moves."""
    actions = sorted(bpy.data.actions, key=lambda a: a.name)
    played = []
    for rig in rigs:
        own = [action for action in actions if imported.slot(action, rig) is not None]
        if own:
            rig.animation_data.use_nla = False
            meshes = [obj for obj in ground.skinned(bpy.data.objects)
                      if any(m.type == "ARMATURE" and m.object == rig for m in obj.modifiers)]
            played.append((rig, own, meshes))
    playing = {action for _rig, own, _meshes in played for action in own}
    shaped = [action for action in actions if action not in playing and shapes_only(action)]
    stray = [action for action in actions if action not in playing and action not in shaped]
    return played, shaped, stray


def judge(model, line):
    """A report line as KNOWN judges it (lib/known.py): the line and whether it fails the check.
    A join's line (`ok WalkStart join: ...`) is keyed apart from its lead's own clip, and a clip
    with a foot unmeasured fails whatever KNOWN says."""
    if UNMEASURED in line:
        return line, True
    words = line.split(" ", 3)
    clip = words[1] + " join" if words[2:3] == ["join:"] else None
    return known.judge(KNOWN, model, line, clip)


def speeds_of(glb, folder):
    """The `<Clip>=<speed>` pairs `folder/<model.glb>.speeds` holds, none without one."""
    path = os.path.join(folder, os.path.basename(glb) + ".speeds")
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as found:
        return [arg.split("=", 1) for arg in found.read().split()]


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    short = "--summary" in args
    args = [arg for arg in args if arg != "--summary"]
    folder = None
    if "--speeds" in args:
        at = args.index("--speeds")
        folder = args[at + 1]
        args = args[:at] + args[at + 2:]
    glb = args[0]
    model = os.path.splitext(os.path.basename(glb))[0]
    pairs = [arg.split("=", 1) for arg in args[1:]]
    if folder is not None:
        built = speeds_of(glb, folder)
        if built:
            log.info("MOTION %s at the speeds its build prints: %s" % (model, " ".join("=".join(p) for p in built)))
        else:
            log.info("MOTION %s: its build prints no speeds, checked standing still" % model)
        pairs = built + pairs
    speeds = {name: float(value) for name, value in pairs}
    fps, loops = imported.settings(glb)
    imported.load_view(glb, fps)
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if not rigs or not bpy.data.actions:
        # A prop: no rig or no clips, nothing moves.
        log.info("MOTION %s no rig or clips: nothing to check" % model)
        log.info("MOTION CHECK: PASS (at %d fps)" % fps)
        sys.exit(0)
    played, shaped, stray = sorted_clips(rigs)
    if not played and stray:
        # The clips move something else, or nothing: no rig can play them, so none is checked.
        log.error("MOTION %s has clips but its rig has no animation data to play them on" % model, glb)
        log.info("MOTION CHECK: FAIL (at %d fps)" % fps)
        sys.exit(1)
    misses = summary.Misses()
    lines, measured = [], True
    for rig, own, meshes in played:
        if len(played) > 1:
            log.info("MOTION %s rig %s plays %s" % (model, rig.name, " ".join(action.name for action in own)))
        checked, passes = check(rig, own, meshes, fps, loops, speeds, misses)
        lines += checked
        measured = measured and passes
    # A shape-key clip has no bones to measure: a face's or a body's blend, not a rig's motion.
    lines += ["ok %s: drives only shape keys, no bones to measure" % action.name for action in shaped]
    for action in stray:
        misses.flag(action.name, "moves-no-rig")
        lines.append("FAIL %s: moves neither a rig nor shape keys" % action.name)
    measured = measured and not stray
    if short:
        for line in summary.lines(misses, sorted({action.name for action in bpy.data.actions})):
            log.info("MOTION " + line)
        passed = measured
        lines = []
    else:
        passed = True
    if folder is not None:
        # CI takes every speed from the build: a gait it has none for would be checked standing
        # still, its slide meaning nothing (#2128).
        unspeeded = [clip for clip in GAITS if clip in bpy.data.actions and clip not in speeds]
        if unspeeded:
            passed = False
            log.error("MOTION %s: its build prints no speed for %s: print them in a SPEEDS line"
                      % (model, ", ".join(unspeeded)), glb)
    for line in lines:
        text, fails = judge(model, line)
        passed = passed and not fails
        if fails:
            log.error("MOTION %s %s" % (model, text), glb)
        else:
            log.info("MOTION %s %s" % (model, text))
    log.info("MOTION CHECK: %s (at %d fps)" % ("PASS" if passed else "FAIL", fps))
    sys.exit(0 if passed else 1)


main()
