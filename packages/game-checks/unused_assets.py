"""Fails on assets that nothing uses (#320). A file under assets/ is used when its res:// path is
named in a script, scene, resource, content file or the project settings, or listed in the default
resource pack (#1860, its models since #1864), through which the game looks it up by its id; when
a used glTF names it as one of its buffers or images; or when it's a texture Godot's import
extracted from a used model next to it (named `<model>_<image>`, its .import carrying the
generating importer's parameters). Each pack's own notes (SOURCE.md, its license) and Godot's .import files are left
out: they come with the files they describe. Asset paths keep to letters, digits and `._/-`, so
a path is always matched whole.

    uv run --locked --package khovax-game-checks packages/game-checks/unused_assets.py
"""

import os
import re
import sys
from pathlib import Path

from game_shared import log
from game_shared.git_files import git_files
from game_shared.resource_packs import (
    MANIFEST,
    extracted_textures,
    gltf_files,
    read_manifest,
    section,
)

NOTES = re.compile(r".*\.import|.*/SOURCE\.md|.*/LICENSE[^/]*")
PLAIN = re.compile(r"[A-Za-z0-9._/-]*")
NAMED = re.compile(rb"res://(assets/[A-Za-z0-9._/-]+)")
NAMING = ("*.gd", "*.tscn", "*.tres", "*.godot", "*.cfg", "*.jsonc")


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    assets = [path for path in git_files("assets") if not NOTES.fullmatch(path)]
    odd = [path for path in assets if not PLAIN.fullmatch(path)]
    if odd:
        log.error(f"asset paths keep to letters, digits and ._/-: {', '.join(odd)}")
        return 1

    # Every asset named by its path.
    named = {
        match.decode()
        for file in git_files(*NAMING)
        for match in NAMED.findall(Path(file).read_bytes())
    }
    if MANIFEST.is_file():
        manifest = read_manifest()
        named |= set(section(manifest, "textures").values()) | set(section(manifest, "models").values())
    models = sorted(path for path in named if path.endswith((".glb", ".gltf")))
    for model in models:
        if model.endswith(".gltf") and not os.path.isfile(model):
            log.error(f"{model} is named, but there is no such file to read its files from")
            return 1
        if model.endswith(".gltf"):
            named |= gltf_files(model)
        named |= extracted_textures(model)

    unused = [path for path in assets if path not in named]
    for path in unused:
        log.error(f"{path} is in the repository but nothing uses it", path)
    return 1 if unused else 0


if __name__ == "__main__":
    sys.exit(main())
