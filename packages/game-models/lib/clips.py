"""Clips: poses keyed into one action per clip, and a quadruped's standard set (every creature
clip, clip_set) that any model built on quadruped.armature can use or adjust. A pose is
{bone: (rx, ry, rz)} in radians about the bone's own axes (quadruped: X bends, Z sways), plus
"root_loc" for the root's (sideways, up, forward) shift in the model's unscaled metres: the root
bone points up, so its own Y axis is up and its Z axis forward. The legs aren't posed by angle:
each paw stays planted where it stands unless a "plant.<paw>" shift or a Step moves it, and the
legs reach for it (legs, #1073); a paw's own rotation tilts it in the world."""

import math

import bpy

from . import clip_set, ground, legs, motion, scene


def cycle_frames(speed, stride, fps):
    """How many frames one gait cycle takes so the feet don't slide: `stride` (metres the body
    moves in one cycle, at the game's size) at `speed` (metres a second the game moves it)."""
    return max(4, round(stride / speed * fps))


class Clip:
    """A clip's keys, [(frame, pose)] or (frame, pose, ease) (motion.fill), whether the game loops
    it, its paws' steps (legs.Step), whether its paws are planted, and a shiver laid over it
    (motion.Shiver, one-shot clips only). A looping clip's last key is its first pose again, one
    cycle on."""

    def __init__(self, keys, loop=False, steps=(), planted=True, shiver=None):
        self.keys = keys
        self.loop = loop
        self.steps = list(steps)
        # Whether the legs reach for the paws (legs.plant), or the clip turns them itself.
        self.planted = planted
        if shiver is not None and loop:
            raise ValueError("a shiver doesn't meet itself at a loop's seam")
        self.shiver = shiver


# The legs' phases in a cycle, as ("front"|"hind", "L"|"R"): 0..1. A walk is four beats, each
# foot down alone in turn (hind, fore on the same side, then the other side); a trot moves the
# diagonal pairs together; a gallop lands the fore pair just apart, then the hind pair.
WALK = {("hind", "L"): 0.0, ("front", "L"): 0.25, ("hind", "R"): 0.5, ("front", "R"): 0.75}
TROT = {("front", "L"): 0.0, ("hind", "R"): 0.0, ("front", "R"): 0.5, ("hind", "L"): 0.5}
GALLOP = {("front", "L"): 0.0, ("front", "R"): 0.1, ("hind", "L"): 0.5, ("hind", "R"): 0.6}


# How long a planted paw only rises off the ground or comes down onto it at each end of its
# swing, as a share of how long it stands, running back with the ground all the while, so it
# can't slide however low it is.
MATCHED = 0.12
def _step(u, duty, sweep, matched):
    """Where a paw is along the ground (metres ahead of under its hip) at `u` (0..1) of its own
    cycle, and how far it's raised (0..1). On the ground (the first `duty` of the cycle) it runs
    back at the body's speed, so it doesn't slide; then it rises, swings forward and comes down,
    joining the ground's run at both ends with no jolt (legs.ease, legs.bump)."""
    if u < duty:
        return sweep * (0.5 - u / duty), 0.0
    s = (u - duty) / (1.0 - duty)
    # Where the ground under it would have taken it by now (metres per whole swing), and the
    # swing forward on top of that.
    ground = -sweep * (1.0 - duty) / duty
    ahead = -sweep / 2 + ground * s + (sweep - ground) * legs.ease((s - matched) / (1.0 - 2.0 * matched))
    # It peaks a little early.
    return ahead, legs.bump(s + 0.25 * s * (1.0 - s))


def _leg(points):
    """A leg's reach from its top joint to its paw's tip, and how far it leans forward at rest
    (radians from straight down; the model faces -Y)."""
    top, tip = points[0], points[-1]
    return math.dist(top, tip), math.atan2(top[1] - tip[1], top[2] - tip[2])


def _sink(reach, lean, slant, bob):
    """How far a planted leg slanted `slant` from straight down lets the body sink, `bob` of the
    way (below its height at rest; less than nothing raises it)."""
    return bob * reach * (math.cos(lean) - math.cos(slant))


