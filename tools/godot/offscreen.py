"""Runs Godot with a renderer but no window anywhere (owner's rule): on a private virtual display
(Xvfb), never on the desktop. Under WSL, a window on WSLg's display becomes a Windows window that
takes focus from the owner's session, even a one-pixel one, so every Godot run that draws
(screenshots, in-game renders, a GIF's frames) goes through this. Headless runs need nothing.

    uv run --locked tools/godot/offscreen.py -- --path . -s res://<script>.gd -- <args>

Everything after the first `--` goes to Godot, which also gets `--display-driver x11`,
`--rendering-driver opengl3` (the Compatibility renderer, on the CPU's llvmpipe) and
`--audio-driver Dummy`, so the music stays silent, and `--fixed-fps 60`: every frame advances the
game by a sixtieth of a second however fast it draws, so a script that waits a number of frames
(the fog easing open, a camera settling) gets the same game time on any machine, and a render is
the same each time. The display matches no screen of the owner's, so no `override.cfg` is needed.
It exits with Godot's exit code."""

import os
import shutil
import sys

# Godot's window, inside the virtual screen: the size of the game's own viewport.
SCREEN = "1280x720x24"
# The options offscreen.py sets and a caller may not override.
FORCED = ("--display-driver", "--rendering-driver", "--audio-driver", "--fixed-fps")
GODOT_FLAGS = [
    "--display-driver", "x11",
    "--rendering-driver", "opengl3",
    "--audio-driver", "Dummy",
    "--fixed-fps", "60",
]


def main() -> int:
    args = sys.argv[1:]
    if args[:1] == ["--"]:
        args = args[1:]
    if not args:
        print(__doc__, file=sys.stderr)
        return 2
    # Godot's own options end at the next `--`; what follows is the script's. A driver given there
    # would override the forced ones, and `--display-driver wayland` would find the desktop again.
    godot_options = args[: args.index("--")] if "--" in args else args
    for option in godot_options:
        if option.split("=")[0] in FORCED:
            print(f"offscreen.py: {option} is forced here and can't be given", file=sys.stderr)
            return 2
    for tool in ("xvfb-run", "godot"):
        if shutil.which(tool) is None:
            print(f"offscreen.py: {tool} is not on the PATH", file=sys.stderr)
            return 2
    # Without these, Godot could still find the desktop's display and open its window there.
    hidden = ("DISPLAY", "WAYLAND_DISPLAY")
    env = {name: value for name, value in os.environ.items() if name not in hidden}
    command = ["xvfb-run", "-a", "-s", f"-screen 0 {SCREEN}", "godot", *GODOT_FLAGS, *args]
    os.execvpe(command[0], command, env)


if __name__ == "__main__":
    sys.exit(main())
