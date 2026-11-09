"""The default resource pack's manifest (#1860), as the checks read it: the pack that describes the
game's own resources, which ResourcePacks (slices/resource_packs/meta/) resolves every lookup
through. Its file names its paths from its own folder, like a player's pack (#1978); read_manifest
gives them relative to the game's project folder, packages/game, where res:// starts.
"""

import glob
import json
import os
import re
from pathlib import Path

# The default pack's folder (#1978), reached through the game's link, and its manifest there.
PACK_FOLDER = "resourcepacks/default/"
MANIFEST = Path(f"{PACK_FOLDER}pack.jsonc")
# A JSON string (kept), a // line comment or a /* */ block comment (dropped, its line breaks kept),
# as the game's Jsonc.strip reads them.
JSONC_TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', re.DOTALL)


def strip_jsonc(text: str) -> str:
    """`text` without its comments, outside strings only, keeping every line break."""

    def kept(match: re.Match[str]) -> str:
        token = match.group(0)
        return token if token.startswith('"') else "\n" * token.count("\n")

    return JSONC_TOKEN.sub(kept, text)


def read_manifest(path: Path = MANIFEST) -> dict[str, object]:
    """The manifest at `path` as a JSON object; ValueError when it isn't one, or names a key twice
    (which JSON would silently let the last one win). The default pack's has its files named from
    the game's project folder (_from_game)."""

    def unique(pairs: list[tuple[str, object]]) -> dict[str, object]:
        keys = [key for key, _ in pairs]
        twice = sorted({key for key in keys if keys.count(key) > 1})
        if twice:
            raise ValueError(f"names {', '.join(twice)} twice")
        return dict(pairs)

    data = json.loads(strip_jsonc(path.read_text(encoding="utf-8")), object_pairs_hook=unique)
    if not isinstance(data, dict):
        raise ValueError("isn't a JSON object")
    return _from_game(data) if path.as_posix().endswith(MANIFEST.as_posix()) else data


def _from_game(manifest: dict[str, object]) -> dict[str, object]:
    """The default pack's manifest with each section's files named from the game's project folder,
    not the pack's. What isn't a file's name is left for section and file_lists to refuse."""

    def named(value: object) -> object:
        if isinstance(value, list):
            return [named(item) for item in value]
        return PACK_FOLDER + value if isinstance(value, str) else value

    return {
        key: {name: named(entry) for name, entry in value.items()} if isinstance(value, dict) else value
        for key, value in manifest.items()
    }


def section(manifest: dict[str, object], kind: str) -> dict[str, str]:
    """The manifest's resources of `kind` ("textures", "models"), each file by its id; ValueError
    when they aren't an object of texts, so no entry slips past the checks."""
    raw = manifest.get(kind)
    if not isinstance(raw, dict):
        raise ValueError(f"has no {kind} object")
    odd = sorted(key for key, value in raw.items() if not isinstance(value, str))
    if odd:
        raise ValueError(f"names no file for the {kind} {', '.join(odd)}")
    return dict(raw)


def textures(manifest: dict[str, object]) -> dict[str, str]:
    """The manifest's textures, each file by its id (section)."""
    return section(manifest, "textures")


def models(manifest: dict[str, object]) -> dict[str, str]:
    """The manifest's models (#1864), each .glb or .gltf by its id (section)."""
    return section(manifest, "models")


def file_lists(manifest: dict[str, object], kind: str) -> dict[str, list[str]]:
    """The manifest's resources of `kind` that are several files each ("region_pieces", #1861),
    each list by its id; ValueError when they aren't an object of lists of texts."""
    raw = manifest.get(kind)
    if not isinstance(raw, dict):
        raise ValueError(f"has no {kind} object")
    odd = sorted(
        key for key, value in raw.items()
        if not isinstance(value, list) or not all(isinstance(file, str) for file in value)
    )  # fmt: skip
    if odd:
        raise ValueError(f"names no list of files for the {kind} {', '.join(odd)}")
    return {key: list(value) for key, value in raw.items()}


def gltf_files(gltf: str) -> set[str]:
    """Every buffer and image the glTF points at, relative to the current folder."""
    document = json.loads(Path(gltf).read_text(encoding="utf-8"))
    uris = [
        entry["uri"]
        for entry in document.get("buffers", []) + document.get("images", [])
        if entry.get("uri")
    ]
    # Joined as text and resolved like `realpath -m`: an absolute-looking URI stays under the
    # glTF's folder, and symlinks resolve. A file through the game's link to the resource packs
    # (#1978) keeps the game's path, not the one climbing out of the project.
    folder = os.path.dirname(gltf)
    packs = os.path.realpath("resourcepacks")
    files = set()
    for uri in uris:
        if uri.startswith("data:"):
            continue
        real = os.path.realpath(f"{folder}/{uri}")
        if real.startswith(packs + os.sep):
            files.add(os.path.join("resourcepacks", os.path.relpath(real, packs)))
        else:
            files.add(os.path.relpath(real))
    return files


def extracted_textures(model: str) -> set[str]:
    """Every texture Godot's import extracted from the model: `<model>_<image>`, generated by its
    importer."""
    stem = os.path.splitext(model)[0]
    return {
        imported.removesuffix(".import")
        for imported in glob.glob(f"{glob.escape(stem)}_*.import")
        if os.path.isfile(imported)
        and any(
            line.startswith("generator_parameters=")
            for line in Path(imported).read_text(encoding="utf-8").split("\n")
        )
    }