def gait(frames, stride, body, phases, duty, fold, lift=0.0, curl=0.0, bob=0.4, roll=0.0, spine_flex=0.0,
         planted=True):
    """A looping gait, posed on every frame: each paw is planted for `duty` of the cycle, running
    back `stride` x `duty` at the body's speed (`stride`: metres the body moves in one cycle, at
    `body`'s unscaled size, the quadruped.Proportions), then lifts (`lift` of its leg's reach at
    the top, its toes tipped down by `curl` radians, a foreleg's twice a hind leg's, a foreleg's
    forearm folded back `fold` radians) and swings forward, at its phase. The legs reach for
    their paws (legs.plant). The hips and the shoulders sink as their planted legs lean (`bob` of
    the way a straight leg would let them), the legs halfway through their step counting most
    (so they bob out of phase and the body pitches), the hips and the chest roll (`roll`,
    radians) toward the leg that bears the weight, and the head counters the bob.

    Not `planted`, the legs swing from their tops as a whole instead, their joints folding by
    `fold` radians at the top of the swing, and the paws slide a little as the legs lean: at a
    run's speed, legs that reach for planted paws turn their joints too sharply from one frame to
    the next (#1073)."""
    reaches = {"front": _leg(body.front_leg), "hind": _leg(body.hind_leg)}
    length = abs(body.hips[1] - body.front_leg[0][1])
    neck = math.dist(body.chest, body.nose)
    sweep = stride * duty
    edge = sweep / 2
    poses = []
    for step in range(frames + 1):
        t = step / frames
        pose, swings, drops = {}, {}, {"front": [0.0, 0.0], "hind": [0.0, 0.0]}
        for (leg, side), phase in phases.items():
            u = (t - phase) % 1.0
            # Free legs needn't run with the ground as they rise and come down.
            ahead, up = _step(u, duty, sweep, MATCHED * duty / (1.0 - duty) if planted else 0.0)
            reach, lean = reaches[leg]
            slant = math.asin(max(-1.0, min(1.0, ahead / reach)))
            swings[leg, side] = (lean - slant, up)
            if planted:
                paw = ("front_paw." if leg == "front" else "hind_paw.") + side
                pose["plant." + paw] = (0.0, lift * reach * up, ahead)
                pose[paw] = ((curl if leg == "front" else curl / 2) * up, 0.0, 0.0)
                if leg == "front":
                    # The forearm folds back as the paw swings, so it clears the ground.
                    pose["forearm." + side] = (fold * up, 0.0, 0.0)
            if u < duty:
                # How much this leg holds the body up: none as it lands and lifts, most halfway.
                weight = math.sin(math.pi * u / duty)
                drops[leg][0] += weight * _sink(reach, lean, slant, bob)
                drops[leg][1] += weight
        # What the planted legs don't hold, the legs at the ends of their sweep do (as a paw
        # lands or lifts), so the body moves on smoothly as they take turns.
        hind, front = (
            (total + max(0.0, 1.0 - weight) * _sink(reaches[leg][0], reaches[leg][1],
                                                    math.asin(edge / reaches[leg][0]), bob))
            / max(1.0, weight)
            for leg, (total, weight) in (("hind", drops["hind"]), ("front", drops["front"])))
        pitch = (front - hind) / length
        hips_roll = -roll * math.cos(2 * math.pi * (t - phases["hind", "L"] - duty / 2))
        chest_roll = -roll * math.cos(2 * math.pi * (t - phases["front", "L"] - duty / 2))
        flex = spine_flex * math.sin(2 * math.pi * t)
        pose.update({"root_loc": (0.0, -hind, 0.0), "hips": (pitch, hips_roll, 0.0), "spine_01": (flex, 0.0, 0.0),
                     "spine_02": (0.0, chest_roll - hips_roll, 0.0)})
        if not planted:
            for (leg, side), (angle, up) in swings.items():
                # The legs hang from the pitched and rolled body: they turn back by as much.
                if leg == "front":
                    pose["upper_arm." + side] = (angle - pitch - flex, 0.0, chest_roll)
                    # A foreleg folds more than a hind one to clear the ground: it hangs straighter.
                    pose["forearm." + side] = (-1.5 * fold * up, 0.0, 0.0)
                    pose["front_paw." + side] = (0.8 * fold * up, 0.0, 0.0)
                else:
                    pose["thigh." + side] = (angle - pitch, 0.0, hips_roll)
                    pose["shin." + side] = (fold * up, 0.0, 0.0)
                    pose["hock." + side] = (-0.9 * fold * up, 0.0, 0.0)
        # The neck lifts the head against most of the shoulders' bob, and the head stays level.
        lifted = -0.6 * front / neck - pitch - flex
        pose["neck"] = (lifted, 0.0, 0.0)
        pose["head"] = (-(pitch + flex + lifted), 0.0, 0.0)
        pose["tail_01"] = (0.15, 0.0, 0.18 * math.sin(2 * math.pi * (t - phases["hind", "L"])))
        poses.append((step + 1, pose))
    return Clip(poses, loop=True, planted=planted)


