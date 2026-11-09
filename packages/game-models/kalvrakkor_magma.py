"""The Korvakkar (#1771), the Kalvrakkor's magma form: its fire side has taken over the whole hound,
lean and fox-like on black basalt cracked with magma, with nine tails of flowing magma fanned out
behind it, each tipped with an ember crystal. Its mesh, paint and body's rig come from the owner's
generated model (`sources/kalvrakkor_magma.glb`, made by import_source.py from the download, sized
to its hex as a stronger monster: see the asset's SOURCE.md). The generator's two black ovals become
our eyes (lib/marked_eyes.py).

The generator's rig holds nine tails on two chains (the owner: "only two are rigged"), so every tail
gets a chain of its own from the mesh (lib/tails.py), which moves in every clip. It names the
generator's bones to the library's quadruped scheme, adds the ears a bone each, and animates every
creature clip with the library's clips, its forelegs planted by lib/adopted.py and its hind legs
bent at the knee (`limbs`, #2026).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/kalvrakkor_magma.py -- resourcepacks/default/models/kalvrakkor_magma/kalvrakkor_magma.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes. `NAME=value`
after the output path sets one of its GAIT values (lib/tuning.py), for the gait sweep
(sweep_gait.py).

Blender is Z-up and it faces -Y (the game's +Z); its left is +X. The source is already at the
game's size, so its metres are the clips' unscaled ones (SCALE 1).
"""

import math
import os
import sys

import bmesh
import bpy
import mathutils
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import adopted, attachments, clips, frostfire, legs, marked_eyes, metrics, rigged, scene, tails, tuning  # noqa: E402
from lib.materials import palette  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "kalvrakkor_magma.glb")
FPS = 30
SCALE = 1.0

# --- Its eyes ----------------------------------------------------------------------------------
# Ours where the generator's black ovals are: a dark eyeball, a glow of the line's magma eye; the lids
# and brows take the skin's colour around the marks.
COLORS = {
    "dark": ((0.02, 0.02, 0.03, 1.0), 0.0),
    "glow": (marked_eyes.linear(frostfire.MAGMA_EYE), 1.0),
}
# The marks are black on a head of dark basalt, off the middle (marked_eyes.BEASTS).
MARKED = marked_eyes.BEASTS["resourcepacks/default/models/kalvrakkor_magma/kalvrakkor_magma.glb"]
# Faint's frames over which the lids shut (eyes.Lids): as it sinks.
FAINT_LIDS = (14, 34)

