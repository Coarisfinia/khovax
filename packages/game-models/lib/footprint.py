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

A piece bigger than one hex (#1907, like the buildings of #1835) stands on the **edge between two
hexes**, its origin at the edge's middle, and is judged against both: its kind in
lib/world_scale.py says how many hexes it takes (`Kind.hexes`). The two hexes lie either side of
the origin along X, their shared edge along Y, so a two-hex gate's arch spans both hexes and the
player walks through it along that edge, from the hex beyond one end of the edge to the hex beyond
the other. Its reach is measured as one hex's is, with the two hexes as one outline grown about the
origin: 1.00 touches the outline, so a vertex reaching across either hex's outer edges, or into the
notches at the shared edge's ends, counts, and the same limits apply.

`fit` sizes a model to its hex before any clip exists (#1522), from its rest pose alone: the
scale the gait and every render are made at, settled first, since a later rescale redoes them."""

import math

import bpy
import numpy

from . import imported, world_scale

# The game's hex, centre to corner, in metres (HexLayout.SIZE).
SIZE = world_scale.HEX_SIZE
INRADIUS = SIZE * math.sqrt(3.0) / 2.0
# The six edge normals on the ground plane, the first straight ahead (-Y).
NORMALS = numpy.array([(math.cos(math.radians(a)), math.sin(math.radians(a))) for a in range(270, 630, 60)])
# Two hexes (#1907): centred either side of the origin along X, so they share the edge along Y
# through it; their edge normals are turned 30 degrees from one hex's, the first along +X.
TWO_NORMALS = numpy.array([(math.cos(math.radians(a)), math.sin(math.radians(a))) for a in range(0, 360, 60)])
# Per number of hexes a piece takes, (each hex's centre, the hexes' edge normals).
HEXES = {
    1: (numpy.zeros((1, 2)), NORMALS),
    2: (numpy.array([(INRADIUS, 0.0), (-INRADIUS, 0.0)]), TWO_NORMALS),
}
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


def reach(meshes, hexes=1):
    """The reach of the deformed `meshes` at the scene's current frame across `hexes` hexes (see
    the module's notes)."""
    found = points(meshes, across=hexes > 1)
    return max(0.0, spread(found, hexes)) if len(found) else 0.0


def points(meshes, across=False):
    """Every vertex of the deformed `meshes` at the scene's current frame, an (n, 3) array in world
    space. With `across`, also where each edge of the triangles the mesh is drawn as crosses the
    plane X = 0: two hexes' shared edge, whose ends their outline notches in at (#1907), so a face
    spanning a notch counts there though all its corners lie inside. Each hex is convex, so the
    vertices and these points are all a triangle can reach in it; a quad's diagonal counts too,
    since a quad that isn't flat is drawn as two triangles."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    found = [numpy.empty((0, 3))]
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        coords = numpy.empty(len(mesh.vertices) * 3)
        mesh.vertices.foreach_get("co", coords)
        if across:
            mesh.calc_loop_triangles()
            corners = numpy.empty(len(mesh.loop_triangles) * 3, dtype=numpy.int32)
            mesh.loop_triangles.foreach_get("vertices", corners)
            corners = corners.reshape(-1, 3)
            ends = numpy.concatenate([corners[:, [0, 1]], corners[:, [1, 2]], corners[:, [2, 0]]])
        evaluated.to_mesh_clear()
        world = numpy.array(evaluated.matrix_world)
        placed = coords.reshape(-1, 3) @ world[:3, :3].T + world[:3, 3]
        found.append(placed)
        if across:
            first, second = placed[ends[:, 0]], placed[ends[:, 1]]
            crosses = first[:, 0] * second[:, 0] < 0.0
            first, second = first[crosses], second[crosses]
            share = first[:, 0] / (first[:, 0] - second[:, 0])
            found.append(first + share[:, None] * (second - first))
    return numpy.concatenate(found)


def spread(points, hexes=1):
    """The reach of `points`, an (n, 3) array in world space, across `hexes` hexes (a key of
    `HEXES`) about the origin: the hex's centre, or the middle of two hexes' shared edge (see the
    module's notes)."""
    centres, normals = HEXES[hexes]
    along = points[:, :2] @ normals.T
    found = None
    for centre in centres:
        # How far each of this hex's edges lies from the origin, along its normal: a point reaches
        # an edge at the share `along / room` of the way. The shared edge passes through the origin
        # (no room), so a point on its far side, in the other hex, can't be reached in this one.
        room = INRADIUS + normals @ centre
        shut = room <= 1e-9 * SIZE
        shares = numpy.where(shut, numpy.where(along > 1e-9 * SIZE, numpy.inf, 0.0),
                             along / numpy.where(shut, 1.0, room)).max(axis=1)
        found = shares if found is None else numpy.minimum(found, shares)
    return float(found.max())


def fit(rest, limits):
    """The scale that sizes a model whose rest pose reaches `rest` to its hex: its rest pose within
    the first of `limits` (rest, clips) and its widest clip, `CLIP_MARGIN` further, within the
    second, each aimed at `SLACK` of its limit."""
    rest_limit, clip_limit = limits
    return SLACK * min(rest_limit / rest, clip_limit / (rest * CLIP_MARGIN))


def report(rig, meshes, limits, clips=None, standing=None, hexes=1):
    """The reach in the rig's rest pose, then for every clip, every frame: the largest reach and
    the frame it's on. The rest pose fails past the first of `limits` (rest, clips), a clip past
    the second, a monster's attack past `ATTACK`. `rig` is None for a static model, which has only
    its rest pose. `clips` names the clips to measure (every clip when None; one the model lacks
    fails), and `standing` a clip measured over all its frames in place of the rest pose, for a
    figure whose rest pose is a T-pose (#1652), and `hexes` how many hexes it stands on (#1907).
    Returns (lines, passed); a model without a mesh fails, rather than passing unseen."""
    if not meshes:
        return ["FAIL no mesh to measure"], False
    rest_limit, clip_limit = limits
    scene = bpy.context.scene
    actions = {action.name: action for action in bpy.data.actions}
    if rig is not None and standing is not None:
        if standing not in actions:
            return ["FAIL rest: the standing clip %s isn't in the model" % standing], False
        far, at = _widest(rig, actions[standing], meshes, hexes)
        rest_how = "standing in %s, frame %d, " % (standing, at)
    else:
        if rig is not None:
            rig.data.pose_position = "REST"
        scene.frame_set(scene.frame_current)
        far, rest_how = reach(meshes, hexes), ""
    passed = far <= rest_limit
    where = "the hex" if hexes == 1 else "its %d hexes" % hexes
    lines = ["%s rest: reach %.3f of %s (%slimit %.2f)" % (
        "ok" if passed else "FAIL", far, where, rest_how, rest_limit)]
    if rig is None or rig.animation_data is None:
        return lines, passed
    for name in sorted(actions if clips is None else clips):
        if name not in actions:
            passed = False
            lines.append("FAIL %s: not in the model" % name)
            continue
        # A prop strikes nothing, so a clip it calls Attack gets no lunge past its hex.
        limit = ATTACK if name in ATTACKS and limits != PROP else clip_limit
        far, at = _widest(rig, actions[name], meshes, hexes)
        fails = far > limit
        passed = passed and not fails
        lines.append("%s %s: reach %.3f of %s (frame %d, limit %.2f)" % (
            "FAIL" if fails else "ok", name, far, where, at, limit))
    return lines, passed


def _widest(rig, action, meshes, hexes=1):
    """The largest reach over every frame of `action` on `rig` across `hexes` hexes, and the frame
    it's on."""
    rig.data.pose_position = "POSE"
    scene = bpy.context.scene
    start, end = imported.play(rig, action)
    far, at = 0.0, start
    for number in range(start, end + 1):
        scene.frame_set(number)
        value = reach(meshes, hexes)
        if value > far:
            far, at = value, number
    return far, at