def _both(pose, bone, rotation):
    pose[bone + ".L"] = rotation
    pose[bone + ".R"] = rotation
    return pose


# How an ear twitches in Idle (#1196): (ear, at which share of the loop it starts, its turn at the
# peak (back, 0, sideways) in radians, frames to flick out, frames to come back). Fast out (an ease
# that gathers speed at once and slows into the peak), slow back; never both ears at once, and
# never alike: the right ear flicks twice in a row.
TWITCHES = [
    ("ear.L", 0.14, (0.10, 0.0, -0.32), 4, 16),
    ("ear.R", 0.47, (0.22, 0.0, 0.18), 3, 12),
    ("ear.R", 0.55, (0.16, 0.0, 0.24), 3, 14),
    ("ear.L", 0.80, (0.30, 0.0, -0.12), 5, 18),
]


def _twitch(frame, start, amplitude, out, back):
    """An ear's turn on `frame` (from 0) for a twitch from `start`: quick to its peak, slow back."""
    since = frame - start
    if since <= 0 or since >= out + back:
        return (0.0, 0.0, 0.0)
    share = motion.EASES["quart"](since / out) if since < out else 1.0 - legs.ease((since - out) / back)
    return tuple(share * value for value in amplitude)


def _flat_wave(x):
    """A wave that lingers at each crest: sin with the third harmonic that flattens its tops
    without a dip (its slope is 4/3 cos^3 x), -1..1, so a weight shift holds on each side and
    moves between them."""
    return (math.sin(x) + math.sin(3.0 * x) / 9.0) / (1.0 - 1.0 / 9.0)


def idle(breath=105, breaths=2):
    """Standing still and alive (#1196), posed on every frame (sparse keys on a wave would flatten
    each crest into a hold): it breathes, `breaths` breaths of `breath` frames a loop, the
    ribcage rising quicker than it falls; it shifts its weight from its left legs to its right
    ones and back once a loop, the paws planted (legs.plant), its head glancing about and its
    tail swaying; and its ears twitch one at a time (TWITCHES). Every wave runs a whole number of
    times a loop and every twitch is over before it ends, so the seam is exact."""
    frames = breath * breaths
    for ear, start, _amplitude, out, back in TWITCHES:
        if round(start * frames) + out + back > frames:
            raise ValueError("%s's twitch at %.2f runs past a loop of %d frames" % (ear, start, frames))
    poses = []
    for step in range(frames + 1):
        # The last frame is the first one again, exactly.
        t = (step % frames) / frames
        lap = 2.0 * math.pi * t
        # The ribcage's rise, 0..1-ish: a breath in is quicker than the breath out.
        chest = 0.5 - 0.5 * math.cos(breaths * lap) + 0.15 * math.sin(breaths * lap) * (1.0 - math.cos(breaths * lap))
        # Toward the left legs (+1) or the right (-1); lingering on each side.
        weight = _flat_wave(lap)
        glance = math.sin(lap + 1.0)
        pose = {
            "root_loc": (0.03 * weight, -0.012 + 0.008 * chest, 0.0),
            # The body rolls a little toward the legs that bear it, the chest a touch more.
            "hips": (0.0, -0.035 * weight, 0.0),
            "spine_02": (0.035 * chest, -0.015 * weight, 0.0),
            "neck": (-0.04 * chest, 0.0, -0.05 * weight),
            "head": (0.03 * chest + 0.03 * math.sin(2.0 * lap), 0.0, 0.12 * glance + 0.04 * weight),
            "jaw": (0.05 + 0.04 * chest, 0.0, 0.0),
            "tail_01": (0.1, 0.0, 0.12 * math.sin(2.0 * lap) - 0.08 * weight),
            "tail_02": (0.0, 0.0, 0.12 * math.sin(2.0 * lap - 0.8)),
            "tail_03": (0.0, 0.0, 0.1 * math.sin(2.0 * lap - 1.6)),
        }
        for ear, start, amplitude, out, back in TWITCHES:
            turn = _twitch(step % frames, round(start * frames), amplitude, out, back)
            x, y, z = pose.get(ear, (0.0, 0.0, 0.0))
            pose[ear] = (x + turn[0], y + turn[1], z + turn[2])
        poses.append((step + 1, pose))
    return Clip(poses, loop=True)


