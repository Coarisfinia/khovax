"""Validates the default resource pack (#1860): the game's own resources, its textures, its models
(#1864), its region files, region pieces and realms (#1861), described by the same manifest a player's pack
will have (#1858), and looked up only through ResourcePacks. It fails when
- the manifest (game_shared.resource_packs.MANIFEST) is missing or isn't a JSON object;
- an id doesn't resolve: it isn't an id (Ids), or its file isn't tracked, isn't imported by Godot
  (a .import beside it, for the kinds Godot imports) or isn't of its kind (an image, a .glb or
  .gltf model, a Markdown region file, piece or realm);
- a resource is unreferenced: the manifest lists it but no script (outside its comments), scene,
  resource or content file of the game's names its id as a string (but for the realms, which the
  game finds by listing the pack), or a file of its kind (an image or model under assets/, a
  region file or piece under regions/, a realm under realms/) is in the repository but not in the
  manifest;
- a script, scene, resource or content file names a texture's, model's, region's or realm's res://
  path instead of its id, so it would get around the resolver, and a pack could never override it;
  or a script names anything by its uid://, loaded or kept for later (stricter than the pack needs:
  scripts never do; #1865, #1919), or builds a path under assets/, regions/ or realms/ at runtime
  (#1865; the tools, which list the assets for the credits, may). A path may hold spaces (#1919).
An id named only in the tests (any tests/ folder, or a test_*.gd anywhere; #1865, #1919) counts as
unreferenced: they name ids to check them. The models the boot flow lists as built before what uses
them are the exception.
The images a listed model uses (a glTF's own files, or the textures Godot extracted from a model,
as unused_assets.py finds them) come with their model's entry, not through the manifest. What a schema can
check (the fields and their types) is content_schemas_check.py's, and what a pack is checked for
on load (each file exists, no path climbs out of the pack) is the content flow's.

    uv run --locked --package khovax-game-checks packages/game-checks/resource_packs_check.py
"""

import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from game_shared import log
from game_shared.gdscript_code import without_comments
from game_shared.git_files import git_files
from game_shared.resource_packs import MANIFEST, file_lists, read_manifest, section, strip_jsonc
from unused_assets import extracted_textures, gltf_files

ID = re.compile(r"[a-z][a-z0-9_]*")
IMAGES = (".svg", ".png", ".jpg", ".jpeg", ".webp")
MODELS = (".glb", ".gltf")


@dataclass(frozen=True)
class Kind:
    """A section of the manifest: what its files are called (`noun`), their endings, whether
    Godot imports them, the files of its kind in the repository (`files`, a glob), and whether an
    entry is a list of files (region pieces) rather than one."""

    noun: str
    endings: tuple[str, ...]
    imported: bool
    files: str
    lists: bool = False
    # Whether the game finds every one by listing the pack (the realms), so none needs naming.
    listed: bool = False


# Each kind of resource the manifest lists, by its section.
KINDS: dict[str, Kind] = {
    "textures": Kind("texture", IMAGES, True, "assets"),
    "models": Kind("model", MODELS, True, "assets"),
    # A region drawn whole in one file, regions/<id>.md, and one arranged from the pieces in
    # regions/<id>/ (#1861).
    "regions": Kind("region", (".md",), False, "regions/*.md"),
    "region_pieces": Kind("region", (".md",), False, "regions/*/*.md", lists=True),
    # Every realm the pack has is played, so nothing names one to look it up (#1861).
    "realms": Kind("realm", (".md",), False, "realms/*.md", listed=True),
}
# What names a resource: the scripts, scenes and resources, and the content files (#1864).
NAMING = ("*.gd", "*.tscn", "*.tres", "*.jsonc")
# The resolver's own slice reads the manifest; it never names a resource.
RESOLVER = "slices/resource_packs/"
STRING = re.compile(r"\"([a-z][a-z0-9_]*)\"")
# A path is a whole string: it runs from the string's quote to the same quote again, anything in
# between, so a file name with spaces or the other quote counts too (#1919), and prose outside
# a string never does.
PATH_CHAR = r"(?:(?!\1).)"
PATH = re.compile(
    rf"([\"'])res://(?P<path>assets/{PATH_CHAR}+?\.(?:"
    + "|".join(ending[1:] for ending in IMAGES + MODELS)
    + rf")|regions/{PATH_CHAR}+|realms/{PATH_CHAR}+)\1"
)

