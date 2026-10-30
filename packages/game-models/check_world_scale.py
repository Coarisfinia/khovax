"""Checks that every model is sized to the world's scale (#1837): a hex's size and a wall's height
against the player's height, from lib/world_scale.py, where the numbers and the kinds are.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_world_scale.py -- <model.glb> [<model.glb> ...]

- **A model built by a script here that isn't a monster** (a prop in lib/footprint.py's sense)
  names its kind in its script (`WORLD_SCALE = "wall"`), and its rest pose is measured against
  that kind: its height, and an edge piece's length along X. A script that names no kind fails.
  A monster is sized against its hex instead (check_footprint.py).
- **The players' figure** (the pack's model PlayerView shows) is measured as PlayerView shows it,
  standing in its idle clip without the parts it hides, against the player's height, so the scale
  stays true to the figure.
- **Any other pack's model a view stands on the board** (the chest) is measured as each view shows
  it, in the clip it stands in, as a prop.
- A tile's decoration is the tile's own look, and a pack's model no view shows is an item's
  picture: neither is measured, as in check_footprint.py.

It prints a line per measure and `WORLD SCALE CHECK: PASS` or `FAIL` (and exits 1 on a fail),
through game_shared.log (#1115): a failing line is an error on the .glb. A model that fails today
waits in KNOWN with the issue that fixes it, and the list only shrinks (lib/known.py)."""

import ast
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import footprint, imported, known, views, world_scale  # noqa: E402

# The Godot project, whose views show the packs' models.
GAME = os.path.join(os.path.dirname(HERE), "game")
# The view that shows the players' figure, whose height is the player's.
FIGURE_VIEW = "PlayerView"
# The constant a model script names its kind in.
KIND = "WORLD_SCALE"

# (model, measure: "height" or "length") that fails today, with the issue that fixes it; that
# issue takes its entries off.
KNOWN = {}


def script_kind(path):
    """The kind the model script at `path` names in its module-level `KIND` constant, or None."""
    with open(path, encoding="utf-8") as source:
        tree = ast.parse(source.read(), path)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                isinstance(target, ast.Name) and target.id == KIND for target in node.targets):
            return node.value.value if isinstance(node.value, ast.Constant) else None
    return None


def size(rig, meshes, standing=None):
    """The (length along X, height) of `meshes`: in the rest pose, or for a figure the most over
    every frame of its `standing` clip."""
    scene = bpy.context.scene
    if rig is None or standing is None:
        if rig is not None:
            rig.data.pose_position = "REST"
        scene.frame_set(scene.frame_current)
        return world_scale.bounds(footprint.points(meshes))
    start, end = imported.play(rig, bpy.data.actions[standing])
    longest, tallest = 0.0, 0.0
    for number in range(start, end + 1):
        scene.frame_set(number)
        length, height = world_scale.bounds(footprint.points(meshes))
        longest, tallest = max(longest, length), max(tallest, height)
    return longest, tallest


def scripted(script, glb, fps):
    """The report lines for a model the script at `script` builds; None for a monster."""
    rig = imported.load_view(glb, fps)
    if footprint.limits(rig, False) != footprint.PROP:
        return None
    kind = script_kind(script)
    if kind is None:
        return ["FAIL kind: %s names no %s kind (lib/world_scale.py's KINDS)" % (
            os.path.basename(script), KIND)]
    length, height = size(rig, footprint.meshes(rig, bpy.data.objects))
    return world_scale.judge(kind, length, height)[0]


def shown(model, glb, fps, scripts):
    """The report lines for a pack's model, each tagged with its view; None when no view shows it."""
    figure = scripts.classes.get(FIGURE_VIEW)
    if figure is None:
        raise ValueError("no script declares %s, whose figure is the player's height" % FIGURE_VIEW)
    # The figure is measured as its own view shows it; the people's views show the same figure.
    is_figure = scripts.const(figure, "MODEL") in views.model_ids(GAME, model)
    found = [scripts.view(figure)] if is_figure else views.find(GAME, model, scripts)
    if not found:
        return None
    lines = []
    for view in found:
        rig = imported.load_view(glb, fps, view.scale)
        meshes = [obj for obj in footprint.meshes(rig, bpy.data.objects) if obj.name not in view.hidden]
        standing = view.standing if rig is not None else None
        if standing is not None and standing not in bpy.data.actions:
            # Measured in its T-pose instead, a figure would pass unseen.
            lines.append("FAIL stance: the standing clip %s isn't in the model (%s)" % (standing, view.name))
            continue
        length, height = size(rig, meshes, standing)
        report = world_scale.judge_figure(height)[0] if is_figure else world_scale.judge("prop", length, height)[0]
        lines += ["%s (%s, scale %.2f)" % (line, view.name, view.scale) for line in report]
    return lines


def main():
    glbs = sys.argv[sys.argv.index("--") + 1:]
    tile_looks = views.decorations(GAME)
    scripts = views.Scripts(GAME)
    passed = True
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        if model in tile_looks:
            log.info("WORLD SCALE %s a tile's decoration: the tile's own look" % model)
            continue
        fps, _loops = imported.settings(glb)
        script = os.path.join(HERE, model + ".py")
        if os.path.exists(script):
            lines = scripted(script, glb, fps)
            if lines is None:
                log.info("WORLD SCALE %s a monster: sized against its hex (check_footprint.py)" % model)
                continue
        else:
            lines = shown(model, glb, fps, scripts)
            if lines is None:
                log.info("WORLD SCALE %s no view puts it on the board: an item's picture" % model)
                continue
        for line in lines:
            text, fails = known.judge(KNOWN, model, line)
            passed = passed and not fails
            if fails:
                log.error("WORLD SCALE %s %s" % (model, text), glb)
            else:
                log.info("WORLD SCALE %s %s" % (model, text))
    log.info("WORLD SCALE CHECK: %s" % ("PASS" if passed and glbs else "FAIL"))
    sys.exit(0 if passed and glbs else 1)


main()