def attack():
    """Anticipation, action, overshoot and settle (#1074): it crouches back with the ears flat,
    still coiling lower as it holds, snaps forward into the lunge with the jaw wide, the body
    running on a little past it, bites (the jaw snapping shut), pulls back, sways past where it
    stands and settles there. The forepaws step out with the lunge and back after the bite, one
    just after the other; the hind paws stay planted and the hind legs push."""
    crouch = {"root_loc": (0, -0.12, -0.12), "hips": (-0.12, 0, 0), "neck": (0.25, 0, 0),
              "head": (-0.1, 0, 0), "tail_01": (-0.2, 0, 0)}
    _both(crouch, "ear", (0.4, 0, 0))
    # The held crouch keeps sinking, so the anticipation never freezes.
    coiled = dict(crouch, root_loc=(0, -0.13, -0.14), hips=(-0.13, 0, 0), neck=(0.28, 0, 0))
    lunge = {"root_loc": (0, 0.05, 0.35), "hips": (0.08, 0, 0), "neck": (-0.15, 0, 0),
             "head": (0.2, 0, 0), "jaw": (0.6, 0, 0), "tail_01": (0.3, 0, 0)}
    _both(lunge, "ear", (0.4, 0, 0))
    bite = dict(lunge, head=(0.26, 0, 0), jaw=(0.0, 0, 0))
    back = {"root_loc": (0, 0.0, 0.06), "hips": (0.02, 0, 0), "neck": (-0.04, 0, 0), "head": (0.05, 0, 0),
            "jaw": (0.06, 0, 0), "tail_01": (0.1, 0, 0)}
    _both(back, "ear", (0.15, 0, 0))
    past = {"root_loc": (0, -0.01, -0.025), "hips": (-0.025, 0, 0), "neck": (0.05, 0, 0), "head": (-0.03, 0, 0),
            "tail_01": (-0.06, 0, 0)}
    _both(past, "ear", (-0.08, 0, 0))
    steps = []
    for side, late in (("L", 0), ("R", 1)):
        steps.append(legs.Step("front_paw." + side, 7 + late, 17 + late, (0.0, 0.0, 0.42), 0.14))
        steps.append(legs.Step("front_paw." + side, 19 + late, 29 + late, (0.0, 0.0, 0.0), 0.08))
    return Clip([(1, {}), (7, crouch), (10, coiled), (16, lunge, {"*": "back", "jaw": None}),
                 (20, bite, {"jaw": "quart"}), (25, back, "quart"), (29, past), (33, {})], steps=steps)


