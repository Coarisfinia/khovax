"""Checks that the player can walk through a portal while it's open (#2157): along the walking line
through the opening, from the ground to the player's height, nothing but the portal itself stands
in the way.

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python src/game-models/check_passage.py -- <model.glb> [<model.glb> ...]

A model built by a model script whose kind (lib/world_scale.py) is `portal` stands on the edge
between two hexes, and the player walks through it along Blender's Y, through its opening at the
origin. The check casts rays along the walking line, front to back, through the player's outline
(`OUTLINE`: as wide as the player is at each height, from the ground to the top of their head),
`STEP` apart across and up it. A ray
may meet the portal (the mesh's piece holding the `portal` bone's vertices, where the player
steps in), and nothing else: a hit on any other part (the arch, a tentacle) fails. A portal is
passable only while it's open, holding its `OPEN` clip (the tentacle gate sitting on the ground,
its tentacles withdrawn: the owner, on #2321), so the check looks at every `FRAME_STEP`th frame of
that clip and its last; a portal without it fails. Its other poses (standing, in its Idle) may block
the way. Every other model passes, so CI runs it on every .glb.

It prints a line per pose and `PASSAGE CHECK: PASS` or `FAIL` (and exits 1 on a fail), through
game_shared.log (#1115): a failing line is an error on the .glb, naming where the first blocking
hit is and how many rays were blocked."""

import math
import os
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log, model_builds  # noqa: E402
from lib import ground, imported, world_scale  # noqa: E402

# The kind of model the player walks through.
PORTAL = "portal"
# The clip a portal holds while the player can walk through it.
OPEN = "Sitting"
# The bone whose vertices are the portal's (the piece holding them is the portal).
PORTAL_BONE = "portal"
# The player's outline, seen from the front: up to each height (metres), how far to each side of
# the middle the passage must be clear. Measured on the players' figure standing in its Idle as
# PlayerView shows it (lib/world_scale.py's player), each band rounded up: its feet, its arms and
# hands, its shoulders and its head, up to the player's height.
OUTLINE = ((0.6, 0.42), (1.3, 0.53), (1.4, 0.35), (1.9, 0.31), (2.1, 0.26), (world_scale.PLAYER_HEIGHT, 0.19))
# How far apart the rays stand (metres), across the outline and up it: closer than anything that
# could block the player is thin.
STEP = 0.025
# Every this many frames of each clip are looked at too.
FRAME_STEP = 6
# How far past a hit a ray goes on, to find what lies behind it.
NUDGE = 1e-4


def pieces(mesh):
    """Each vertex's piece (a root index): welded by position, joined along edges."""
    parent = list(range(len(mesh.vertices)))

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    first = {}
    for vertex in mesh.vertices:
        key = tuple(round(value, 4) for value in vertex.co)
        if key in first:
            parent[find(vertex.index)] = find(first[key])
        else:
            first[key] = vertex.index
    for edge in mesh.edges:
        one, other = find(edge.vertices[0]), find(edge.vertices[1])
        if one != other:
            parent[max(one, other)] = min(one, other)
    return [find(index) for index in range(len(mesh.vertices))]


def portal_faces(skin, mesh):
    """The indices of the faces of the portal's piece in `mesh` (skin's evaluated mesh), or None
    when no vertex is the portal bone's."""
    group = skin.vertex_groups.get(PORTAL_BONE)
    if group is None:
        return None
    own = [vertex.index for vertex in skin.data.vertices
           if any(element.group == group.index and element.weight > 0.0 for element in vertex.groups)]
    if not own:
        return None
    roots = pieces(mesh)
    portal = {roots[index] for index in own}
    return {polygon.index for polygon in mesh.polygons if roots[polygon.vertices[0]] in portal}


def blocked(tree, portal, start, direction, length):
    """The first point along the ray that isn't on the portal, or None."""
    travelled = 0.0
    origin = start.copy()
    while travelled < length:
        hit, _normal, face, distance = tree.ray_cast(origin, direction, length - travelled)
        if hit is None:
            return None
        if face not in portal:
            return hit
        travelled += distance + NUDGE
        origin = hit + direction * NUDGE
    return None