# Lookups around the resolver that name no path the check above could read (#1865): a uid://
# reference, or a path built from parts at runtime (a string that starts a path under one of the
# pack's folders but isn't a whole file's). A relative path is import_rules.py's to refuse.
# Any uid:// string, not only a load()'s or preload()'s argument: a threaded load, or a uid kept
# in a constant and loaded later, gets around the resolver too (#1919).
UID_STRING = re.compile(rf"([\"'])(?P<uid>uid://{PATH_CHAR}*)\1")
PACK_STRING = re.compile(rf"([\"'])res://(?:assets|regions|realms)(?:/{PATH_CHAR}*)?\1")
WHOLE_FILE = re.compile(rf"([\"'])res://{PATH_CHAR}+\.[A-Za-z0-9]+\1")
# The tools list the assets as files (the credits), never looking one up for the game.
TOOLS = "tools/"
# The tests name ids to check them, so an id only they name is unreferenced (#1865): any file in
# a tests/ folder, the top-level one or a slice's, or named test_*.gd anywhere (#1919)...
TEST_FILE = re.compile(r"(?:^|/)tests/|(?:^|/)test_[^/]*\.gd$")
# ...but for the test builds' mode, game code that only shares the name...
NOT_TESTS = frozenset({"game/test_mode.gd"})
# ...but for the models built before what uses them, which the boot flow lists to check each
# until it's used (#1476, #1634, #1635), and the clip libraries built before their body (#1935).
WAITING = Path("tests/e2e/test_boot_flow.gd")
WAITING_LISTS = re.compile(
    r"^const (?:UNWORN_MODELS|UNPLACED_PROPS|UNPLACED_MODELS|UNWORN_CLIPS)\b.*?(?=^\S|\Z)", re.MULTILINE | re.DOTALL
)

type Problems = list[tuple[str, str | None]]
# A kind's entries: each id's files (one, but for a kind of lists).
type Entries = dict[str, list[str]]


def model_images(models: list[str]) -> set[str]:
    """Every image the models the manifest lists use: a glTF's own files and the textures Godot
    extracted from a model."""
    images: set[str] = set()
    for model in models:
        images |= extracted_textures(model)
        if model.endswith(".gltf") and os.path.isfile(model):
            images |= gltf_files(model)
    return images


def code_of(file: str) -> str:
    """The file's text, a script's or content file's without its comments, so an id named only in
    a comment counts as unreferenced."""
    text = Path(file).read_text(encoding="utf-8")
    if file.endswith(".gd"):
        return without_comments(text)
    return strip_jsonc(text) if file.endswith(".jsonc") else text


def unresolved(kind: Kind, entries: Entries, tracked: set[str]) -> Problems:
    """Why each id of `kind` doesn't resolve to its files, imported where Godot imports them."""
    problems: Problems = []
    noun = kind.noun
    for resource_id, paths in entries.items():
        if not ID.fullmatch(resource_id):
            problems.append((f"{noun} id {resource_id!r} isn't lowercase words and underscores", None))
        if not paths:
            problems.append((f"{noun} {resource_id} names no files", None))
        for path in paths:
            if path not in tracked:
                problems.append((f"{noun} {resource_id}'s file {path} isn't in the repository", None))
            elif kind.imported and f"{path}.import" not in tracked:
                problems.append((f"{noun} {resource_id}'s file {path} isn't imported by Godot", path))
            if not path.endswith(kind.endings):
                problems.append(
                    (f"{noun} {resource_id}'s file {path} isn't one of {', '.join(kind.endings)}", None)
                )
    return problems


def unreferenced(kind: Kind, entries: Entries, named: set[str], files: list[str]) -> Problems:
    """The resources of `kind` nothing looks up, and its files the manifest leaves out."""
    noun = kind.noun
    problems: Problems = [
        (f"{noun} {resource_id} is in the default pack, but no script, scene, resource or "
         "content file looks it up", None)
        for resource_id in entries
        if resource_id not in named and not kind.listed
    ]  # fmt: skip
    listed = {path for paths in entries.values() for path in paths}
    problems += [
        (f"{file} is a {noun} file, but the default pack doesn't list it"
         + (" (or a model that uses it)" if kind.endings == IMAGES else ""), file)
        for file in files
        if file not in listed
    ]  # fmt: skip
    return problems