def hit():
    """Recoil from a blow (#1074): it snaps back, head up and ears flat, the body running on a
    little further, a shiver running through its back and neck; then it rebounds past where it
    stood, the ears flicking forward and wobbling, and settles, the paws planted."""
    recoil = {"root_loc": (0, -0.04, -0.14), "spine_01": (0.12, 0, 0.1), "spine_02": (0.1, 0, 0.1),
              "neck": (-0.3, 0, 0.15), "head": (-0.25, 0, 0.1), "jaw": (0.35, 0, 0),
              "tail_01": (-0.4, 0, 0)}
    _both(recoil, "ear", (0.6, 0, 0))
    reeling = dict(recoil, root_loc=(0, -0.05, -0.17), spine_01=(0.14, 0, 0.12), neck=(-0.34, 0, 0.17))
    rebound = {"root_loc": (0, -0.01, 0.03), "spine_01": (-0.03, 0, -0.02), "spine_02": (-0.02, 0, -0.02),
               "neck": (0.07, 0, -0.03), "head": (0.05, 0, -0.02), "jaw": (0.05, 0, 0), "tail_01": (0.08, 0, 0)}
    # The ears are still coming up as it rebounds, and flick upright last.
    _both(rebound, "ear", (0.25, 0, 0))
    flick = {"ear.L": "elastic", "ear.R": "elastic"}
    shiver = motion.Shiver(["spine_01", "spine_02", "neck"], 4, 18, math.radians(1.5))
    return Clip([(1, {}), (4, recoil, "expo"), (8, reeling), (16, rebound), (26, {}, flick)], shiver=shiver)


# A long attack's braced stance (#1158): where each paw stands, (sideways, up, forward) from rest
# in unscaled metres, the forepaws wide and ahead, the hind paws back, so it leans into the attack.
BRACE = {"front_paw": (0.06, 0.0, 0.18), "hind_paw": (0.04, 0.0, -0.08)}
# How many frames its wind-up (ChannelStart) takes, from rest to the braced stance.
CHANNEL_START = 24


def _braced(t):
    """The braced stance at `t` (0..1) of the held loop: low and leaning in, the jaw wide and the
    ears flat, the body pushed back and the jaw working as it holds the attack, the head swaying
    once. Every wave leaves the stance at t=0 with no speed, so the wind-up's still
    end, the loop's seam and the release's start meet without a jolt."""
    def wave(waves):
        # 0 at t=0 and 1, rising and falling smoothly in between, `waves` times.
        return 0.5 - 0.5 * math.cos(2 * math.pi * waves * t)
    # Once to each side and back, leaving and returning to the middle with no speed.
    sway = math.sin(2 * math.pi * t) ** 3
    pose = {
        "root_loc": (0.0, -0.10 + 0.01 * wave(2), 0.04 - 0.015 * wave(2)),
        "hips": (-0.06, 0.0, 0.0),
        "spine_02": (0.04 + 0.02 * wave(2), 0.0, 0.0),
        "neck": (0.08 + 0.03 * wave(1), 0.0, 0.04 * sway),
        "head": (-0.06 - 0.03 * wave(1), 0.0, -0.04 * sway),
        "jaw": (0.55 + 0.06 * wave(3), 0.0, 0.0),
        # Held out stiff: a swaying tail would still trail behind its sway at the loop's start, a
        # step from the wind-up's still end (motion.follow).
        "tail_01": (0.3, 0.0, 0.0),
    }
    _both(pose, "ear", (0.5, 0.0, 0.0))
    for paw, (side, up, forward) in BRACE.items():
        pose["plant." + paw + ".L"] = (side, up, forward)
        pose["plant." + paw + ".R"] = (-side, up, forward)
    return pose


def _brace_steps(out, front, hind):
    """Each paw's step out to its BRACE spot (`out`) or back to rest, the forepaws from frame
    `front` and the hind paws from `hind`, the right one a frame after the left."""
    steps = []
    for paw, start, height in (("front_paw", front, 0.08), ("hind_paw", hind, 0.05)):
        side, up, forward = BRACE[paw] if out else (0.0, 0.0, 0.0)
        for name, sign, late in (("L", 1.0, 0), ("R", -1.0, 1)):
            steps.append(legs.Step(paw + "." + name, start + late, start + late + 8, (sign * side, up, forward),
                                   height))
    return steps