# --- The rig -----------------------------------------------------------------------------------
# The generator's bones (import_source.py named them) to the library's quadruped scheme the clips
# key. Weights first go from the bones that go to the ones that stay (MERGES): the pelvis' zigzag of
# three short bones and the generator's two tail chains (the tails get their own, TAILS) into the
# hips, the chest's stub into the chest, the skull's top into the head,
# and each paw's toe bones into the bone above them, so the paw the clips plant is the whole foot.
STALKS = ("stalk_%02d.L", "stalk_%02d.R")
MERGES = {
    **{stalk % number: "hips" for stalk in STALKS for number in range(1, 5)},
    "chain1_02": "chain1_01", "chain2_01": "hips", "chain2_02": "hips", "chain3_01": "hips", "stalk_03": "stalk_02",
    "1_leg_04": "1_leg_03", "1_paw": "1_leg_03", "2_leg_04": "2_leg_03", "2_paw": "2_leg_03",
    "3_paw": "3_leg_04", "4_paw": "4_leg_04",
}
RENAMES = {
    "chain1_01": "spine_02", "stalk_01": "neck", "stalk_02": "head",
    **{"%d_leg_%02d" % (number, index + 1): "%s.%s" % (name, side)
       for number, side, names in ((1, "L", ("upper_arm", "forearm", "front_paw")),
                                   (2, "R", ("upper_arm", "forearm", "front_paw")),
                                   (3, "L", ("thigh", "shin", "hock", "hind_paw")),
                                   (4, "R", ("thigh", "shin", "hock", "hind_paw")))
       for index, name in enumerate(names)},
}
# The legs' tops hold much of the trunk's skin: above this height (metres) the shoulders' and the
# haunches' skin goes to the chest and the hips, so a swinging leg doesn't drag the trunk thin (the
# volume check), as Fohossa's legs give theirs up. So does every leg bone's skin nearer the midline
# than BELLY (metres, from MIDDLE) above UNDERSIDE: the chest's underside between the forelegs, which
# lies below the elbows, and the belly between the hind legs, which a leg swinging would draw up
# toward the spine.
TRUNK = 0.28
BELLY, UNDERSIDE = 0.035, 0.22
# The brisket, the upper arms' skin ahead of this depth (metres along Y), goes to the chest too, so
# the neck's base keeps its depth as a foreleg steps out (as quadruped.bind_underside's `brisket`).
BRISKET = -0.215
# The generator's forelegs have a stub of an upper arm over a long stiff paw: the elbow and the wrist
# move down to these heights (metres), along the leg, and each leg's skin goes to the bone at its
# height, blended over BLEND either side of a joint, so the leg bends where a hound's does.
ELBOW, WRIST, BLEND = 0.27, 0.10, 0.02
# The generator's legs stand straight, and a straight leg's joint swings far for a small move of
# its paw and snaps straight as it reaches (the motion check's jitter, #2026; the model skill's
# Tolvakkor trap): each shoulder's joint moves forward and each elbow back (metres), so the foreleg
# stands bent at the elbow; each hip's joint moves back over the paw and each knee forward, so the
# hind leg stays bent as it reaches back. The skin stays where it is.
SHOULDER_FORWARD, ELBOW_BACK = 0.14, 0.06
HIP_BACK, KNEE_FORWARD = 0.07, 0.06
# The heel's skin below this height (metres) goes from the hock to the hind paw, so the whole sole
# is the paw's and stays where the paw is planted as the hock turns.
HEEL = 0.06
# The tip of its nose: the head bone points along the head to it, so the clips' nods turn the head
# about its own crosswise axis; it bites with it.
NOSE = (0.014, -0.547, 0.625)
# How many tails it has, each found on the mesh and given a chain of its own (lib/tails.py).
TAILS = 9
# Its ears, a bone each, the generator having none: (its base, its tip). A vertex is an ear's when
# it lies along that line, nearer it than EAR_REACH and off the head's middle by EAR_OFF.
MIDDLE = 0.014
EARS = {"L": ((0.062, -0.33, 0.675), (0.082, -0.341, 0.807)), "R": ((-0.034, -0.33, 0.675), (-0.055, -0.341, 0.807))}
EAR_REACH, EAR_OFF = 0.062, 0.022
# The skin comes off the head over this share of the ear from its base.
EAR_BLEND = 0.3

# Its eyes mirror each other (lib/metrics.py); the rest of its proportions are measured as notes
# until the owner approves its look.
REFERENCE = {}

FOLLOW = {name: value for name, value in clips.FOLLOW.items() if not name.startswith(("jaw", "tail_"))}

# The game's speeds (metres a second): a wild monster glides a tile (sqrt(3) apart) in 0.8 s, a
# companion follows at a tile every 0.3 s.
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_TILES, RUN_TILES = 0.6, 1.0
WALK_DUTY, WALK_LIFT, WALK_CURL, WALK_ROLL, WALK_BOB = 0.22, 0.18, 0.4, 0.02, 0.2
RUN_DUTY, RUN_FOLD, RUN_SPINE_FLEX, RUN_ROLL, RUN_BOB = 0.12, 0.35, 0.03, 0.0, 0.4
# Its paws stand only briefly in either gait, so a walking paw runs with the ground for longer as
# it lifts and lands (clips.gait's `matched`), and a galloping one runs on only so far past where it
# lifts and lands (`overshoot`): a leg as short as its would otherwise swing up level with its belly.
WALK_MATCHED, RUN_OVERSHOOT = 0.4, 0.16
GAIT = ("SHOULDER_FORWARD", "ELBOW_BACK", "HIP_BACK", "KNEE_FORWARD", "WALK_TILES", "WALK_DUTY", "WALK_LIFT",
        "WALK_CURL", "WALK_ROLL", "WALK_BOB", "WALK_MATCHED", "RUN_TILES", "RUN_DUTY", "RUN_FOLD", "RUN_SPINE_FLEX",
        "RUN_ROLL", "RUN_BOB", "RUN_OVERSHOOT")
