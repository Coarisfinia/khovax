"""Fails when a tracked file's ending isn't on ENDINGS (owner, #1095): every ending the repository
used when the check came, except .sh and .bat. A file's ending is what follows the last dot of its
name, the dot included (.gitignore's is .gitignore); a name without a dot counts as a whole.

A new ending needs the owner's sign-off on its issue first (owner's rule, #1095): an agent never
adds one to ENDINGS on its own.

The shell scripts still tracked wait in SH_EXEMPT, each with the issue that ports it, and an
exemption no longer used fails too, so the list only shrinks.

    uv run --locked packages/checks/file_endings.py
"""

import os
import sys
from pathlib import Path, PurePosixPath

from git_files import git_files

# The endings allowed, each with what it's for. A new one needs the owner's sign-off (#1095).
ENDINGS: dict[str, str] = {
    ".gd": "GDScript, the game's code",
    ".gdshader": "Godot shaders",
    ".tscn": "Godot scenes",
    ".uid": "the ids Godot keeps next to scripts and resources",
    ".import": "Godot's import settings for an asset",
    ".godot": "the Godot project file",
    ".cfg": "Godot's export presets",
    ".gdignore": "keeps Godot from importing a folder",
    ".jsonc": "content data",
    ".json": "the content's schemas and other JSON data",
    ".replay": "the golden replays' inputs",
    ".md": "docs, region pieces, rule change files, asset sources and licenses",
    "LICENSE": "the repository's license",
    ".png": "images",
    ".svg": "vector icons",
    ".gltf": "models",
    ".glb": "models",
    ".bin": "a glTF model's buffers",
    ".ogg": "music and sounds",
    ".py": "the tooling, run with uv, and the Blender model scripts",
    ".toml": "the uv project and gdstyle's settings",
    ".lock": "locked dependencies",
    ".ts": "the web e2e (#1041 moves it to Python)",
    ".yml": "the GitHub Actions workflows",
    ".gitignore": "what git leaves untracked",
    ".gitattributes": "how git treats files",
}
# The shell scripts still waiting for their port (path: the issue that ports it).
SH_EXEMPT: dict[str, int] = {
    "packages/checks/script_check.sh": 1096,
}

THIS = "packages/checks/file_endings.py"


def ending(path: str) -> str:
    """What follows the last dot of the file's name, the dot included, or the whole name."""
    name = PurePosixPath(path).name
    return name[name.rindex(".") :] if "." in name else name


def main() -> int:
    os.chdir(Path(__file__).resolve().parents[2])
    tracked = set(git_files())
    failed = False
    for path in sorted(tracked):
        if path in SH_EXEMPT or ending(path) in ENDINGS:
            continue
        print(
            f"::error file={path}::its ending {ending(path)} isn't allowed ({THIS}, ENDINGS);"
            " a new ending needs the owner's sign-off on its issue first (#1095)"
        )
        failed = True
    for path, issue in SH_EXEMPT.items():
        if path not in tracked:
            print(
                f"::error file={THIS}::{path} is no longer tracked: drop its exemption"
                f" (#{issue}) from SH_EXEMPT"
            )
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