def channel(frames=60):
    """A long attack, held for as long as it lasts (#1158), as three clips the game plays in turn
    (name: Clip): ChannelStart rears back with the jaw opening and snaps into the braced stance,
    the forepaws stepping out wide and ahead and the hind paws back; Channel holds the stance, a
    loop of `frames`, for as long as the attack lasts; ChannelEnd snaps the jaw shut, recoils,
    steps back to stand and settles. The start ends and the end starts on the loop's first pose."""
    braced = _braced(0.0)
    rear = {"root_loc": (0.0, -0.06, -0.12), "hips": (-0.1, 0.0, 0.0), "neck": (-0.25, 0.0, 0.0),
            "head": (-0.2, 0.0, 0.0), "jaw": (0.25, 0.0, 0.0), "tail_01": (-0.15, 0.0, 0.0)}
    _both(rear, "ear", (0.3, 0.0, 0.0))
    # It holds the rear a moment, still drawing back (#1074), snaps into the lunge and runs on past
    # the stance, settling back into it.
    reared = dict(rear, root_loc=(0.0, -0.065, -0.135), neck=(-0.28, 0.0, 0.0))
    lunge = dict(braced, root_loc=(0.0, -0.09, 0.07), jaw=(0.65, 0.0, 0.0))
    start = Clip([(1, {}), (9, rear), (11, reared), (17, lunge, {"*": "quart", "jaw": "back"}), (CHANNEL_START, braced)],
                 steps=_brace_steps(True, 6, 3))
    held = Clip([(step + 1, _braced(step / frames)) for step in range(frames + 1)], loop=True)
    # The jaw snaps shut and the head jerks up while the body holds the stance; it rises and
    # steps back only once the snap is over, so the legs can reach their paws all along.
    snap = dict(braced, neck=(-0.1, 0.0, 0.0), head=(-0.12, 0.0, 0.0), jaw=(0.0, 0.0, 0.0))
    _both(snap, "ear", (0.6, 0.0, 0.0))
    # Standing again, it sways back a little past where it stands and settles (#1074).
    past = {"root_loc": (0.0, 0.0, -0.02), "hips": (-0.02, 0.0, 0.0), "neck": (-0.05, 0.0, 0.0),
            "head": (-0.03, 0.0, 0.0), "tail_01": (0.06, 0.0, 0.0)}
    _both(past, "ear", (-0.08, 0.0, 0.0))
    end = Clip([(1, braced), (6, snap, {"*": "quart", "jaw": "expo"}), (20, past), (28, {})],
               steps=_brace_steps(False, 7, 10))
    return {"ChannelStart": start, "Channel": held, "ChannelEnd": end}


# How far (radians) a lying foreleg's forearm turns its wrist forward beyond the leg's own swing.
FOREARM_FLAT = 0.8


