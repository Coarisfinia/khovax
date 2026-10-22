"""Starts Blender for the model tools, on the GPU where it can (#1050).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python <script.py> -- <args>

Under WSL, Mesa's default OpenGL falls back to the CPU's software rasteriser; its d3d12 driver
reaches the real GPU, but only when asked for. Only Blender's process gets it, never the shell:
Godot's Compatibility renderer skins meshes on the GPU, and on d3d12 that breaks every skinned
mesh. Blender skins on the CPU, so its renders come out the same, only faster.
A script that raises only prints its traceback, and Blender still exits 0 (#1077), so a failed
check would look like a success: --python-exit-code makes every raise exit 1. It comes first,
because Blender reads its options in order and applies it to the --python scripts after it.
Everything else goes to Blender as given. It exits with Blender's exit code."""

import os
import shutil
import sys


def main() -> int:
    if shutil.which("blender") is None:
        print("blender.py: blender is not on the PATH", file=sys.stderr)
        return 2
    env = dict(os.environ)
    # WSL's GPU device: only there does Mesa need to be pointed at d3d12.
    if os.path.exists("/dev/dxg"):
        env["GALLIUM_DRIVER"] = "d3d12"
    command = ["blender", "--python-exit-code", "1", *sys.argv[1:]]
    os.execvpe(command[0], command, env)


if __name__ == "__main__":
    sys.exit(main())