OUT = tuning.arguments(globals(), GAIT)
WALK_FRAMES = clips.cycle_frames(WALK_SPEED, TILE * WALK_TILES, FPS)
RUN_FRAMES = clips.cycle_frames(RUN_SPEED, TILE * RUN_TILES, FPS)
WALK_STRIDE = WALK_SPEED * WALK_FRAMES / FPS / SCALE
RUN_STRIDE = RUN_SPEED * RUN_FRAMES / FPS / SCALE

# How far its belly lies above the ground, and how much of the wolf's reach its clips keep
# (adopted.lesser): a lean body on legs a little shorter than the wolf's.
BELLY_HEIGHT = 0.27
SHARE = 0.22
FAINT_FOREPAWS = 0.2
SLEEP_PAWS = {"front_paw": (0.0, 0.0, 0.13), "hind_paw": (0.06, 0.0, -0.06)}


def at_height(*bones, height):
    """The point at `height` on the line a leg's `bones` run along, top first, standing upright."""
    for bone in bones:
        if bone.tail.z <= height <= bone.head.z:
            return bone.head.lerp(bone.tail, (bone.head.z - height) / (bone.head.z - bone.tail.z))
    raise ValueError("no bone reaches %.3f" % height)


def foreleg_skin(skin, leg):
    """Foreleg `leg`'s skin to the bone at its height (ELBOW, WRIST), however much each held."""
    names = ["%s_leg_%02d" % (leg, number) for number in (1, 2, 3)]
    groups = [skin.vertex_groups[name] for name in names]
    indices = {group.index for group in groups}
    for vertex in skin.data.vertices:
        held = sum(element.weight for element in vertex.groups if element.group in indices)
        if held <= 0.0:
            continue
        lower = min(1.0, max(0.0, (ELBOW + BLEND - vertex.co.z) / (2.0 * BLEND)))
        paw = min(1.0, max(0.0, (WRIST + BLEND - vertex.co.z) / (2.0 * BLEND)))
        shares = (held * (1.0 - lower), held * (lower - paw), held * paw)
        for group, share in zip(groups, shares):
            group.add([vertex.index], share, "REPLACE")