def misplaced_regions(whole: Entries, pieces: Entries) -> Problems:
    """The region files listed under another region's id: a region drawn whole is
    regions/<id>.md, and a region's pieces lie in regions/<id>/, so variants, which match pieces by
    file name (#1590), never borrow another region's."""
    problems: Problems = [
        (f"region {region_id}'s file is {paths}, not regions/{region_id}.md", MANIFEST.as_posix())
        for region_id, paths in whole.items()
        if paths != [f"regions/{region_id}.md"]
    ]  # fmt: skip
    for region_id, paths in pieces.items():
        problems += [
            (f"region {region_id}'s piece {path} isn't in regions/{region_id}/", MANIFEST.as_posix())
            for path in paths
            if not path.startswith(f"regions/{region_id}/") or path.count("/") != 2
        ]  # fmt: skip
        if len(set(paths)) != len(paths):
            problems.append((f"region {region_id} lists a piece twice", MANIFEST.as_posix()))
    return problems


def manifest_sections() -> tuple[dict[str, Entries], Problems]:
    """Each kind's entries in the manifest, and why any can't be read."""
    entries: dict[str, Entries] = {name: {} for name in KINDS}
    if not MANIFEST.is_file():
        return entries, [(f"the default resource pack has no manifest at {MANIFEST.as_posix()}", None)]
    problems: Problems = []
    try:
        manifest = read_manifest()
    except ValueError as error:
        return entries, [(f"the default pack's manifest {error}", MANIFEST.as_posix())]
    for name, kind in KINDS.items():
        try:
            if kind.lists:
                entries[name] = file_lists(manifest, name)
            else:
                entries[name] = {key: [path] for key, path in section(manifest, name).items()}
        except ValueError as error:
            problems.append((f"the default pack's manifest {error}", MANIFEST.as_posix()))
    return entries, problems


def waiting() -> set[str]:
    """The models the boot flow checks before anything uses them (WAITING)."""
    code = code_of(WAITING.as_posix()) if WAITING.is_file() else ""
    return {match for block in WAITING_LISTS.findall(code) for match in STRING.findall(block)}


def is_test(file: str) -> bool:
    """Whether the file is a test's (TEST_FILE), so the ids it names don't count as looked up."""
    return bool(TEST_FILE.search(file)) and file not in NOT_TESTS


def around_resolver(file: str, code: str) -> Problems:
    """Where the file's `code` reaches a resource around the resolver: by its path, by its
    uid://, or by a path built at runtime."""
    problems: Problems = [
        (f"names {match['path']} directly: look it up by its id (ResourcePacks)", file)
        for match in PATH.finditer(code)
    ]
    if file.endswith(".gd"):
        problems += [
            (f"names {found} by its uid://: scripts never load by uid:// (a resource by its id, ResourcePacks)", file)
            for found in (match["uid"] for match in UID_STRING.finditer(code))
        ]  # fmt: skip
    if not file.startswith(TOOLS):
        problems += [
            (f"builds a path from {found} at runtime: look it up by its id (ResourcePacks)", file)
            for found in (match[0] for match in PACK_STRING.finditer(code))
            if not WHOLE_FILE.fullmatch(found) and not PATH.search(found)
        ]  # fmt: skip
    return problems


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    problems: Problems = []
    naming = [file for file in git_files(*NAMING) if not file.startswith(RESOLVER)]
    for file in naming:
        problems += around_resolver(file, code_of(file))

    entries, read_problems = manifest_sections()
    problems += read_problems
    problems += [
        (f"region {region_id} is both drawn whole and in pieces", MANIFEST.as_posix())
        for region_id in sorted(entries["regions"].keys() & entries["region_pieces"].keys())
    ]
    problems += misplaced_regions(entries["regions"], entries["region_pieces"])
    problems += [
        (f"realm {realm_id}'s file is {paths}, not realms/{realm_id}.md", MANIFEST.as_posix())
        for realm_id, paths in entries["realms"].items()
        if paths != [f"realms/{realm_id}.md"]
    ]
    tracked = set(git_files("assets", "regions", "realms"))
    models = {path for paths in entries["models"].values() for path in paths}
    used_by_models = model_images(sorted(models & tracked))
    named = {
        match
        for file in naming
        if not is_test(file)
        for match in STRING.findall(code_of(file))
    }
    named |= waiting()
    for name, kind in KINDS.items():
        files = sorted(
            path
            for path in git_files(kind.files)
            if path.endswith(kind.endings) and path not in used_by_models
            and (kind.files != "regions/*.md" or path.count("/") == 1)
        )
        problems += unresolved(kind, entries[name], tracked)
        problems += unreferenced(kind, entries[name], named, files)
    for message, file in problems:
        log.error(message, file)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
