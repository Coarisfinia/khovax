"""Checks the credit notes of the default resource pack's assets (#2585): each lies beside its
asset in the pack, as SOURCE.md (game_shared.resource_packs.CREDIT_NOTE), and the game's Credits
tab reads them from the loaded packs (PackCredits), so nothing here is generated. It fails when
- an asset folder (resourcepacks/default/<kind>/<folder>/, for the textures, models, sounds and runes)
  has no credit note;
- a texture, model, sound or rune the manifest lists has no credit note in its folder or a folder above
  it in the pack (credit_note), so the game would credit it nowhere;
- a credit note lacks its `# ` title, or its `- **Author:**`, `- **Source:**` or `- **License:**`
  line, or leaves one empty (#70);
- an asset is under the Quaternius Asset License (QAL, #1954): the author's site, quaternius.com,
  offers its files under it since 2026-08-28, and it forbids redistributing them as assets, which
  this public repository and a shareable resource pack do. A note whose source names quaternius.com
  (not Poly Pizza's CC0 pages, quaternius-items), whose license names the QAL, or whose folder holds
  a license file with the QAL's text fails, unless it has an `- **Owner's OK:**` line naming where
  the owner allowed it.

    uv run --locked --package khovax-game-checks src/game-checks/asset_credits_check.py
"""

import os
import re
import sys
from pathlib import Path

from game_shared import log
from game_shared.resource_packs import CREDIT_NOTE, CREDITED, PACK_FOLDER, credit_note, read_manifest, section

# The lines a credit note must have, by their start; each may continue on lines indented by two
# spaces below it.
FIELDS = ("- **Author:**", "- **Source:**", "- **License:**")
SOURCE = "- **Source:**"
LICENSE = "- **License:**"
OWNERS_OK = "- **Owner's OK:**"
# The author's own license by any of its names ("Quaternius Asset License", "Quaternius's own
# licence", "Quaternius License"), in any case, or its short name QAL in capitals only.
QAL = re.compile(r"(?i:quaternius(?:'s)?\s+(?:own\s+)?(?:asset\s+)?licen[cs]e)|\bQAL\b")

type Problems = list[tuple[str, str]]


def note_lines(note: str) -> list[str]:
    """The note's lines, its line endings normalized, so a note saved on Windows reads the same."""
    return Path(note).read_text(encoding="utf-8").replace("\r", "").split("\n")


def block(lines: list[str], i: int) -> str:
    """The line at i and its continuation lines (indented by two spaces)."""
    found = [lines[i]]
    for line in lines[i + 1 :]:
        if not line.startswith("  "):
            break
        found.append(line)
    return "\n".join(found)


def field(lines: list[str], name: str) -> str:
    """The first line starting with `name` that gives it a value, with its continuation, or ""."""
    for i, line in enumerate(lines):
        if line.startswith(name) and line.removeprefix(name).strip():
            return block(lines, i)
    return ""


def every_field(lines: list[str], name: str) -> str:
    """Every line starting with `name`, each with its continuation lines."""
    return "\n".join(block(lines, i) for i, line in enumerate(lines) if line.startswith(name))


def license_files(folder: str) -> list[str]:
    """The license files (LICENSE* or LICENCE*, in any case, not Godot's .import files) in the
    folder and every folder below it."""
    return sorted(
        f"{top}/{name}"
        for top, _, names in os.walk(folder)
        for name in names
        if name.upper().startswith("LICEN") and not name.endswith(".import")
    )


def note_problems(note: str) -> Problems:
    """What the credit note `note` lacks, and why its asset may not be here under the QAL."""
    lines = note_lines(note)
    problems: Problems = []
    if not lines[0].startswith("# ") or not lines[0].removeprefix("# ").strip():
        problems.append(("starts with no `# ` title, which the Credits tab names it by", note))
    problems += [(f"has no {name} line, or leaves it empty (#70)", note) for name in FIELDS if not field(lines, name)]
    if field(lines, OWNERS_OK):
        return problems
    refused = []
    # The author's own downloads (their site, or another store) are under the QAL; only Poly
    # Pizza's CC0 pages are not.
    source = every_field(lines, SOURCE).lower()
    if "quaternius" in source and "poly.pizza" not in source:
        refused.append("its source is the author's own, whose files are under the QAL")
    if QAL.search(every_field(lines, LICENSE)):
        refused.append("its license is the Quaternius Asset License (QAL)")
    refused += [
        f"its license file {path} is the Quaternius Asset License (QAL)"
        for path in license_files(os.path.dirname(note))
        if QAL.search(Path(path).read_text(encoding="utf-8", errors="replace"))
    ]
    return problems + [
        (
            f"{reason} (#1954): it forbids redistributing the asset, so it stays out of the repository"
            " and every pack unless the owner allows it (an `- **Owner's OK:**` line naming where)",
            note,
        )
        for reason in refused
    ]


def problems(manifest: dict[str, object], root: str = PACK_FOLDER) -> Problems:
    """Every credit problem of the pack at `root` whose manifest is `manifest` (its files named
    from the same folder as `root`)."""
    found: Problems = []
    notes: set[str] = set()
    for kind in CREDITED:
        folder = f"{root}{kind}"
        if os.path.isdir(folder):
            for name in sorted(os.listdir(folder)):
                asset_folder = f"{folder}/{name}"
                if not os.path.isdir(asset_folder):
                    continue
                if os.path.isfile(f"{asset_folder}/{CREDIT_NOTE}"):
                    notes.add(f"{asset_folder}/{CREDIT_NOTE}")
                else:
                    found.append((f"has no {CREDIT_NOTE} crediting its author, source and license", asset_folder))
        for asset_id, path in sorted(section(manifest, kind).items()):
            note = credit_note(path, root)
            if note is None:
                found.append((f"{kind} {asset_id}'s file has no {CREDIT_NOTE} beside it or above it in the pack", path))
            else:
                notes.add(note)
    for note in sorted(notes):
        found += note_problems(note)
    return found


def main() -> int:
    if len(sys.argv) != 1:
        log.error("usage: asset_credits_check.py")
        return 2
    try:
        manifest = read_manifest()
    except (OSError, ValueError) as problem:
        log.error(f"the default pack's manifest can't be read: {problem}")
        return 1
    found = problems(manifest)
    for message, file in found:
        log.error(message, file)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
