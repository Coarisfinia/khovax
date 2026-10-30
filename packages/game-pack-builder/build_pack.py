"""Builds a resource pack (#1869): a folder holding its manifest, pack.jsonc, and its raw files
(images, glTF models, Markdown and JSONC) becomes <id>.desktop.pck and <id>.mobile.pck, imported
with the game's import settings by the Godot version the game is built with.

    uv run --locked --package khovax-game-pack-builder packages/game-pack-builder/build_pack.py <pack> <out>

or, from the zip each release ships (release_zip.py), python3 build_pack.py <pack> <out>.

A pack is data, never code (#1859): every file must be on the allow-list (ALLOWED), and a Godot
.import file beside one (the default pack keeps the game's import settings that way) may name no
script and no importer but a texture's or a scene's. Anything else refuses the whole pack.

The pack's files go under res://packs/<id>/ in a copy of template/, a project with the game's
import settings, which Godot imports and exports once per preset: a texture imported with VRAM
compression packs as S3TC/BPTC for desktop and ETC2/ASTC for mobile, so each platform gets its
own .pck. Godot is the one setup-godot pins (GODOT_VERSION; in the builder each release ships,
release_zip.py, godot.json beside it): GODOT, ~/godot/godot or godot on the
PATH when it's that version, else it's downloaded to ~/godot/godot and checked against its
GODOT_SHA512 (Linux x86_64 only).
"""

import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

from game_shared import log
from game_shared.resource_packs import read_manifest

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "template"
# The one place Godot's version and checksum are pinned (#924), and the copy of them the released
# builder carries instead (release_zip.py, #1871).
SETUP_GODOT = HERE.parents[1] / ".github" / "actions" / "setup-godot" / "action.yml"
RELEASED_GODOT = HERE / "godot.json"
MANIFEST = "pack.jsonc"
PRESETS = ("desktop", "mobile")
# What a pack may hold: images, models (a glTF's buffers too), text, and Godot's .import files.
ALLOWED = (".png", ".jpg", ".jpeg", ".webp", ".svg", ".glb", ".gltf", ".bin", ".md", ".jsonc")
IMPORT = ".import"
# The importers a .import may name, each with the type it imports as and the files it imports.
IMPORTERS = {
    "texture": ("CompressedTexture2D", (".png", ".jpg", ".jpeg", ".webp", ".svg")),
    "scene": ("PackedScene", (".glb", ".gltf")),
}
# A setting that names a script, unless it names none.
SCRIPT_SETTING = re.compile(r"^[^=\n]*script[^=\n]*=(?!null$|\"\"$).*$", re.MULTILINE | re.IGNORECASE)
# A .import names no file at all: no res://, uid:// or other scheme, so no setting saves to or
# loads from a path.
SCHEME = re.compile(r"[a-z]+://", re.IGNORECASE)
# Nor any other path: a string that starts at a root or a drive, or climbs out, nor a setting
# that ties the file to a project (Godot writes those itself).
PATH_STRING = re.compile(r'"(?:[/\\]|[A-Za-z]:|[^"\n]*\.\.[/\\])')
PROJECT_BOUND = re.compile(r"^(?:uid|path(?:\.[a-z0-9_]+)?|source_file|dest_files)=|^\[deps\]", re.MULTILINE)
# How long downloading Godot may stall, in seconds.
DOWNLOAD_TIMEOUT = 300
REMAP_SETTING = re.compile(r'^(importer|type)="([^"\n]*)"$')
# How long Godot may take to import or export a pack, in seconds.
TIMEOUT = 900