def look(skin, rig):
    """(rays blocked, rays cast, the first blocking hit) in the pose the scene is in, or None
    without a portal."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = skin.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    mesh.transform(skin.matrix_world)
    portal = portal_faces(skin, mesh)
    if portal is None:
        evaluated.to_mesh_clear()
        return None
    tree = BVHTree.FromPolygons([vertex.co.copy() for vertex in mesh.vertices],
                                [tuple(polygon.vertices) for polygon in mesh.polygons])
    front = min(vertex.co.y for vertex in mesh.vertices) - 0.1
    back = max(vertex.co.y for vertex in mesh.vertices) + 0.1
    evaluated.to_mesh_clear()
    count, cast, first = 0, 0, None
    for number in range(int(math.ceil(world_scale.PLAYER_HEIGHT / STEP)) + 1):
        z = min(0.01 + number * STEP, world_scale.PLAYER_HEIGHT)
        half = next(width for height, width in OUTLINE if z <= height)
        across = int(math.ceil(2.0 * half / STEP))
        for step in range(across + 1):
            x = -half + 2.0 * half * step / across
            cast += 1
            hit = blocked(tree, portal, Vector((x, front, z)), Vector((0.0, 1.0, 0.0)), back - front)
            if hit is not None:
                count += 1
                first = first or hit
    return count, cast, first


def check(glb):
    """The report lines for one model and whether it passed."""
    model = os.path.splitext(os.path.basename(glb))[0]
    script = model_builds.build_script(glb)
    if not os.path.exists(script) or world_scale.script_kind(script) != PORTAL:
        return ["PASSAGE %s not a portal: nothing to walk through" % model], True
    fps, _loops = imported.settings(glb)
    rig = imported.load_view(glb, fps)
    skins = ground.skinned(bpy.data.objects)
    if rig is None or len(skins) != 1:
        return ["PASSAGE %s FAIL: a portal needs one skinned mesh on a rig" % model], False
    skin = skins[0]
    action = bpy.data.actions.get(OPEN)
    if rig.animation_data is None or action is None:
        return ["PASSAGE %s FAIL: no %s clip, the pose the player walks through it in" % (model, OPEN)], False
    start, end = (int(round(value)) for value in action.frame_range)
    poses = [(OPEN, action, frame) for frame in sorted(set(range(start, end + 1, FRAME_STEP)) | {end})]
    worst = {}
    for name, action, frame in poses:
        imported.play(rig, action)
        bpy.context.scene.frame_set(frame)
        found = look(skin, rig)
        if found is None:
            return ["PASSAGE %s FAIL: no vertex is the %s bone's, so no portal to step into" % (
                model, PORTAL_BONE)], False
        count, cast, first = found
        kept = worst.get(name)
        if kept is None or count > kept[0]:
            worst[name] = (count, cast, first, frame)
    lines, passed = [], True
    for name, (count, cast, first, frame) in worst.items():
        if count:
            passed = False
            lines.append("PASSAGE %s FAIL %s: %d of %d rays through the player's outline (ground to"
                         " %.2f m) hit more than the portal%s, first at x %.2f, y %.2f,"
                         " z %.2f" % (model, name, count, cast, world_scale.PLAYER_HEIGHT,
                                      " (frame %d)" % frame,
                                      first.x, first.y, first.z))
        else:
            lines.append("PASSAGE %s ok %s: %d rays through the passage meet only the portal" % (
                model, name, cast))
    return lines, passed


def main():
    glbs = sys.argv[sys.argv.index("--") + 1:]
    passed = True
    for glb in glbs:
        lines, fine = check(glb)
        passed = passed and fine
        for line in lines:
            if " FAIL" in line:
                log.error(line, glb)
            else:
                log.info(line)
    log.info("PASSAGE CHECK: %s" % ("PASS" if passed and glbs else "FAIL"))
    sys.exit(0 if passed and glbs else 1)


main()