def faint(body_height):
    """The legs give way (#1074): it staggers, catches itself once, then sinks onto its belly,
    `body_height` down, the hind legs folding under it where they stood and the forepaws stepping
    out in front; the head hits the ground and bounces once, the tail lying out behind (a
    hanging tail would hold the body off the ground once animate grounds the clip), and it keeps
    sinking into the ground's hold as its ears droop, rather than freezing there."""
    stagger = {"root_loc": (0, -body_height * 0.08, 0), "spine_02": (0, 0, 0.06), "neck": (0.15, 0, 0),
               "head": (0.12, 0, -0.12)}
    _both(stagger, "ear", (0.35, 0, 0))
    caught = {"root_loc": (0, -body_height * 0.04, 0), "spine_02": (0, 0, -0.03), "neck": (0.02, 0, 0),
              "head": (-0.04, 0, 0.08)}
    _both(caught, "ear", (0.25, 0, 0))
    sinking = {"root_loc": (0, -body_height * 0.45, 0), "neck": (0.2, 0, 0), "head": (0.1, 0, 0.1)}
    _both(sinking, "ear", (0.5, 0, 0))
    lying = {"root_loc": (0, -body_height * 0.9, 0), "neck": (0.45, 0, 0), "head": (0.25, 0, 0.25),
             "jaw": (0.1, 0, 0), "ear.L": (0.7, 0, 0.2), "ear.R": (0.7, 0, -0.2), "tail_01": (0.45, 0, 0.3),
             "tail_02": (0.1, 0, 0.3)}
    # The forearms lie along the ground, the elbows down on it, as a canine lies on its front.
    _both(lying, "forearm", (-FOREARM_FLAT, 0, 0))
    # The head knocks onto the ground and bounces back up a little.
    bounce = dict(lying, neck=(0.38, 0, 0), head=(0.2, 0, 0.22))
    # The held end: a little lower, the head heavier, the ears drooping, the tail tip curled in.
    still = dict(lying, root_loc=(0, -body_height * 0.92, 0), neck=(0.47, 0, 0), head=(0.27, 0, 0.27),
                 jaw=(0.12, 0, 0), tail_02=(0.1, 0, 0.36))
    still["ear.L"], still["ear.R"] = (0.8, 0, 0.25), (0.8, 0, -0.25)
    # One after the other, so it lies on its forearms rather than propped up on folded forelegs.
    steps = []
    for side, sign, late in (("L", 1.0, 0), ("R", -1.0, 2)):
        steps.append(legs.Step("front_paw." + side, 14 + late, 28 + late, (0.0, 0.0, 0.45), 0.1))
        # The hind paws splay out and back, so the knees fold beside the belly, not under it.
        steps.append(legs.Step("hind_paw." + side, 17 + late, 30 + late, (0.12 * sign, 0.0, -0.12), 0.06))
    return Clip([(1, {}), (6, stagger), (10, caught), (19, sinking), (32, lying), (35, bounce, "quart"),
                 (39, lying), (50, still)], steps=steps)


# Overlap and follow-through (motion.follow): which bones trail their parent, and how:
# (frequency in Hz, damping, response, how much the root's movement swings them). The chains
# run spine, neck, head (and its jaw and ears), and hips to the tail's tip, each looser than the
# bone before it; the legs keep their paws planted (LEGS).
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


# The quadruped's legs (legs.plant): a foreleg bends where its shoulder blade meets its upper
# arm (it stands almost straight below the shoulder, so the blade gives it its reach), its
# forearm swinging with the whole leg; a hind leg bends at the knee, its hock turning with its
# thigh.
LEGS = ([legs.Leg("scapula." + side, "upper_arm." + side, "front_paw." + side, follower="forearm." + side,
                  follows=False) for side in ("L", "R")]
        + [legs.Leg("thigh." + side, "shin." + side, "hind_paw." + side, follower="hock." + side)
           for side in ("L", "R")])


# How many times animate lifts a planted clip off the ground and plants its legs again at most.
SETTLE_ROUNDS = 3
# A lift below this (metres) is rounding, not a pose sinking into the ground.
SETTLED = 1e-4


def _key(rig, poses, scale):
    """Keys every bone's turn on every frame, and the root's shift. A "loc.<bone>" channel (a
    child of the root, its axes the root's) holds that bone at its (sideways, up, forward) shift
    from rest in the model, in unscaled metres, whatever the root does."""
    for frame, pose in poses:
        root = pose.get("root_loc", (0.0, 0.0, 0.0))
        for bone in rig.pose.bones:
            bone.rotation_euler = pose.get(bone.name, (0.0, 0.0, 0.0))
            bone.keyframe_insert("rotation_euler", frame=frame)
            if bone.parent is None:
                bone.location = tuple(scale * value for value in root)
                bone.keyframe_insert("location", frame=frame)
            elif "loc." + bone.name in pose:
                if bone.parent.parent is not None:
                    raise ValueError("loc.%s: only a child of the root is placed in the model" % bone.name)
                held = pose["loc." + bone.name]
                bone.location = tuple(scale * (value - shift) for value, shift in zip(held, root))
                bone.keyframe_insert("location", frame=frame)


def _lift(poses, lifts, scale):
    """Raises the root by each frame's lift (metres, scaled; less than nothing lowers it)."""
    for (_frame, pose), lift in zip(poses, lifts):
        x, y, z = pose.get("root_loc", (0.0, 0.0, 0.0))
        pose["root_loc"] = (x, y + lift / scale, z)