def refused(pack: Path) -> list[str]:
    """Why the pack can't be built, one reason per file: a file off the allow-list, a link, or a
    .import file naming a script or another importer. Empty when it's all data."""
    if pack.is_symlink():
        return [f"{pack} is a link"]
    reasons = []
    for path in sorted(pack.rglob("*")):
        name = path.relative_to(pack).as_posix()
        if path.is_symlink():
            reasons.append(f"{name} is a link")
        elif path.is_dir():
            continue
        elif not path.is_file():
            reasons.append(f"{name} isn't a plain file")
        elif name.endswith(IMPORT):
            reasons += [f"{name} {problem}" for problem in import_problems(path)]
        elif name.endswith(".gltf"):
            reasons += [f"{name} {problem}" for problem in gltf_problems(pack, path)]
        elif not name.endswith(ALLOWED):
            reasons.append(f"{name} isn't one of {', '.join(ALLOWED)} (a pack is data, never code)")
    return reasons


def import_problems(path: Path) -> list[str]:
    """Why a .import file can't come with a pack: its [remap] doesn't name exactly one importer
    of IMPORTERS, with its type, for a file of its kind beside it; or a setting names a script or
    a path."""
    settings = path.read_text(encoding="utf-8", errors="replace")
    remap: dict[str, list[str]] = {"importer": [], "type": []}
    section = ""
    for line in settings.split("\n"):
        if line.startswith("["):
            section = line.strip()
        elif section == "[remap]" and (found := REMAP_SETTING.match(line)):
            remap[found[1]].append(found[2])
        elif section == "[remap]" and line.split("=")[0].strip() in remap:
            remap[line.split("=")[0].strip()].append(line)
    problems = []
    importer = remap["importer"][0] if len(remap["importer"]) == 1 else None
    if importer not in IMPORTERS:
        problems.append(f"doesn't name exactly one importer of {', '.join(IMPORTERS)}")
    else:
        kind, sources = IMPORTERS[importer]
        source = path.with_name(path.name.removesuffix(IMPORT))
        if remap["type"] != [kind]:
            problems.append(f"imports as {remap['type']}, not {kind}")
        if not source.name.endswith(sources) or not source.is_file() or source.is_symlink():
            problems.append(f"imports no {'/'.join(sources)} file beside it")
    problems += [f"names a script: {setting}" for setting in SCRIPT_SETTING.findall(settings)]
    if SCHEME.search(settings) or PATH_STRING.search(settings) or PROJECT_BOUND.search(settings):
        problems.append("names a path (a pack's settings name no file)")
    return problems


def gltf_problems(pack: Path, gltf: Path) -> list[str]:
    """Why a glTF can't come with a pack: it isn't JSON, or a buffer or image it points at isn't
    embedded (data:) nor a plain file inside the pack, so Godot's import would read elsewhere."""
    try:
        document = json.loads(gltf.read_text(encoding="utf-8"))
        uris = [
            entry["uri"]
            for entry in document.get("buffers", []) + document.get("images", [])
            if "uri" in entry
        ]
    except (ValueError, TypeError, AttributeError, KeyError):
        return ["isn't a glTF Godot could read"]
    problems = []
    for uri in uris:
        if isinstance(uri, str) and uri.startswith("data:"):
            continue
        target = gltf.parent / uri if isinstance(uri, str) else None
        inside = (
            target is not None
            and not SCHEME.search(uri)
            and not Path(uri).is_absolute()
            and target.resolve().is_relative_to(pack.resolve())
            and target.is_file()
            and not target.is_symlink()
        )
        if not inside:
            problems.append(f"points at {uri!r}, which isn't a plain file in the pack")
    return problems


def pinned() -> tuple[str, str]:
    """Godot's pinned version and its Linux editor's SHA-512, from setup-godot, or from the
    released builder's godot.json."""
    if RELEASED_GODOT.is_file():
        released = json.loads(RELEASED_GODOT.read_text(encoding="utf-8"))
        return released["version"], released["sha512"]
    text = SETUP_GODOT.read_text(encoding="utf-8")
    version = re.search(r'"GODOT_VERSION=([0-9.]+)"', text)
    checksum = re.search(r'"GODOT_SHA512=([0-9a-f]+)"', text)
    if not version or not checksum:
        raise ValueError(f"{SETUP_GODOT} pins no GODOT_VERSION and GODOT_SHA512")
    return version[1], checksum[1]


