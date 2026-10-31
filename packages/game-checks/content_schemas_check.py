"""Checks the content data against its schemas (#72). Godot's data_to_json.gd strips the JSONC
comments with the game's own stripper, then jv checks each kind's files against its schema: the
core's (#506), core/data/<kind>/, against core/data/schemas/<kind>.schema.json, and a kind a slice
owns (#412), slices/<slice>/data/<kind>/, against the <kind>.schema.json beside it. A core kind a
resource pack holds (the tile blueprints, #1901) lies in the default pack's PACK_DATA/<kind>/,
checked against the core's schema, which is the format every pack's files share. The slice's own
kind sits directly in its data/, beside <slice>.schema.json, so no folder repeats the slice's name
(#442). A folder without its schema fails, so a slice's data never borrows another's schema; so
does a schema without its data, which would sit unchecked, and a kind with two schemas.

    [GODOT=<binary>] [JV=<binary>] uv run --locked --package khovax-game-checks \\
        packages/game-checks/content_schemas_check.py

GODOT defaults to `godot`, JV to `jv`.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

from game_shared import log

TARGET = Path("build/data-json")
# The default resource pack's folder, where it keeps the core kinds it holds (#1901).
PACK_DATA = Path("slices/resource_packs/data")
# A script error can leave Godot running forever.
TIMEOUT_SECONDS = 60


def schema_problems() -> tuple[dict[str, str], list[tuple[str, str | None]]]:
    """Each kind's schema by its name, and what's wrong with the schemas and their folders (each
    with the file it's about, if any)."""
    problems: list[tuple[str, str | None]] = []
    for folder in sorted(Path("core/data").glob("*/")) + sorted(Path("slices").glob("*/data/*/")):
        if folder.as_posix() == "core/data/schemas":
            continue
        core_schema = Path(f"core/data/schemas/{folder.name}.schema.json")
        if folder.parent == PACK_DATA and core_schema.is_file():
            schema = core_schema
        elif folder.parts[0] == "slices":
            schema = folder.with_name(f"{folder.name}.schema.json")
        else:
            schema = Path(f"core/data/schemas/{folder.name}.schema.json")
        if not schema.is_file():
            problems.append((f"{folder.as_posix()}/ has no schema at {schema.as_posix()}", None))
    schema_of: dict[str, str] = {}
    schemas = sorted(Path("core/data/schemas").glob("*.schema.json"))
    schemas += sorted(Path("slices").glob("*/data/*.schema.json"))
    for schema in schemas:
        name = schema.name.removesuffix(".schema.json")
        path = schema.as_posix()
        if schema.parts[0] != "slices":
            folder = Path(f"core/data/{name}")
            if not folder.is_dir():
                folder = PACK_DATA / name
        else:
            folder = schema.parent / name
        if folder == Path(f"slices/{name}/data/{name}"):
            if not any(schema.parent.glob("*.jsonc")):
                problems.append((f"has no {schema.parent.as_posix()}/*.jsonc to check", path))
        elif not folder.is_dir():
            problems.append((f"has no {folder.as_posix()}/ folder to check", path))
        if name in schema_of:
            problems.append((f"{name} already has a schema: {schema_of[name]}", path))
        schema_of.setdefault(name, path)
    return schema_of, problems


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    schema_of, problems = schema_problems()
    for message, file in problems:
        log.error(message, file)
    if problems:
        return 1
    # A file left over from an earlier local run would be checked as if it were content.
    shutil.rmtree(TARGET, ignore_errors=True)
    godot = os.environ.get("GODOT") or "godot"
    command = [godot, "--headless", "--path", ".", "-s", "res://tools/godot/data_to_json.gd"]
    try:
        converting = subprocess.run(command, timeout=TIMEOUT_SECONDS, check=False)
    except subprocess.TimeoutExpired:
        log.error("data_to_json.gd timed out")
        return 1
    if converting.returncode != 0:
        log.error("data_to_json.gd failed")
        return 1
    # Godot exits 0 even when a script fails to compile, so check every file was converted.
    sources = [*Path("core/data").rglob("*.jsonc"), *Path("slices").glob("*/data/**/*.jsonc")]
    written = list(TARGET.rglob("*.json"))
    if len(sources) != len(written):
        log.error(f"{len(sources)} content files, but data_to_json.gd wrote {len(written)}")
        return 1
    converted = sorted(TARGET.glob("*/*.json"))
    jv = os.environ.get("JV") or "jv"
    failed = 0
    for file in converted:
        kind = file.parent.name
        if kind not in schema_of:
            log.error(f"content kind {kind} has no schema")
            return 1
        if subprocess.run([jv, schema_of[kind], file], check=False).returncode != 0:
            log.error(f"{file.as_posix()} doesn't match {schema_of[kind]}")
            failed += 1
    print(f"{len(converted)} content files checked, {failed} failed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
