"""Validates the default resource pack (#1860): the game's own resources, its textures, its models
(#1864), its region files, region pieces and realms (#1861), its quests (#1888), its species
(#1903), its translation catalogues (#1902) and its tile blueprints (#1901), described by the same
manifest a player's pack will have (#1858), and looked up only through ResourcePacks. It fails when
- the manifest (game_shared.resource_packs.MANIFEST) is missing or isn't a JSON object;
- an id doesn't resolve: it isn't an id (Ids), or its file isn't tracked, isn't imported by Godot
  (a .import beside it, for the kinds Godot imports) or isn't of its kind (an image, a .glb or
  .gltf model, a Markdown region file, piece or realm, a JSONC quest, species or tile blueprint, a
  .po catalogue named after its locale);
- a resource is unreferenced: the manifest lists it but no script (outside its comments), scene,
  resource or content file of the game's names its id as a string (but for the realms, the
  quests, the species, the catalogues and the tile blueprints, which the game finds by listing the
  pack), or a file of its kind (an image or model under assets/, a region file or piece under
  regions/, a realm under realms/, a quest in the quests slice's data/, a species directly in
  slices/species/data/, a catalogue under translations/, a tile blueprint in
  slices/resource_packs/data/tiles/) is in the repository but not in the manifest;
- a quest's or species' entry isn't its own file (slices/quests/data/<id>.jsonc,
  slices/species/data/<id>.jsonc), so it's named after its file (#72);
- a tile blueprint lies outside the pack (in the core's old core/data/tiles/), or its entry isn't
  slices/resource_packs/data/tiles/<id>.jsonc, so it's named after its file (#802);
- a script, scene, resource or content file names a texture's, model's, region's, realm's, quest's,
  species', catalogue's or tile blueprint's res:// path instead of its id, so it would get around
  the resolver, and a pack could never override it (project.godot naming a catalogue for Godot to
  load gets around it too, #1902); or a script names anything by its uid://, loaded or kept for
  later (stricter than the pack needs: scripts never do; #1865, #1919), or builds a path under
  assets/, regions/, realms/, translations/, the quests', the species' or the tile blueprints'
  folder at runtime (#1865; the tools, which list the assets for the credits, may). A path may hold
  spaces (#1919).
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


# Where the default pack's quests lie (#1888): in the quests slice, which owns the kind and its
# schema (#412).
QUESTS = "slices/quests/data"
# Where the species lie (#1903): each directly in the species slice's data/, beside its schema and
# its abilities' folder, which aren't species.
SPECIES = "slices/species/data"
# Where the default pack's tile blueprints lie (#1901), and where they lay in the core before.
TILES = "slices/resource_packs/data/tiles"
OLD_TILES = "core/data/tiles"
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
    # Every quest the pack has is one the players can take, so nothing names one (#1888).
    "quests": Kind("quest", (".jsonc",), False, f"{QUESTS}/*.jsonc", listed=True),
    # Every species the packs have is in the game, so nothing names one to look it up (#1903).
    "species": Kind("species", (".jsonc",), False, f"{SPECIES}/*.jsonc", listed=True),
    # Every language's catalogue, translations/<locale>.po, registered at start, so nothing names
    # one either (#1902). The template, khovax.pot, stays beside them, where its tool writes it.
    "translations": Kind("translation", (".po",), False, "translations/*.po", listed=True),
    # Every tile kind the pack has is one the rules know, so nothing names one (#1901).
    "tiles": Kind("tile", (".jsonc",), False, f"{TILES}/*.jsonc", listed=True),
}
# The project setting through which Godot would load catalogues itself, around the pack (#1902).
PROJECT = Path("project.godot")
PROJECT_TRANSLATIONS = re.compile(r"^locale/translations=", re.MULTILINE)
# What names a resource: the scripts, scenes and resources, and the content files (#1864).
NAMING = ("*.gd", "*.tscn", "*.tres", "*.jsonc")
# The resolver's own slice reads the manifest; it never names a resource, but for the tile
# blueprints the default pack holds (#1901), which name their models like any content.
RESOLVER = "slices/resource_packs/"
STRING = re.compile(r"\"([a-z][a-z0-9_]*)\"")
# A path is a whole string: it runs from the string's quote to the same quote again, anything in
# between, so a file name with spaces or the other quote counts too (#1919), and prose outside
# a string never does.
PATH_CHAR = r"(?:(?!\1).)"
# The same, but within one folder: a species' file, never its abilities' (#1903).
NAME_CHAR = r"(?:(?!\1)[^/])"
PATH = re.compile(
    rf"([\"'])res://(?P<path>assets/{PATH_CHAR}+?\.(?:"
    + "|".join(ending[1:] for ending in IMAGES + MODELS)
    + rf")|regions/{PATH_CHAR}+|realms/{PATH_CHAR}+|{QUESTS}/{PATH_CHAR}+?\.jsonc"
    + rf"|{SPECIES}/{NAME_CHAR}+\.jsonc"
    + rf"|translations/{PATH_CHAR}+?\.po"
    + rf"|{TILES}/{PATH_CHAR}+|{OLD_TILES}(?:/{PATH_CHAR}*)?)\1"
)

# Lookups around the resolver that name no path the check above could read (#1865): a uid://
# reference, or a path built from parts at runtime (a string that starts a path under one of the
# pack's folders but isn't a whole file's). A relative path is import_rules.py's to refuse.
# Any uid:// string, not only a load()'s or preload()'s argument: a threaded load, or a uid kept
# in a constant and loaded later, gets around the resolver too (#1919).
UID_STRING = re.compile(rf"([\"'])(?P<uid>uid://{PATH_CHAR}*)\1")
# The quests' folder also holds their schema, a whole file, which names no quest; the species'
# folder also holds the abilities' folder, which isn't theirs.
PACK_STRING = re.compile(
    rf"([\"'])res://(?:(?:assets|regions|realms|translations|{QUESTS}|{TILES}|{OLD_TILES})"
    + rf"(?:/{PATH_CHAR}*)?|{SPECIES}(?:/{NAME_CHAR}*)?)\1"
)
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
    naming = [
        file
        for file in git_files(*NAMING)
        if not file.startswith(RESOLVER) or file.startswith(TILES + "/")
    ]
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
    problems += [
        (f"quest {quest_id}'s file is {paths}, not {QUESTS}/{quest_id}.jsonc", MANIFEST.as_posix())
        for quest_id, paths in entries["quests"].items()
        if paths != [f"{QUESTS}/{quest_id}.jsonc"]
    ]
    problems += [
        (f"species {species_id}'s file is {paths}, not {SPECIES}/{species_id}.jsonc", MANIFEST.as_posix())
        for species_id, paths in entries["species"].items()
        if paths != [f"{SPECIES}/{species_id}.jsonc"]
    ]
    problems += [
        (f"translation {locale}'s file is {paths}, not translations/{locale}.po", MANIFEST.as_posix())
        for locale, paths in entries["translations"].items()
        if paths != [f"translations/{locale}.po"]
    ]
    if PROJECT.is_file() and PROJECT_TRANSLATIONS.search(PROJECT.read_text(encoding="utf-8")):
        problems.append(
            ("loads translation catalogues itself: list them in the default pack (ResourcePacks)", PROJECT.as_posix())
        )
    problems += [
        (f"tile {tile_id}'s file is {paths}, not {TILES}/{tile_id}.jsonc", MANIFEST.as_posix())
        for tile_id, paths in entries["tiles"].items()
        if paths != [f"{TILES}/{tile_id}.jsonc"]
    ]
    problems += [
        (f"is a tile blueprint outside the default pack: move it to {TILES}/ and list it", file)
        for file in git_files(OLD_TILES)
    ]
    tracked = set(git_files("assets", "regions", "realms", "translations", QUESTS, SPECIES, TILES))
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
            and (name != "species" or os.path.dirname(path) == SPECIES)
        )
        problems += unresolved(kind, entries[name], tracked)
        problems += unreferenced(kind, entries[name], named, files)
    for message, file in problems:
        log.error(message, file)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
