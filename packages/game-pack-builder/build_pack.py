"""Builds a resource pack (#1869): a folder holding its manifest, pack.jsonc, and its raw files
(images, glTF models, Markdown and JSONC) becomes <id>.desktop.pck and <id>.mobile.pck, imported
with the game's import settings by the Godot version the game is built with.

    uv run --locked --package khovax-game-pack-builder packages/game-pack-builder/build_pack.py <pack> <out>

A pack is data, never code (#1859): every file must be on the allow-list (ALLOWED), and a Godot
.import file beside one (the default pack keeps the game's import settings that way) may name no
script and no importer but a texture's or a scene's. Anything else refuses the whole pack.

The pack's files go under res://packs/<id>/ in a copy of template/, a project with the game's
import settings, which Godot imports and exports once per preset: a texture imported with VRAM
compression packs as S3TC/BPTC for desktop and ETC2/ASTC for mobile, so each platform gets its
own .pck. Godot is the one setup-godot pins (GODOT_VERSION): GODOT, ~/godot/godot or godot on the
PATH when it's that version, else it's downloaded to ~/godot/godot and checked against its
GODOT_SHA512 (Linux x86_64 only).
"""

import hashlib
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
# The one place Godot's version and checksum are pinned (#924).
SETUP_GODOT = HERE.parents[1] / ".github" / "actions" / "setup-godot" / "action.yml"
MANIFEST = "pack.jsonc"
PRESETS = ("desktop", "mobile")
# What a pack may hold: images, models (a glTF's buffers too), text, and Godot's .import files.
ALLOWED = (".png", ".jpg", ".jpeg", ".webp", ".svg", ".glb", ".gltf", ".bin", ".md", ".jsonc")
IMPORT = ".import"
IMPORTERS = ('importer="texture"', 'importer="scene"')
# A setting that names a script, unless it names none.
SCRIPT_SETTING = re.compile(r"^[^=\n]*script[^=\n]*=(?!null$|\"\"$).*$", re.MULTILINE | re.IGNORECASE)
# How long Godot may take to import or export a pack, in seconds.
TIMEOUT = 900


def refused(pack: Path) -> list[str]:
    """Why the pack can't be built, one reason per file: a file off the allow-list, a link, or a
    .import file naming a script or another importer. Empty when it's all data."""
    reasons = []
    for path in sorted(pack.rglob("*")):
        name = path.relative_to(pack).as_posix()
        if path.is_symlink():
            reasons.append(f"{name} is a link")
        elif path.is_dir():
            continue
        elif name.endswith(IMPORT):
            settings = path.read_text(encoding="utf-8", errors="replace")
            if not any(importer in settings for importer in IMPORTERS):
                reasons.append(f"{name} imports with neither the texture nor the scene importer")
            for setting in SCRIPT_SETTING.findall(settings):
                reasons.append(f"{name} names a script: {setting}")
        elif not name.endswith(ALLOWED):
            reasons.append(f"{name} isn't one of {', '.join(ALLOWED)} (a pack is data, never code)")
    return reasons


def pinned() -> tuple[str, str]:
    """Godot's pinned version and its Linux editor's SHA-512, from setup-godot."""
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
    with tempfile.TemporaryDirectory() as folder:
        archive = Path(folder) / "godot.zip"
        urllib.request.urlretrieve(url, archive)
        if hashlib.sha512(archive.read_bytes()).hexdigest() != checksum:
            raise RuntimeError(f"{url} doesn't match its pinned SHA-512")
        with zipfile.ZipFile(archive) as files:
            files.extract(name, folder)
        home.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(Path(folder) / name, home)
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
    done = subprocess.run(
        [editor, "--headless", "--path", str(project), *arguments],
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
    )
    output = done.stdout + done.stderr
    if done.returncode != 0 or re.search(r"^(SCRIPT )?ERROR:", output, re.MULTILINE):
        raise RuntimeError(f"godot {' '.join(arguments)} failed:\n{output}")


def build(pack: Path, out: Path) -> list[Path]:
    """Builds the pack's .pck files into `out`; ValueError when the pack is refused."""
    if not (pack / MANIFEST).is_file():
        raise ValueError(f"{pack} has no {MANIFEST}")
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
