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


# Case: (how it builds the model, whether the check passes it, what it must print to say why), so
# a crash, which exits 1 too, never passes for the failure.
CASES = {
    "prop": (prop, True, "no rig or clips: nothing to check"),
    "played": (played, True, "ok Idle:"),
    "elsewhere": (elsewhere, False, "has clips but its rig has no animation data to play them on"),
}


def checked(folder, name, build):
    """Builds the model, exports it and returns check_motion.py's exit code and the lines it logged
    (game_shared.log prints to stdout; Blender's tracebacks go to stderr, so a crash's source lines
    never count as the check's verdict)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    glb = os.path.join(folder, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_animation_mode="ACTIONS")
    with open(glb + ".import", "w", encoding="utf-8") as found:
        found.write("animation/fps=30\n")
    command = [bpy.app.binary_path, "--python-exit-code", "1", "--background", "--factory-startup",
               "--python", os.path.join(HERE, "check_motion.py"), "--", glb]
    # Out of CI's annotations: the failure a case expects isn't an error of this run.
    env = {key: value for key, value in os.environ.items() if key != "GITHUB_ACTIONS"}
    run = subprocess.run(command, check=False, capture_output=True, text=True, env=env)
    print(run.stdout + run.stderr)
    return run.returncode, run.stdout.splitlines()


def main():
    passed = True
    with tempfile.TemporaryDirectory() as folder:
        for name, (build, passes, says) in CASES.items():
            code, lines = checked(folder, name, build)
            verdict = "MOTION CHECK: %s " % ("PASS" if passes else "FAIL")
            right = ((code == 0) == passes and any(line.startswith(verdict) for line in lines)
                     and any(says in line for line in lines))
            passed = passed and right
            line = "%s %s: the check %s (exit %d), it should %s, saying \"%s\"" % (
                "ok" if right else "FAIL", name, "passes" if code == 0 else "fails", code,
                "pass" if passes else "fail", says)
            if right:
                log.info("MOTION TEST " + line)
            else:
                log.error("MOTION TEST " + line)
    log.info("MOTION TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
