"""Runs Godot with a renderer but no window anywhere (owner's rule): on a private virtual display
(Xvfb), never on the desktop. Under WSL, a window on WSLg's display becomes a Windows window that
takes focus from the owner's session, even a one-pixel one, so every Godot run that draws
(screenshots, in-game renders, a GIF's frames) goes through this. Headless runs need nothing.

    uv run --locked packages/game-offscreen/offscreen.py -- --path packages/game -s res://<script>.gd \
        -- <args>

Everything after the first `--` goes to Godot, which also gets `--display-driver x11`,
`--rendering-driver opengl3` (the Compatibility renderer, on the CPU's llvmpipe) and
`--audio-driver Dummy`, so the music stays silent, and `--fixed-fps 60`: every frame advances the
game by a sixtieth of a second however fast it draws, so a script that waits a number of frames
(the fog easing open, a camera settling) gets the same game time on any machine.

Every run gets its own throwaway `user://` folder (#1188): Godot's data folder (`XDG_DATA_HOME`)
points at a temporary folder that is deleted when Godot exits. A `-s` script reads and writes
`user://` before the game's LaunchMode applies a `--user-dir`, so without this it would write the
shared folder's `profile.json` and `world.json`, a player's or another agent's. So no
`--user-dir` is needed here, and one given lands in the throwaway folder too. Only the renderer's
shader cache is kept: the throwaway folder links the project's shared one, so shaders aren't
compiled again on every run. Two runs of one build with the same `--seed` then draw the same
pixels (#1140): nothing drawn reads the clock. One thing still runs on real time: the content the boot reads on a worker
thread (ContentFill, #816), so a walk through an exit can hold for a different number of frames.
A script that walks there calls `ContentFill.wait()` first, as the test flows do. The display
matches no screen of the owner's, so no `override.cfg` is needed. It exits with Godot's exit
code."""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

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

# The renderer's shader cache, inside the user folder (LaunchOptions.SHADER_CACHE).
SHADER_CACHE = "shader_cache"


def project_name(godot_options: list[str]) -> str | None:
    """The `config/name` of the project `--path` names (else the working folder's), which names
    its default user folder, or None when there is none."""
    folder = Path(".")
    for index, option in enumerate(godot_options):
        if option == "--path" and index + 1 < len(godot_options):
            folder = Path(godot_options[index + 1])
        elif option.startswith("--path="):
            folder = Path(option.removeprefix("--path="))
    try:
        text = (folder / "project.godot").read_text(encoding="utf-8")
    except OSError:
        return None
    found = re.search(r'^config/name="([^"]+)"', text, re.MULTILINE)
    return found.group(1) if found else None


def throwaway_data_home(godot_options: list[str], env: dict[str, str]) -> str:
    """A temporary folder for Godot's data folder (`XDG_DATA_HOME`), so `user://` is a fresh
    folder in it, holding a link to the project's shared shader cache. The caller deletes it."""
    data_home = tempfile.mkdtemp(prefix="khovax-offscreen-")
    name = project_name(godot_options)
    if name is not None:
        default_home = Path(env.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
        user_folder = Path("godot") / "app_userdata" / name
        shared_cache = default_home / user_folder / SHADER_CACHE
        shared_cache.mkdir(parents=True, exist_ok=True)
        (Path(data_home) / user_folder).mkdir(parents=True)
        (Path(data_home) / user_folder / SHADER_CACHE).symlink_to(shared_cache)
    return data_home


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
    data_home = throwaway_data_home(godot_options, env)
    env["XDG_DATA_HOME"] = data_home
    command = ["xvfb-run", "-a", "-s", f"-screen 0 {SCREEN}", "godot", *GODOT_FLAGS, *args]
    try:
        return subprocess.run(command, env=env, check=False).returncode
    finally:
        # The link goes, the shared shader cache it points at stays.
        shutil.rmtree(data_home)


if __name__ == "__main__":
    sys.exit(main())
