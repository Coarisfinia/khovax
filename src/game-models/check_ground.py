"""Checks that no clip of a model sinks into the ground (model skill): every frame of every clip,
the lowest point of the deformed mesh and of each paw or foot bone, against z = 0.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_ground.py -- <model.glb> [tolerance=0.005] [--summary]

It prints a line per clip and `GROUND CHECK: PASS` or `FAIL` (and exits 1 on a fail). With
`--summary` (#1524) it prints only what sinks in which clip and how deep, one line each
(lib/summary.py)."""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import ground, summary  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
short = "--summary" in args
args = [arg for arg in args if arg != "--summary"]
tolerance = float(args[1]) if len(args) > 1 else 0.005
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0])
rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
meshes = ground.skinned(bpy.data.objects)
misses = summary.Misses()
lines, passed = ground.report(rig, meshes, tolerance, misses)
if short:
    lines = summary.lines(misses, [action.name for action in bpy.data.actions])
for line in lines:
    print("GROUND", line)
print("GROUND CHECK:", "PASS" if passed else "FAIL", "(tolerance %.3f)" % tolerance)
sys.exit(0 if passed else 1)
