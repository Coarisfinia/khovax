"""Links the game's project to the resource packs' folder at the repository's root (#1978): the
default pack's files lie in resourcepacks/default/, laid out like a player's pack, outside the
project, and Godot imports and loads only what is under res://. The link,
src/game/resourcepacks, is a symlink, or on Windows a directory junction, which needs neither
admin rights nor Developer Mode. Git leaves it out (.gitignore): Windows checks a tracked symlink
out as a text file. Run it once per checkout or worktree, before Godot opens the project:

    uv run --locked src/game-build/link_resource_packs.py
"""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKS = ROOT / "resourcepacks"
LINK = ROOT / "src" / "game" / "resourcepacks"


def main() -> int:
    if len(sys.argv) != 1:
        print("usage: link_resource_packs.py", file=sys.stderr)
        return 2
    if not PACKS.is_dir():
        print(f"{PACKS} isn't a folder", file=sys.stderr)
        return 1
    if LINK.is_symlink() or LINK.is_junction():
        if LINK.resolve() == PACKS.resolve():
            return 0
        print(f"{LINK} points at {LINK.resolve()}, not {PACKS}: remove it and run this again", file=sys.stderr)
        return 1
    if LINK.exists():
        # A file there is most likely a symlink a Windows checkout wrote as text.
        print(f"{LINK} is in the way of the link: remove it and run this again", file=sys.stderr)
        return 1
    if os.name == "nt":
        subprocess.run(["cmd", "/c", "mklink", "/J", str(LINK), str(PACKS)], check=True, capture_output=True)
    else:
        # Relative, so the link holds wherever the checkout is, a worktree's copy included.
        LINK.symlink_to(os.path.relpath(PACKS, LINK.parent), target_is_directory=True)
    print(f"{LINK} -> {PACKS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