def rename(rig, skin):
    rigged.merge(skin, MERGES)
    rigged.merge(skin, {"1_leg_01": "chain1_01", "2_leg_01": "chain1_01", "3_leg_01": "hips", "4_leg_01": "hips"},
                 lambda vertex: vertex.co.z > TRUNK)
    rigged.merge(skin, {"%d_leg_%02d" % (leg, number): "chain1_01" if leg < 3 else "hips"
                        for leg in (1, 2, 3, 4) for number in (1, 2, 3, 4) if leg > 2 or number < 4},
                 lambda vertex: vertex.co.z > UNDERSIDE and abs(vertex.co.x - MIDDLE) < BELLY)
    rigged.merge(skin, {"1_leg_01": "chain1_01", "2_leg_01": "chain1_01"}, lambda vertex: vertex.co.y < BRISKET)
    rigged.merge(skin, {"3_leg_03": "3_leg_04", "4_leg_03": "4_leg_04"}, lambda vertex: vertex.co.z < HEEL)
    for name in MERGES:
        if skin.vertex_groups.get(name):
            skin.vertex_groups.remove(skin.vertex_groups[name])
    for leg in ("1", "2"):
        foreleg_skin(skin, leg)
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = rig.data.edit_bones
    # Each foot's toe bones go into the bone above them, which reaches to the toe's tip.
    for keep, toes in (("1_leg_03", ("1_leg_04", "1_paw")), ("2_leg_03", ("2_leg_04", "2_paw")),
                       ("3_leg_04", ("3_paw",)), ("4_leg_04", ("4_paw",))):
        edit[keep].tail = edit[toes[-1]].tail
        for toe in toes:
            edit.remove(edit[toe])
    for leg in ("1", "2"):
        upper, fore, paw = (edit["%s_leg_%02d" % (leg, number)] for number in (1, 2, 3))
        elbow, wrist = at_height(upper, fore, paw, height=ELBOW), at_height(upper, fore, paw, height=WRIST)
        elbow += Vector((0.0, ELBOW_BACK, 0.0))
        upper.head.y -= SHOULDER_FORWARD
        upper.tail = elbow
        fore.head, fore.tail = elbow, wrist
        paw.head = wrist
    for leg in ("3", "4"):
        thigh, shin = edit["%s_leg_01" % leg], edit["%s_leg_02" % leg]
        knee = thigh.tail - Vector((0.0, KNEE_FORWARD, 0.0))
        thigh.head.y += HIP_BACK
        thigh.tail = knee
        shin.head = knee
    hips, chest, neck, head = edit["hips"], edit["chain1_01"], edit["stalk_01"], edit["stalk_02"]
    # Everything behind the middle hangs from the hips, not from a spine bone, so the spine bends
    # without moving the hind legs' tops.
    for name in ("3_leg_01", "4_leg_01"):
        edit[name].use_connect = False
        edit[name].parent = hips
    for stalk in STALKS:
        for number in (4, 3, 2, 1):
            if stalk % number in edit:
                edit.remove(edit[stalk % number])
    for name in ("chain3_01", "chain2_02", "chain2_01"):
        edit.remove(edit[name])
    chest.tail = neck.head
    for side in ("1", "2"):
        edit[side + "_leg_01"].use_connect = False
        edit[side + "_leg_01"].parent = chest
    neck.use_connect = False
    neck.parent = chest
    edit.remove(edit["chain1_02"])
    edit.remove(edit["stalk_03"])
    head.tail = Vector(NOSE)
    bpy.ops.object.mode_set(mode="OBJECT")
    rigged.rename(rig, skin, RENAMES)
    rigged.roll(rig)


def limbs(rig):
    """The legs for the clips: adopted's forelegs; each hind leg bends at its knee, its hock turning
    with its thigh (clips.LEGS' pantograph). adopted's bends it at the hock, where the generator's
    leg runs almost straight from the hip, and it can't reach back far enough for a longer stride."""
    out = [leg for leg in adopted.limbs(rig) if not leg.paw.startswith("hind_paw")]
    return out + [legs.Leg("thigh." + side, "shin." + side, "hind_paw." + side, follower="hock." + side)
                  for side in ("L", "R")]


