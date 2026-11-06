"""Checks that every quest's `dominated` step can be met (#2027): the species it names has to be
able to stand wild in the instance it names. A species can, in one of the regions the instance
loads (its own, or a variant's, Blueprint.variants), when
- one of that region's pieces names it for a spot (`a wild monster, always <species>`, WildSpot):
  the arranger lays every piece of a region (RegionArranger), so every layout holds it;
- that region has a spot that rolls its species (`a wild monster, of a species rolled from …` or
  `a wild monster hiding in …`, LegendMeaning) and the species is on the blueprint's
  `wild_species`; or
- it is the first form of a rolled species' line, which a rolled spot may start as, a baby
  (WildBabies, #1697): the species it ascended from, and that one's, back to one that ascends from
  none, the lowest id where two ascend into the same (SpeciesContent.first_form).
One region is enough: a quest may ask for a monster that only a variant places (the one holding a
corruption), and a variant's region with only some pieces of its own keeps the blueprint's others
(InstanceBlueprints._piece_texts). A step without a species or an instance counts any species or
anywhere, so it can always be met. What a schema or the content flow checks (that the ids resolve,
that the files read) isn't checked again here. resource_packs_check.py runs it, on the default
pack's quests, species and regions.

    uv run --locked --package khovax-game-checks packages/game-checks/quest_reachability.py
"""

import json
import os
import re
import sys
from pathlib import Path

from game_shared import log
from game_shared.resource_packs import file_lists, read_manifest, section, strip_jsonc

BLUEPRINTS = "slices/blueprints/data"
START_PIECE = "start.md"
NAMED = "a wild monster, always "
ROLLED = "a wild monster, of a species rolled from the instance blueprint's list"
HIDING = "a wild monster hiding in "
LEGEND_LINE = re.compile(r"^- `(?P<symbol>[^`]+)`: (?P<meaning>.+)$", re.MULTILINE)
TILES = re.compile(r"^## Tiles\s*\n+```\n(?P<grid>.*?)\n```", re.MULTILINE | re.DOTALL)

Problems = list[tuple[str, str]]


def read_jsonc(path: str) -> dict:
    return json.loads(strip_jsonc(Path(path).read_text(encoding="utf-8")))


def first_forms(species: dict[str, dict]) -> dict[str, str]:
    """The first form of each species' line, by species id (SpeciesContent.first_form)."""
    ascends_from: dict[str, str] = {}
    for from_id in sorted(species):
        into = (species[from_id].get("ascension") or {}).get("into")
        if isinstance(into, str) and into not in ascends_from:
            ascends_from[into] = from_id
    forms: dict[str, str] = {}
    for species_id in species:
        form = species_id
        seen = {form}
        while form in ascends_from and ascends_from[form] not in seen:
            form = ascends_from[form]
            seen.add(form)
        forms[species_id] = form
    return forms


def spots(text: str) -> tuple[bool, set[str]]:
    """Whether the region piece `text` draws a spot that rolls its species, and the species its
    drawn spots name; a legend line no tile is drawn as places nothing."""
    tiles = TILES.search(text)
    grid = tiles.group("grid") if tiles else ""
    rolls = False
    named: set[str] = set()
    for line in LEGEND_LINE.finditer(text):
        if line.group("symbol") not in grid:
            continue
        meaning = line.group("meaning")
        if meaning == ROLLED or meaning.startswith(HIDING):
            rolls = True
        elif meaning.startswith(NAMED):
            named.add(meaning.removeprefix(NAMED).split(", ")[0])
    return rolls, named


def region_files(
    region_id: str, whole: dict[str, list[str]], pieces: dict[str, list[str]]
) -> dict[str, str]:
    """The files of the region `region_id`, each by its file name: its own file, or its pieces."""
    files = whole.get(region_id) or pieces.get(region_id) or []
    return {os.path.basename(file): file for file in files}


def regions_of(
    instance: str, blueprint: dict, whole: dict[str, list[str]], pieces: dict[str, list[str]]
) -> list[list[str]]:
    """The files of each region the instance loads: its own, then each variant's, whose folder
    without a start piece changes only the pieces it holds (InstanceBlueprints._piece_texts)."""
    own = region_files(instance, whole, pieces)
    loaded = [list(own.values())]
    for variant in blueprint.get("variants", []):
        region_id = variant.get("region", "")
        if not region_id or region_id == instance:
            continue
        files = region_files(region_id, whole, pieces)
        if region_id in pieces and instance in pieces and START_PIECE not in files:
            files = own | files
        loaded.append(list(files.values()))
    return loaded


def can_stand(files: list[str], wild_species: dict[str, int], forms: dict[str, str]) -> set[str]:
    """Every species that can stand wild in the region made of `files`."""
    rolls = False
    standing: set[str] = set()
    for file in files:
        piece_rolls, named = spots(Path(file).read_text(encoding="utf-8"))
        rolls = rolls or piece_rolls
        standing |= named
    if rolls:
        standing |= set(wild_species)
        standing |= {forms.get(species, species) for species in wild_species}
    return standing


def dominated_steps(node: object) -> list[dict]:
    """Every `dominated` step in a quest's `node`, however deep its choices lead."""
    if isinstance(node, list):
        return [step for item in node for step in dominated_steps(item)]
    if not isinstance(node, dict):
        return []
    found = [node] if node.get("condition") == "dominated" else []
    return found + [step for value in node.values() for step in dominated_steps(value)]


def line_of(path: str, species: str) -> int | None:
    """The line of the `dominated` step naming `species`, or, for a step written over several
    lines, the first line naming the species at all."""
    lines = Path(path).read_text(encoding="utf-8").split("\n")
    naming = [number for number, line in enumerate(lines, 1) if f'"species": "{species}"' in line]
    on_one = [number for number in naming if '"dominated"' in lines[number - 1]]
    return (on_one or naming or [None])[0]


def problems(manifest: dict[str, object]) -> list[tuple[str, str, int | None]]:
    """Each `dominated` step of the manifest's quests whose species can't stand wild in its
    instance: why, the quest's file and the step's line. ValueError when the manifest's sections
    don't read."""
    quests = section(manifest, "quests")
    species = {key: read_jsonc(file) for key, file in section(manifest, "species").items()}
    whole = {key: [file] for key, file in section(manifest, "regions").items()}
    pieces = file_lists(manifest, "region_pieces")
    forms = first_forms(species)
    found: list[tuple[str, str, int | None]] = []
    for quest_id, file in sorted(quests.items()):
        for step in dominated_steps(read_jsonc(file).get("steps", [])):
            wanted = step.get("species")
            instance = step.get("instance")
            if not isinstance(wanted, str) or not isinstance(instance, str):
                continue
            blueprint_file = f"{BLUEPRINTS}/{instance}.jsonc"
            if not Path(blueprint_file).is_file():
                found.append((f"quest {quest_id} asks for {instance}, which has no blueprint", file, None))
                continue
            blueprint = read_jsonc(blueprint_file)
            wild = blueprint.get("wild_species", {})
            if not any(
                wanted in can_stand(files, wild, forms)
                for files in regions_of(instance, blueprint, whole, pieces)
            ):
                found.append((
                    f"quest {quest_id} asks to dominate a {wanted} in {instance}, which never has"
                    " one: it isn't on its wild_species, no piece of its regions names it, and it"
                    " isn't the first form of a species it rolls",
                    file,
                    line_of(file, wanted),
                ))  # fmt: skip
    return found


def main() -> int:
    # The game's project folder (#1101): every path is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    found = problems(read_manifest())
    for message, file, line in found:
        log.error(message, file, line)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
