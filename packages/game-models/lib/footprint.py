"""The hex footprint (#1520): how far a monster reaches across its hex, seen from above, for
check_footprint.py. The game stands a wild monster at its tile's centre at scale 1 on pointy-top
hexes `SIZE` from centre to corner (HexLayout.SIZE), turned to face a neighbour, so across an
edge. The model faces -Y, so the hex's six edges face -Y, +Y and the four directions 30 degrees
either side of the X axis. A pose's **reach** is the largest projection of any vertex of the
deformed meshes onto those six edge normals, over the hex's inradius: 1.00 touches an edge, below
it stays inside.

Standing in its rest pose, a regular monster keeps 5 % padding inside its hex and a boss, enraged
or stronger one may reach 5 % past it (the owner, on #1514); during its clips each may reach 5 %
further (the owner, on #1533), and an attack may lunge 30 % past it, whatever the monster (`ATTACK`:
the owner, on #1528). `REGULAR` and `LARGE` hold the (rest, clips) limits.

A prop (a gate, an egg: anything that doesn't walk) stands on its hex like a monster and is
judged against it the same way, never let off (the owner, on #1641, after a gate twice a hex's
width slipped past through an exemption): at rest with the regular monster's padding, and in its
clips never past the hex's edge, since it neither moves on nor strikes into the tile beside it.
`PROP` holds its limits, and `limits` tells which a model gets. A pack's model is held to them as
its view shows it (#1652): `report` measures only the clips the view plays, and a figure standing
in its idle clip in place of its rest pose, a T-pose.

`fit` sizes a model to its hex before any clip exists (#1522), from its rest pose alone: the
scale the gait and every render are made at, settled first, since a later rescale redoes them."""

import math

import bpy
import numpy

from . import imported

# The game's hex, centre to corner, in metres (HexLayout.SIZE).
SIZE = 1.0
INRADIUS = SIZE * math.sqrt(3.0) / 2.0
# The six edge normals on the ground plane, the first straight ahead (-Y).
NORMALS = numpy.array([(math.cos(math.radians(a)), math.sin(math.radians(a))) for a in range(270, 630, 60)])
REGULAR = (0.95, 1.05)
LARGE = (1.05, 1.10)
PROP = (0.95, 1.00)
# The clip every monster has (lib/clip_set.py's creature set); a model without it is a prop.
WALK = "Walk"
# The clips that strike, and how far past the hex they may reach.
ATTACKS = ("Attack",)
ATTACK = 1.30
# How much further than its rest pose a model's widest clip (an attack aside) reaches, assumed
# before the clips exist: Drakkudor's lunge reached 0.923 against 0.878 at rest (#1522).
# check_footprint.py confirms the fit once they're built.
CLIP_MARGIN = 0.923 / 0.878
# The share of a limit `fit` aims at, so a rounding in the export never tips it over.
SLACK = 0.99


def limits(rig, large):
    """The (rest, clips) limits for a model with armature `rig` (None for a static one): a
    prop's when it doesn't walk (no rig, or no `WALK` clip), else a boss's when `large`, else a
    regular monster's. `PROP` is the strictest, so a monster missing its walk is held tighter,
    never let off."""
    if rig is None or not any(action.name == WALK for action in bpy.data.actions):
        return PROP
    return LARGE if large else REGULAR


def meshes(rig, objects):
    """Every mesh of the model, skinned or riding on a bone (a horn, a gem), but not the
    importer's bone display shapes. `rig` is None for a static model."""
    bones = rig.pose.bones if rig is not None else []
    shapes = {bone.custom_shape for bone in bones if bone.custom_shape is not None}
    return [obj for obj in objects if obj.type == "MESH" and obj not in shapes]


def reach(meshes):
    """The reach of the deformed `meshes` at the scene's current frame (see the module's notes)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    far = 0.0
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        coords = numpy.empty(len(mesh.vertices) * 3)
        mesh.vertices.foreach_get("co", coords)
        evaluated.to_mesh_clear()
        if not len(coords):
            continue
        world = numpy.array(evaluated.matrix_world)
        far = max(far, spread(coords.reshape(-1, 3) @ world[:3, :3].T + world[:3, 3]))
    return far


def spread(points):
    """The reach of `points`, an (n, 3) array in world space, as the hex's centre at the origin
    sees it (see the module's notes)."""
    return float((points[:, :2] @ NORMALS.T).max()) / INRADIUS


def fit(rest, limits):
    """The scale that sizes a model whose rest pose reaches `rest` to its hex: its rest pose within
    the first of `limits` (rest, clips) and its widest clip, `CLIP_MARGIN` further, within the
    second, each aimed at `SLACK` of its limit."""
    rest_limit, clip_limit = limits
    return SLACK * min(rest_limit / rest, clip_limit / (rest * CLIP_MARGIN))


def report(rig, meshes, limits, clips=None, standing=None):
    """The reach in the rig's rest pose, then for every clip, every frame: the largest reach and
    the frame it's on. The rest pose fails past the first of `limits` (rest, clips), a clip past
    the second, a monster's attack past `ATTACK`. `rig` is None for a static model, which has only
    its rest pose. `clips` names the clips to measure (every clip when None; one the model lacks
    fails), and `standing` a clip measured over all its frames in place of the rest pose, for a
    figure whose rest pose is a T-pose (#1652). Returns (lines, passed); a model without a mesh
    fails, rather than passing unseen."""
    if not meshes:
        return ["FAIL no mesh to measure"], False
    rest_limit, clip_limit = limits
    scene = bpy.context.scene
    actions = {action.name: action for action in bpy.data.actions}
    if rig is not None and standing is not None:
        if standing not in actions:
            return ["FAIL rest: the standing clip %s isn't in the model" % standing], False
        far, at = _widest(rig, actions[standing], meshes)
        rest_how = "standing in %s, frame %d, " % (standing, at)
    else:
        if rig is not None:
            rig.data.pose_position = "REST"
        scene.frame_set(scene.frame_current)
        far, rest_how = reach(meshes), ""
    passed = far <= rest_limit
    lines = ["%s rest: reach %.3f of the hex (%slimit %.2f)" % (
        "ok" if passed else "FAIL", far, rest_how, rest_limit)]
    if rig is None or rig.animation_data is None:
        return lines, passed
    for name in sorted(actions if clips is None else clips):
        if name not in actions:
            passed = False
            lines.append("FAIL %s: not in the model" % name)
            continue
        # A prop strikes nothing, so a clip it calls Attack gets no lunge past its hex.
        limit = ATTACK if name in ATTACKS and limits != PROP else clip_limit
        far, at = _widest(rig, actions[name], meshes)
        fails = far > limit
        passed = passed and not fails
        lines.append("%s %s: reach %.3f of the hex (frame %d, limit %.2f)" % (
            "FAIL" if fails else "ok", name, far, at, limit))
    return lines, passed


def _widest(rig, action, meshes):
    """The largest reach over every frame of `action` on `rig`, and the frame it's on."""
    rig.data.pose_position = "POSE"
    scene = bpy.context.scene
    start, end = imported.play(rig, action)
    far, at = 0.0, start
    for number in range(start, end + 1):
        scene.frame_set(number)
        value = reach(meshes)
        if value > far:
            far, at = value, number
    return far, at