def godot(version: str, checksum: str) -> str:
    """A Godot editor of the pinned version, downloaded to ~/godot/godot when there is none."""
    home = Path.home() / "godot" / "godot"
    for candidate in (os.environ.get("GODOT"), str(home), shutil.which("godot")):
        if candidate and is_version(candidate, version):
            return candidate
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise RuntimeError(f"no Godot {version} found: install it and point GODOT at it")
    name = f"Godot_v{version}-stable_linux.x86_64"
    url = f"https://github.com/godotengine/godot/releases/download/{version}-stable/{name}.zip"
    log.text("notice", f"downloading Godot {version} to {home}")
    try:
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "godot.zip"
            with urllib.request.urlopen(url, timeout=DOWNLOAD_TIMEOUT) as download:
                archive.write_bytes(download.read())
            if hashlib.sha512(archive.read_bytes()).hexdigest() != checksum:
                raise RuntimeError(f"{url} doesn't match its pinned SHA-512")
            with zipfile.ZipFile(archive) as files:
                files.extract(name, folder)
            home.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(Path(folder) / name, home)
    except (OSError, zipfile.BadZipFile, shutil.Error) as problem:
        raise RuntimeError(f"Godot {version} couldn't be downloaded: {problem}") from problem
    home.chmod(0o755)
    return str(home)


def is_version(editor: str, version: str) -> bool:
    """Whether `editor` runs and is Godot `version`, stable."""
    try:
        found = subprocess.run([editor, "--version"], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return found.stdout.startswith(f"{version}.stable.")


def run(editor: str, project: Path, *arguments: str) -> None:
    """Runs Godot headless on the project; RuntimeError with its output when it fails or reports
    an error."""
    try:
        done = subprocess.run(
            [editor, "--headless", "--path", str(project), *arguments],
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
        )
    except subprocess.TimeoutExpired as late:
        raise RuntimeError(f"godot {' '.join(arguments)} took over {TIMEOUT} s:\n{late.output}") from late
    output = done.stdout + done.stderr
    if done.returncode != 0 or re.search(r"^(SCRIPT )?ERROR:", output, re.MULTILINE):
        raise RuntimeError(f"godot {' '.join(arguments)} failed:\n{output}")


def build(pack: Path, out: Path) -> list[Path]:
    """Builds the pack's .pck files into `out`; ValueError when the pack is refused."""
    if not (pack / MANIFEST).is_file():
        raise ValueError(f"{pack} has no {MANIFEST}")
    reasons = refused(pack)
    if reasons:
        raise ValueError("refused: " + "; ".join(reasons))
    pack_id = read_manifest(pack / MANIFEST).get("id")
    if not isinstance(pack_id, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", pack_id):
        raise ValueError(f"{pack / MANIFEST} has no id of lowercase words and underscores")
    editor = godot(*pinned())
    out.mkdir(parents=True, exist_ok=True)
    built = []
    with tempfile.TemporaryDirectory() as folder:
        project = Path(folder) / "project"
        shutil.copytree(TEMPLATE, project)
        shutil.copytree(pack, project / "packs" / pack_id)
        run(editor, project, "--import")
        for preset in PRESETS:
            target = (out / f"{pack_id}.{preset}.pck").resolve()
            run(editor, project, "--export-pack", preset, str(target))
            if not target.is_file():
                raise RuntimeError(f"Godot wrote no {target}")
            built.append(target)
    return built


def main() -> int:
    if len(sys.argv) != 3:
        log.error("usage: build_pack.py <pack folder> <out folder>")
        return 2
    try:
        for target in build(Path(sys.argv[1]), Path(sys.argv[2])):
            print(target)
    except (ValueError, RuntimeError) as problem:
        log.error(str(problem))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