def ears(rig, skin):
    """A bone for each ear, hung from the head, holding the skin along it."""
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for side, (base, tip) in EARS.items():
        bone = rig.data.edit_bones.new("ear." + side)
        bone.head, bone.tail = Vector(base), Vector(tip)
        bone.parent = rig.data.edit_bones["head"]
        bone.align_roll(Vector((0.0, -1.0, 0.0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    head = skin.vertex_groups["head"]
    for side, (base, tip) in EARS.items():
        group = skin.vertex_groups.new(name="ear." + side)
        start, along = Vector(base), Vector(tip) - Vector(base)
        for vertex in skin.data.vertices:
            if (vertex.co.x - MIDDLE) * (base[0] - MIDDLE) <= 0.0 or abs(vertex.co.x - MIDDLE) < EAR_OFF:
                continue
            share = (vertex.co - start).dot(along) / along.length_squared
            if share <= 0.0 or (vertex.co - start - along * share).length > EAR_REACH:
                continue
            held = min(1.0, share / EAR_BLEND)
            head.add([vertex.index], 1.0 - held, "REPLACE")
            group.add([vertex.index], held, "REPLACE")


def _at(vertex):
    """Where a vertex is: the export splits vertices along UV seams, so one place can hold several."""
    return tuple(round(value, 5) for value in vertex.co)


def close_holes(skin):
    """Closes the generator's holes in the skin (one, on the small of the back) in the colour of the
    skin beside each. A hole's ring can already hold a stray face of the generator's: that one stays."""
    mesh = bmesh.new()
    mesh.from_mesh(skin.data)
    uvs = mesh.loops.layers.uv.active
    edges_at = {}
    for edge in mesh.edges:
        edges_at.setdefault(tuple(sorted(map(_at, edge.verts))), []).append(edge)
    following, corner, beside = {}, {}, {}
    for edges in edges_at.values():
        if len(edges) == 1 and len(edges[0].link_loops) == 1:
            loop = edges[0].link_loops[0]
            # Walked against its old face's direction, so the new faces point the same way.
            following[_at(loop.link_loop_next.vert)] = _at(loop.vert)
            corner[_at(loop.link_loop_next.vert)] = loop.link_loop_next.vert
            beside[_at(loop.link_loop_next.vert)] = sum((each[uvs].uv for each in loop.face.loops), Vector((0.0, 0.0))) / 3.0
    taken = {frozenset(map(_at, face.verts)) for face in mesh.faces}
    while following:
        ring = [min(following)]
        while following[ring[-1]] != ring[0]:
            ring.append(following.pop(ring[-1]))
        following.pop(ring[-1])
        facing = mathutils.geometry.normal([corner[point].co for point in ring])
        colour = beside[ring[0]]
        # A dented ring: the first corner whose fan stays inside it.
        for root in range(len(ring)):
            order = ring[root:] + ring[:root]
            fan = [(order[0], order[index], order[index + 1]) for index in range(1, len(order) - 1)]
            if all(mathutils.geometry.normal([corner[point].co for point in each]).dot(facing) > 0.0 for each in fan):
                break
        else:
            raise ValueError("no fan fills the hole at %s" % (ring,))
        for triangle in fan:
            if frozenset(triangle) not in taken:
                face = mesh.faces.new([corner[point] for point in triangle])
                for loop in face.loops:
                    loop[uvs].uv = colour
    mesh.to_mesh(skin.data)
    mesh.free()


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    for obj in [obj for obj in bpy.context.scene.objects if obj not in (rig, skin)]:
        bpy.data.objects.remove(obj)
    rig.name, skin.name = "KalvrakkorMagmaRig", "KalvrakkorMagma"
    rigged.flatten(rig, skin)
    close_holes(skin)
    scene.select_only(skin)
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    rename(rig, skin)
    ears(rig, skin)
    fan = tails.Fan(rig, skin, TAILS)
    lids, spots = marked_eyes.replace(rig, skin, palette(COLORS), FAINT_LIDS, marked=MARKED, rim=True)
    attachments.add(rig, spots, [(NOSE, "head")])
    body = adopted.Body(rig, NOSE)
    clips.animate(rig, {
        "Idle": clips.idle(),
        "Walk": clips.gait(WALK_FRAMES, WALK_STRIDE, body, clips.WALK, duty=WALK_DUTY, fold=0.0, lift=WALK_LIFT,
                           curl=WALK_CURL, roll=WALK_ROLL, bob=WALK_BOB, matched=WALK_MATCHED),
        "Run": clips.gait(RUN_FRAMES, RUN_STRIDE, body, clips.GALLOP, duty=RUN_DUTY, fold=RUN_FOLD,
                          spine_flex=RUN_SPINE_FLEX, roll=RUN_ROLL, bob=RUN_BOB, planted=False,
                          overshoot=RUN_OVERSHOOT),
        "Attack": adopted.lesser(clips.attack(), SHARE),
        "Hit": adopted.lesser(clips.hit(), SHARE),
        "Faint": adopted.lesser(clips.faint(BELLY_HEIGHT, forepaws=FAINT_FOREPAWS), SHARE),
        **{name: adopted.lesser(clip, SHARE) for name, clip in clips.channel().items()},
        "Feed": clips.feed(forepaws=0.04),
        "Sleep": clips.sleep(clips.curled(BELLY_HEIGHT), SLEEP_PAWS),
    }, SCALE, ground_meshes=[skin], chains=FOLLOW, limbs=limbs(rig), overlays=[lids.shut, fan.move])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(OUT)
