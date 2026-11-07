"""Tests check_motion.py's verdict on models built here that it can't measure (#2132): a prop (a
box, no rig, no clips) passes, and so does a rig with a clip it plays; a rig beside a clip that
moves something else (an empty), so the rig has nothing to play it on, fails, where it used to pass
as "no rig or clips".

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/test_motion.py

Each model is exported to a .glb with a bare .import beside it and checked in a Blender of its own,
as CI checks the game's. It prints each case and `MOTION TEST: PASS` or `FAIL` (and exits 1 on a
fail)."""

import os
import subprocess
import sys
import tempfile

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402


def box():
    """A 10 cm box standing on the ground."""
    bpy.ops.mesh.primitive_cube_add(size=0.1, location=(0.0, 0.0, 0.05))
    return bpy.context.active_object


def rig():
    """An armature of one upright bone."""
    armature = bpy.data.armatures.new("rig")
    obj = bpy.data.objects.new("rig", armature)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bone = armature.edit_bones.new("body")
    bone.head, bone.tail = (0.0, 0.0, 0.0), (0.0, 0.0, 0.1)
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def keyed(obj, path, frames):
    """Keys `obj`'s `path` (on the object, or a bone's `pose.bones["..."]` path) at each frame,
    a little further each time, into a clip named Idle."""
    obj.animation_data_create()
    obj.animation_data.action = bpy.data.actions.new("Idle")
    target = obj.path_resolve(path.rsplit(".", 1)[0]) if "." in path else obj
    name = path.rsplit(".", 1)[-1]
    for frame in frames:
        getattr(target, name)[0] = 0.001 * frame
        target.keyframe_insert(name, frame=frame)


def prop():
    box()


def played():
    obj = rig()
    keyed(obj, 'pose.bones["body"].location', (0, 10))


def elsewhere():
    rig()
    holder = bpy.data.objects.new("holder", None)
    bpy.context.scene.collection.objects.link(holder)
    keyed(holder, "location", (0, 10))


# Case: (how it builds the model, whether the check passes it).
CASES = {
    "prop": (prop, True),
    "played": (played, True),
    "elsewhere": (elsewhere, False),
}


def checked(folder, name, build):
    """Builds the model, exports it and returns check_motion.py's exit code."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    glb = os.path.join(folder, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_animation_mode="ACTIONS")
    with open(glb + ".import", "w", encoding="utf-8") as found:
        found.write("animation/fps=30\n")
    command = [bpy.app.binary_path, "--python-exit-code", "1", "--background", "--factory-startup",
               "--python", os.path.join(HERE, "check_motion.py"), "--", glb]
    return subprocess.run(command, check=False).returncode


def main():
    passed = True
    with tempfile.TemporaryDirectory() as folder:
        for name, (build, passes) in CASES.items():
            code = checked(folder, name, build)
            right = (code == 0) == passes
            passed = passed and right
            line = "%s %s: the check %s (exit %d), it should %s" % (
                "ok" if right else "FAIL", name, "passes" if code == 0 else "fails", code,
                "pass" if passes else "fail")
            if right:
                log.info("MOTION TEST " + line)
            else:
                log.error("MOTION TEST " + line)
    log.info("MOTION TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
