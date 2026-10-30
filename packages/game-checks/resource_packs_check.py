"""Validates the default resource pack (#1860): the game's own resources, described by the same
manifest a player's pack will have (#1858), and looked up only through ResourcePacks. It fails when
- the manifest (game_shared.resource_packs.MANIFEST) is missing or isn't a JSON object;
- an id doesn't resolve: it isn't an id (Ids), or its file isn't tracked, isn't imported by Godot
  (a .import beside it) or isn't an image;
- a texture is unreferenced: the manifest lists it but no script (outside its comments), scene or
  resource of the game's names its id as a string, or an image under assets/ is in the repository but not in the manifest;
- a script, scene or resource names a texture's res:// path instead of its id, so it would get
  around the resolver, and a pack could never override it.
The images a model uses (a glTF's own files, or the textures Godot extracted from a model, as
unused_assets.py finds them) come with their model, not through the manifest. What a schema can
check (the fields and their types) is content_schemas_check.py's, and what a pack is checked for
on load (each file exists, no path climbs out of the pack) is the content flow's.

    uv run --locked --package khovax-game-checks packages/game-checks/resource_packs_check.py
"""

import os
import re
import sys
from pathlib import Path

from game_shared import log
from game_shared.gdscript_code import without_comments
from game_shared.git_files import git_files
from game_shared.resource_packs import MANIFEST, read_manifest, textures
from unused_assets import extracted_textures, gltf_files

ID = re.compile(r"[a-z][a-z0-9_]*")
IMAGES = (".svg", ".png", ".jpg", ".jpeg", ".webp")
NAMING = ("*.gd", "*.tscn", "*.tres")
# The resolver's own slice reads the manifest; it never names a texture.
RESOLVER = "slices/resource_packs/"
STRING = re.compile(r"\"([a-z][a-z0-9_]*)\"")
IMAGE_PATH = re.compile(r"res://(assets/[A-Za-z0-9._/-]+\.(?:svg|png|jpe?g|webp))")

type Problems = list[tuple[str, str | None]]


def model_images() -> set[str]:
    """Every image a model under assets/ uses: a glTF's own files and the textures Godot
    extracted from a model."""
    images: set[str] = set()
    for model in git_files("assets/*.glb", "assets/*.gltf"):
        images |= extracted_textures(model)
        if model.endswith(".gltf"):
            images |= gltf_files(model)
    return images


def code_of(file: str) -> str:
    """The file's text, a script's without its comments, so an id named only in a comment counts
    as unreferenced."""
    text = Path(file).read_text(encoding="utf-8")
    return without_comments(text) if file.endswith(".gd") else text


def unresolved(entries: dict[str, str], tracked: set[str]) -> Problems:
    """Why each texture id doesn't resolve to an imported image."""
    problems: Problems = []
    for texture_id, path in entries.items():
        if not ID.fullmatch(texture_id):
            problems.append((f"texture id {texture_id!r} isn't lowercase words and underscores", None))
        if path not in tracked:
            problems.append((f"texture {texture_id}'s file {path} isn't in the repository", None))
        elif f"{path}.import" not in tracked:
            problems.append((f"texture {texture_id}'s file {path} isn't imported by Godot", path))
        if not path.endswith(IMAGES):
            problems.append((f"texture {texture_id}'s file {path} isn't an image", None))
    return problems


def unreferenced(entries: dict[str, str], named: set[str], images: list[str]) -> Problems:
    """The textures nothing looks up, and the images the manifest leaves out."""
    problems: Problems = [
        (f"texture {texture_id} is in the default pack, but no script, scene or resource looks "
         "it up", None)
        for texture_id in entries
        if texture_id not in named
    ]  # fmt: skip
    listed = set(entries.values())
    problems += [
        (f"{image} is an image under assets/, but the default pack doesn't list it (or a model "
         "that uses it)", image)
        for image in images
        if image not in listed
    ]  # fmt: skip
    return problems


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    problems: Problems = []
    naming = [file for file in git_files(*NAMING) if not file.startswith(RESOLVER)]
    for file in naming:
        for path in IMAGE_PATH.findall(Path(file).read_text(encoding="utf-8")):
            problems.append((f"names {path} directly: look it up by its id (ResourcePacks)", file))

    entries: dict[str, str] = {}
    if not MANIFEST.is_file():
        problems.append((f"the default resource pack has no manifest at {MANIFEST.as_posix()}", None))
    else:
        try:
            entries = textures(read_manifest())
        except ValueError as error:
            problems.append((f"the default pack's manifest {error}", MANIFEST.as_posix()))

    tracked = set(git_files("assets"))
    used_by_models = model_images()
    images = sorted(
        path for path in tracked if path.endswith(IMAGES) and path not in used_by_models
    )
    named = {match for file in naming for match in STRING.findall(code_of(file))}
    problems += unresolved(entries, tracked)
    problems += unreferenced(entries, named, images)
    for message, file in problems:
        log.error(message, file)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