def animate(rig, clips, scale, ground_meshes=(), chains=FOLLOW, limbs=LEGS, overlays=()):
    """Keys every clip (name: Clip) as its own action and stashes it on an NLA track the glTF
    export turns into a named animation. Each clip is filled in to every frame, its `chains`
    trail their parents (motion) and its `limbs` reach for their paws (legs), so every bone moves
    on its own curve, and every bone is keyed on every frame, so each clip sets the whole pose.
    A looping clip's curves cycle (Blender's Cycles modifier), so they run on through the seam.
    `scale` is the model's (scene.apply_scale), which the root's shifts are scaled by. With
    `ground_meshes` (the bound body), every frame where they sink below the ground lifts the
    root onto it, and the legs reach down again to their planted paws. Prints how far any leg
    fell short of its planted paw per clip, and fails past legs.REACH_TOLERANCE. `overlays` are
    functions that add channels of their own to every clip once it's filled in (its name, its
    poses, every frame, and whether it loops), before the chains trail, like wisps.Wisps.drift.
    It refuses a set of `clips` without every creature clip (clip_set, #1157)."""
    lacking = clip_set.missing(clips)
    if lacking:
        raise ValueError("a creature needs every clip of lib/clip_set.py; missing: " + ", ".join(lacking))
    rig.animation_data_create()
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="POSE")
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
    shape = motion.Rig(rig)
    fps = bpy.context.scene.render.fps
    root = next(bone.name for bone in rig.pose.bones if bone.parent is None)
    # A paw's spot is where it stands at rest, raised as far as it sinks into the ground there.
    rises = {}
    if ground_meshes:
        _low, feet = ground.lowest(rig, ground_meshes, [leg.paw for leg in limbs])
        rises = {paw: max(0.0, ground.CLEARANCE - low) for paw, low in feet.items()}
    for name, clip in clips.items():
        filled = motion.fill(clip.keys, clip.loop)
        if clip.shiver is not None:
            clip.shiver(filled, fps)
        for overlay in overlays:
            overlay(name, filled, clip.loop)
        planned = legs.steps(motion.follow(shape, filled, chains, scale, fps, clip.loop), clip.steps)
        poses, short, sinks = planned, (0.0, ""), []
        if clip.planted:
            poses, short, sinks = legs.plant(shape, planned, limbs, scale, rises)
        if any(sink > 0.0 for sink in sinks):
            # Where a leg can't reach its paw unstretched, the body comes down onto it, eased.
            _lift(planned, [-sink for sink in ground.envelope(sinks, 3, clip.loop)], scale)
            poses, short, _sinks = legs.plant(shape, planned, limbs, scale, rises)
        action = bpy.data.actions.new(name)
        rig.animation_data.action = action
        _key(rig, poses, scale)
        frames = [frame for frame, _pose in poses]
        # Each round lifts the body where it sinks; a planted clip's legs then reach down to their
        # paws again, and the next round checks the new legs don't sink.
        for round_ in range(SETTLE_ROUNDS + 1 if ground_meshes else 0):
            planted = [leg.paw for leg in limbs] if clip.planted else []
            lifts = ground.settle(rig, ground_meshes, root, frames, loop=clip.loop, ignore=planted)
            if not clip.planted or max(lifts) < SETTLED:
                break
            if round_ == SETTLE_ROUNDS:
                raise RuntimeError("%s: still sinking into the ground after %d rounds" % (name, SETTLE_ROUNDS))
            _lift(planned, lifts, scale)
            poses, short, _sinks = legs.plant(shape, planned, limbs, scale, rises)
            _key(rig, poses, scale)
        if clip.loop:
            for curve in _curves(action):
                curve.modifiers.new("CYCLES")
        if clip.planted:
            print("LEGS %s: short of a paw by %.4f m at most (%s)" % (name, *short))
            if short[0] > legs.REACH_TOLERANCE:
                raise RuntimeError("%s: %s can't reach its planted paw" % (name, short[1]))
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.name = name
        rig.animation_data.action = None
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in rig.pose.bones:
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
