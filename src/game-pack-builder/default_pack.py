"""Gathers the game's default resource pack (#1860) into a pack folder build_pack.py builds (#1869):
its manifest as pack.jsonc, and every file it lists (a glTF's buffers and images too) at its path
in the pack, each with the game's import settings, so the pack imports as the game does.

    uv run --locked --package khovax-game-pack-builder src/game-pack-builder/default_pack.py <out>

Of each .import file only its importer and its settings are kept: Godot gives the pack's copies
their own uids and imported files, so a pack never claims one of the game's. The textures Godot
extracts from a model aren't copied: importing the model extracts them again.
"""

import os
import re
import shutil
import sys
from pathlib import Path

from game_shared import log
from game_shared.resource_packs import MANIFEST, PACK_FOLDER, file_lists, gltf_files, read_manifest, section

GAME = Path(__file__).resolve().parents[1] / "game"
# The default pack's own folder at the repository's root (#1978), which the game reaches through
# its link, resourcepacks/ (src/game-build/link_resource_packs.py).
PACK_ROOT = GAME.parents[1] / "resourcepacks" / "default"
SINGLE = (
    "textures", "models", "audio", "regions", "realms", "quests", "species", "tiles", "translations", "loot_tables",
    "materials", "harvest_tables",
)
LISTS = ("region_pieces",)
# The .import lines that tie the file to the game's project: its uid and imported files.
PROJECT_BOUND = re.compile(r"^(uid|path(\.[a-z0-9_]+)?|source_file|dest_files)=")


def listed(manifest: dict[str, object]) -> list[str]:
    """Every file the manifest lists, a glTF's buffers and images included, from res://."""
    files = [path for kind in SINGLE for path in section(manifest, kind).values()]
    files += [path for kind in LISTS for paths in file_lists(manifest, kind).values() for path in paths]
    for model in [path for path in files if path.endswith(".gltf")]:
        files += sorted(gltf_files(model))
    return sorted(set(files))


def import_settings(text: str) -> str:
    """A .import file's text without what ties it to the game's project (PROJECT_BOUND), and
    without its [deps], which Godot writes again."""
    kept = []
    section_name = ""
    for line in text.split("\n"):
        if line.startswith("["):
            section_name = line
        if section_name == "[deps]" or PROJECT_BOUND.match(line):
            continue
        kept.append(line)
    return "\n".join(kept)


def gather(out: Path) -> None:
    """Copies the default pack into `out`, which must not exist yet."""
    os.chdir(GAME)
    manifest = read_manifest()
    out.mkdir(parents=True)
    shutil.copyfile(MANIFEST, out / "pack.jsonc")
    for path in listed(manifest):
        source = Path(path)
        # Only the pack folder's own plain files, each to its own place in the pack.
        inside = source.resolve().is_relative_to(PACK_ROOT)
        if source.is_symlink() or not inside or not source.is_file():
            raise ValueError(f"{path} isn't a plain file in the default pack")
        target = (out / path.removeprefix(PACK_FOLDER)).resolve()
        if not target.is_relative_to(out):
            raise ValueError(f"{path} lies outside the pack")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        imported = Path(f"{path}.import")
        if imported.is_symlink():
            raise ValueError(f"{imported} isn't a plain file in the game")
        if imported.is_file():
            Path(f"{target}.import").write_text(
                import_settings(imported.read_text(encoding="utf-8")), encoding="utf-8"
            )


def main() -> int:
    if len(sys.argv) != 2:
        log.error("usage: default_pack.py <out folder>")
        return 2
    out = Path(sys.argv[1]).resolve()
    if out.exists():
        log.error(f"{out} already exists")
        return 1
    try:
        gather(out)
    except (OSError, ValueError) as problem:
        log.error(f"the default pack can't be gathered: {problem}")
        return 1
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
