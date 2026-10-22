"""Prints the export template files (as named in Godot's templates archive) that the presets in
export_presets.cfg need, one per line, so CI and the release unpack exactly those and nothing
names the platforms twice.

    uv run --locked packages/game-build/export_templates.py [<export_presets.cfg>]

Without an argument it reads the game's, packages/game/export_presets.cfg (#1101).
"""

import re
import sys
from pathlib import Path

PRESET = re.compile(r"\[preset\.[0-9]+\]")
OPTIONS = re.compile(r"\[preset\.[0-9]+\.options\]")
PLATFORM = re.compile(r'platform="([^"]*)"')
TEMPLATES = {
    "Android": ["android_debug.apk", "android_release.apk"],
    "Windows Desktop": ["windows_release_x86_64.exe"],
    "Linux": ["linux_release.x86_64"],
    "Web": [],
}
# The web's templates depend on its options: with threads or without.
WEB = {"false": "web_nothreads_release.zip", "true": "web_release.zip"}


def main() -> int:
    game = Path(__file__).resolve().parents[1] / "game"
    presets = Path(sys.argv[1]) if len(sys.argv) > 1 else game / "export_presets.cfg"
    needed = set()
    section = None
    web = False
    for line in presets.read_text(encoding="utf-8", newline="").split("\n"):
        if PRESET.fullmatch(line):
            section = "preset"
        elif OPTIONS.fullmatch(line):
            section = "options"
        elif section == "preset" and (platform := PLATFORM.match(line)):
            if platform[1] not in TEMPLATES:
                print(f"no export template is known for platform: {platform[1]}", file=sys.stderr)
                return 1
            needed.update(TEMPLATES[platform[1]])
            web = platform[1] == "Web"
        elif section == "options" and line.startswith("variant/thread_support="):
            threads = line.partition("=")[2]
            if web and threads in WEB:
                needed.add(WEB[threads])
            web = False
    for template in sorted(needed):
        print(template)
    return 0


if __name__ == "__main__":
    sys.exit(main())
