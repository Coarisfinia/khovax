"""Zips the pack builder for a game release (#1871), for pack makers: build_pack.py, its template
project, the parts of game_shared it imports, its README (PACK_MAKERS.md) and godot.json, the
Godot version and checksum the game's release is built with, which build_pack.py reads instead of
setup-godot. It runs with a plain Python, no uv or workspace needed.

    uv run --locked --package khovax-game-pack-builder packages/game-pack-builder/release_zip.py <out.zip>
"""

import json
import sys
import zipfile
from pathlib import Path

import build_pack
from game_shared import log

HERE = Path(__file__).resolve().parent
SHARED = HERE.parent / "game-shared" / "game_shared"
# The folder everything unpacks into.
FOLDER = "pack-builder"
# The game_shared modules build_pack.py imports, each importing nothing but the standard library.
SHARED_MODULES = ("__init__.py", "log.py", "resource_packs.py")


def files() -> dict[str, bytes]:
    """The zip's files, by their path in it."""
    found = {
        "build_pack.py": (HERE / "build_pack.py").read_bytes(),
        "README.md": (HERE / "PACK_MAKERS.md").read_bytes(),
    }
    for path in sorted(build_pack.TEMPLATE.rglob("*")):
        if path.is_file():
            found[f"template/{path.relative_to(build_pack.TEMPLATE).as_posix()}"] = path.read_bytes()
    for module in SHARED_MODULES:
        found[f"game_shared/{module}"] = (SHARED / module).read_bytes()
    version, checksum = build_pack.pinned()
    found["godot.json"] = (json.dumps({"version": version, "sha512": checksum}, indent=2) + "\n").encode()
    return found


def main() -> int:
    if len(sys.argv) != 2:
        log.error("usage: release_zip.py <out.zip>")
        return 2
    out = Path(sys.argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in files().items():
            archive.writestr(f"{FOLDER}/{name}", data)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
